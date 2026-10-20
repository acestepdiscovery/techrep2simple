import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:printing/printing.dart';
import 'package:uuid/uuid.dart';
import '../../../core/constants/app_colors.dart';
import '../models/report_model.dart';
import '../models/sector_options.dart';
import '../models/tax_options.dart';
import '../models/currency_options.dart';
import '../../settings/widgets/tax_editor.dart';
import '../providers/reports_provider.dart';
import '../../clients/models/client_model.dart';
import '../../clients/providers/clients_provider.dart';
import '../../../shared/services/analytics_service.dart';
import '../../../shared/services/instance_token_guard.dart';
import '../../../shared/services/kill_switch_service.dart';
import '../../../shared/services/local_db_service.dart';
import '../../../shared/services/pdf_service.dart';
import '../../../shared/services/team_service.dart';
import '../../auth/providers/auth_provider.dart';
import '../../../shared/widgets/photo_picker_widget.dart';
import '../../settings/providers/settings_provider.dart';
import '../../profile/providers/profile_context_provider.dart';
import '../../subscription/subscription_provider.dart';
import '../../subscription/paywall_bottom_sheet.dart';
import '../../team/screens/team_dashboard_screen.dart' show teamTabRequestProvider, TeamTabRequest;
import '../../settings/screens/settings_screen.dart' show settingsExpandCompanyProvider;
import 'signature_screen.dart';
import '../../../shared/services/photo_storage.dart';

class CreateReportScreen extends ConsumerStatefulWidget {
  final String? reportId;
  final ReportPreset? templatePreset;
  const CreateReportScreen({super.key, this.reportId, this.templatePreset});

  @override
  ConsumerState<CreateReportScreen> createState() =>
      _CreateReportScreenState();
}

// (#4b) Une ligne de champ personnalisé (intitulé + valeur) avec ses contrôleurs.
class _CFRow {
  final TextEditingController label;
  final TextEditingController value;
  _CFRow(String l, String v)
      : label = TextEditingController(text: l),
        value = TextEditingController(text: v);
  void dispose() {
    label.dispose();
    value.dispose();
  }
}

class _CreateReportScreenState extends ConsumerState<CreateReportScreen> {
  final _formKey = GlobalKey<FormState>();
  final _scroll = ScrollController();

  // Controllers – client
  final _clientName = TextEditingController();
  final _clientAddress = TextEditingController();
  final _clientPhone = TextEditingController();
  final _clientContact = TextEditingController();
  final _contractNumber = TextEditingController();
  final _clientBusinessId = TextEditingController();
  // Controllers – intervention
  final _interventionType = TextEditingController();
  // Controllers – equipment
  final _equipmentType = TextEditingController();
  final _equipmentBrand = TextEditingController();
  final _equipmentModel = TextEditingController();
  final _equipmentSerial = TextEditingController();
  // Controllers – work
  final _description = TextEditingController();
  final _observations = TextEditingController();
  // Controllers – billing
  final _laborHours = TextEditingController();
  final _laborRate = TextEditingController();

  SectorTemplate _sector = SectorTemplate.generic;
  DateTime _date = DateTime.now();
  DateTime? _endDate;
  DateTime? _startTime;
  DateTime? _endTime;
  Map<String, dynamic> _sectorFields = {};
  bool _isSaving = false;
  bool _isLoading = false;
  DateTime? _existingCreatedAt;
  // (2026-10-14) Rapport d'origine en modification : ses champs absents du
  // formulaire (modèle PDF, lien cloud, « signé à distance », badge IA) étaient
  // PERDUS à chaque enregistrement.
  ReportModel? _existing;
  int _reportNumber = 0;
  String? _reportNumberFormat;
  // Override taxe (facture) de CE rapport ; null = défaut global des Réglages.
  double? _taxRate;
  String? _taxLabel;
  String? _taxMention;
  String? _clientId;

  final List<XFile> _photos = [];
  final List<MaterialItem> _materials = [];
  String? _sigClientStartData;
  String? _sigTechStartData;
  String? _sigClientData;
  String? _sigTechData;

  // (#4b) « Sous contrat ? » + champs libres (intitulé → valeur).
  bool _sousContrat = false;
  final List<_CFRow> _customRows = [];

  late String _reportId;
  Timer? _autoSaveTimer;
  bool _isDirty = false;
  // (2026-10-19) Rapport créé par l'IA (badge « IA ») — avant, perdu à l'ouverture.
  bool _aiEnhanced = false;
  // (2026-10-19) Contenu « de départ » (rapport rouvert ou modèle) : l'auto-
  // enregistrement et la sauvegarde à la sortie n'écrivent QUE s'il a changé.
  // Avant, rouvrir un rapport le réenregistrait au bout de 2 s (remplir les
  // champs déclenchait l'auto-save) → statut repassé en « Brouillon ».
  String? _baseline;

  // Parent-controlled section expansion — survives parent setState calls (fix 1E)
  final Map<int, bool> _sectionExpanded = {
    0: true, 1: false, 2: false, 3: false, 4: false,
    5: false, 6: false, 7: false, 8: false,
  };
  bool _clientSectionError = false;
  bool _travauxSectionError = false;

  Set<int> _visibleNavSet = {0};
  final List<GlobalKey> _navKeys = List.generate(9, (_) => GlobalKey());
  // Keys for the pill widgets so we can auto-scroll the horizontal pill bar
  // to keep the active pill(s) in view when the user scrolls the form.
  final List<GlobalKey> _pillKeys = List.generate(9, (_) => GlobalKey());

  bool get _isEditMode => widget.reportId != null;

  @override
  void initState() {
    super.initState();
    _reportId = widget.reportId ?? const Uuid().v4();
    if (_isEditMode) {
      _loadExisting();
    } else {
      LocalDbService().getNextReportNumber().then((n) {
        if (mounted) setState(() => _reportNumber = n);
      });
      if (widget.templatePreset != null) {
        WidgetsBinding.instance.addPostFrameCallback(
            (_) => _fillFromTemplate(widget.templatePreset!.data));
      }
    }
    _addDirtyListeners();
    _scroll.addListener(_updateActiveNav);
  }

  Future<void> _loadExisting() async {
    setState(() => _isLoading = true);
    final report = await LocalDbService().getReport(widget.reportId!);
    if (!mounted) return;
    if (report != null) _fillFromReport(report);
    setState(() => _isLoading = false);
  }

  void _fillFromReport(ReportModel report) {
    _clientName.text = report.clientName;
    _clientAddress.text = report.clientAddress;
    _clientPhone.text = report.clientPhone;
    _clientContact.text = report.clientContact;
    _contractNumber.text = report.contractNumber;
    _clientBusinessId.text = report.clientBusinessId;
    _interventionType.text = report.interventionType;
    _equipmentType.text = report.equipmentType;
    _equipmentBrand.text = report.equipmentBrand;
    _equipmentModel.text = report.equipmentModel;
    _equipmentSerial.text = report.equipmentSerial;
    _description.text = report.description;
    _observations.text = report.observations;
    if (report.laborHours != null) _laborHours.text = report.laborHours!.toString();
    if (report.laborRate != null) _laborRate.text = report.laborRate!.toString();
    setState(() {
      _sector = report.sector;
      _date = report.date;
      _endDate = report.endDate;
      _startTime = report.startTime;
      _endTime = report.endTime;
      _sectorFields = Map.from(report.sectorFields);
      _clientId = report.clientId;
      _sigClientStartData = report.signatureClientStartData;
      _sigTechStartData = report.signatureTechStartData;
      _sigClientData = report.signatureClientData;
      _sigTechData = report.signatureTechData;
      _existingCreatedAt = report.createdAt;
      _existing = report;
      _sousContrat = report.sousContrat;
      for (final r in _customRows) {
        r.dispose();
      }
      _customRows.clear();
      report.customFields.forEach((k, v) {
        final r = _CFRow(k, v);
        r.label.addListener(_onDirty);
        r.value.addListener(_onDirty);
        _customRows.add(r);
      });
      _materials
        ..clear()
        ..addAll(report.materials);
      _reportNumber = report.reportNumber;
      _reportNumberFormat = report.reportNumberFormat;
      _taxRate = report.taxRate;
      _taxLabel = report.taxLabel;
      _taxMention = report.taxMention;
      // (2026-10-19) 🔴 Les PHOTOS n'étaient jamais rechargées en modification :
      // la section était vide et le premier enregistrement (auto ou à la sortie)
      // réécrivait le rapport SANS ses photos. Fichiers disparus = ignorés.
      _photos
        ..clear()
        ..addAll(report.photosPaths
            .where((p) => p.isNotEmpty && (kIsWeb || File(p).existsSync()))
            .map(XFile.new));
      // Auto-expand sections that already have data when editing
      _sectionExpanded[1] = report.clientName.isNotEmpty;
      _sectionExpanded[3] = report.equipmentType.isNotEmpty;
      _sectionExpanded[5] = report.description.isNotEmpty;
      _sectionExpanded[6] = report.photosPaths.isNotEmpty;
      _sectionExpanded[7] = report.signatureClientData != null ||
          report.signatureTechData != null ||
          report.signatureClientStartData != null ||
          report.signatureTechStartData != null;
      _sectionExpanded[8] = report.laborHours != null ||
          report.laborRate != null ||
          report.materials.isNotEmpty;
    });
    _baseline = _contentKey();
  }

  /// [resetBaseline] = false quand l'utilisateur charge un modèle dans un
  /// rapport déjà ouvert : ce changement doit être enregistré (auto-save).
  void _fillFromTemplate(Map<String, dynamic> data, {bool resetBaseline = true}) {
    final now = DateTime.now().toIso8601String();
    // (2026-10-19) Date détectée par l'IA (« ai_date ») ; un modèle, lui, prend
    // toujours la date du jour.
    final aiDate = DateTime.tryParse('${data['ai_date'] ?? ''}');
    // (2026-10-20) Un modèle n'a plus d'infos client (ReportPreset.forNewReport) :
    // on ne remplace un champ client QUE s'il est fourni — sinon charger un modèle
    // dans un rapport commencé effaçait le client déjà saisi.
    final given = ReportPreset.reportData(data);
    bool has(String k) => given.containsKey(k);
    final r = ReportModel.fromMap({
      // (2026-10-19) Les 2 formats de modèles (formulaire / fiche du rapport).
      ...given,
      'id': _reportId,
      'date': aiDate?.toIso8601String() ?? now,
      'created_at': now,
      'updated_at': now,
      'status': 'draft',
      'report_number': 0,
      'cloud_url': null,
      'pdf_local_path': null,
      'signature_client_data': null,
      'signature_tech_data': null,
      'signature_client_start_data': null,
      'signature_tech_start_data': null,
      'photos': '[]',
    });
    if (has('client_name')) _clientName.text = r.clientName;
    if (has('client_address')) _clientAddress.text = r.clientAddress;
    if (has('client_phone')) _clientPhone.text = r.clientPhone;
    if (has('client_contact')) _clientContact.text = r.clientContact;
    if (has('contract_number')) _contractNumber.text = r.contractNumber;
    if (has('client_business_id')) _clientBusinessId.text = r.clientBusinessId;
    _interventionType.text = r.interventionType;
    _equipmentType.text = r.equipmentType;
    _equipmentBrand.text = r.equipmentBrand;
    _equipmentModel.text = r.equipmentModel;
    if (has('equipment_serial')) _equipmentSerial.text = r.equipmentSerial;
    _description.text = r.description;
    _observations.text = r.observations;
    if (r.laborHours != null) _laborHours.text = r.laborHours!.toString();
    if (r.laborRate != null) _laborRate.text = r.laborRate!.toString();
    setState(() {
      _sector = r.sector;
      _sectorFields = Map.from(r.sectorFields);
      if (has('client_id')) _clientId = r.clientId;
      _materials..clear()..addAll(r.materials);
      if (aiDate != null) _date = aiDate;
      _aiEnhanced = _aiEnhanced || r.aiEnhanced;
      // (2026-10-19) Aussi : horaires (reportés sur la date du rapport), « sous
      // contrat », champs libres et taxe — avant, perdus avec un modèle.
      DateTime? onDate(DateTime? t) => t == null
          ? null
          : DateTime(_date.year, _date.month, _date.day, t.hour, t.minute);
      if (r.startTime != null) _startTime = onDate(r.startTime);
      if (r.endTime != null) _endTime = onDate(r.endTime);
      _sousContrat = r.sousContrat;
      if (r.customFields.isNotEmpty) {
        for (final row in _customRows) {
          row.dispose();
        }
        _customRows.clear();
        r.customFields.forEach((k, v) {
          final row = _CFRow(k, v);
          row.label.addListener(_onDirty);
          row.value.addListener(_onDirty);
          _customRows.add(row);
        });
      }
      _taxRate ??= r.taxRate;
      _taxLabel ??= r.taxLabel;
      _taxMention ??= r.taxMention;
      _sectionExpanded[1] = r.clientName.isNotEmpty;
      _sectionExpanded[3] = r.equipmentType.isNotEmpty;
      _sectionExpanded[5] = r.description.isNotEmpty;
      _sectionExpanded[8] = r.laborHours != null || r.laborRate != null || r.materials.isNotEmpty;
    });
    // (2026-10-19) Modèle / exemple ouvert puis abandonné sans rien changer →
    // plus de brouillon parasite dans la liste.
    if (resetBaseline) _baseline = _contentKey();
  }

  @override
  void deactivate() {
    // (#4c) FLUSH FINAL : persiste le brouillon MÊME si on quitte avant les 2s du
    // debounce (ex. on remplit 1 champ et on quitte aussitôt). `reportsProvider`
    // survit au widget (non autoDispose) → le brouillon apparaîtra dans la liste.
    // Idempotent (id de session stable).
    // (2026-10-19) ICI et plus dans dispose() : dans dispose(), `ref` lève
    // « Cannot use ref after the widget was disposed » → cette sauvegarde n'a
    // JAMAIS fonctionné (et la suite du nettoyage était sautée). Trouvé par
    // test/report_form_edit_test.dart.
    _autoSaveTimer?.cancel();
    if (_hasChanges()) {
      ref
          .read(reportsProvider.notifier)
          .upsertSilently(_buildReport(ReportStatus.draft));
    }
    super.deactivate();
  }

  @override
  void dispose() {
    _autoSaveTimer?.cancel();
    for (final c in [
      _clientName, _clientAddress, _clientPhone, _clientContact,
      _contractNumber, _clientBusinessId, _interventionType, _equipmentType, _equipmentBrand,
      _equipmentModel, _equipmentSerial, _description, _observations,
      _laborHours, _laborRate,
    ]) {
      c.removeListener(_onDirty);
      c.dispose();
    }
    for (final r in _customRows) {
      r.dispose();
    }
    _scroll.removeListener(_updateActiveNav);
    _scroll.dispose();
    super.dispose();
  }

  // ─── Auto-save ────────────────────────────────────────────────────────────────

  void _addDirtyListeners() {
    for (final c in [
      _clientName, _clientAddress, _clientPhone, _clientContact,
      _contractNumber, _clientBusinessId, _interventionType, _equipmentType, _equipmentBrand,
      _equipmentModel, _equipmentSerial, _description, _observations,
      _laborHours, _laborRate,
    ]) {
      c.addListener(_onDirty);
    }
  }

  void _onDirty() {
    if (!_isDirty) setState(() => _isDirty = true);
    _scheduleAutoSave();
  }

  void _scheduleAutoSave() {
    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer(const Duration(seconds: 2), _autoSave);
  }

  // (A) Au moins UNE info renseignée → le rapport mérite d'être un brouillon.
  bool _hasAnyContent() {
    final hasAnyText = [
      _clientName, _clientAddress, _clientPhone, _clientContact,
      _contractNumber, _clientBusinessId, _interventionType, _equipmentType, _equipmentBrand,
      _equipmentModel, _equipmentSerial, _description, _observations,
      _laborHours, _laborRate,
    ].any((c) => c.text.trim().isNotEmpty);
    final hasOtherContent = _photos.isNotEmpty ||
        _materials.isNotEmpty ||
        _sigClientStartData != null ||
        _sigTechStartData != null ||
        _sigClientData != null ||
        _sigTechData != null ||
        _customRows.any((r) =>
            r.label.text.trim().isNotEmpty || r.value.text.trim().isNotEmpty) ||
        _sectorFields.values.any((v) => v.toString().isNotEmpty);
    return hasAnyText || hasOtherContent;
  }

  /// Empreinte du contenu saisi (sans les dates d'écriture, le statut ni
  /// l'identité qui suit le profil actif).
  String _contentKey() {
    final m = Map<String, dynamic>.of(_buildReport(ReportStatus.draft).toMap());
    for (final k in const [
      'updated_at', 'created_at', 'status', 'report_number',
      'technician_name', 'technician_id', 'company_id',
    ]) {
      m.remove(k);
    }
    return jsonEncode(m);
  }

  /// Rien à enregistrer tant que le contenu de départ n'a pas changé.
  bool _hasChanges() {
    if (!_hasAnyContent()) return false;
    final base = _baseline;
    return base == null || _contentKey() != base;
  }

  Future<void> _autoSave() async {
    if (!mounted) return;
    if (!_hasChanges()) return;
    // Ce contenu est désormais enregistré (pas de 2e écriture à la sortie).
    _baseline = _contentKey();
    // (A) Passe par le PROVIDER (et plus par un insert direct) → la liste des
    // rapports reflète le brouillon EN DIRECT, sans attendre un autre save.
    await ref
        .read(reportsProvider.notifier)
        .upsertSilently(_buildReport(ReportStatus.draft));
  }

  /// (2026-10-19) Après / avant un enregistrement EXPLICITE (brouillon, envoi) :
  /// plus d'auto-enregistrement ni de sauvegarde de sortie pour CE contenu —
  /// sinon elles réécrivaient le rapport tout juste envoyé en « Brouillon ».
  void _clearAutosave() {
    _autoSaveTimer?.cancel();
    _autoSaveTimer = null;
    _baseline = _contentKey();
  }

  // ─── PDF preview ──────────────────────────────────────────────────────────────

  Future<void> _previewCurrentPdf() async {
    setState(() => _isSaving = true);
    final report = _buildReport(ReportStatus.draft);
    // (identité par profil) Aperçu fidèle : toute l'identité entreprise suit le
    // profil actif (perso → tes infos ; équipe → infos de l'équipe ou blanc,
    // jamais tes infos perso).
    final s = ref.read(activeCompanySettingsProvider);
    // (R/#6) Le logo suit le PROFIL : perso → logo solo ; équipe → logo d'équipe
    // du coéquipier (team_logo_path, repli solo). Résolu dans activeCompanySettings.
    final logoPath = (s['logo_path'] ?? '').toString();
    final logoBytes =
        (!kIsWeb && logoPath.isNotEmpty && File(logoPath).existsSync())
            ? await File(logoPath).readAsBytes()
            : null;
    final bytes = await PdfService().generateReport(
      report,
      photos: _photos,
      companyName: s['company_name'],
      technicianName: s['technician_name'],
      logoBytes: logoBytes,
      companyAddress: s['company_address'],
      companyPhone: s['company_phone'],
      companyEmail: s['company_email'],
      companySiret: s['company_siret'],
      companyTva: s['company_tva'],
      currencyCode: appCurrencyCode,
    );
    setState(() => _isSaving = false);
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: Text('cr_pdf_preview'.tr())),
          body: PdfPreview(
            build: (_) async => bytes,
            allowPrinting: false,
            allowSharing: false,
            canChangeOrientation: false,
            canChangePageFormat: false,
          ),
        ),
      ),
    );
  }

  // ─── Helpers ────────────────────────────────────────────────────────────────

  // FR1 — quick-fill start time
  void _setStartTimeOffset(int minutesBefore) {
    final now = DateTime.now();
    final dt = now.subtract(Duration(minutes: minutesBefore));
    setState(() => _startTime = DateTime(
          _date.year, _date.month, _date.day, dt.hour, dt.minute));
  }

  // FR4 — undo time clear
  void _clearTime(bool isStart) {
    final previous = isStart ? _startTime : _endTime;
    setState(() {
      if (isStart) {
        _startTime = null;
      } else {
        _endTime = null;
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text((isStart ? 'cr_time_start_cleared' : 'cr_time_end_cleared').tr()),
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          label: 'common_cancel'.tr(),
          onPressed: () => setState(() {
            if (isStart) {
              _startTime = previous;
            } else {
              _endTime = previous;
            }
          }),
        ),
      ),
    );
  }

  // FR4 — undo material removal
  void _removeMaterial(int index) {
    final removed = _materials[index];
    setState(() => _materials.removeAt(index));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('cr_material_removed'.tr(args: [removed.label])),
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          label: 'common_cancel'.tr(),
          onPressed: () => setState(() => _materials.insert(index, removed)),
        ),
      ),
    );
  }

  // slot: 'clientStart' | 'techStart' | 'clientEnd' | 'techEnd'
  // (b) Explique la signature à distance SANS quitter la rédaction (le rapport
  // est de toute façon auto-enregistré en brouillon). La vraie action se fait
  // après l'envoi, depuis la page de gestion du rapport.
  void _showRemoteSignatureInfo() {
    showDialog<void>(
      context: context,
      builder: (dlg) => AlertDialog(
        icon: const Icon(Icons.send_to_mobile_outlined,
            color: AppColors.primary),
        title: Text('cr_remote_info_title'.tr()),
        content: Text(
          'cr_remote_info_body'.tr(),
          style: const TextStyle(fontSize: 13, height: 1.4),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(dlg),
            child: Text('common_understood'.tr()),
          ),
        ],
      ),
    );
  }

  Future<void> _openSignature(String slot) async {
    final titles = {
      'clientStart': 'cr_sig_title_client_start'.tr(),
      'techStart': 'cr_sig_title_tech_start'.tr(),
      'clientEnd': 'cr_sig_title_client_end'.tr(),
      'techEnd': 'cr_sig_title_tech_end'.tr(),
    };
    final existing = {
      'clientStart': _sigClientStartData,
      'techStart': _sigTechStartData,
      'clientEnd': _sigClientData,
      'techEnd': _sigTechData,
    };
    final bytes = await Navigator.of(context).push<List<int>>(
      MaterialPageRoute(
        builder: (_) => SignatureScreen(
          title: titles[slot]!,
          existingData: existing[slot],
        ),
      ),
    );
    if (bytes != null) {
      final encoded = base64Encode(bytes);
      setState(() {
        switch (slot) {
          case 'clientStart': _sigClientStartData = encoded;
          case 'techStart':   _sigTechStartData = encoded;
          case 'clientEnd':   _sigClientData = encoded;
          case 'techEnd':     _sigTechData = encoded;
        }
        _sectionExpanded[7] = true;
      });
    }
  }

  Future<void> _pickTime(bool isStart) async {
    // (2026-10-20) Sinon, à la fermeture du sélecteur, le focus revient au
    // dernier champ texte et l'écran saute vers lui.
    FocusManager.instance.primaryFocus?.unfocus();
    final now = DateTime.now();
    final initial = TimeOfDay.fromDateTime(
      isStart ? (_startTime ?? now) : (_endTime ?? now),
    );
    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
    );
    if (picked != null) {
      final base = _date;
      final dt = DateTime(
          base.year, base.month, base.day, picked.hour, picked.minute);
      setState(() {
        if (isStart) {
          _startTime = dt;
        } else {
          _endTime = dt;
        }
      });
    }
  }

  void _pickClient() {
    final clients = ref.read(clientsProvider).valueOrNull ?? [];
    if (clients.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('cr_no_client_in_directory'.tr()),
        ),
      );
      return;
    }
    showModalBottomSheet(
      context: context,
      builder: (_) => _ClientPickerSheet(
        clients: clients,
        onPick: (c) {
          setState(() {
            _clientId = c.id;
            _clientName.text = c.name;
            _clientAddress.text = c.address;
            _clientPhone.text = c.phone;
            _clientContact.text = c.contactPerson;
            _contractNumber.text = c.contractNumber;
            _clientBusinessId.text = c.businessId;
          });
        },
      ),
    );
  }

  void _addMaterial() {
    showDialog(
      context: context,
      builder: (_) => _MaterialDialog(
        onAdd: (m) => setState(() => _materials.add(m)),
      ),
    );
  }

  // (#4b) Toggle « SOUS CONTRAT ? » + section de champs libres (intitulé/valeur
  // avec « + » pour ajouter). Stockés dans report.sousContrat / report.customFields,
  // et rendus dans le PDF.
  Widget _extrasBlock() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: Text('cr_under_contract_q'.tr(),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          value: _sousContrat,
          onChanged: (v) => setState(() {
            _sousContrat = v;
            _scheduleAutoSave();
          }),
        ),
        const Divider(height: 12),
        Row(children: [
          Icon(Icons.tune, size: 16, color: AppColors.primary),
          const SizedBox(width: 6),
          Text('cr_custom_fields'.tr(),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        ]),
        Padding(
          padding: const EdgeInsets.only(top: 2, bottom: 6),
          child: Text(
            'cr_custom_fields_hint'.tr(),
            style: const TextStyle(fontSize: 11.5, color: Colors.grey),
          ),
        ),
        ..._customRows.asMap().entries.map((e) {
          final i = e.key;
          final row = e.value;
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: row.label,
                    decoration: InputDecoration(
                      isDense: true,
                      labelText: 'cr_custom_label'.tr(),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: row.value,
                    decoration: InputDecoration(
                      isDense: true,
                      labelText: 'cr_custom_value'.tr(),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  tooltip: 'cr_custom_remove'.tr(),
                  onPressed: () => setState(() {
                    _customRows.removeAt(i).dispose();
                    _scheduleAutoSave();
                  }),
                ),
              ],
            ),
          );
        }),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => setState(() {
              final r = _CFRow('', '');
              r.label.addListener(_onDirty);
              r.value.addListener(_onDirty);
              _customRows.add(r);
            }),
            icon: const Icon(Icons.add, size: 18),
            label: Text('cr_custom_add'.tr()),
          ),
        ),
      ],
    );
  }

  ReportModel _buildReport(ReportStatus status) {
    final now = DateTime.now();
    final s = ref.read(settingsProvider).valueOrNull ?? {};
    final teamState = ref.read(teamStateProvider).valueOrNull;
    // (identité par profil) Le rapport est ÉQUIPE seulement si le profil actif
    // = équipe ET qu'on a une équipe. Sinon c'est un rapport PERSO (companyId
    // null → identité perso au rendu). C'est ce qui rend le toggle « pour qui »
    // réellement effectif.
    final inTeam = teamState?.hasTeam == true &&
        ref.read(activeProfileModeProvider) == ProfileMode.equipe;
    return ReportModel(
      id: _reportId,
      reportNumber: _reportNumber,
      reportNumberFormat: _reportNumberFormat,
      clientId: _clientId,
      clientName: _clientName.text.trim(),
      clientAddress: _clientAddress.text.trim(),
      clientPhone: _clientPhone.text.trim(),
      clientContact: _clientContact.text.trim(),
      contractNumber: _contractNumber.text.trim(),
      clientBusinessId: _clientBusinessId.text.trim(),
      interventionType: _interventionType.text.trim(),
      sector: _sector,
      date: _date,
      endDate: _endDate,
      startTime: _startTime,
      endTime: _endTime,
      description: _description.text.trim(),
      observations: _observations.text.trim(),
      equipmentType: _equipmentType.text.trim(),
      equipmentBrand: _equipmentBrand.text.trim(),
      equipmentModel: _equipmentModel.text.trim(),
      equipmentSerial: _equipmentSerial.text.trim(),
      sectorFields: _sectorFields,
      photosPaths: _photos.map((x) => x.path).toList(),
      signatureClientStartData: _sigClientStartData,
      signatureTechStartData: _sigTechStartData,
      signatureClientData: _sigClientData,
      signatureTechData: _sigTechData,
      laborHours: parseLocalNumber(_laborHours.text),
      laborRate: parseLocalNumber(_laborRate.text),
      materials: List.from(_materials),
      taxRate: _taxRate,
      taxLabel: _taxLabel,
      taxMention: _taxMention,
      // (2026-10-19) Rapport d'ÉQUIPE : le nom de technicien PROPRE à l'équipe
      // (Équipe → Réglages équipe), comme sur le PDF ; avant, le nom perso partait
      // dans la liste du responsable et dans sa copie de validation.
      technicianName: (inTeam &&
              (s['team_technician_name'] ?? '').toString().trim().isNotEmpty)
          ? s['team_technician_name'].toString().trim()
          : s['technician_name']?.toString(),
      technicianId: inTeam ? ref.read(firebaseUserProvider).valueOrNull?.uid : null,
      companyId: inTeam ? teamState?.companyId : null,
      status: status,
      sousContrat: _sousContrat,
      customFields: {
        for (final r in _customRows)
          if (r.label.text.trim().isNotEmpty)
            r.label.text.trim(): r.value.text.trim(),
      },
      pdfTemplate: _existing?.pdfTemplate,
      pdfLocalPath: _existing?.pdfLocalPath,
      cloudUrl: _existing?.cloudUrl,
      // « Signé à distance » reste vrai tant que la signature client n'a pas été
      // refaite sur place.
      signedRemotely: (_existing?.signedRemotely ?? false) &&
          _sigClientData == _existing?.signatureClientData,
      aiEnhanced: (_existing?.aiEnhanced ?? false) || _aiEnhanced,
      // (2026-10-19) Le commentaire du responsable disparaissait au premier
      // enregistrement ; on le garde jusqu'au nouvel envoi.
      rejectionComment:
          status == ReportStatus.submitted ? null : _existing?.rejectionComment,
      createdAt: _existingCreatedAt ?? now,
      updatedAt: now,
    );
  }

  Future<void> _editReportNumberAndFormat(BuildContext context) async {
    final settings = ref.read(settingsProvider).valueOrNull ?? {};
    final numCtrl = TextEditingController(
        text: _reportNumber > 0 ? _reportNumber.toString() : '');

    const presets = [
      ('{num}', 'fmt_preset_simple', '001'),
      ('{year}-{num}', 'fmt_preset_annual', '2026-001'),
      ('{year}/{num}', 'fmt_preset_year_num', '2026/001'),
      ('{company}/{year}/{month}/{day}/{num}', 'fmt_preset_company_date', 'AMARIS/2026/04/23/001'),
      ('{client}-{num}', 'fmt_preset_client_num', 'DUPONT-001'),
      ('{client}/{year}/{month}/{day}/{num}', 'fmt_preset_client_date', 'DUPONT/2026/05/18/001'),
    ];

    String? fmtSelected = _reportNumberFormat;
    final isCustom = fmtSelected != null && !presets.any((p) => p.$1 == fmtSelected);
    final customCtrl = TextEditingController(text: isCustom ? fmtSelected : '');
    bool showCustom = isCustom;

    await showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setS) {
          String preview(String fmt) => PdfService.resolveReportNumber(
            numCtrl.text.isNotEmpty ? (int.tryParse(numCtrl.text) ?? 1) : (_reportNumber > 0 ? _reportNumber : 1),
            fmt,
            clientName: _clientName.text.isNotEmpty ? _clientName.text : 'Client',
            date: _date,
            technicianName: settings['technician_name'],
            companyName: ref.read(activeCompanyNameProvider).isNotEmpty
                ? ref.read(activeCompanyNameProvider)
                : settings['company_name'],
          );

          return AlertDialog(
            title: Text('fmt_num_and_format'.tr()),
            content: Scrollbar(
              thumbVisibility: true,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: numCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(labelText: 'fmt_token_num'.tr(), isDense: true),
                      autofocus: true,
                      onChanged: (_) => setS(() {}),
                    ),
                    const SizedBox(height: 16),
                    Text('fmt_format_label'.tr(), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        ChoiceChip(
                          label: Text('fmt_global_default'.tr(), style: const TextStyle(fontSize: 12)),
                          selected: fmtSelected == null && !showCustom,
                          visualDensity: VisualDensity.compact,
                          onSelected: (_) => setS(() { fmtSelected = null; showCustom = false; }),
                        ),
                        ...presets.map((p) {
                          final (value, label, _) = p;
                          return ChoiceChip(
                            label: Text(label.tr(), style: const TextStyle(fontSize: 12)),
                            selected: !showCustom && fmtSelected == value,
                            visualDensity: VisualDensity.compact,
                            onSelected: (_) => setS(() { fmtSelected = value; showCustom = false; }),
                          );
                        }),
                        ChoiceChip(
                          label: Text('fmt_custom'.tr(), style: const TextStyle(fontSize: 12)),
                          selected: showCustom,
                          visualDensity: VisualDensity.compact,
                          onSelected: (_) => setS(() => showCustom = true),
                        ),
                      ],
                    ),
                    if (!showCustom && fmtSelected != null) ...[
                      const SizedBox(height: 6),
                      Text('common_example'.tr(args: [preview(fmtSelected!)]),
                          style: const TextStyle(fontSize: 11, color: Colors.blue)),
                    ],
                    if (showCustom) ...[
                      const SizedBox(height: 8),
                      TextField(
                        controller: customCtrl,
                        decoration: const InputDecoration(hintText: '{company}/{year}/{num}', isDense: true),
                        onChanged: (_) => setS(() {}),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6, runSpacing: 4,
                        children: [
                          for (final (token, label, isSep) in [
                            ('{num}', 'fmt_token_num'.tr(), false), ('{client}', 'fmt_token_client'.tr(), false),
                            ('{company}', 'fmt_token_company'.tr(), false), ('{year}', 'fmt_token_year'.tr(), false),
                            ('{month}', 'fmt_token_month'.tr(), false), ('{day}', 'fmt_token_day'.tr(), false),
                            ('/', '/', true), ('-', '-', true), ('_', '_', true),
                          ])
                            ActionChip(
                              label: Text(label, style: TextStyle(fontSize: 11, color: isSep ? Colors.grey.shade700 : null)),
                              avatar: Icon(Icons.add, size: 14, color: isSep ? Colors.grey : null),
                              backgroundColor: isSep ? Colors.grey.shade100 : null,
                              visualDensity: VisualDensity.compact,
                              onPressed: () {
                                final sel = customCtrl.selection;
                                final text = customCtrl.text;
                                final pos = sel.isValid ? sel.baseOffset : text.length;
                                customCtrl.value = TextEditingValue(
                                  text: text.substring(0, pos) + token + text.substring(pos),
                                  selection: TextSelection.collapsed(offset: pos + token.length),
                                );
                                setS(() {});
                              },
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text('fmt_preview'.tr(args: [preview(customCtrl.text.isEmpty ? '{num}' : customCtrl.text)]),
                          style: const TextStyle(fontSize: 11, color: Colors.blue)),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: Text('common_cancel'.tr())),
              ElevatedButton(
                onPressed: () {
                  final v = int.tryParse(numCtrl.text.trim());
                  if (v != null && v > 0) {
                    setState(() => _reportNumber = v);
                    // (2026-10-14) Avertir si un autre rapport porte déjà ce n°.
                    final messenger = ScaffoldMessenger.of(context);
                    LocalDbService()
                        .isReportNumberTaken(v, exceptId: _reportId)
                        .then((taken) {
                      if (taken) {
                        messenger.showSnackBar(SnackBar(
                          content: Text('cr_number_taken'.tr(args: ['$v'])),
                          backgroundColor: Colors.orange.shade800,
                          duration: const Duration(seconds: 6),
                        ));
                      }
                    });
                  }
                  final fmt = showCustom
                      ? (customCtrl.text.trim().isEmpty ? null : customCtrl.text.trim())
                      : fmtSelected;
                  setState(() => _reportNumberFormat = fmt);
                  Navigator.pop(ctx);
                },
                child: const Text('OK'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<bool> _guard() async {
    final result = await KillSwitchService.check();
    if (result.allowed) return true;
    if (!mounted) return false;
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text('service_unavailable_title'.tr()),
        content: Text(result.message),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: Text('common_close'.tr())),
        ],
      ),
    );
    return false;
  }

  Future<void> _saveAsDraft() async {
    if (!await _guard()) return;
    if (!mounted) return;
    final (tokenBlocked, tokenMsg) = await InstanceTokenGuard.check();
    if (tokenBlocked) {
      if (mounted) await InstanceTokenGuard.showBlockedDialog(context, tokenMsg);
      return;
    }
    // (A) Un brouillon doit pouvoir s'enregistrer avec AU MOINS UNE info (pas
    // forcément le client). Sinon rien à enregistrer → on prévient et on sort.
    if (!_hasAnyContent()) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('cr_save_need_info'.tr())),
      );
      return;
    }
    setState(() => _isSaving = true);
    _clearAutosave();
    await ref
        .read(reportsProvider.notifier)
        .saveReport(_buildReport(ReportStatus.draft));
    setState(() => _isSaving = false);
    _clearAutosave();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('cr_report_saved'.tr()),
          backgroundColor: AppColors.success,
        ),
      );
      context.go('/home');
    }
  }

  Future<void> _submit() async {
    if (!await _guard()) return;
    if (!mounted) return;
    final (tokenBlocked, tokenMsg) = await InstanceTokenGuard.check();
    if (tokenBlocked) {
      if (mounted) await InstanceTokenGuard.showBlockedDialog(context, tokenMsg);
      return;
    }
    if (!_formKey.currentState!.validate()) {
      final clientErr = _clientName.text.trim().isEmpty;
      final travauxErr = _description.text.trim().isEmpty;
      setState(() {
        _clientSectionError = clientErr;
        _travauxSectionError = travauxErr;
        if (clientErr) _sectionExpanded[1] = true;
        if (travauxErr) _sectionExpanded[5] = true;
      });
      // (2026-10-20) Défile jusqu'au 1er champ manquant : avant, l'écran restait
      // où il était → « Envoyer » semblait ne rien faire quand la description
      // (plus bas) était vide (vu au test équipe sur émulateur).
      if (clientErr || travauxErr) _scrollToNav(clientErr ? 1 : 5);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('cr_required_fields_missing'.tr()),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
      return;
    }
    setState(() {
      _clientSectionError = false;
      _travauxSectionError = false;
    });
    setState(() => _isSaving = true);
    _clearAutosave(); // (2026-10-19) un auto-save en attente écrasait l'envoi
    final report = _buildReport(ReportStatus.submitted);
    await ref.read(reportsProvider.notifier).saveReport(report);
    final s = ref.read(settingsProvider).valueOrNull ?? {};
    final user = ref.read(firebaseUserProvider).valueOrNull;
    AnalyticsService.log(
      event: 'report_submitted',
      userUid: user?.uid,
      userName: user?.displayName,
      clientName: report.clientName,
      // (monitoring) identité réelle du rapport : équipe si rapport d'équipe,
      // sinon l'entreprise perso. + companyId/isTeamReport pour les stats par équipe.
      companyName: report.companyId != null
          ? ref.read(activeCompanyNameProvider)
          : s['company_name'],
      technicianName: s['technician_name'],
      reportNumber: report.reportNumber,
      sector: report.sector.label,
      interventionType: report.interventionType,
      companyId: report.companyId,
      isTeamReport: report.companyId != null,
    );
    // Sync to team Firestore if in team mode
    final teamState = ref.read(teamStateProvider).valueOrNull;
    // (2026-10-19) Seulement un rapport D'ÉQUIPE de CETTE équipe : un rapport
    // PERSO (profil perso) partait aussi chez le responsable.
    if (teamState != null &&
        teamState.hasTeam &&
        report.companyId == teamState.companyId) {
      try {
        await TeamService().syncReport(teamState.companyId!, report);
      } catch (_) {
        // Non-fatal — report is saved locally, sync can retry later
      }
    }
    setState(() => _isSaving = false);
    _clearAutosave();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('cr_report_submitted'.tr()),
          backgroundColor: AppColors.statusSubmitted,
        ),
      );
      // (Q) On atterrit sur la PAGE DE GESTION du rapport (édition, partage,
      // envoi cloud…). Retour = liste des rapports.
      context.go('/home');
      context.push('/report/${report.id}');
    }
  }

  Future<void> _saveAsClient() async {
    if (_clientName.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('cr_enter_client_first'.tr())),
      );
      return;
    }
    final now = DateTime.now();
    final client = ClientModel(
      id: const Uuid().v4(),
      name: _clientName.text.trim(),
      address: _clientAddress.text.trim(),
      phone: _clientPhone.text.trim(),
      contactPerson: _clientContact.text.trim(),
      contractNumber: _contractNumber.text.trim(),
      businessId: _clientBusinessId.text.trim(),
      createdAt: now,
      updatedAt: now,
    );
    await ref.read(clientsProvider.notifier).saveClient(client);
    // (2026-10-19) Le rapport est rattaché au client créé : avant, il restait
    // sans lien → l'historique de ce client n'affichait pas ce rapport.
    if (mounted) setState(() => _clientId = client.id);
    _scheduleAutoSave();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('cr_client_added'.tr(args: [client.name])),
          backgroundColor: AppColors.success,
        ),
      );
    }
  }

  // ─── Presets ────────────────────────────────────────────────────────────────

  // (2026-10-19) _currentPresetData() (ancien format camelCase) retiré :
  // les modèles utilisent ReportPreset.fromReport (relu par ReportPreset.reportData).

  // (C) Icône grisée + pastille « PRO » quand l'utilisateur n'est pas abonné.
  Widget _proIcon(IconData icon, bool isPro) {
    if (isPro) return Icon(icon);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Icon(icon, color: Colors.white60),
        Positioned(
          right: -7,
          top: -5,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
            decoration: BoxDecoration(
              color: Colors.amber.shade700,
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Text('PRO',
                style: TextStyle(
                    fontSize: 7,
                    fontWeight: FontWeight.bold,
                    color: Colors.white)),
          ),
        ),
      ],
    );
  }

  // (C) Dialog « réservé Pro » → propose d'ouvrir le paywall.
  void _showProRequired(String feature) {
    showDialog<void>(
      context: context,
      builder: (dlg) => AlertDialog(
        icon: const Icon(Icons.workspace_premium_outlined,
            color: AppColors.primary),
        title: Text(feature),
        content: Text('cr_templates_pro_body'.tr()),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dlg),
              child: Text('common_later'.tr())),
          FilledButton(
            onPressed: () {
              Navigator.pop(dlg);
              PaywallBottomSheet.show(context, reason: feature);
            },
            child: Text('ar_see_pro'.tr()),
          ),
        ],
      ),
    );
  }

  Future<void> _saveAsPreset() async {
    String name = '';
    final ok = await showDialog<bool>(
      context: context,
      builder: (dlg) => AlertDialog(
        title: Text('cr_save_template'.tr()),
        content: TextField(
          autofocus: true,
          decoration: InputDecoration(
            labelText: 'rd_template_name'.tr(),
            hintText: 'cr_template_name_hint'.tr(),
          ),
          onChanged: (v) => name = v,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dlg, false), child: Text('common_cancel'.tr())),
          TextButton(onPressed: () => Navigator.pop(dlg, true), child: Text('common_save'.tr())),
        ],
      ),
    );
    if (ok != true || name.trim().isEmpty) return;
    final preset = ReportPreset(
      id: const Uuid().v4(),
      name: name.trim(),
      createdAt: DateTime.now(),
      // (2026-10-19) Format unique (celui de la fiche du rapport) : relu partout,
      // et garde aussi le matériel, les champs libres, « sous contrat ».
      data: ReportPreset.fromReport(_buildReport(ReportStatus.draft)),
    );
    await LocalDbService().savePreset(preset);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('rd_template_saved'.tr(args: [preset.name])), backgroundColor: AppColors.success),
      );
    }
  }

  Future<void> _loadPreset() async {
    final presets = await LocalDbService().getAllPresets();
    if (!mounted) return;
    if (presets.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('cr_no_templates_saved'.tr())),
      );
      return;
    }
    final chosen = await showDialog<ReportPreset>(
      context: context,
      builder: (_) => SimpleDialog(
        title: Text('cr_load_template'.tr()),
        children: [
          for (final p in presets)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, p),
              child: Row(
                children: [
                  Expanded(child: Text(p.name)),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                    onPressed: () async {
                      await LocalDbService().deletePreset(p.id);
                      // ignore: use_build_context_synchronously
                      if (context.mounted) Navigator.pop(context);
                    },
                  ),
                ],
              ),
            ),
        ],
      ),
    );
    if (chosen == null) return;
    // (2026-10-19) Lecture unique, les 2 formats (avant : seuls les modèles du
    // formulaire se chargeaient ici ; ceux de la fiche du rapport : formulaire vide).
    // (2026-10-20) Sans les infos du client du modèle (on garde celles saisies).
    _fillFromTemplate(ReportPreset.forNewReport(chosen.data), resetBaseline: false);
    _scheduleAutoSave();
  }

  // ─── Section nav ─────────────────────────────────────────────────────────────
  // Design decisions (permanent — not debug-only):
  // • Multi-highlight: all pills whose section header is visible on screen
  //   are highlighted simultaneously, so the user always knows where they are.
  // • Extra bottom padding (300 px): allows the last sections to scroll past
  //   the highlight threshold so their pills can become active.
  // • Pill bar auto-scroll: whenever the active set changes, the pill bar
  //   scrolls to keep the first highlighted pill in view, solving the dead-zone
  //   where early pills were scrolled off-screen and couldn't be tapped.

  void _updateActiveNav() {
    const threshold = 150.0;
    const navKeyOrder = [0, 1, 2, 3, 5, 6, 7, 8];

    int found = navKeyOrder.first;
    final viewportHeight =
        _scroll.hasClients ? _scroll.position.viewportDimension : 600.0;
    final newVisible = <int>{};

    for (final idx in navKeyOrder) {
      final ctx = _navKeys[idx].currentContext;
      if (ctx == null) continue;
      final box = ctx.findRenderObject() as RenderBox?;
      if (box == null || !box.attached) continue;
      final top = box.localToGlobal(Offset.zero).dy;
      if (top <= threshold) found = idx;
      if (top >= 0 && top <= viewportHeight) newVisible.add(idx);
    }

    final nextVisible = newVisible.isEmpty ? {found} : newVisible;
    if (nextVisible != _visibleNavSet) {
      setState(() {
        _visibleNavSet = nextVisible;
      });
      // Auto-scroll pill bar to show the first highlighted pill.
      final firstVisible = navKeyOrder.firstWhere(
          (idx) => nextVisible.contains(idx),
          orElse: () => found);
      final pillCtx = _pillKeys[firstVisible].currentContext;
      if (pillCtx != null) {
        Scrollable.ensureVisible(pillCtx,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            alignment: 0.0);
      }
    }
  }

  void _scrollToNav(int keyIdx) {
    // (2026-10-20) Un champ texte resté actif (clavier fermé) ramenait l'écran
    // vers lui juste après le défilement : le bouton de section « ne marchait
    // pas » (vu au test sur émulateur : « Travaux », « Signatures »).
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _visibleNavSet = {keyIdx};
      _sectionExpanded[keyIdx] = true;
    });
    // Defer scrolls to the post-frame so the section has time to expand
    // before ensureVisible tries to locate it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final pillCtx = _pillKeys[keyIdx].currentContext;
      if (pillCtx != null) {
        Scrollable.ensureVisible(pillCtx,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            alignment: 0.3);
      }
      final ctx = _navKeys[keyIdx].currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(ctx,
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeInOut);
      }
    });
  }

  PreferredSizeWidget _buildNavBar() {
    final items = [
      (0, Icons.category_outlined, 'cr_nav_type'.tr()),
      (1, Icons.person_outline, 'cr_nav_client'.tr()),
      (2, Icons.build_outlined, 'cr_nav_mission'.tr()),
      (3, Icons.settings_outlined, 'cr_nav_equip'.tr()),
      (5, Icons.description_outlined, 'cr_nav_work'.tr()),
      (6, Icons.photo_camera_outlined, 'cr_nav_photos'.tr()),
      (7, Icons.draw_outlined, 'cr_nav_signatures'.tr()),
      (8, Icons.receipt_outlined, 'cr_nav_billing'.tr()),
    ];
    return PreferredSize(
      preferredSize: const Size.fromHeight(44),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
        child: Row(
          children: items.map((item) {
            final (keyIdx, icon, label) = item;
            // Multi-highlight: show all currently visible sections as active.
            final active = _visibleNavSet.contains(keyIdx);
            return Padding(
              key: _pillKeys[keyIdx], // used by auto-scroll to bring pill into view
              padding: const EdgeInsets.only(right: 6),
              child: GestureDetector(
                onTap: () => _scrollToNav(keyIdx),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: active
                        ? Colors.white.withValues(alpha: 0.2)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: active
                          ? Colors.white
                          : Colors.white.withValues(alpha: 0.4),
                      width: active ? 1.5 : 1.0,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon,
                          size: 13,
                          color: active
                              ? Colors.white
                              : Colors.white.withValues(alpha: 0.7)),
                      const SizedBox(width: 4),
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 11,
                          color: active
                              ? Colors.white
                              : Colors.white.withValues(alpha: 0.7),
                          fontWeight:
                              active ? FontWeight.w600 : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  bool _isExpanded(int idx) => _sectionExpanded[idx] ?? false;
  void _toggleSection(int idx) =>
      setState(() => _sectionExpanded[idx] = !_isExpanded(idx));

  // ─── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final settings = ref.watch(settingsProvider).valueOrNull ?? {};
    // (devise) Pose la devise courante (globale) pour les helpers formatMoney du
    // formulaire (totaux, matériaux, libellé €/h) → suit le pays/réglage.
    appCurrencyCode = resolveCurrencyCode(
      settings,
      region: WidgetsBinding.instance.platformDispatcher.locale.countryCode,
      language: context.locale.languageCode,
    );
    // (C) Les MODÈLES sont réservés au Pro (comme facture / signature distante).
    final isPro = ref.watch(effectiveSubscriptionProvider);
    final globalFmt = settings['report_number_format']?.toString() ?? '{num}';
    final fmt = _reportNumberFormat ?? globalFmt;
    final resolvedNum = _reportNumber > 0
        ? PdfService.resolveReportNumber(
            _reportNumber,
            fmt,
            clientName: _clientName.text.trim().isNotEmpty ? _clientName.text.trim() : null,
            date: _date,
            technicianName: settings['technician_name']?.toString(),
            companyName: ref.read(activeCompanyNameProvider).isNotEmpty
                ? ref.read(activeCompanyNameProvider)
                : settings['company_name']?.toString(),
          )
        : null;
    final appBarLabel = _isEditMode
        ? 'cr_edit_prefix'.tr(args: ['${resolvedNum ?? '#${_reportNumber.toString().padLeft(3, '0')}'}'])
        : resolvedNum ?? 'rl_new_report'.tr();

    return Scaffold(
      appBar: AppBar(
        title: GestureDetector(
          onTap: () => _editReportNumberAndFormat(context),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(child: Text(appBarLabel, overflow: TextOverflow.ellipsis)),
              const SizedBox(width: 4),
              const Icon(Icons.edit, size: 14, color: Colors.white54),
            ],
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf_outlined),
            tooltip: 'cr_pdf_preview'.tr(),
            onPressed: _isSaving ? null : _previewCurrentPdf,
          ),
          IconButton(
            icon: _proIcon(Icons.folder_open_outlined, isPro),
            tooltip: 'cr_load_template'.tr(),
            onPressed:
                isPro ? _loadPreset : () => _showProRequired('cr_load_template'.tr()),
          ),
          IconButton(
            icon: _proIcon(Icons.bookmark_add_outlined, isPro),
            tooltip: 'cr_save_template'.tr(),
            onPressed: isPro
                ? _saveAsPreset
                : () => _showProRequired('cr_save_template'.tr()),
          ),
          TextButton.icon(
            onPressed: _isSaving ? null : _saveAsDraft,
            icon: const Icon(Icons.save_outlined, color: Colors.white),
            label: Text('cr_draft'.tr(),
                style: const TextStyle(color: Colors.white)),
          ),
        ],
        bottom: _buildNavBar(),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: ElevatedButton.icon(
            onPressed: _isSaving ? null : _submit,
            icon: _isSaving
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.send),
            label: Text('cr_submit_report'.tr()),
          ),
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          controller: _scroll,
          // (2026-10-20) Toutes les sections construites d'emblée (≈ 10, léger) :
          // une ListView ne construit que ce qui est près de l'écran → les
          // boutons de section vers une section lointaine (Travaux, Signatures…)
          // ne trouvaient pas leur cible et ne faisaient rien, et la validation
          // ignorait les champs des sections non construites. Vu sur émulateur.
          cacheExtent: 100000,
          padding: const EdgeInsets.all(16),
          children: [
            // (#8) Sélecteur d'identité réactivé — RÉUTILISE le système existant
            // (activeProfileProvider), aucun nouveau mécanisme. Affiché UNIQUEMENT
            // si l'utilisateur a réellement 2 profils (solo + équipe) ; sinon
            // l'identité suit automatiquement le seul profil dispo (zéro friction
            // pour les utilisateurs solo).
            if (ref.watch(canSwitchProfileProvider))
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: _ReportIdentityToggle(),
              ),

            // (#3 / Option 1) Bandeau « Mon entreprise » UNIQUEMENT pour les solos
            // purs (qui n'ont PAS le toggle). Dès qu'il y a une équipe, le toggle
            // ci-dessus EST le contrôle d'identité (il affiche l'identité active +
            // un ⚠️ orange si vide + le lien d'édition) → on évite le doublon
            // bandeau+toggle. `!canSwitchProfile` ≡ pas d'équipe ≡ profil perso forcé.
            if (!ref.watch(canSwitchProfileProvider))
              const _SoloIdentityBanner(),

            _CollapsibleSection(
              key: _navKeys[0],
              title: 'cr_section_type'.tr(),
              icon: Icons.category_outlined,
              expanded: _isExpanded(0),
              onToggle: () => _toggleSection(0),
              child: _SectorSelector(
                selected: _sector,
                onChanged: (s) => setState(() { _sector = s; _sectorFields = {}; }),
              ),
            ),

            _CollapsibleSection(
              key: _navKeys[1],
              title: 'cr_section_client'.tr(),
              icon: Icons.person_outline,
              expanded: _isExpanded(1),
              onToggle: () => _toggleSection(1),
              hasError: _clientSectionError,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  OutlinedButton.icon(
                    onPressed: _pickClient,
                    icon: const Icon(Icons.contacts_outlined, size: 18),
                    label: Text('cr_pick_from_directory'.tr()),
                  ),
                  const SizedBox(height: 10),
                  _Field(
                    controller: _clientName,
                    label: 'cr_client_name_required'.tr(),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'cr_required'.tr() : null,
                  ),
                  _Field(controller: _clientAddress, label: 'field_address'.tr()),
                  _Field(controller: _clientPhone, label: 'cr_phone'.tr(), keyboardType: TextInputType.phone),
                  _Field(controller: _clientContact, label: 'cr_contact_onsite'.tr()),
                  _Field(controller: _contractNumber, label: 'cr_contract_number'.tr()),
                  _Field(controller: _clientBusinessId, label: 'cr_client_business_id'.tr()),
                  _extrasBlock(),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: _saveAsClient,
                      icon: const Icon(Icons.person_add_outlined, size: 16),
                      label: Text('cr_save_to_directory'.tr(), style: const TextStyle(fontSize: 12)),
                    ),
                  ),
                ],
              ),
            ),

            _CollapsibleSection(
              key: _navKeys[2],
              title: 'cr_section_intervention'.tr(),
              icon: Icons.build_outlined,
              expanded: _isExpanded(2),
              onToggle: () => _toggleSection(2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Field(controller: _interventionType, label: 'cr_intervention_type'.tr()),
                  // (2026-10-14) Si le début passe après la fin, la fin suit.
                  _DateTile(
                      date: _date,
                      onChanged: (d) => setState(() {
                            _date = d;
                            if (_endDate != null && _endDate!.isBefore(d)) _endDate = d;
                          })),
                  Row(
                    children: [
                      Expanded(
                        child: _endDate != null
                            ? _DateTile(
                                label: 'cr_end_date'.tr(),
                                date: _endDate!,
                                // fin jamais avant le début
                                firstDate: _date,
                                onChanged: (d) => setState(() => _endDate = d),
                              )
                            : TextButton.icon(
                                onPressed: () => setState(() => _endDate = _date),
                                icon: const Icon(Icons.date_range, size: 16),
                                label: Text('cr_multiday'.tr(), style: const TextStyle(fontSize: 12)),
                              ),
                      ),
                      if (_endDate != null)
                        IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          tooltip: 'cr_remove_end_date'.tr(),
                          onPressed: () => setState(() => _endDate = null),
                        ),
                    ],
                  ),
                  Row(
                    children: [
                      Expanded(child: _TimeTile(label: 'cr_time_start'.tr(), time: _startTime, onTap: () => _pickTime(true), onClear: _startTime != null ? () => _clearTime(true) : null)),
                      const SizedBox(width: 10),
                      Expanded(child: _TimeTile(label: 'cr_time_end'.tr(), time: _endTime, onTap: () => _pickTime(false), onClear: _endTime != null ? () => _clearTime(false) : null)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    children: [
                      for (final e in [('cr_now'.tr(), 0), ('−15 min', 15), ('−30 min', 30), ('−1 h', 60)])
                        ActionChip(
                          label: Text(e.$1),
                          onPressed: () => _setStartTimeOffset(e.$2),
                          visualDensity: VisualDensity.compact,
                          backgroundColor: AppColors.primary.withValues(alpha: 0.08),
                          labelStyle: const TextStyle(color: AppColors.primary, fontSize: 11),
                          padding: const EdgeInsets.symmetric(horizontal: 2),
                        ),
                    ],
                  ),
                ],
              ),
            ),

            _CollapsibleSection(
              key: _navKeys[3],
              title: 'cr_section_equipment'.tr(),
              icon: Icons.settings_outlined,
              expanded: _isExpanded(3),
              onToggle: () => _toggleSection(3),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Field(controller: _equipmentType, label: 'cr_equipment_type'.tr()),
                  Row(
                    children: [
                      Expanded(child: _Field(controller: _equipmentBrand, label: 'cr_brand'.tr())),
                      const SizedBox(width: 10),
                      Expanded(child: _Field(controller: _equipmentModel, label: 'cr_model'.tr())),
                    ],
                  ),
                  _Field(controller: _equipmentSerial, label: 'cr_serial'.tr()),
                ],
              ),
            ),

            if (_sector != SectorTemplate.generic)
              _CollapsibleSection(
                key: _navKeys[4],
                title: _sector.label,
                icon: Icons.tune_outlined,
                expanded: _isExpanded(4),
                onToggle: () => _toggleSection(4),
                child: _SectorSpecificFields(
                  sector: _sector,
                  fields: _sectorFields,
                  onChanged: (f) => setState(() => _sectorFields = f),
                ),
              ),

            _CollapsibleSection(
              key: _navKeys[5],
              title: 'cr_section_work'.tr(),
              icon: Icons.description_outlined,
              expanded: _isExpanded(5),
              onToggle: () => _toggleSection(5),
              hasError: _travauxSectionError,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Field(controller: _description, label: 'cr_work_description_required'.tr(), maxLines: 5,
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'cr_required'.tr() : null),
                  _Field(controller: _observations, label: 'cr_observations'.tr(), maxLines: 3),
                ],
              ),
            ),

            _CollapsibleSection(
              key: _navKeys[6],
              title: 'cr_nav_photos'.tr(),
              icon: Icons.photo_camera_outlined,
              expanded: _isExpanded(6),
              onToggle: () => _toggleSection(6),
              child: PhotoPickerWidget(
                photos: _photos,
                // (2026-10-14) Copie en stockage PERMANENT : le sélecteur dépose
                // la photo dans le cache, que le système vide → photos perdues.
                onAdd: (xFile) async {
                  final kept = await PhotoStorage.persist(xFile.path);
                  if (!mounted) return;
                  setState(() {
                    _photos.add(XFile(kept));
                    _sectionExpanded[6] = true;
                  });
                },
                onRemove: (i) => setState(() => _photos.removeAt(i)),
              ),
            ),

            _CollapsibleSection(
              key: _navKeys[7],
              title: 'cr_nav_signatures'.tr(),
              icon: Icons.draw_outlined,
              expanded: _isExpanded(7),
              onToggle: () => _toggleSection(7),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('cr_section_signatures_start'.tr(),
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(child: _SignatureButton(
                        b64Data: _sigClientStartData,
                        label: 'cr_sig_client_start'.tr(),
                        onTap: () => _openSignature('clientStart'),
                        onClear: _sigClientStartData != null ? () => setState(() => _sigClientStartData = null) : null,
                      )),
                      const SizedBox(width: 12),
                      Expanded(child: _SignatureButton(
                        b64Data: _sigTechStartData,
                        label: 'cr_sig_tech_start'.tr(),
                        onTap: () => _openSignature('techStart'),
                        onClear: _sigTechStartData != null ? () => setState(() => _sigTechStartData = null) : null,
                      )),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text('cr_section_signatures_end'.tr(),
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(child: _SignatureButton(
                        b64Data: _sigClientData,
                        label: 'cr_sig_client_end'.tr(),
                        onTap: () => _openSignature('clientEnd'),
                        onClear: _sigClientData != null ? () => setState(() => _sigClientData = null) : null,
                      )),
                      const SizedBox(width: 12),
                      Expanded(child: _SignatureButton(
                        b64Data: _sigTechData,
                        label: 'cr_sig_tech_end'.tr(),
                        onTap: () => _openSignature('techEnd'),
                        onClear: _sigTechData != null ? () => setState(() => _sigTechData = null) : null,
                      )),
                    ],
                  ),
                  // (b) Signature à distance du client — bouton informatif qui ne
                  // COUPE PAS l'élan : il ouvre juste une explication (la vraie
                  // action se fait après l'envoi, depuis la page de gestion).
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _showRemoteSignatureInfo,
                      icon: const Icon(Icons.send_to_mobile_outlined, size: 18),
                      label: Text('cr_remote_sign_btn'.tr()),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        side: BorderSide(
                            color: AppColors.primary.withValues(alpha: 0.4)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'cr_remote_sign_hint'.tr(),
                    style:
                        TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),

            _CollapsibleSection(
              key: _navKeys[8],
              title: 'cr_section_billing'.tr(),
              icon: Icons.receipt_outlined,
              expanded: _isExpanded(8),
              onToggle: () => _toggleSection(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: _Field(controller: _laborHours, label: 'cr_labor_hours'.tr(), keyboardType: const TextInputType.numberWithOptions(decimal: true))),
                      const SizedBox(width: 10),
                      Expanded(child: _Field(controller: _laborRate, label: 'cr_hourly_rate'.tr(args: [currencySymbolOf(appCurrencyCode)]), keyboardType: const TextInputType.numberWithOptions(decimal: true))),
                    ],
                  ),
                  if (_materials.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    ..._materials.asMap().entries.map((e) => _MaterialTile(item: e.value, onRemove: () => _removeMaterial(e.key))),
                  ],
                  OutlinedButton.icon(
                    onPressed: _addMaterial,
                    icon: const Icon(Icons.add, size: 18),
                    label: Text('cr_add_material'.tr()),
                  ),
                  // (Taxe) Override de taxe POUR CE RAPPORT. Pré-rempli avec le
                  // défaut global des Réglages ; éditable (pays/taux/mention).
                  Builder(builder: (context) {
                    final region = WidgetsBinding
                        .instance.platformDispatcher.locale.countryCode;
                    final language = context.locale.languageCode;
                    final cfg = resolveReportTax(settings,
                        reportRate: _taxRate,
                        reportLabel: _taxLabel,
                        reportMention: _taxMention,
                        region: region,
                        language: language);
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.percent,
                          color: AppColors.primary),
                      title: Text('tax_for_report'.tr()),
                      subtitle: Text(
                          '${cfg.label} ${formatTaxRate(cfg.rate)} %',
                          style: const TextStyle(fontSize: 12)),
                      trailing: const Icon(Icons.chevron_right,
                          size: 18, color: Colors.grey),
                      onTap: () async {
                        // Pour un rapport, « Réinitialiser » ramène au défaut
                        // GLOBAL (Réglages), pas au défaut brut de la locale.
                        final globalDefault = resolveGlobalTax(settings,
                            region: region, language: language);
                        final result = await showTaxEditor(context,
                            initial: cfg, localeDefault: globalDefault);
                        if (result != null) {
                          setState(() {
                            _taxRate = result.rate;
                            _taxLabel = result.label;
                            _taxMention = result.mention;
                          });
                          _onDirty();
                        }
                      },
                    );
                  }),
                  // (2026-10-19) Recalculé à CHAQUE frappe (heures / taux) : avant,
                  // le total ne suivait que la 1re lettre tapée (pas de rebuild).
                  ListenableBuilder(
                    listenable: Listenable.merge([_laborHours, _laborRate]),
                    builder: (context, _) =>
                        (_laborHours.text.isNotEmpty || _materials.isNotEmpty)
                            ? Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: _TotalPreview(
                                  hours: parseLocalNumber(_laborHours.text) ?? 0,
                                  rate: parseLocalNumber(_laborRate.text) ?? 0,
                                  materials: _materials,
                                ),
                              )
                            : const SizedBox.shrink(),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 8),
            // Extra padding so the last sections (Photos, Signatures, Facturation)
            // can scroll up past the pill highlight threshold. Without this,
            // the bottom sections can never reach the top of the viewport and
            // their pills would never become active.
            const SizedBox(height: 300),
          ],
        ),
      ),
    );
  }
}

// ─── Client picker bottom sheet ──────────────────────────────────────────────

class _ClientPickerSheet extends StatelessWidget {
  final List<ClientModel> clients;
  final void Function(ClientModel) onPick;

  const _ClientPickerSheet(
      {required this.clients, required this.onPick});

  @override
  Widget build(BuildContext context) => ListView.builder(
        shrinkWrap: true,
        padding: const EdgeInsets.only(top: 8, bottom: 24),
        itemCount: clients.length + 1,
        itemBuilder: (_, i) {
          if (i == 0) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Text('cr_pick_a_client'.tr(),
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 16)),
            );
          }
          final c = clients[i - 1];
          return ListTile(
            leading: CircleAvatar(
              backgroundColor:
                  AppColors.primary.withValues(alpha: 0.12),
              child: Text(
                c.name.trim().isNotEmpty ? c.name.trim()[0].toUpperCase() : '?',
                style: const TextStyle(color: AppColors.primary),
              ),
            ),
            title: Text(c.name),
            subtitle: c.phone.isNotEmpty ? Text(c.phone) : null,
            onTap: () {
              onPick(c);
              Navigator.pop(context);
            },
          );
        },
      );
}

// ─── Material dialog ─────────────────────────────────────────────────────────

class _MaterialDialog extends StatefulWidget {
  final void Function(MaterialItem) onAdd;
  const _MaterialDialog({required this.onAdd});

  @override
  State<_MaterialDialog> createState() => _MaterialDialogState();
}

class _MaterialDialogState extends State<_MaterialDialog> {
  final _label = TextEditingController();
  final _ref = TextEditingController();
  final _qty = TextEditingController(text: '1');
  final _price = TextEditingController();

  @override
  void dispose() {
    for (final c in [_label, _ref, _qty, _price]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text('md_title'.tr()),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _label,
                decoration:
                    InputDecoration(labelText: 'md_designation'.tr()),
                autofocus: true,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _ref,
                decoration: InputDecoration(labelText: 'md_reference'.tr()),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  // FR3 — stepper for quantity
                  IconButton(
                    icon: const Icon(Icons.remove_circle_outline,
                        color: AppColors.primary),
                    onPressed: () {
                      final v = (parseLocalNumber(_qty.text) ??
                              1)
                          .toInt();
                      if (v > 1) setState(() => _qty.text = '${v - 1}');
                    },
                  ),
                  Expanded(
                    child: TextField(
                      controller: _qty,
                      textAlign: TextAlign.center,
                      decoration: InputDecoration(labelText: 'md_qty'.tr()),
                      // decimal: true → touche virgule sur iPhone (2,5 m de tube…)
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline,
                        color: AppColors.primary),
                    onPressed: () {
                      final v = (parseLocalNumber(_qty.text) ??
                              1)
                          .toInt();
                      setState(() => _qty.text = '${v + 1}');
                    },
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: TextField(
                      controller: _price,
                      decoration:
                          InputDecoration(labelText: 'md_unit_price'.tr(args: [currencySymbolOf(appCurrencyCode)])),
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('common_cancel'.tr())),
          ElevatedButton(
            onPressed: () {
              if (_label.text.trim().isEmpty) return;
              widget.onAdd(MaterialItem(
                reference: _ref.text.trim(),
                label: _label.text.trim(),
                quantity: parseLocalNumber(_qty.text) ??
                    1,
                unitPrice: parseLocalNumber(_price.text) ??
                    0,
              ));
              Navigator.pop(context);
            },
            child: Text('common_add'.tr()),
          ),
        ],
      );
}

// ─── Material tile ────────────────────────────────────────────────────────────

class _MaterialTile extends StatelessWidget {
  final MaterialItem item;
  final VoidCallback onRemove;

  const _MaterialTile({required this.item, required this.onRemove});

  @override
  Widget build(BuildContext context) => ListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        title: Text(item.label,
            style: const TextStyle(fontSize: 13)),
        subtitle: item.reference.isNotEmpty
            ? Text('mt_ref_prefix'.tr(args: [item.reference]),
                style: const TextStyle(fontSize: 11))
            : null,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${item.quantity} × ${formatMoney(item.unitPrice)} = '
              '${formatMoney(item.total)}',
              style: const TextStyle(fontSize: 12),
            ),
            IconButton(
              icon:
                  const Icon(Icons.delete_outline, size: 18, color: Colors.red),
              onPressed: onRemove,
            ),
          ],
        ),
      );
}

// ─── Total preview ────────────────────────────────────────────────────────────

class _TotalPreview extends StatelessWidget {
  final double hours;
  final double rate;
  final List<MaterialItem> materials;

  const _TotalPreview(
      {required this.hours,
      required this.rate,
      required this.materials});

  @override
  Widget build(BuildContext context) {
    // (2026-10-19) Mêmes arrondis que la facture (PdfService.invoiceTotals) :
    // sinon 1 centime d'écart possible entre l'aperçu et la facture.
    final labor = roundMoney(hours * rate);
    final matTotal =
        materials.fold<double>(0, (acc, m) => acc + roundMoney(m.total));
    final total = roundMoney(labor + matTotal);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
        border:
            Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          if (hours > 0)
            _TotalRow('cr_labor'.tr(),
                '${formatQuantity(hours)} h × ${formatMoney(rate)}/h',
                labor),
          if (matTotal > 0) _TotalRow('cr_materials'.tr(), '', matTotal),
          const Divider(height: 12),
          _TotalRow('cr_total_ht'.tr(), '', total, bold: true),
        ],
      ),
    );
  }
}

class _TotalRow extends StatelessWidget {
  final String label;
  final String detail;
  final double amount;
  final bool bold;

  const _TotalRow(this.label, this.detail, this.amount,
      {this.bold = false});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Expanded(
              child: Text(
                detail.isEmpty ? label : '$label  ($detail)',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight:
                      bold ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
            Text(
              formatMoney(amount),
              style: TextStyle(
                fontSize: 13,
                fontWeight: bold ? FontWeight.bold : FontWeight.normal,
                color: bold ? AppColors.primary : Colors.black87,
              ),
            ),
          ],
        ),
      );
}

// ─── Sector-specific fields ───────────────────────────────────────────────────

class _SectorSpecificFields extends StatelessWidget {
  final SectorTemplate sector;
  final Map<String, dynamic> fields;
  final void Function(Map<String, dynamic>) onChanged;

  const _SectorSpecificFields({
    required this.sector,
    required this.fields,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final defs = _fieldDefs(sector);
    return Column(
      children: defs.map((def) {
        if (def['type'] == 'dropdown') {
          final stored = fields[def['key']] as String?;
          final opts = def['options'] as List<String>;
          // (filet de sécurité) Si la valeur stockée n'est pas dans la liste
          // (vieux rapport non migré, clé inconnue), on l'ajoute → le dropdown
          // ne plante jamais (l'assert « value ∈ items » est respecté).
          final allOpts = (stored != null && stored.isNotEmpty && !opts.contains(stored))
              ? [...opts, stored]
              : opts;
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: DropdownButtonFormField<String>(
              initialValue: (stored?.isEmpty == false) ? stored : null,
              decoration:
                  InputDecoration(labelText: def['label'] as String),
              // value = CLÉ stable, affichage = libellé traduit.
              items: allOpts
                  .map((o) =>
                      DropdownMenuItem(value: o, child: Text(sectorValueLabel(o))))
                  .toList(),
              onChanged: (v) {
                final updated = Map<String, dynamic>.from(fields);
                updated[def['key'] as String] = v ?? '';
                onChanged(updated);
              },
            ),
          );
        }
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: TextFormField(
            initialValue: fields[def['key']] as String? ?? '',
            decoration:
                InputDecoration(labelText: def['label'] as String),
            keyboardType: def['numeric'] == true
                ? const TextInputType.numberWithOptions(decimal: true)
                : null,
            onChanged: (v) {
              final updated = Map<String, dynamic>.from(fields);
              updated[def['key'] as String] = v;
              onChanged(updated);
            },
          ),
        );
      }).toList(),
    );
  }

  // (i18n) Seuls les `label` (affichage) sont traduits. `key` (clé customFields) et
  // `options` (VALEUR stockée quand l'utilisateur sélectionne) restent en FR → traduire
  // les options orphelinerait les vieux rapports + planterait le dropdown (assert valeur∉items).
  // Refactor options = décision séparée (stocker une clé + libellé traduit + migration).
  static List<Map<String, dynamic>> _fieldDefs(SectorTemplate s) {
    switch (s) {
      case SectorTemplate.plomberie:
        return [
          {
            'key': 'type_tuyauterie',
            'label': 'sf_type_tuyauterie'.tr(),
            'type': 'dropdown',
            'options': ['pvc', 'copper', 'steel', 'pe', 'pex', 'other'],
          },
          {'key': 'diametre_mm', 'label': 'sf_diametre_mm'.tr(), 'numeric': true},
          {'key': 'longueur_m', 'label': 'sf_longueur_m'.tr(), 'numeric': true},
          {
            'key': 'pression_testee_bar',
            'label': 'sf_pression_testee'.tr(),
            'numeric': true
          },
          {'key': 'remarques_specifiques', 'label': 'sf_remarques_specifiques'.tr()},
        ];
      case SectorTemplate.incendie:
        return [
          {'key': 'reference_extincteur', 'label': 'sf_reference_extincteur'.tr()},
          {
            'key': 'type_agent',
            'label': 'sf_type_agent'.tr(),
            'type': 'dropdown',
            'options': [
              'co2',
              'powder_abc',
              'water_spray',
              'foam',
              'halon',
              'other'
            ],
          },
          {
            'key': 'pression_manometre',
            'label': 'sf_pression_manometre'.tr(),
            'numeric': true
          },
          {
            'key': 'date_prochaine_verif',
            'label': 'sf_date_prochaine_verif'.tr()
          },
        ];
      case SectorTemplate.it:
        return [
          {'key': 'nom_machine', 'label': 'sf_nom_machine'.tr()},
          {'key': 'adresse_ip', 'label': 'sf_adresse_ip'.tr()},
          {'key': 'systeme_exploitation', 'label': 'sf_systeme_exploitation'.tr()},
          {'key': 'ticket_reference', 'label': 'sf_ticket_reference'.tr()},
          {'key': 'actions_effectuees', 'label': 'sf_actions_effectuees'.tr()},
        ];
      case SectorTemplate.maintenance:
        return [
          {'key': 'numero_machine', 'label': 'sf_numero_machine'.tr()},
          {
            'key': 'type_entretien',
            'label': 'sf_type_entretien'.tr(),
            'type': 'dropdown',
            'options': ['preventive', 'corrective', 'predictive', 'improvement'],
          },
          {
            'key': 'heures_machine',
            'label': 'sf_heures_machine'.tr(),
            'numeric': true
          },
          {'key': 'pieces_remplacees', 'label': 'sf_pieces_remplacees'.tr()},
        ];
      case SectorTemplate.nettoyage:
        return [
          {'key': 'surface_m2', 'label': 'sf_surface_m2'.tr(), 'numeric': true},
          {'key': 'produits_utilises', 'label': 'sf_produits_utilises'.tr()},
          {
            'key': 'frequence',
            'label': 'sf_frequence'.tr(),
            'type': 'dropdown',
            'options': [
              'once',
              'daily',
              'weekly',
              'monthly',
              'other'
            ],
          },
        ];
      case SectorTemplate.btp:
        return [
          {'key': 'reference_chantier', 'label': 'sf_reference_chantier'.tr()},
          {'key': 'nature_travaux', 'label': 'sf_nature_travaux'.tr()},
          {
            'key': 'surface_ou_volume',
            'label': 'sf_surface_ou_volume'.tr(),
            'numeric': true
          },
          {'key': 'materiaux_utilises', 'label': 'sf_materiaux_utilises'.tr()},
        ];
      case SectorTemplate.transport:
        return [
          {
            'key': 'type_vehicule',
            'label': 'sf_type_vehicule'.tr(),
            'type': 'dropdown',
            'options': ['truck', 'van', 'trailer', 'tractor', 'bus', 'utility', 'other'],
          },
          {'key': 'immatriculation', 'label': 'sf_immatriculation'.tr()},
          {'key': 'kilometrage', 'label': 'sf_kilometrage'.tr(), 'numeric': true},
          {'key': 'trajet', 'label': 'sf_trajet'.tr()},
          {
            'key': 'type_intervention',
            'label': 'sf_type_intervention'.tr(),
            'type': 'dropdown',
            'options': ['servicing', 'repair', 'technical_inspection', 'accident', 'breakdown', 'other'],
          },
          {'key': 'chargement', 'label': 'sf_chargement'.tr()},
          {'key': 'chauffeur', 'label': 'sf_chauffeur'.tr()},
        ];
      default:
        return [];
    }
  }
}

// ─── Shared sub-widgets ───────────────────────────────────────────────────────

class _DateTile extends StatelessWidget {
  final DateTime date;
  final void Function(DateTime) onChanged;
  final String? label;
  final DateTime? firstDate;

  const _DateTile(
      {required this.date, required this.onChanged, this.label, this.firstDate});

  @override
  Widget build(BuildContext context) => ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.calendar_today, color: AppColors.primary),
        title: Text(label ?? 'field_date'.tr()),
        // (2026-10-14) Format de la langue (avant : « jj/mm/aaaa » pour tous,
        // alors que le PDF d'un Américain affiche « 10/14/2026 »).
        subtitle: Text(
          DateFormat.yMd().format(date),
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
        onTap: () async {
          FocusManager.instance.primaryFocus?.unfocus(); // (2026-10-20) idem heures
          final first = firstDate ?? DateTime(2020);
          final picked = await showDatePicker(
            context: context,
            initialDate: date.isBefore(first) ? first : date,
            firstDate: first,
            lastDate: DateTime(2035),
          );
          if (picked != null) onChanged(picked);
        },
      );
}

class _TimeTile extends StatelessWidget {
  final String label;
  final DateTime? time;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  const _TimeTile(
      {required this.label,
      this.time,
      required this.onTap,
      this.onClear});

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade400),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(Icons.access_time,
                  size: 16, color: AppColors.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: TextStyle(
                            fontSize: 11, color: Colors.grey.shade600)),
                    Text(
                      time != null ? DateFormat.jm().format(time!) : '—',
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
              if (onClear != null)
                GestureDetector(
                  onTap: onClear,
                  child: const Icon(Icons.clear,
                      size: 16, color: Colors.grey),
                ),
            ],
          ),
        ),
      );
}

class _SignatureButton extends StatelessWidget {
  final String? b64Data;
  final String label;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  const _SignatureButton(
      {this.b64Data,
      required this.label,
      required this.onTap,
      this.onClear});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (b64Data != null) ...[
            Stack(
              children: [
                Container(
                  height: 70,
                  decoration: BoxDecoration(
                    border: Border.all(
                        color: AppColors.success, width: 1.5),
                    borderRadius: BorderRadius.circular(8),
                    color: Colors.white,
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(7),
                    child: Image.memory(base64Decode(b64Data!),
                        fit: BoxFit.contain),
                  ),
                ),
                if (onClear != null)
                  Positioned(
                    top: 4,
                    right: 4,
                    child: GestureDetector(
                      onTap: onClear,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: const BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle),
                        child: const Icon(Icons.close,
                            size: 12, color: Colors.white),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
          ],
          OutlinedButton.icon(
            onPressed: onTap,
            icon: Icon(
              b64Data != null
                  ? Icons.edit_outlined
                  : Icons.draw_outlined,
              size: 18,
            ),
            label: Text(
              b64Data != null ? 'cr_modify'.tr() : label,
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ],
      );
}

// Parent-controlled: expansion state lives in _CreateReportScreenState (fixes 1E).
// hasError turns the header red when required fields inside fail validation (fix 1B).
class _CollapsibleSection extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;
  final bool expanded;
  final bool hasError;
  final VoidCallback onToggle;

  const _CollapsibleSection({
    super.key,
    required this.title,
    required this.icon,
    required this.child,
    required this.expanded,
    required this.onToggle,
    this.hasError = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = hasError ? Colors.red : AppColors.primary;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Icon(icon, color: color, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: color,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Divider(color: hasError ? Colors.red.shade200 : null)),
                  const SizedBox(width: 4),
                  Icon(
                    expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                    color: color,
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            firstChild: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: child,
            ),
            secondChild: const SizedBox(width: double.infinity),
            crossFadeState: expanded ? CrossFadeState.showFirst : CrossFadeState.showSecond,
            duration: const Duration(milliseconds: 200),
          ),
        ],
      ),
    );
  }
}

class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final int maxLines;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;

  const _Field({
    required this.controller,
    required this.label,
    this.maxLines = 1,
    this.keyboardType,
    this.validator,
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextFormField(
          controller: controller,
          decoration: InputDecoration(labelText: label),
          maxLines: maxLines,
          keyboardType: keyboardType,
          validator: validator,
        ),
      );
}

class _SectorSelector extends StatelessWidget {
  final SectorTemplate selected;
  final ValueChanged<SectorTemplate> onChanged;

  const _SectorSelector(
      {required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: SectorTemplate.values.map((s) {
          final isSelected = s == selected;
          return FilterChip(
            label: Text(s.label),
            selected: isSelected,
            onSelected: (_) => onChanged(s),
            selectedColor: AppColors.primary.withValues(alpha: 0.15),
            labelStyle: TextStyle(
              color: isSelected ? AppColors.primary : Colors.black87,
              fontWeight:
                  isSelected ? FontWeight.bold : FontWeight.normal,
            ),
          );
        }).toList(),
      );
}

// ─── Bandeau « Mon entreprise » (utilisateur solo) ───────────────────────────
// Toujours visible pour un solo SANS équipe : point d'entrée permanent vers
// Réglages → Mon entreprise. Deux états :
//   • nom d'entreprise VIDE  → alerte orange (sinon le PDF n'a pas de nom).
//   • nom RENSEIGNÉ          → discret « Compléter / modifier » (SIRET, logo, TVA…),
//     toujours cliquable pour finir de remplir quand on veut.
class _SoloIdentityBanner extends ConsumerWidget {
  const _SoloIdentityBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider).valueOrNull ?? {};
    final companyName = (settings['company_name'] ?? '').toString().trim();
    final empty = companyName.isEmpty;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () {
          // Réglages → tuile « Mon entreprise » dépliée (réutilise l'existant).
          ref.read(settingsExpandCompanyProvider.notifier).state =
              DateTime.now().microsecondsSinceEpoch;
          context.go('/settings');
        },
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: empty
                ? Colors.orange.shade50
                : AppColors.primary.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: empty
                    ? Colors.orange.shade200
                    : AppColors.primary.withValues(alpha: 0.20)),
          ),
          child: Row(children: [
            Icon(empty ? Icons.warning_amber_rounded : Icons.business_outlined,
                size: 20,
                color: empty ? Colors.orange.shade800 : AppColors.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    empty ? 'cr_solo_set_company'.tr() : 'cr_solo_my_company_prefix'.tr(args: [companyName]),
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: empty ? Colors.orange.shade900 : Colors.black87),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    empty
                        ? 'cr_solo_empty_sub'.tr()
                        : 'cr_solo_filled_sub'.tr(),
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 18, color: Colors.grey.shade400),
          ]),
        ),
      ),
    );
  }
}

// ─── Toggle d'identité en haut de la création de rapport ──────────────────────
// (#8) Réactivé : affiché quand l'utilisateur a 2 profils (solo + équipe).
// Réutilise activeProfileProvider → l'identité du PDF suit le choix.
class _ReportIdentityToggle extends ConsumerWidget {
  const _ReportIdentityToggle();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(activeProfileModeProvider);
    final team = ref.watch(teamStateProvider).valueOrNull;
    final teamName = (team?.companyName ?? 'cr_team_default'.tr()).trim();
    final activeName = ref.watch(activeCompanyNameProvider);
    final canPerso = ref.watch(canUsePersoProfileProvider);
    final canEquipe = ref.watch(canUseEquipeProfileProvider);

    void explain(ProfileMode m) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(m == ProfileMode.equipe
            ? 'cr_id_explain_equipe'.tr()
            : 'cr_id_explain_perso'.tr()),
      ));
    }

    Widget pill(ProfileMode m, IconData icon, String label, bool available) {
      final selected = mode == m && available;
      return Expanded(
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: !available
              ? () => explain(m)
              : (mode == m
                  ? null
                  : () {
                      ref.read(activeProfileProvider.notifier).setMode(m);
                      // (#10/D5) Bascule en perso sans abo solo → avertir que les
                      // exports perso passent par les 5 gratuits/mois (device),
                      // plutôt que de bloquer le switch.
                      if (m == ProfileMode.perso &&
                          !ref.read(hasSoloSubProvider)) {
                        ScaffoldMessenger.of(context)
                            .showSnackBar(SnackBar(
                          content: Text('cr_id_perso_quota_warn'.tr()),
                          duration: const Duration(seconds: 5),
                        ));
                      }
                    }),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
            decoration: BoxDecoration(
              color: selected ? AppColors.primary : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(available ? icon : Icons.lock_outline,
                    size: 16,
                    color: selected
                        ? Colors.white
                        : (available
                            ? Colors.grey.shade600
                            : Colors.grey.shade400)),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(label,
                      maxLines: 2,
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 12.5,
                          height: 1.1,
                          fontWeight: FontWeight.w600,
                          color: selected
                              ? Colors.white
                              : (available
                                  ? Colors.grey.shade700
                                  : Colors.grey.shade400))),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.badge_outlined, size: 16, color: AppColors.primary),
            const SizedBox(width: 6),
            Expanded(
              child: Text('cr_id_created_for'.tr(),
                  style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary)),
            ),
          ]),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.grey.shade200),
            ),
            padding: const EdgeInsets.all(4),
            child: Row(children: [
              pill(ProfileMode.perso, Icons.person_outline,
                  'cr_id_my_personal_reports'.tr(), canPerso),
              const SizedBox(width: 4),
              pill(ProfileMode.equipe, Icons.business_outlined, teamName,
                  canEquipe),
            ]),
          ),
          const SizedBox(height: 6),
          Text(
            activeName.isEmpty
                ? 'cr_id_no_identity_warn'.tr()
                : 'cr_id_loaded_prefix'.tr(args: [activeName]),
            style: TextStyle(
                fontSize: 11,
                color: activeName.isEmpty ? Colors.orange : Colors.grey.shade600),
          ),
          // (#10) Lien d'édition : on n'édite PAS ici, on ENVOIE au bon endroit
          // (comme l'avertissement « complétez dans Réglages »). Le brouillon est
          // auto-enregistré → aucune perte en quittant.
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () {
                if (mode == ProfileMode.perso) {
                  // (K) Réglages + tuile « Mon entreprise » déroulée.
                  ref.read(settingsExpandCompanyProvider.notifier).state =
                      DateTime.now().microsecondsSinceEpoch;
                  context.go('/settings');
                } else {
                  // (J) → Réglages équipe + carte « infos entreprise » déroulée.
                  ref.read(teamTabRequestProvider.notifier).state =
                      TeamTabRequest(
                          tab: 2,
                          expandCompany: true,
                          nonce: DateTime.now().microsecondsSinceEpoch);
                  context.go('/team-tab');
                }
              },
              icon: const Icon(Icons.open_in_new, size: 13),
              label: Text(
                mode == ProfileMode.perso
                    ? 'cr_id_edit_solo'.tr()
                    : 'cr_id_edit_team'.tr(),
                style: const TextStyle(fontSize: 11),
              ),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

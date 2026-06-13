import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:printing/printing.dart';
import 'package:uuid/uuid.dart';
import '../../../core/constants/app_colors.dart';
import '../models/report_model.dart';
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
  int _reportNumber = 0;
  String? _reportNumberFormat;
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
  }

  void _fillFromTemplate(Map<String, dynamic> data) {
    final now = DateTime.now().toIso8601String();
    final r = ReportModel.fromMap({
      ...data,
      'id': _reportId,
      'date': now,
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
    _clientName.text = r.clientName;
    _clientAddress.text = r.clientAddress;
    _clientPhone.text = r.clientPhone;
    _clientContact.text = r.clientContact;
    _contractNumber.text = r.contractNumber;
    _interventionType.text = r.interventionType;
    _equipmentType.text = r.equipmentType;
    _equipmentBrand.text = r.equipmentBrand;
    _equipmentModel.text = r.equipmentModel;
    _equipmentSerial.text = r.equipmentSerial;
    _description.text = r.description;
    _observations.text = r.observations;
    if (r.laborHours != null) _laborHours.text = r.laborHours!.toString();
    if (r.laborRate != null) _laborRate.text = r.laborRate!.toString();
    setState(() {
      _sector = r.sector;
      _sectorFields = Map.from(r.sectorFields);
      _clientId = r.clientId;
      _materials..clear()..addAll(r.materials);
      _sectionExpanded[1] = r.clientName.isNotEmpty;
      _sectionExpanded[3] = r.equipmentType.isNotEmpty;
      _sectionExpanded[5] = r.description.isNotEmpty;
      _sectionExpanded[8] = r.laborHours != null || r.laborRate != null || r.materials.isNotEmpty;
    });
  }

  @override
  void dispose() {
    // (#4c) FLUSH FINAL : persiste le brouillon MÊME si on quitte avant les 2s du
    // debounce (ex. on remplit 1 champ et on quitte aussitôt). Les contrôleurs
    // sont encore vivants ici ; `reportsProvider` survit au widget (non autoDispose)
    // → le brouillon apparaîtra dans la liste. Idempotent (id de session stable).
    if (_hasAnyContent()) {
      ref
          .read(reportsProvider.notifier)
          .upsertSilently(_buildReport(ReportStatus.draft));
    }
    _autoSaveTimer?.cancel();
    for (final c in [
      _clientName, _clientAddress, _clientPhone, _clientContact,
      _contractNumber, _interventionType, _equipmentType, _equipmentBrand,
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
      _contractNumber, _interventionType, _equipmentType, _equipmentBrand,
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
      _contractNumber, _interventionType, _equipmentType, _equipmentBrand,
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

  Future<void> _autoSave() async {
    if (!mounted) return;
    if (!_hasAnyContent()) return;
    // (A) Passe par le PROVIDER (et plus par un insert direct) → la liste des
    // rapports reflète le brouillon EN DIRECT, sans attendre un autre save.
    await ref
        .read(reportsProvider.notifier)
        .upsertSilently(_buildReport(ReportStatus.draft));
  }

  void _clearAutosave() {
    _autoSaveTimer?.cancel();
    _autoSaveTimer = null;
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
    );
    setState(() => _isSaving = false);
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('Aperçu PDF')),
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
        content: Text('Heure ${isStart ? 'de début' : 'de fin'} effacée'),
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          label: 'Annuler',
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
        content: Text('${removed.label} supprimé'),
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          label: 'Annuler',
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
        title: const Text('Signature à distance (Pro)'),
        content: const Text(
          'Pas besoin que le client soit présent : envoyez-lui un lien, il '
          'signe depuis son téléphone, et la signature s\'ajoute toute seule '
          'au rapport.\n\n'
          '👉 Disponible une fois le rapport SOUMIS (bouton « Soumettre » en '
          'bas) : ouvrez-le ensuite dans « Mes rapports » puis « Signature à '
          'distance ».\n\n'
          'Continuez votre rédaction tranquillement — le rapport est '
          'enregistré en brouillon en temps réel, vous ne perdez rien.',
          style: TextStyle(fontSize: 13, height: 1.4),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(dlg),
            child: const Text('Compris'),
          ),
        ],
      ),
    );
  }

  Future<void> _openSignature(String slot) async {
    final titles = {
      'clientStart': 'Client — Début d\'intervention',
      'techStart': 'Technicien — Début d\'intervention',
      'clientEnd': 'Client — Fin d\'intervention',
      'techEnd': 'Technicien — Fin d\'intervention',
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
        const SnackBar(
          content: Text(
              'Aucun client dans l\'annuaire. Ajoutez-en un d\'abord.'),
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
          title: const Text('SOUS CONTRAT ?',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
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
          const Text('Champs personnalisés',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        ]),
        const Padding(
          padding: EdgeInsets.only(top: 2, bottom: 6),
          child: Text(
            'Ajoutez les lignes que vous voulez (intitulé + valeur) — elles '
            'apparaissent dans le PDF.',
            style: TextStyle(fontSize: 11.5, color: Colors.grey),
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
                    decoration: const InputDecoration(
                      isDense: true,
                      labelText: 'Intitulé',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: row.value,
                    decoration: const InputDecoration(
                      isDense: true,
                      labelText: 'Valeur',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  tooltip: 'Retirer',
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
            label: const Text('Ajouter un champ'),
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
      laborHours: double.tryParse(_laborHours.text.replaceAll(',', '.')),
      laborRate: double.tryParse(_laborRate.text.replaceAll(',', '.')),
      materials: List.from(_materials),
      technicianName: s['technician_name']?.toString(),
      technicianId: inTeam ? ref.read(firebaseUserProvider).valueOrNull?.uid : null,
      companyId: inTeam ? teamState?.companyId : null,
      status: status,
      sousContrat: _sousContrat,
      customFields: {
        for (final r in _customRows)
          if (r.label.text.trim().isNotEmpty)
            r.label.text.trim(): r.value.text.trim(),
      },
      createdAt: _existingCreatedAt ?? now,
      updatedAt: now,
    );
  }

  Future<void> _editReportNumberAndFormat(BuildContext context) async {
    final settings = ref.read(settingsProvider).valueOrNull ?? {};
    final numCtrl = TextEditingController(
        text: _reportNumber > 0 ? _reportNumber.toString() : '');

    const presets = [
      ('{num}', 'Simple', '001'),
      ('{year}-{num}', 'Annuel', '2026-001'),
      ('{year}/{num}', 'Année/N°', '2026/001'),
      ('{company}/{year}/{month}/{day}/{num}', 'Société/Date', 'AMARIS/2026/04/23/001'),
      ('{client}-{num}', 'Client-N°', 'DUPONT-001'),
      ('{client}/{year}/{month}/{day}/{num}', 'Client/Date', 'DUPONT/2026/05/18/001'),
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
            title: const Text('Numéro & format'),
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
                      decoration: const InputDecoration(labelText: 'Numéro', isDense: true),
                      autofocus: true,
                      onChanged: (_) => setS(() {}),
                    ),
                    const SizedBox(height: 16),
                    const Text('Format', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        ChoiceChip(
                          label: const Text('Défaut global', style: TextStyle(fontSize: 12)),
                          selected: fmtSelected == null && !showCustom,
                          visualDensity: VisualDensity.compact,
                          onSelected: (_) => setS(() { fmtSelected = null; showCustom = false; }),
                        ),
                        ...presets.map((p) {
                          final (value, label, _) = p;
                          return ChoiceChip(
                            label: Text(label, style: const TextStyle(fontSize: 12)),
                            selected: !showCustom && fmtSelected == value,
                            visualDensity: VisualDensity.compact,
                            onSelected: (_) => setS(() { fmtSelected = value; showCustom = false; }),
                          );
                        }),
                        ChoiceChip(
                          label: const Text('Personnalisé', style: TextStyle(fontSize: 12)),
                          selected: showCustom,
                          visualDensity: VisualDensity.compact,
                          onSelected: (_) => setS(() => showCustom = true),
                        ),
                      ],
                    ),
                    if (!showCustom && fmtSelected != null) ...[
                      const SizedBox(height: 6),
                      Text('Ex : ${preview(fmtSelected!)}',
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
                            ('{num}', 'Numéro', false), ('{client}', 'Client', false),
                            ('{company}', 'Société', false), ('{year}', 'Année', false),
                            ('{month}', 'Mois', false), ('{day}', 'Jour', false),
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
                      Text('Aperçu : ${preview(customCtrl.text.isEmpty ? '{num}' : customCtrl.text)}',
                          style: const TextStyle(fontSize: 11, color: Colors.blue)),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
              ElevatedButton(
                onPressed: () {
                  final v = int.tryParse(numCtrl.text.trim());
                  if (v != null && v > 0) setState(() => _reportNumber = v);
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
        title: const Text('Service indisponible'),
        content: Text(result.message),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('Fermer')),
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
        const SnackBar(
            content: Text('Renseignez au moins une information à enregistrer.')),
      );
      return;
    }
    setState(() => _isSaving = true);
    await ref
        .read(reportsProvider.notifier)
        .saveReport(_buildReport(ReportStatus.draft));
    setState(() => _isSaving = false);
    _clearAutosave();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Rapport enregistré'),
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Des champs obligatoires sont manquants (surlignés en rouge).'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }
    setState(() {
      _clientSectionError = false;
      _travauxSectionError = false;
    });
    setState(() => _isSaving = true);
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
    if (teamState != null && teamState.hasTeam) {
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
        const SnackBar(
          content: Text('Rapport soumis ✓'),
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
        const SnackBar(content: Text('Saisissez d\'abord un nom de client')),
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
      createdAt: now,
      updatedAt: now,
    );
    await ref.read(clientsProvider.notifier).saveClient(client);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${client.name} ajouté à l\'annuaire ✓'),
          backgroundColor: AppColors.success,
        ),
      );
    }
  }

  // ─── Presets ────────────────────────────────────────────────────────────────

  Map<String, dynamic> _currentPresetData() => {
        'clientName': _clientName.text.trim(),
        'clientAddress': _clientAddress.text.trim(),
        'clientPhone': _clientPhone.text.trim(),
        'clientContact': _clientContact.text.trim(),
        'contractNumber': _contractNumber.text.trim(),
        'interventionType': _interventionType.text.trim(),
        'sector': _sector.name,
        'sectorFields': _sectorFields,
        'description': _description.text.trim(),
        'observations': _observations.text.trim(),
        'equipmentType': _equipmentType.text.trim(),
        'equipmentBrand': _equipmentBrand.text.trim(),
        'equipmentModel': _equipmentModel.text.trim(),
        'equipmentSerial': _equipmentSerial.text.trim(),
        'laborHours': _laborHours.text.trim(),
        'laborRate': _laborRate.text.trim(),
        if (_startTime != null) 'startTimeHour': _startTime!.hour,
        if (_startTime != null) 'startTimeMinute': _startTime!.minute,
        if (_endTime != null) 'endTimeHour': _endTime!.hour,
        if (_endTime != null) 'endTimeMinute': _endTime!.minute,
      };

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
        content: const Text(
          'Les modèles de rapport sont réservés à la version Pro. Passez Pro '
          'pour réutiliser vos rapports types et gagner du temps.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dlg),
              child: const Text('Plus tard')),
          FilledButton(
            onPressed: () {
              Navigator.pop(dlg);
              PaywallBottomSheet.show(context, reason: feature);
            },
            child: const Text('Voir Pro'),
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
        title: const Text('Sauvegarder comme modèle'),
        content: TextField(
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Nom du modèle',
            hintText: 'Ex: Maintenance chaudière',
          ),
          onChanged: (v) => name = v,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dlg, false), child: const Text('Annuler')),
          TextButton(onPressed: () => Navigator.pop(dlg, true), child: const Text('Sauvegarder')),
        ],
      ),
    );
    if (ok != true || name.trim().isEmpty) return;
    final preset = ReportPreset(
      id: const Uuid().v4(),
      name: name.trim(),
      createdAt: DateTime.now(),
      data: _currentPresetData(),
    );
    await LocalDbService().savePreset(preset);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Modèle "${preset.name}" sauvegardé ✓'), backgroundColor: AppColors.success),
      );
    }
  }

  Future<void> _loadPreset() async {
    final presets = await LocalDbService().getAllPresets();
    if (!mounted) return;
    if (presets.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Aucun modèle sauvegardé')),
      );
      return;
    }
    final chosen = await showDialog<ReportPreset>(
      context: context,
      builder: (_) => SimpleDialog(
        title: const Text('Charger un modèle'),
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
    final d = chosen.data;
    final now = DateTime.now();
    setState(() {
      _clientName.text = d['clientName'] ?? '';
      _clientAddress.text = d['clientAddress'] ?? '';
      _clientPhone.text = d['clientPhone'] ?? '';
      _clientContact.text = d['clientContact'] ?? '';
      _contractNumber.text = d['contractNumber'] ?? '';
      _interventionType.text = d['interventionType'] ?? '';
      _description.text = d['description'] ?? '';
      _observations.text = d['observations'] ?? '';
      _equipmentType.text = d['equipmentType'] ?? '';
      _equipmentBrand.text = d['equipmentBrand'] ?? '';
      _equipmentModel.text = d['equipmentModel'] ?? '';
      _equipmentSerial.text = d['equipmentSerial'] ?? '';
      _laborHours.text = d['laborHours'] ?? '';
      _laborRate.text = d['laborRate'] ?? '';
      _sector = SectorTemplate.values.firstWhere(
        (s) => s.name == d['sector'], orElse: () => SectorTemplate.generic);
      _sectorFields = Map<String, dynamic>.from(d['sectorFields'] ?? {});
      if (d['startTimeHour'] != null) {
        _startTime = DateTime(now.year, now.month, now.day,
            d['startTimeHour'] as int, d['startTimeMinute'] as int);
      }
      if (d['endTimeHour'] != null) {
        _endTime = DateTime(now.year, now.month, now.day,
            d['endTimeHour'] as int, d['endTimeMinute'] as int);
      }
    });
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
    const items = [
      (0, Icons.category_outlined, 'Type'),
      (1, Icons.person_outline, 'Client'),
      (2, Icons.build_outlined, 'Mission'),
      (3, Icons.settings_outlined, 'Équip.'),
      (5, Icons.description_outlined, 'Travaux'),
      (6, Icons.photo_camera_outlined, 'Photos'),
      (7, Icons.draw_outlined, 'Signatures'),
      (8, Icons.receipt_outlined, 'Facturat.'),
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
        ? 'Modifier ${resolvedNum ?? '#${_reportNumber.toString().padLeft(3, '0')}'}'
        : resolvedNum ?? 'Nouveau rapport';

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
            tooltip: 'Aperçu PDF',
            onPressed: _isSaving ? null : _previewCurrentPdf,
          ),
          IconButton(
            icon: _proIcon(Icons.folder_open_outlined, isPro),
            tooltip: 'Charger un modèle',
            onPressed:
                isPro ? _loadPreset : () => _showProRequired('Charger un modèle'),
          ),
          IconButton(
            icon: _proIcon(Icons.bookmark_add_outlined, isPro),
            tooltip: 'Sauvegarder comme modèle',
            onPressed: isPro
                ? _saveAsPreset
                : () => _showProRequired('Sauvegarder comme modèle'),
          ),
          TextButton.icon(
            onPressed: _isSaving ? null : _saveAsDraft,
            icon: const Icon(Icons.save_outlined, color: Colors.white),
            label: const Text('Brouillon',
                style: TextStyle(color: Colors.white)),
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
            label: const Text('Soumettre le rapport'),
          ),
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          controller: _scroll,
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
              title: 'Type de rapport',
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
              title: 'Client',
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
                    label: const Text('Sélectionner depuis l\'annuaire'),
                  ),
                  const SizedBox(height: 10),
                  _Field(
                    controller: _clientName,
                    label: 'Nom du client *',
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Requis' : null,
                  ),
                  _Field(controller: _clientAddress, label: 'Adresse'),
                  _Field(controller: _clientPhone, label: 'Téléphone', keyboardType: TextInputType.phone),
                  _Field(controller: _clientContact, label: 'Contact sur place'),
                  _Field(controller: _contractNumber, label: 'N° de contrat'),
                  _extrasBlock(),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: _saveAsClient,
                      icon: const Icon(Icons.person_add_outlined, size: 16),
                      label: const Text('Enregistrer dans l\'annuaire', style: TextStyle(fontSize: 12)),
                    ),
                  ),
                ],
              ),
            ),

            _CollapsibleSection(
              key: _navKeys[2],
              title: 'Intervention',
              icon: Icons.build_outlined,
              expanded: _isExpanded(2),
              onToggle: () => _toggleSection(2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Field(controller: _interventionType, label: "Type d'intervention"),
                  _DateTile(date: _date, onChanged: (d) => setState(() => _date = d)),
                  Row(
                    children: [
                      Expanded(
                        child: _endDate != null
                            ? _DateTile(
                                label: 'Date de fin',
                                date: _endDate!,
                                onChanged: (d) => setState(() => _endDate = d),
                              )
                            : TextButton.icon(
                                onPressed: () => setState(() => _endDate = _date),
                                icon: const Icon(Icons.date_range, size: 16),
                                label: const Text('Intervention multi-jours', style: TextStyle(fontSize: 12)),
                              ),
                      ),
                      if (_endDate != null)
                        IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          tooltip: 'Retirer la date de fin',
                          onPressed: () => setState(() => _endDate = null),
                        ),
                    ],
                  ),
                  Row(
                    children: [
                      Expanded(child: _TimeTile(label: 'Début', time: _startTime, onTap: () => _pickTime(true), onClear: _startTime != null ? () => _clearTime(true) : null)),
                      const SizedBox(width: 10),
                      Expanded(child: _TimeTile(label: 'Fin', time: _endTime, onTap: () => _pickTime(false), onClear: _endTime != null ? () => _clearTime(false) : null)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    children: [
                      for (final e in [('Maintenant', 0), ('−15 min', 15), ('−30 min', 30), ('−1 h', 60)])
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
              title: 'Équipement',
              icon: Icons.settings_outlined,
              expanded: _isExpanded(3),
              onToggle: () => _toggleSection(3),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Field(controller: _equipmentType, label: "Type d'équipement"),
                  Row(
                    children: [
                      Expanded(child: _Field(controller: _equipmentBrand, label: 'Marque')),
                      const SizedBox(width: 10),
                      Expanded(child: _Field(controller: _equipmentModel, label: 'Modèle')),
                    ],
                  ),
                  _Field(controller: _equipmentSerial, label: 'N° de série'),
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
              title: 'Détails des travaux',
              icon: Icons.description_outlined,
              expanded: _isExpanded(5),
              onToggle: () => _toggleSection(5),
              hasError: _travauxSectionError,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Field(controller: _description, label: 'Description des travaux *', maxLines: 5,
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Requis' : null),
                  _Field(controller: _observations, label: 'Observations / Recommandations', maxLines: 3),
                ],
              ),
            ),

            _CollapsibleSection(
              key: _navKeys[6],
              title: 'Photos',
              icon: Icons.photo_camera_outlined,
              expanded: _isExpanded(6),
              onToggle: () => _toggleSection(6),
              child: PhotoPickerWidget(
                photos: _photos,
                onAdd: (xFile) => setState(() {
                  _photos.add(xFile);
                  _sectionExpanded[6] = true;
                }),
                onRemove: (i) => setState(() => _photos.removeAt(i)),
              ),
            ),

            _CollapsibleSection(
              key: _navKeys[7],
              title: 'Signatures',
              icon: Icons.draw_outlined,
              expanded: _isExpanded(7),
              onToggle: () => _toggleSection(7),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Début d\'intervention',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(child: _SignatureButton(
                        b64Data: _sigClientStartData,
                        label: 'Client (début)',
                        onTap: () => _openSignature('clientStart'),
                        onClear: _sigClientStartData != null ? () => setState(() => _sigClientStartData = null) : null,
                      )),
                      const SizedBox(width: 12),
                      Expanded(child: _SignatureButton(
                        b64Data: _sigTechStartData,
                        label: 'Technicien (début)',
                        onTap: () => _openSignature('techStart'),
                        onClear: _sigTechStartData != null ? () => setState(() => _sigTechStartData = null) : null,
                      )),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text('Fin d\'intervention',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(child: _SignatureButton(
                        b64Data: _sigClientData,
                        label: 'Client (fin)',
                        onTap: () => _openSignature('clientEnd'),
                        onClear: _sigClientData != null ? () => setState(() => _sigClientData = null) : null,
                      )),
                      const SizedBox(width: 12),
                      Expanded(child: _SignatureButton(
                        b64Data: _sigTechData,
                        label: 'Technicien (fin)',
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
                      label: const Text('Faire signer le client à distance'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        side: BorderSide(
                            color: AppColors.primary.withValues(alpha: 0.4)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Le client n\'est pas là ? Vous pourrez l\'envoyer signer par '
                    'lien après l\'envoi du rapport. (Pro)',
                    style:
                        TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),

            _CollapsibleSection(
              key: _navKeys[8],
              title: 'Facturation (optionnel)',
              icon: Icons.receipt_outlined,
              expanded: _isExpanded(8),
              onToggle: () => _toggleSection(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: _Field(controller: _laborHours, label: 'Heures de main-d\'œuvre', keyboardType: const TextInputType.numberWithOptions(decimal: true))),
                      const SizedBox(width: 10),
                      Expanded(child: _Field(controller: _laborRate, label: 'Taux horaire (€/h)', keyboardType: const TextInputType.numberWithOptions(decimal: true))),
                    ],
                  ),
                  if (_materials.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    ..._materials.asMap().entries.map((e) => _MaterialTile(item: e.value, onRemove: () => _removeMaterial(e.key))),
                  ],
                  OutlinedButton.icon(
                    onPressed: _addMaterial,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Ajouter un matériau / pièce'),
                  ),
                  if (_laborHours.text.isNotEmpty || _materials.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    _TotalPreview(
                      hours: double.tryParse(_laborHours.text.replaceAll(',', '.')) ?? 0,
                      rate: double.tryParse(_laborRate.text.replaceAll(',', '.')) ?? 0,
                      materials: _materials,
                    ),
                  ],
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
            return const Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Text('Sélectionner un client',
                  style: TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 16)),
            );
          }
          final c = clients[i - 1];
          return ListTile(
            leading: CircleAvatar(
              backgroundColor:
                  AppColors.primary.withValues(alpha: 0.12),
              child: Text(
                c.name[0].toUpperCase(),
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
        title: const Text('Ajouter un matériau'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _label,
                decoration:
                    const InputDecoration(labelText: 'Désignation *'),
                autofocus: true,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _ref,
                decoration: const InputDecoration(labelText: 'Référence'),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  // FR3 — stepper for quantity
                  IconButton(
                    icon: const Icon(Icons.remove_circle_outline,
                        color: AppColors.primary),
                    onPressed: () {
                      final v = (double.tryParse(
                                  _qty.text.replaceAll(',', '.')) ??
                              1)
                          .toInt();
                      if (v > 1) setState(() => _qty.text = '${v - 1}');
                    },
                  ),
                  Expanded(
                    child: TextField(
                      controller: _qty,
                      textAlign: TextAlign.center,
                      decoration: const InputDecoration(labelText: 'Qté'),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline,
                        color: AppColors.primary),
                    onPressed: () {
                      final v = (double.tryParse(
                                  _qty.text.replaceAll(',', '.')) ??
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
                          const InputDecoration(labelText: 'Prix unit. (€)'),
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
              child: const Text('Annuler')),
          ElevatedButton(
            onPressed: () {
              if (_label.text.trim().isEmpty) return;
              widget.onAdd(MaterialItem(
                reference: _ref.text.trim(),
                label: _label.text.trim(),
                quantity: double.tryParse(
                        _qty.text.replaceAll(',', '.')) ??
                    1,
                unitPrice: double.tryParse(
                        _price.text.replaceAll(',', '.')) ??
                    0,
              ));
              Navigator.pop(context);
            },
            child: const Text('Ajouter'),
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
            ? Text('Réf: ${item.reference}',
                style: const TextStyle(fontSize: 11))
            : null,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${item.quantity} × ${item.unitPrice.toStringAsFixed(2)} € = '
              '${item.total.toStringAsFixed(2)} €',
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
    final labor = hours * rate;
    final matTotal =
        materials.fold<double>(0, (acc, m) => acc + m.total);
    final total = labor + matTotal;

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
            _TotalRow('Main-d\'œuvre',
                '${hours.toStringAsFixed(1)}h × ${rate.toStringAsFixed(2)} €/h',
                labor),
          if (matTotal > 0) _TotalRow('Matériaux', '', matTotal),
          const Divider(height: 12),
          _TotalRow('TOTAL HT', '', total, bold: true),
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
              '${amount.toStringAsFixed(2)} €',
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
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: DropdownButtonFormField<String>(
              initialValue: (fields[def['key']] as String?)?.isEmpty == false
                  ? fields[def['key']] as String?
                  : null,
              decoration:
                  InputDecoration(labelText: def['label'] as String),
              items: (def['options'] as List<String>)
                  .map((o) =>
                      DropdownMenuItem(value: o, child: Text(o)))
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

  static List<Map<String, dynamic>> _fieldDefs(SectorTemplate s) {
    switch (s) {
      case SectorTemplate.plomberie:
        return [
          {
            'key': 'type_tuyauterie',
            'label': 'Type de tuyauterie',
            'type': 'dropdown',
            'options': ['PVC', 'Cuivre', 'Acier', 'PE', 'PEX', 'Autre'],
          },
          {'key': 'diametre_mm', 'label': 'Diamètre (mm)', 'numeric': true},
          {'key': 'longueur_m', 'label': 'Longueur (m)', 'numeric': true},
          {
            'key': 'pression_testee_bar',
            'label': 'Pression testée (bar)',
            'numeric': true
          },
          {'key': 'remarques_specifiques', 'label': 'Remarques spécifiques'},
        ];
      case SectorTemplate.incendie:
        return [
          {'key': 'reference_extincteur', 'label': 'Référence extincteur'},
          {
            'key': 'type_agent',
            'label': 'Type d\'agent extincteur',
            'type': 'dropdown',
            'options': [
              'CO₂',
              'Poudre ABC',
              'Eau pulvérisée',
              'Mousse',
              'Halon',
              'Autre'
            ],
          },
          {
            'key': 'pression_manometre',
            'label': 'Pression manomètre (bar)',
            'numeric': true
          },
          {
            'key': 'date_prochaine_verif',
            'label': 'Date prochaine vérification'
          },
        ];
      case SectorTemplate.it:
        return [
          {'key': 'nom_machine', 'label': 'Nom machine / serveur'},
          {'key': 'adresse_ip', 'label': 'Adresse IP'},
          {'key': 'systeme_exploitation', 'label': 'Système d\'exploitation'},
          {'key': 'ticket_reference', 'label': 'Référence ticket'},
          {'key': 'actions_effectuees', 'label': 'Actions effectuées'},
        ];
      case SectorTemplate.maintenance:
        return [
          {'key': 'numero_machine', 'label': 'N° machine / équipement'},
          {
            'key': 'type_entretien',
            'label': 'Type d\'entretien',
            'type': 'dropdown',
            'options': ['Préventif', 'Curatif', 'Prédictif', 'Amélioratif'],
          },
          {
            'key': 'heures_machine',
            'label': 'Heures machine',
            'numeric': true
          },
          {'key': 'pieces_remplacees', 'label': 'Pièces remplacées'},
        ];
      case SectorTemplate.nettoyage:
        return [
          {'key': 'surface_m2', 'label': 'Surface (m²)', 'numeric': true},
          {'key': 'produits_utilises', 'label': 'Produits utilisés'},
          {
            'key': 'frequence',
            'label': 'Fréquence',
            'type': 'dropdown',
            'options': [
              'Unique',
              'Quotidien',
              'Hebdomadaire',
              'Mensuel',
              'Autre'
            ],
          },
        ];
      case SectorTemplate.btp:
        return [
          {'key': 'reference_chantier', 'label': 'Référence chantier'},
          {'key': 'nature_travaux', 'label': 'Nature des travaux'},
          {
            'key': 'surface_ou_volume',
            'label': 'Surface / volume',
            'numeric': true
          },
          {'key': 'materiaux_utilises', 'label': 'Matériaux utilisés'},
        ];
      case SectorTemplate.transport:
        return [
          {
            'key': 'type_vehicule',
            'label': 'Type de véhicule',
            'type': 'dropdown',
            'options': ['Camion', 'Camionnette', 'Remorque', 'Tracteur', 'Bus', 'Utilitaire', 'Autre'],
          },
          {'key': 'immatriculation', 'label': 'N° d\'immatriculation'},
          {'key': 'kilometrage', 'label': 'Kilométrage', 'numeric': true},
          {'key': 'trajet', 'label': 'Trajet / destination'},
          {
            'key': 'type_intervention',
            'label': 'Type d\'intervention',
            'type': 'dropdown',
            'options': ['Entretien', 'Réparation', 'Contrôle technique', 'Accident', 'Panne', 'Autre'],
          },
          {'key': 'chargement', 'label': 'Chargement / marchandise'},
          {'key': 'chauffeur', 'label': 'Nom du chauffeur'},
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
  final String label;

  const _DateTile({required this.date, required this.onChanged, this.label = 'Date'});

  @override
  Widget build(BuildContext context) => ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.calendar_today, color: AppColors.primary),
        title: Text(label),
        subtitle: Text(
          '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}',
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
        onTap: () async {
          final picked = await showDatePicker(
            context: context,
            initialDate: date,
            firstDate: DateTime(2020),
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
                      time != null
                          ? '${time!.hour.toString().padLeft(2, '0')}:${time!.minute.toString().padLeft(2, '0')}'
                          : '—',
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
              b64Data != null ? 'Modifier' : label,
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
                    empty ? 'Renseignez votre entreprise' : 'Mon entreprise · $companyName',
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: empty ? Colors.orange.shade900 : Colors.black87),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    empty
                        ? 'Nom, logo, SIRET, adresse… pour qu\'ils apparaissent sur vos PDF.'
                        : 'Compléter / modifier (logo, SIRET, adresse, TVA…).',
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
    final teamName = (team?.companyName ?? 'Mon équipe').trim();
    final activeName = ref.watch(activeCompanyNameProvider);
    final canPerso = ref.watch(canUsePersoProfileProvider);
    final canEquipe = ref.watch(canUseEquipeProfileProvider);

    void explain(ProfileMode m) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(m == ProfileMode.equipe
            ? 'Rejoignez ou créez une équipe pour créer un rapport au nom d\'une '
                'équipe.'
            : 'Un abonnement solo est nécessaire pour des rapports perso '
                'lorsque vous êtes en équipe.'),
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
                            .showSnackBar(const SnackBar(
                          content: Text(
                            'Profil perso : sans abonnement solo, vos exports '
                            'perso comptent dans vos 5 exports PDF gratuits/mois.',
                          ),
                          duration: Duration(seconds: 5),
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
            const Expanded(
              child: Text('Ce rapport est créé pour :',
                  style: TextStyle(
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
                  'Mes rapports\nperso', canPerso),
              const SizedBox(width: 4),
              pill(ProfileMode.equipe, Icons.business_outlined, teamName,
                  canEquipe),
            ]),
          ),
          const SizedBox(height: 6),
          Text(
            activeName.isEmpty
                ? '⚠️ Aucune identité renseignée pour ce profil — le PDF n\'aura '
                    'pas de nom d\'entreprise. Complétez dans Réglages.'
                : 'Identité chargée : « $activeName ».',
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
                    ? 'Modifier mon identité solo'
                    : 'Voir / modifier l\'identité de l\'équipe',
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

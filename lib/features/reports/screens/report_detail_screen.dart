import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import '../../../shared/widgets/zoomable_pdf_view.dart';
import 'package:share_plus/share_plus.dart';
import '../../../shared/utils/share_origin.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../../../core/constants/app_colors.dart';
import '../models/report_model.dart';
import '../models/sector_options.dart';
import '../models/tax_options.dart';
import '../models/currency_options.dart';
import '../providers/reports_provider.dart';
import '../providers/archive_provider.dart';
import '../../settings/providers/settings_provider.dart';
import '../../../shared/services/analytics_service.dart';
import '../../auth/providers/auth_provider.dart';
import '../../../shared/services/team_service.dart';
import '../widgets/remote_signature_sheet.dart';
import '../../../shared/services/remote_signature_service.dart';
import '../../../shared/services/dropbox_service.dart';
import '../../../shared/services/kill_switch_service.dart';
import '../../../shared/services/google_drive_service.dart';
import '../../../shared/services/local_db_service.dart';
import '../../../shared/services/onedrive_service.dart';
import '../../../shared/services/pdf_service.dart';
import '../../../shared/services/subscription_service.dart';
import '../../../shared/widgets/status_badge.dart';
import '../../subscription/paywall_bottom_sheet.dart';
import '../../subscription/subscription_provider.dart';

class ReportDetailScreen extends ConsumerWidget {
  final String reportId;
  const ReportDetailScreen({super.key, required this.reportId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reportsAsync = ref.watch(reportsProvider);

    return reportsAsync.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) =>
          Scaffold(body: Center(child: Text('common_error'.tr(args: ['$e'])))),
      data: (reports) {
        final report =
            reports.where((r) => r.id == reportId).firstOrNull;
        if (report == null) {
          return Scaffold(
            appBar: AppBar(title: Text('rd_not_found_title'.tr())),
            body: Center(
                child:
                    Text('rd_not_found_body'.tr())),
          );
        }
        return _ReportDetailView(report: report);
      },
    );
  }
}

class _ReportDetailView extends ConsumerStatefulWidget {
  final ReportModel report;
  const _ReportDetailView({required this.report});

  @override
  ConsumerState<_ReportDetailView> createState() =>
      _ReportDetailViewState();
}

class _ReportDetailViewState extends ConsumerState<_ReportDetailView> {
  bool _isGeneratingPdf = false;
  // ignore: unused_field
  bool _isSavingPdf = false;
  bool _isPreviewingPdf = false;
  bool _isGeneratingInvoice = false;

  // ─── Pending remote signature state ──────────────────────────────────────────
  String? _pendingSigToken;
  String? _pendingSigUrl;
  String? _pendingSigCode;
  StreamSubscription<Map<String, dynamic>?>? _bgSigSub;

  // ─── Photo request state (admin→tech) ────────────────────────────────────────
  String? _photoRequestBy;

  // ─── Edit-once lock ──────────────────────────────────────────────────────────
  // Reports that have been submitted can only be edited once.
  // We track which reports have already been edited using SharedPreferences.
  static const _editedKey = 'edited_report_ids';

  @override
  void initState() {
    super.initState();
    _loadPendingSig();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadPhotoRequest();
    });
  }

  @override
  void dispose() {
    _bgSigSub?.cancel();
    super.dispose();
  }

  Future<void> _loadPendingSig() async {
    final prefs = await SharedPreferences.getInstance();
    final id = widget.report.id;
    final token = prefs.getString('pending_sig_token_$id');
    if (token == null || !mounted) return;
    final url = prefs.getString('pending_sig_url_$id') ?? '';
    final code = prefs.getString('pending_sig_code_$id') ?? '';
    setState(() {
      _pendingSigToken = token;
      _pendingSigUrl = url;
      _pendingSigCode = code;
    });
    _startBgSigListener(token);
  }

  void _startBgSigListener(String token) {
    _bgSigSub?.cancel();
    _bgSigSub = RemoteSignatureService.streamRequest(token).listen((data) async {
      if (data?['status'] != 'signed') return;
      final sig = data!['signature_b64'] as String?;
      if (sig == null || sig.isEmpty) return;
      _bgSigSub?.cancel();
      await _clearPendingSig();
      await _applyBgSignature(sig);
    });
  }

  Future<void> _clearPendingSig() async {
    final prefs = await SharedPreferences.getInstance();
    final id = widget.report.id;
    await prefs.remove('pending_sig_token_$id');
    await prefs.remove('pending_sig_url_$id');
    await prefs.remove('pending_sig_code_$id');
    if (mounted) {
      setState(() {
        _pendingSigToken = null;
        _pendingSigUrl = null;
        _pendingSigCode = null;
      });
    }
  }

  Future<void> _loadPhotoRequest() async {
    final team = ref.read(teamStateProvider).valueOrNull;
    if (team?.companyId == null) return;
    final by = await TeamService()
        .getPhotoRequest(team!.companyId!, widget.report.id);
    if (mounted && by != null) setState(() => _photoRequestBy = by);
  }

  Future<void> _clearPhotoRequest() async {
    final team = ref.read(teamStateProvider).valueOrNull;
    if (team?.companyId == null) return;
    try {
      await TeamService()
          .clearPhotoRequest(team!.companyId!, widget.report.id);
      if (mounted) setState(() => _photoRequestBy = null);
    } catch (_) {}
  }

  Future<void> _applyBgSignature(String base64Sig) async {
    try {
      final updated = widget.report.copyWith(
        signatureClientData: base64Sig,
        signedRemotely: true,
      );
      await LocalDbService().updateReport(updated);
      await ref.read(reportsProvider.notifier).refresh();
      final team = ref.read(teamStateProvider).valueOrNull;
      if (team?.companyId != null) {
        await TeamService().syncReport(team!.companyId!, updated);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('rd_sig_received'.tr()),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (_) {}
  }

  Future<void> _reopenRemoteSignature() async {
    final token = _pendingSigToken;
    final url = _pendingSigUrl;
    final code = _pendingSigCode;
    if (token == null) return;
    _bgSigSub?.cancel();
    await _clearPendingSig();
    if (!mounted) return;
    final result = await showModalBottomSheet<dynamic>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => RemoteSignatureSheet(
        report: widget.report,
        initialToken: token,
        initialCode: code,
        initialShareUrl: url,
      ),
    );
    if (result == 'suspended' && mounted) {
      await _loadPendingSig();
    }
  }

  Future<void> _onEditPressed(BuildContext context, ReportModel report) async {
    // Reports signed remotely are locked — signature cannot be invalidated
    if (report.signedRemotely) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('rd_locked_remote_sig'.tr()),
        ),
      );
      return;
    }
    // Drafts and rejected reports can always be edited freely
    if (report.status == ReportStatus.draft ||
        report.status == ReportStatus.rejected) {
      context.push('/create-report?id=${report.id}');
      return;
    }
    // Pro users can edit without restriction
    if (ref.read(effectiveSubscriptionProvider)) {
      context.push('/create-report?id=${report.id}');
      return;
    }

    // For submitted/validated: free users get one edit after submission
    final prefs = await SharedPreferences.getInstance();
    final editedIds = prefs.getStringList(_editedKey) ?? [];
    if (editedIds.contains(report.id)) {
      if (context.mounted) {
        showDialog(
          context: context,
          builder: (dlg) => AlertDialog(
            title: Row(children: [
              const Icon(Icons.lock_outline, color: Colors.orange),
              const SizedBox(width: 8),
              Expanded(child: Text('rd_edit_blocked_title'.tr())),
            ]),
            content: Text('rd_edit_blocked_body'.tr()),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dlg),
                child: Text('common_ok'.tr()),
              ),
            ],
          ),
        );
      }
      return;
    }
    // First edit: warn and record
    if (!context.mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dlg) => AlertDialog(
        title: Row(children: [
          const Icon(Icons.edit_outlined, color: Colors.orange),
          const SizedBox(width: 8),
          Text('rd_edit_confirm_title'.tr()),
        ]),
        content: Text('rd_edit_confirm_body'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dlg, false),
            child: Text('common_cancel'.tr()),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dlg, true),
            child: Text('rd_edit_anyway'.tr()),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await prefs.setStringList(_editedKey, [...editedIds, report.id]);
    if (context.mounted) context.push('/create-report?id=${report.id}');
  }

  Future<Uint8List?> _loadLogoBytes() async {
    if (kIsWeb) return null;
    // (R/#6) Le logo vient des réglages locaux (l'image de l'user, pas une fuite).
    // Rapport d'ÉQUIPE → logo PROPRE à l'équipe (`team_logo_path`, repli solo) ;
    // rapport SOLO → logo solo. Le nom/SIRET suivent l'identité équipe (_pdfSettings).
    final settings = ref.read(settingsProvider).valueOrNull ?? {};
    String path;
    if (widget.report.companyId != null) {
      final teamLogo = (settings['team_logo_path'] ?? '').toString();
      path = teamLogo.isNotEmpty
          ? teamLogo
          : (settings['logo_path'] ?? '').toString();
    } else {
      path = (settings['logo_path'] ?? '').toString();
    }
    if (path.isEmpty) return null;
    final file = File(path);
    if (!file.existsSync()) return null;
    return file.readAsBytes();
  }

  // (identité équipe) Réglages ajustés pour la génération PDF / nommage : pour un
  // rapport d'ÉQUIPE (companyId non nul), les champs entreprise deviennent ceux
  // de l'ÉQUIPE (ou BLANC) — JAMAIS les infos perso. Rapport perso → réglages
  // locaux inchangés. Évite la fuite « nom équipe + SIRET perso ».
  Map<String, String> _pdfSettings() {
    final base = Map<String, String>.from(
        ref.read(settingsProvider).valueOrNull ?? <String, String>{});
    if (widget.report.companyId != null) {
      final t = ref.read(teamStateProvider).valueOrNull;
      base['company_name'] = t?.companyName ?? '';
      base['company_address'] = t?.companyAddress ?? '';
      base['company_phone'] = t?.companyPhone ?? '';
      base['company_email'] = t?.companyEmail ?? '';
      base['company_siret'] = t?.companySiret ?? '';
      base['company_tva'] = t?.companyTva ?? '';
      // (#6) Nom technicien PROPRE à l'équipe (distinct du solo, repli solo).
      final teamTech = (base['team_technician_name'] ?? '').trim();
      if (teamTech.isNotEmpty) base['technician_name'] = teamTech;
    }
    return base;
  }

  // (Chantier solo↔équipe) Nom d'entreprise à mettre sur le PDF SELON le
  // rapport : un rapport d'équipe (companyId non nul) porte le nom de l'équipe ;
  // un rapport perso porte le nom des réglages locaux. Pour un solo, c'est
  // identique à avant (companyId nul → réglages).
  String? _pdfCompanyName(Map<dynamic, dynamic> settings) {
    final team = ref.read(teamStateProvider).valueOrNull;
    if (widget.report.companyId != null &&
        (team?.companyName ?? '').trim().isNotEmpty) {
      return team!.companyName;
    }
    return settings['company_name']?.toString();
  }

  Future<Uint8List> _generatePdfBytes() async {
    final settings = _pdfSettings();
    final photos = kIsWeb
        ? <XFile>[]
        : widget.report.photosPaths
            .where((p) => File(p).existsSync())
            .map((p) => XFile(p))
            .toList();
    final logoBytes = await _loadLogoBytes();
    return PdfService().generateReport(
      widget.report,
      photos: photos,
      companyName: _pdfCompanyName(settings),
      technicianName: settings['technician_name'],
      logoBytes: logoBytes,
      companyAddress: settings['company_address'],
      companyPhone: settings['company_phone'],
      companyEmail: settings['company_email'],
      companySiret: settings['company_siret'],
      companyTva: settings['company_tva'],
      pdfTemplate: widget.report.pdfTemplate ?? settings['pdf_template'] ?? 'professionnel',
      reportNumberFormat: widget.report.reportNumberFormat ?? settings['report_number_format'] ?? '{num}',
      currencyCode: resolveCurrencyCode(
        settings,
        region: WidgetsBinding.instance.platformDispatcher.locale.countryCode,
        // `Intl.defaultLocale` (= langue de l'app) plutôt que context.locale :
        // évite l'usage de BuildContext après un await (_loadLogoBytes).
        language: Intl.defaultLocale,
      ),
    );
  }

  Future<void> _previewPdf() async {
    setState(() => _isPreviewingPdf = true);
    try {
      final bytes = await _generatePdfBytes();
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          // (1.3) Aperçu avec zoom garanti (boutons +/− + pan).
          builder: (_) => ZoomablePdfView(bytes: bytes, title: 'cr_pdf_preview'.tr()),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('rd_pdf_error'.tr(args: ['$e'])), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isPreviewingPdf = false);
    }
  }

  // Checks kill switch + subscription quota before a PDF export.
  // Free users get SubscriptionService.freeMonthlyExports per month.
  // Same report can be exported/shared multiple times without depleting the
  // counter more than once (tracked in SharedPreferences by reportId).
  Future<bool> _guardPdfExport() async {
    if (!await _guardUpload()) return false;

    // (#10) La couverture suit le TAG du rapport, pas un Pro agrégé :
    //   • rapport ÉQUIPE (companyId != null) → couvert UNIQUEMENT par l'abo équipe
    //     (siège actif). Sinon bloqué — pas de repli gratuit (anti-fraude). Un solo
    //     Pro NE couvre PAS un rapport d'équipe (décision D3).
    //   • rapport PERSO (companyId == null) → couvert par l'abo SOLO ; sinon les
    //     5 gratuits/mois (par device). Vaut aussi pour un membre d'équipe qui fait
    //     un rapport perso (identité perso → pas de fraude sous le nom de la company).
    final isTeamReport = widget.report.companyId != null;

    if (isTeamReport) {
      final companySub = ref.read(companySubscriptionProvider).valueOrNull;
      final lifetimeSeats =
          ref.read(companyLifetimeSeatsProvider).valueOrNull ?? 0;
      final companyActive = companySub.isActive || lifetimeSeats > 0;
      final memberActive = ref.read(memberActiveProvider).valueOrNull ?? true;
      if (companyActive && memberActive) return true; // couvert par l'abo équipe
      if (mounted) {
        await showDialog(
          context: context,
          builder: (dlg) => AlertDialog(
            title: Text('rd_seat_inactive_title'.tr()),
            content: Text('rd_seat_inactive_body'.tr()),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(dlg),
                child: Text('common_understood'.tr()),
              ),
            ],
          ),
        );
      }
      return false;
    }

    // Rapport PERSO couvert par l'abo SOLO → illimité (sans toucher le compteur
    // gratuit du device, qui ne doit décompter QUE les exports réellement gratuits).
    if (ref.read(subscriptionProvider).valueOrNull.isActive) return true;

    // Check if this report was already counted this month
    final now = DateTime.now();
    final monthKey =
        'exported_ids_${now.year}_${now.month.toString().padLeft(2, '0')}';
    final prefs = await SharedPreferences.getInstance();
    final exported = prefs.getStringList(monthKey) ?? [];
    final alreadyCounted = exported.contains(widget.report.id);

    if (alreadyCounted) return true; // re-share same report = free

    // (#quota-double) Protection DOUBLE NÉGATIVE : bloqué si le DEVICE *ou* le
    // COMPTE a atteint la limite → un nouveau téléphone avec le MÊME compte ne
    // réinitialise PAS les 5 (le compteur compte vit dans Firestore). Le compteur
    // compte est best-effort (null si offline/règles → on applique le device seul).
    final deviceCount = await SubscriptionService.getMonthlyExportCount();
    final accountCount =
        await SubscriptionService.getAccountMonthlyExportCount();
    final reachedLimit =
        deviceCount >= SubscriptionService.freeMonthlyExports ||
            (accountCount != null &&
                accountCount >= SubscriptionService.freeMonthlyExports);
    if (reachedLimit) {
      if (mounted) {
        await PaywallBottomSheet.show(
          context,
          reason:
              'rd_quota_reached'.tr(args: ['${SubscriptionService.freeMonthlyExports}']),
        );
      }
      return false;
    }

    await SubscriptionService.incrementExportCount(); // device
    await SubscriptionService.incrementAccountExportCount(); // compte (best-effort)
    await prefs.setStringList(monthKey, [...exported, widget.report.id]);
    return true;
  }

  Future<void> _sharePdf() async {
    if (!await _guardPdfExport()) return;
    setState(() => _isGeneratingPdf = true);
    try {
      final bytes = await _generatePdfBytes();
      final clientSlug = widget.report.clientName
          .replaceAll(' ', '_')
          .replaceAll(RegExp(r'[^\w]'), '');
      final filename =
          '${'file_report_prefix'.tr()}_${clientSlug}_${widget.report.id.substring(0, 8)}.pdf';
      await Printing.sharePdf(
          bytes: bytes, filename: filename, bounds: shareOrigin(context));

      final s = _pdfSettings();
      final user = ref.read(firebaseUserProvider).valueOrNull;
      AnalyticsService.log(
        event: 'pdf_shared',
        userUid: user?.uid,
        userName: user?.displayName,
        clientName: widget.report.clientName,
        companyName: _pdfCompanyName(s),
        technicianName: s['technician_name'],
        reportNumber: widget.report.reportNumber,
        sector: widget.report.sector.label,
        interventionType: widget.report.interventionType,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('rd_pdf_error'.tr(args: ['$e'])),
              backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isGeneratingPdf = false);
    }
  }

  Future<void> _generateInvoice() async {
    if (!ref.read(effectiveSubscriptionProvider)) {
      await PaywallBottomSheet.show(
        context,
        reason: 'rd_invoice_pro'.tr(),
      );
      return;
    }
    setState(() => _isGeneratingInvoice = true);
    try {
      final s = _pdfSettings();
      final report = widget.report;
      // Défaut global de taxe (les Réglages) ; le rapport peut l'override.
      final globalTax = resolveGlobalTax(
        s,
        region: WidgetsBinding.instance.platformDispatcher.locale.countryCode,
        language: context.locale.languageCode,
      );
      final bytes = await PdfService().generateInvoice(
        report,
        companyName: _pdfCompanyName(s),
        companyAddress: s['company_address'],
        companyPhone: s['company_phone'],
        companyEmail: s['company_email'],
        companySiret: s['company_siret'],
        taxRate: globalTax.rate,
        taxLabel: globalTax.label,
        taxMention: globalTax.mention,
        currencyCode: resolveCurrencyCode(
          s,
          region: WidgetsBinding.instance.platformDispatcher.locale.countryCode,
          language: context.locale.languageCode,
        ),
      );
      final dir = await getTemporaryDirectory();
      final invoiceNum =
          '${'pdf_invoice_prefix'.tr()}-${report.reportNumber.toString().padLeft(3, '0')}-${DateTime.now().year}';
      final file = File('${dir.path}/$invoiceNum.pdf');
      await file.writeAsBytes(bytes);
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'application/pdf')],
        subject: invoiceNum,
        sharePositionOrigin: shareOrigin(context),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('rd_invoice_error'.tr(args: ['$e'])),
              backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isGeneratingInvoice = false);
    }
  }

  void _showSaveTemplateDialog(BuildContext context, ReportModel report) {
    // (C) Modèles réservés au Pro (comme facture / signature distante).
    if (!ref.read(effectiveSubscriptionProvider)) {
      PaywallBottomSheet.show(
        context,
        reason: 'rd_templates_pro'.tr(),
      );
      return;
    }
    final nameCtrl = TextEditingController(
        text: report.interventionType.isNotEmpty
            ? report.interventionType
            : report.clientName.isNotEmpty
                ? report.clientName
                : 'rd_template_default'.tr());
    showDialog(
      context: context,
      builder: (dlg) => AlertDialog(
        title: Row(children: [
          const Icon(Icons.copy_outlined, color: AppColors.primary),
          const SizedBox(width: 8),
          Flexible(child: Text('rd_save_template_title'.tr())),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'rd_save_template_note'.tr(),
              style: const TextStyle(fontSize: 13, color: Colors.black54),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: nameCtrl,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'rd_template_name'.tr(),
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dlg),
            child: Text('common_cancel'.tr()),
          ),
          FilledButton(
            onPressed: () async {
              final name = nameCtrl.text.trim();
              if (name.isEmpty) return;
              Navigator.pop(dlg);
              final preset = ReportPreset(
                id: const Uuid().v4(),
                name: name,
                createdAt: DateTime.now(),
                data: report.toMap(),
              );
              await LocalDbService().savePreset(preset);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('rd_template_saved'.tr(args: [name])),
                    backgroundColor: AppColors.success,
                  ),
                );
              }
            },
            child: Text('common_save'.tr()),
          ),
        ],
      ),
    );
  }

  // ignore: unused_element
  Future<void> _savePdfLocally() async {
    if (kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('rd_save_local_web'.tr())),
      );
      return;
    }
    setState(() => _isSavingPdf = true);
    try {
      final bytes = await _generatePdfBytes();
      final dir = await getApplicationDocumentsDirectory();
      final clientSlug = widget.report.clientName
          .replaceAll(' ', '_')
          .replaceAll(RegExp(r'[^\w]'), '');
      final filename =
          '${'file_report_prefix'.tr()}_${clientSlug}_${widget.report.id.substring(0, 8)}.pdf';
      final file = File('${dir.path}/$filename');
      await file.writeAsBytes(bytes);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('rd_pdf_saved'.tr(args: [filename])),
            backgroundColor: AppColors.success,
            action: SnackBarAction(
              label: 'rd_share'.tr(),
              textColor: Colors.white,
              onPressed: _sharePdf,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('common_error'.tr(args: ['$e'])), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSavingPdf = false);
    }
  }

  String _buildTextReport() {
    final r = widget.report;
    final s = _pdfSettings();
    final company = s['company_name'] ?? '';
    final tech = s['technician_name'] ?? '';
    final date = DateFormat.yMMMMd().format(r.date);
    final buf = StringBuffer();

    buf.writeln('${'pdf_report_title'.tr()}${r.reportNumber > 0 ? ' #${r.reportNumber.toString().padLeft(3, '0')}' : ''}');
    if (company.isNotEmpty) buf.writeln(company);
    if (tech.isNotEmpty) buf.writeln('${'pdf_lbl_technician'.tr()} : $tech');
    buf.writeln('pdf_date_prefix'.tr(args: [date]));
    if (r.startTime != null || r.endTime != null) {
      buf.writeln('${'tx_schedule'.tr()} : ${_horaireStr(r)}');
    }
    buf.writeln();

    buf.writeln('── ${'pdf_sec_client'.tr()} ──');
    buf.writeln('${'pdf_lbl_name'.tr()} : ${r.clientName.isEmpty ? "—" : r.clientName}');
    if (r.clientAddress.isNotEmpty) buf.writeln('${'pdf_lbl_address'.tr()} : ${r.clientAddress}');
    if (r.clientPhone.isNotEmpty) buf.writeln('${'pdf_lbl_phone'.tr()} : ${r.clientPhone}');
    if (r.clientContact.isNotEmpty) buf.writeln('${'pdf_lbl_contact_short'.tr()} : ${r.clientContact}');
    if (r.contractNumber.isNotEmpty) buf.writeln('${'pdf_lbl_contract'.tr()} : ${r.contractNumber}');
    buf.writeln();

    buf.writeln('── ${'pdf_sec_intervention'.tr()} ──');
    if (r.sector != SectorTemplate.generic) buf.writeln('${'tx_sector'.tr()} : ${r.sector.label}');
    if (r.interventionType.isNotEmpty) buf.writeln('${'pdf_lbl_type'.tr()} : ${r.interventionType}');
    if (r.sectorFields.isNotEmpty) {
      for (final e in r.sectorFields.entries) {
        if (e.value != null && e.value.toString().isNotEmpty) {
          buf.writeln('${_formatKey(e.key)} : ${sectorValueLabel(e.value.toString())}');
        }
      }
    }
    buf.writeln();

    if (r.description.isNotEmpty) {
      buf.writeln('── ${'pdf_sec_work'.tr()} ──');
      buf.writeln(r.description);
      buf.writeln();
    }
    if (r.observations.isNotEmpty) {
      buf.writeln('── ${'pdf_observations'.tr()} ──');
      buf.writeln(r.observations);
      buf.writeln();
    }

    if (r.laborHours != null || r.materials.isNotEmpty) {
      buf.writeln('── ${'pdf_sec_billing'.tr()} ──');
      if (r.laborHours != null) {
        final labor = r.laborHours! * (r.laborRate ?? 0);
        buf.writeln('${'pdf_lbl_labor'.tr()} : ${formatQuantity(r.laborHours!)} h × ${_money(r.laborRate ?? 0)}/h = ${_money(labor)}');
      }
      for (final m in r.materials) {
        buf.writeln('• ${m.label} × ${formatQuantity(m.quantity)} = ${_money(m.total)}');
      }
      buf.writeln('${'pdf_total_ht'.tr()}${_totalStr(r)}');
    }

    return buf.toString().trim();
  }

  String _buildJsonReport() {
    final r = widget.report;
    final s = _pdfSettings();
    final map = <String, dynamic>{
      'reportNumber': r.reportNumber,
      'exportedAt': DateTime.now().toIso8601String(),
      'company': s['company_name'] ?? '',
      'technician': s['technician_name'] ?? '',
      'status': r.status.name,
      'date': r.date.toIso8601String(),
      'startTime': r.startTime?.toIso8601String(),
      'endTime': r.endTime?.toIso8601String(),
      'client': {
        'name': r.clientName,
        'address': r.clientAddress,
        'phone': r.clientPhone,
        'contact': r.clientContact,
        'contractNumber': r.contractNumber,
      },
      'intervention': {
        'sector': r.sector.name,
        'type': r.interventionType,
        'description': r.description,
        'observations': r.observations,
        'sectorFields': r.sectorFields,
      },
      'equipment': {
        'type': r.equipmentType,
        'brand': r.equipmentBrand,
        'model': r.equipmentModel,
        'serial': r.equipmentSerial,
      },
      'billing': {
        'laborHours': r.laborHours,
        'laborRate': r.laborRate,
        'materials': r.materials
            .map((m) => {
                  'label': m.label,
                  'quantity': m.quantity,
                  'unitPrice': m.unitPrice,
                  'total': m.total,
                })
            .toList(),
        'totalHT': _totalStr(r),
      },
      'photos': r.photosPaths.length,
      'hasClientSignature': r.signatureClientData != null,
      'hasTechSignature': r.signatureTechData != null,
    };
    return const JsonEncoder.withIndent('  ').convert(map);
  }

  Future<void> _shareAsHtml() async {
    final r = widget.report;
    final s = _pdfSettings();
    final company = s['company_name'] ?? '';
    final tech = s['technician_name'] ?? '';
    final date = DateFormat.yMMMMd().format(r.date);

    String row(String label, String value) =>
        value.isEmpty ? '' : '<tr><td class="lbl">$label</td><td>$value</td></tr>';

    String section(String title, String content) =>
        '<h2>$title</h2><table>$content</table>';

    final billingRows = StringBuffer();
    if (r.laborHours != null) {
      final labor = r.laborHours! * (r.laborRate ?? 0);
      billingRows.write(row('pdf_lbl_labor'.tr(),
          '${formatQuantity(r.laborHours!)} h × ${_money(r.laborRate ?? 0)}/h = ${_money(labor)}'));
    }
    for (final m in r.materials) {
      billingRows.write(row(m.label, '${formatQuantity(m.quantity)} × ${_money(m.unitPrice)} = ${_money(m.total)}'));
    }
    if (billingRows.isNotEmpty) {
      billingRows.write(row('pdf_col_total'.tr(), _totalStr(r)));
    }

    final sectorRows = r.sectorFields.entries
        .where((e) => e.value != null && e.value.toString().isNotEmpty)
        .map((e) => row(_formatKey(e.key), sectorValueLabel(e.value.toString())))
        .join();

    final html = '''<!DOCTYPE html>
<html lang="${context.locale.languageCode}">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${'tx_html_title'.tr(args: [r.reportNumber.toString().padLeft(3, '0')])}</title>
<style>
  body { font-family: Arial, sans-serif; max-width: 800px; margin: 0 auto; padding: 24px; color: #222; }
  header { background: #1565C0; color: white; padding: 20px 24px; border-radius: 8px; margin-bottom: 24px; }
  header h1 { margin: 0 0 4px; font-size: 20px; }
  header p { margin: 0; opacity: .85; font-size: 13px; }
  h2 { color: #1565C0; font-size: 14px; text-transform: uppercase; letter-spacing: 1px; margin: 20px 0 6px; border-bottom: 1px solid #e0e0e0; padding-bottom: 4px; }
  table { width: 100%; border-collapse: collapse; margin-bottom: 8px; }
  td { padding: 5px 8px; font-size: 13px; vertical-align: top; }
  td.lbl { color: #666; width: 160px; }
  .desc { white-space: pre-wrap; font-size: 13px; background: #f9f9f9; padding: 10px; border-radius: 6px; }
  .total { font-weight: bold; border-top: 1px solid #ccc; }
</style>
</head>
<body>
<header>
  <h1>${'tx_report_heading'.tr()}${r.reportNumber > 0 ? ' #${r.reportNumber.toString().padLeft(3, '0')}' : ''}</h1>
  <p>${company.isNotEmpty ? '$company${tech.isNotEmpty ? ' · ' : ''}' : ''}${tech.isNotEmpty ? 'pdf_tech_prefix'.tr(args: [tech]) : ''} · $date</p>
</header>

${section('pdf_sec_client'.tr(), [
      row('pdf_lbl_name'.tr(), r.clientName),
      row('pdf_lbl_address'.tr(), r.clientAddress),
      row('pdf_lbl_phone'.tr(), r.clientPhone),
      row('pdf_lbl_contact_short'.tr(), r.clientContact),
      row('pdf_lbl_contract'.tr(), r.contractNumber),
    ].join())}

${section('pdf_sec_intervention'.tr(), [
      row('tx_sector'.tr(), r.sector != SectorTemplate.generic ? r.sector.label : ''),
      row('pdf_lbl_type'.tr(), r.interventionType),
      row('tx_schedule'.tr(), r.startTime != null || r.endTime != null ? _horaireStr(r) : ''),
      sectorRows,
    ].join())}

${r.description.isNotEmpty ? '<h2>${'pdf_sec_work'.tr()}</h2><div class="desc">${r.description}</div>' : ''}
${r.observations.isNotEmpty ? '<h2>${'pdf_observations'.tr()}</h2><div class="desc">${r.observations}</div>' : ''}
${billingRows.isNotEmpty ? section('pdf_sec_billing'.tr(), billingRows.toString()) : ''}

</body>
</html>''';

    try {
      final dir = await getTemporaryDirectory();
      final slug = r.clientName.replaceAll(RegExp(r'[^\w]'), '_');
      final file = File('${dir.path}/${'file_report_prefix'.tr()}_${slug}_${r.id.substring(0, 8)}.html');
      await file.writeAsString(html);
      await Share.shareXFiles([XFile(file.path, mimeType: 'text/html')],
          subject: 'tx_html_title'.tr(args: [r.reportNumber.toString().padLeft(3, '0')]),
          sharePositionOrigin: shareOrigin(context));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('tx_html_error'.tr(args: ['$e'])), backgroundColor: Colors.red),
        );
      }
    }
  }

  // ignore: unused_element
  void _showOtherFormats(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('rd_other_formats'.tr(),
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.text_snippet_outlined, color: AppColors.primary),
                title: Text('rd_share_text'.tr()),
                subtitle: Text('rd_share_text_sub'.tr(), style: const TextStyle(fontSize: 12)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.pop(ctx);
                  Share.share(_buildTextReport(),
                      sharePositionOrigin: shareOrigin(context));
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.data_object, color: AppColors.primary),
                title: Text('rd_export_json'.tr()),
                subtitle: Text('rd_export_json_sub'.tr(), style: const TextStyle(fontSize: 12)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.pop(ctx);
                  Share.share(
                    _buildJsonReport(),
                    subject: '${'tx_html_title'.tr(args: [widget.report.reportNumber.toString().padLeft(3, '0')])}.json',
                    sharePositionOrigin: shareOrigin(context),
                  );
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.html_outlined, color: AppColors.primary),
                title: Text('rd_export_html'.tr()),
                subtitle: Text('rd_export_html_sub'.tr(), style: const TextStyle(fontSize: 12)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.pop(ctx);
                  _shareAsHtml();
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.copy_outlined, color: AppColors.primary),
                title: Text('rd_copy_clipboard'.tr()),
                subtitle: Text('rd_copy_clipboard_sub'.tr(), style: const TextStyle(fontSize: 12)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.pop(ctx);
                  Clipboard.setData(ClipboardData(text: _buildTextReport()));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('rd_copied_clipboard'.tr())),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _uploadToGoogleDrive() async {
    if (!mounted) return;
    if (!await _guardUpload()) return;
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        content: Row(children: [
          const CircularProgressIndicator(),
          const SizedBox(width: 16),
          Expanded(child: Text('rd_uploading_drive'.tr())),
        ]),
      ),
    );

    try {
      final settings = _pdfSettings();
      final bytes = await _generatePdfBytes();
      final slug = widget.report.clientName
          .replaceAll(' ', '_')
          .replaceAll(RegExp(r'[^\w]'), '');
      final filename =
          '${'file_report_prefix'.tr()}_${slug}_${widget.report.id.substring(0, 8)}.pdf';

      final link = await GoogleDriveService.uploadPdf(
        bytes,
        filename,
        companyName: _pdfCompanyName(settings),
        technicianName: settings['technician_name'],
        folderPattern: settings['drive_folder_pattern'],
      );
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop(); // dismiss loading dialog (on root navigator)

      if (link == null) return; // user cancelled sign-in

      showDialog(
        context: context,
        builder: (dlg) => AlertDialog(
          title: Row(children: [
            const Icon(Icons.check_circle, color: Colors.green),
            const SizedBox(width: 8),
            Text('rd_sent_to_drive'.tr()),
          ]),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                  'rd_drive_deposited'.tr(args: ['${GoogleDriveService.folderNameFor(settings['company_name'])}'])),
              const SizedBox(height: 12),
              Text('rd_share_link'.tr(),
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 12)),
              const SizedBox(height: 4),
              SelectableText(link,
                  style:
                      const TextStyle(fontSize: 11, color: Colors.blue)),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dlg),
                child: Text('common_close'.tr())),
            ElevatedButton.icon(
              onPressed: () {
                final messenger = ScaffoldMessenger.of(dlg);
                Navigator.pop(dlg);
                Clipboard.setData(ClipboardData(text: link));
                messenger.showSnackBar(
                  SnackBar(content: Text('rd_link_copied'.tr())),
                );
              },
              icon: const Icon(Icons.copy, size: 16),
              label: Text('rd_copy_link'.tr()),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop(); // dismiss loading dialog
      showDialog(
        context: context,
        builder: (dlg) => AlertDialog(
          title: Text('rd_drive_error'.tr()),
          content: Text(e.toString()),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dlg),
                child: Text('common_close'.tr())),
          ],
        ),
      );
    }
  }

  Future<void> _uploadToCloud(
    String serviceName,
    String loadingMsg,
    String successTitle,
    Future<String?> Function(Map<String, String> settings) doUpload,
  ) async {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        content: Row(children: [
          const CircularProgressIndicator(),
          const SizedBox(width: 16),
          Expanded(child: Text(loadingMsg)),
        ]),
      ),
    );
    try {
      final settings = _pdfSettings();
      final link = await doUpload(settings);
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop(); // dismiss loading dialog
      if (link == null) return;
      final user = ref.read(firebaseUserProvider).valueOrNull;
      AnalyticsService.log(
        event: 'pdf_uploaded_${serviceName.toLowerCase()}',
        userUid: user?.uid,
        userName: user?.displayName,
        clientName: widget.report.clientName,
        companyName: _pdfCompanyName(settings),
        technicianName: settings['technician_name'],
        reportNumber: widget.report.reportNumber,
        sector: widget.report.sector.label,
        interventionType: widget.report.interventionType,
      );
      showDialog(
        context: context,
        builder: (dlg) => AlertDialog(
          title: Row(children: [
            const Icon(Icons.check_circle, color: Colors.green),
            const SizedBox(width: 8),
            Text(successTitle),
          ]),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('rd_share_link'.tr(),
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
              const SizedBox(height: 4),
              SelectableText(link,
                  style: const TextStyle(fontSize: 11, color: Colors.blue)),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dlg),
                child: Text('common_close'.tr())),
            ElevatedButton.icon(
              onPressed: () {
                final messenger = ScaffoldMessenger.of(dlg);
                Navigator.pop(dlg);
                Clipboard.setData(ClipboardData(text: link));
                messenger.showSnackBar(
                  SnackBar(content: Text('rd_link_copied'.tr())),
                );
              },
              icon: const Icon(Icons.copy, size: 16),
              label: Text('rd_copy_link'.tr()),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop(); // dismiss loading dialog
      showDialog(
        context: context,
        builder: (dlg) => AlertDialog(
          title: Text('rd_cloud_error'.tr(args: [serviceName])),
          content: Text(e.toString()),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dlg),
                child: Text('common_close'.tr())),
          ],
        ),
      );
    }
  }

  Future<void> _uploadToOneDrive() async {
    if (!await _guardUpload()) return;
    await _uploadToCloud(
      'OneDrive',
      'rd_uploading_onedrive'.tr(),
      'rd_sent_to_onedrive'.tr(),
      (settings) async {
        final bytes = await _generatePdfBytes();
        final slug = widget.report.clientName
            .replaceAll(' ', '_')
            .replaceAll(RegExp(r'[^\w]'), '');
        final filename =
            '${'file_report_prefix'.tr()}_${slug}_${widget.report.id.substring(0, 8)}.pdf';
        return OneDriveService.uploadPdf(
          bytes,
          filename,
          companyName: _pdfCompanyName(settings),
          technicianName: settings['technician_name'],
          folderPattern: settings['drive_folder_pattern'],
        );
      },
    );
  }

  Future<void> _uploadToDropbox() async {
    if (!await _guardUpload()) return;
    await _uploadToCloud(
      'Dropbox',
      'rd_uploading_dropbox'.tr(),
      'rd_sent_to_dropbox'.tr(),
      (settings) async {
        final bytes = await _generatePdfBytes();
        final slug = widget.report.clientName
            .replaceAll(' ', '_')
            .replaceAll(RegExp(r'[^\w]'), '');
        final filename =
            '${'file_report_prefix'.tr()}_${slug}_${widget.report.id.substring(0, 8)}.pdf';
        return DropboxService.uploadPdf(
          bytes,
          filename,
          companyName: _pdfCompanyName(settings),
          technicianName: settings['technician_name'],
          folderPattern: settings['drive_folder_pattern'],
        );
      },
    );
  }

  /// Returns true if the app is active (kill switch allows). Shows a dialog and
  /// returns false if blocked. Uses the cached result — no extra Firestore read
  /// if the cache is still fresh from app launch or a recent check.
  Future<bool> _guardUpload() async {
    final result = await KillSwitchService.check();
    if (result.allowed) return true;
    if (!mounted) return false;
    showDialog(
      context: context,
      builder: (dlg) => AlertDialog(
        title: Text('service_unavailable_title'.tr()),
        content: Text(result.message),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dlg),
              child: Text('common_close'.tr())),
        ],
      ),
    );
    return false;
  }

  Future<void> _showNumberOverride(BuildContext context, ReportModel report) async {
    final ctrl = TextEditingController(
        text: report.reportNumber > 0 ? report.reportNumber.toString() : '');
    await showDialog(
      context: context,
      builder: (dlg) => AlertDialog(
        title: Text('rd_number_title'.tr()),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: 'rd_number_label'.tr(),
            hintText: report.reportNumber.toString(),
            isDense: true,
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dlg),
              child: Text('common_cancel'.tr())),
          ElevatedButton(
            onPressed: () async {
              final v = int.tryParse(ctrl.text.trim());
              if (v == null || v <= 0) return;
              final updated = report.copyWith(reportNumber: v);
              await ref.read(reportsProvider.notifier).saveReport(updated);
              if (dlg.mounted) Navigator.pop(dlg);
            },
            child: Text('common_save'.tr()),
          ),
        ],
      ),
    );
  }

  Future<void> _showTemplateOverride(BuildContext context, ReportModel report) async {
    final settings = _pdfSettings();
    final globalTemplate = settings['pdf_template'] ?? 'professionnel';
    String? selected = report.pdfTemplate;

    await showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Text('rd_template_pdf_title'.tr()),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RadioGroup<String?>(
                groupValue: selected,
                onChanged: (v) => setS(() => selected = v),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    RadioListTile<String?>(
                      value: null,
                      title: Text('rd_template_default_opt'.tr(args: [globalTemplate == 'professionnel' ? 'rd_template_pro_name'.tr() : 'rd_template_simple'.tr()])),
                      subtitle: Text('rd_follows_global'.tr(), style: const TextStyle(fontSize: 11)),
                    ),
                    RadioListTile<String?>(
                      value: 'simple',
                      title: Text('rd_template_simple'.tr()),
                      subtitle: Text('rd_template_simple_sub'.tr(), style: const TextStyle(fontSize: 11)),
                    ),
                    RadioListTile<String?>(
                      value: 'professionnel',
                      title: Text('rd_template_pro_name'.tr()),
                      subtitle: Text('rd_template_pro_sub'.tr(), style: const TextStyle(fontSize: 11)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text('common_cancel'.tr())),
            ElevatedButton(
              onPressed: () async {
                final updated = selected == null
                    ? report.copyWith(clearPdfTemplate: true)
                    : report.copyWith(pdfTemplate: selected);
                await ref.read(reportsProvider.notifier).saveReport(updated);
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: Text('common_apply'.tr()),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showFormatOverride(BuildContext context, ReportModel report) async {
    final settings = _pdfSettings();
    final globalFormat = settings['report_number_format'] ?? '{num}';

    const presets = [
      ('{num}', 'fmt_preset_simple', '001'),
      ('{year}-{num}', 'fmt_preset_annual', '2026-001'),
      ('{year}/{num}', 'fmt_preset_year_num', '2026/001'),
      ('{company}/{year}/{month}/{day}/{num}', 'fmt_preset_company_date', 'AMARIS/2026/04/23/001'),
      ('{client}-{num}', 'fmt_preset_client_num', 'DUPONT-001'),
    ];

    String? selected = report.reportNumberFormat;
    final isCustom = selected != null && !presets.any((p) => p.$1 == selected);
    final customCtrl = TextEditingController(text: isCustom ? selected : '');
    bool showCustom = isCustom;

    await showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Text('fmt_override_title'.tr()),
          content: Scrollbar(
            thumbVisibility: true,
            child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    ChoiceChip(
                      label: Text('fmt_global_default'.tr(), style: const TextStyle(fontSize: 12)),
                      selected: selected == null && !showCustom,
                      visualDensity: VisualDensity.compact,
                      tooltip: PdfService.resolveReportNumber(report.reportNumber > 0 ? report.reportNumber : 1, globalFormat, clientName: report.clientName.isNotEmpty ? report.clientName : 'Client', date: report.date, technicianName: settings['technician_name'], companyName: _pdfCompanyName(settings)),
                      onSelected: (_) => setS(() { selected = null; showCustom = false; }),
                    ),
                    ...presets.map((p) {
                      final (value, label, example) = p;
                      return ChoiceChip(
                        label: Text(label.tr(), style: const TextStyle(fontSize: 12)),
                        selected: !showCustom && selected == value,
                        visualDensity: VisualDensity.compact,
                        tooltip: 'common_example'.tr(args: [example]),
                        onSelected: (_) => setS(() { selected = value; showCustom = false; }),
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
                if (!showCustom && selected != null) ...[
                  const SizedBox(height: 6),
                  Text('common_example'.tr(args: [PdfService.resolveReportNumber(report.reportNumber > 0 ? report.reportNumber : 1, selected!, clientName: report.clientName.isNotEmpty ? report.clientName : 'Client', date: report.date, technicianName: settings['technician_name'], companyName: _pdfCompanyName(settings))]),
                      style: const TextStyle(fontSize: 11, color: Colors.blue)),
                ],
                if (showCustom) ...[
                  const SizedBox(height: 8),
                  TextField(
                    controller: customCtrl,
                    decoration: const InputDecoration(hintText: '{client}-{num}', isDense: true),
                    onChanged: (_) => setS(() {}),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      for (final (token, label, isSep) in [
                        ('{num}', 'fmt_token_num'.tr(), false),
                        ('{client}', 'fmt_token_client'.tr(), false),
                        ('{company}', 'fmt_token_company'.tr(), false),
                        ('{year}', 'fmt_token_year'.tr(), false),
                        ('{month}', 'fmt_token_month'.tr(), false),
                        ('{day}', 'fmt_token_day'.tr(), false),
                        ('/', '/', true),
                        ('-', '-', true),
                        ('_', '_', true),
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
                  Text(
                    'fmt_preview'.tr(args: [PdfService.resolveReportNumber(report.reportNumber > 0 ? report.reportNumber : 1, customCtrl.text.isEmpty ? '{num}' : customCtrl.text, clientName: report.clientName.isNotEmpty ? report.clientName : 'Client', date: report.date, technicianName: settings['technician_name'], companyName: _pdfCompanyName(settings))]),
                    style: const TextStyle(fontSize: 11, color: Colors.blue),
                  ),
                ],
              ],
            ),
          ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text('common_cancel'.tr())),
            ElevatedButton(
              onPressed: () async {
                final ReportModel updated;
                if (selected == null && !showCustom) {
                  updated = report.copyWith(clearReportNumberFormat: true);
                } else {
                  final fmt = showCustom
                      ? (customCtrl.text.trim().isEmpty ? '{num}' : customCtrl.text.trim())
                      : selected!;
                  updated = report.copyWith(reportNumberFormat: fmt);
                }
                await ref.read(reportsProvider.notifier).saveReport(updated);
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: Text('fmt_apply'.tr()),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showTitleEditDialog(BuildContext context, ReportModel report) async {
    final settings = _pdfSettings();
    final numCtrl = TextEditingController(
        text: report.reportNumber > 0 ? report.reportNumber.toString() : '');

    const presets = [
      ('{num}', 'fmt_preset_simple', '001'),
      ('{year}-{num}', 'fmt_preset_annual', '2026-001'),
      ('{year}/{num}', 'fmt_preset_year_num', '2026/001'),
      ('{company}/{year}/{month}/{day}/{num}', 'fmt_preset_company_date', 'AMARIS/2026/04/23/001'),
      ('{client}-{num}', 'fmt_preset_client_num', 'DUPONT-001'),
      ('{client}/{year}/{month}/{day}/{num}', 'fmt_preset_client_date', 'DUPONT/2026/05/18/001'),
    ];

    String? fmtSelected = report.reportNumberFormat;

    await showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setS) {
          String preview(String fmt) => PdfService.resolveReportNumber(
            numCtrl.text.isNotEmpty ? (int.tryParse(numCtrl.text) ?? report.reportNumber) : report.reportNumber,
            fmt,
            clientName: report.clientName.isNotEmpty ? report.clientName : 'Client',
            date: report.date,
            technicianName: settings['technician_name'],
            companyName: _pdfCompanyName(settings),
          );

          return AlertDialog(
            title: Text('fmt_num_and_format'.tr()),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: numCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'fmt_token_num'.tr(),
                      hintText: report.reportNumber.toString(),
                      isDense: true,
                    ),
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
                        selected: fmtSelected == null,
                        visualDensity: VisualDensity.compact,
                        onSelected: (_) => setS(() => fmtSelected = null),
                      ),
                      ...presets.map((p) {
                        final (value, label, _) = p;
                        return ChoiceChip(
                          label: Text(label.tr(), style: const TextStyle(fontSize: 12)),
                          selected: fmtSelected == value,
                          visualDensity: VisualDensity.compact,
                          onSelected: (_) => setS(() => fmtSelected = value),
                        );
                      }),
                    ],
                  ),
                  if (fmtSelected != null) ...[
                    const SizedBox(height: 6),
                    Text('common_example'.tr(args: [preview(fmtSelected!)]),
                        style: const TextStyle(fontSize: 11, color: Colors.blue)),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: Text('common_cancel'.tr())),
              ElevatedButton(
                onPressed: () async {
                  final v = int.tryParse(numCtrl.text.trim());
                  final updatedNum = v != null && v > 0 ? v : report.reportNumber;
                  final updated = fmtSelected == null
                      ? report.copyWith(reportNumber: updatedNum, clearReportNumberFormat: true)
                      : report.copyWith(reportNumber: updatedNum, reportNumberFormat: fmtSelected);
                  await ref.read(reportsProvider.notifier).saveReport(updated);
                  if (ctx.mounted) Navigator.pop(ctx);
                },
                child: Text('fmt_apply'.tr()),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _requestNewRemoteSignature(BuildContext context, ReportModel report) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dlg) => AlertDialog(
        title: Text('rd_new_sig_title'.tr()),
        content: Text('rd_new_sig_body'.tr()),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dlg, false),
              child: Text('common_cancel'.tr())),
          FilledButton(
            onPressed: () => Navigator.pop(dlg, true),
            child: Text('common_continue'.tr()),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    // Clear the old remote signature lock before opening the sheet
    final cleared = report.copyWith(
      signedRemotely: false,
      clearSignatureClient: true,
    );
    await LocalDbService().updateReport(cleared);
    await ref.read(reportsProvider.notifier).refresh();

    if (!context.mounted) return;
    _requestRemoteSignature(context);
  }

  Future<void> _requestRemoteSignature(BuildContext context) async {
    if (ref.read(firebaseUserProvider).valueOrNull == null) return;
    final result = await showModalBottomSheet<dynamic>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => RemoteSignatureSheet(report: widget.report),
    );
    if (result == 'suspended' && mounted) {
      await _loadPendingSig();
    }
  }

  void _showCloudOptions() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _CloudOptionsSheet(
        report: widget.report,
        onGoogleDriveTap: _uploadToGoogleDrive,
        onOneDriveTap: _uploadToOneDrive,
        onDropboxTap: _uploadToDropbox,
        onShareText: () => Share.share(_buildTextReport(),
            sharePositionOrigin: shareOrigin(context)),
        onShareJson: () => Share.share(
          _buildJsonReport(),
          subject:
              '${'tx_html_title'.tr(args: [widget.report.reportNumber.toString().padLeft(3, '0')])}.json',
          sharePositionOrigin: shareOrigin(context),
        ),
        onShareHtml: _shareAsHtml,
        onCopyText: () {
          Clipboard.setData(ClipboardData(text: _buildTextReport()));
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text('rd_copied_clipboard'.tr())),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Always use latest from provider so title updates immediately after edits
    final report = ref.watch(reportsProvider).valueOrNull
            ?.where((r) => r.id == widget.report.id).firstOrNull
        ?? widget.report;
    final fmt = DateFormat.yMd();
    final dateStr = report.endDate != null
        ? 'rd_date_range'.tr(args: [fmt.format(report.date), fmt.format(report.endDate!)])
        : DateFormat.yMMMMd().format(report.date);

    return Scaffold(
      appBar: AppBar(
        title: GestureDetector(
          onTap: () => _showTitleEditDialog(context, report),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  report.clientName.isEmpty
                      ? 'rd_appbar_default'.tr()
                      : report.reportNumber > 0
                          ? '#${report.reportNumber.toString().padLeft(3, '0')} · ${report.clientName}'
                          : report.clientName,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.edit, size: 14, color: Colors.white54),
            ],
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'cr_modify'.tr(),
            onPressed: () => _onEditPressed(context, report),
          ),
          PopupMenuButton<String>(
            onSelected: (val) async {
              if (val == 'duplicate') {
                final nextNum =
                    await LocalDbService().getNextReportNumber();
                final now = DateTime.now();
                final copy = ReportModel(
                  id: const Uuid().v4(),
                  reportNumber: nextNum,
                  reportNumberFormat: report.reportNumberFormat,
                  clientId: report.clientId,
                  clientName: report.clientName,
                  clientAddress: report.clientAddress,
                  clientPhone: report.clientPhone,
                  clientContact: report.clientContact,
                  contractNumber: report.contractNumber,
                  interventionType: report.interventionType,
                  sector: report.sector,
                  date: now,
                  startTime: report.startTime,
                  endTime: report.endTime,
                  description: report.description,
                  observations: report.observations,
                  equipmentType: report.equipmentType,
                  equipmentBrand: report.equipmentBrand,
                  equipmentModel: report.equipmentModel,
                  equipmentSerial: report.equipmentSerial,
                  sectorFields: Map.from(report.sectorFields),
                  laborHours: report.laborHours,
                  laborRate: report.laborRate,
                  materials: List.from(report.materials),
                  status: ReportStatus.draft,
                  createdAt: now,
                  updatedAt: now,
                );
                await ref.read(reportsProvider.notifier).saveReport(copy);
                if (context.mounted) {
                  context.push('/create-report?id=${copy.id}');
                }
              } else if (val == 'template') {
                await _showTemplateOverride(context, report);
              } else if (val == 'number') {
                await _showNumberOverride(context, report);
              } else if (val == 'format') {
                await _showFormatOverride(context, report);
              } else if (val == 'delete') {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (dlg) => AlertDialog(
                    title: Text('rd_delete_title'.tr()),
                    content: Text('rd_delete_body'.tr()),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(dlg, false),
                          child: Text('common_cancel'.tr())),
                      TextButton(
                          onPressed: () => Navigator.pop(dlg, true),
                          child: Text('common_delete'.tr(),
                              style: const TextStyle(color: Colors.red))),
                    ],
                  ),
                );
                if (confirmed == true && context.mounted) {
                  final snapshot = report;
                  // (B/L) Suppression DOUCE → archive (récupérable).
                  await ref
                      .read(archivedReportsProvider.notifier)
                      .archive(report.id);
                  if (!context.mounted) return;
                  context.pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                          'rd_archived_snack'.tr(args: [snapshot.clientName.isNotEmpty ? snapshot.clientName : "#${snapshot.reportNumber}"])),
                      duration: const Duration(seconds: 6),
                      action: SnackBarAction(
                        label: 'common_cancel'.tr(),
                        onPressed: () => ref
                            .read(archivedReportsProvider.notifier)
                            .restore(snapshot.id),
                      ),
                    ),
                  );
                }
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'duplicate',
                child: Row(children: [
                  const Icon(Icons.copy_outlined, size: 18),
                  const SizedBox(width: 8),
                  Text('rd_menu_duplicate'.tr()),
                ]),
              ),
              PopupMenuItem(
                value: 'template',
                child: Row(children: [
                  const Icon(Icons.style_outlined, size: 18),
                  const SizedBox(width: 8),
                  Text('rd_menu_template'.tr()),
                ]),
              ),
              PopupMenuItem(
                value: 'number',
                child: Row(children: [
                  const Icon(Icons.tag, size: 18),
                  const SizedBox(width: 8),
                  Text('rd_menu_edit_number'.tr()),
                ]),
              ),
              PopupMenuItem(
                value: 'format',
                child: Row(children: [
                  const Icon(Icons.format_list_numbered, size: 18),
                  const SizedBox(width: 8),
                  Text('rd_menu_format'.tr()),
                ]),
              ),
              PopupMenuItem(
                value: 'delete',
                child: Text('common_delete'.tr(),
                    style: const TextStyle(color: Colors.red)),
              ),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              StatusBadge(status: report.status),
              const Spacer(),
              Text(dateStr,
                  style:
                      TextStyle(color: Colors.grey.shade600)),
            ],
          ),
          if (report.startTime != null || report.endTime != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: [
                  const Icon(Icons.access_time,
                      size: 14, color: Colors.grey),
                  const SizedBox(width: 4),
                  Text(
                    _horaireStr(report),
                    style: TextStyle(
                        color: Colors.grey.shade600, fontSize: 13),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 16),

          // Client
          _InfoCard(
            title: 'cr_section_client'.tr(),
            icon: Icons.person_outline,
            children: [
              _InfoRow('rd_name'.tr(), report.clientName),
              if (report.clientAddress.isNotEmpty)
                _InfoRow('field_address'.tr(), report.clientAddress),
              if (report.clientPhone.isNotEmpty)
                _InfoRow('cr_phone'.tr(), report.clientPhone),
              if (report.clientContact.isNotEmpty)
                _InfoRow('field_contact'.tr(), report.clientContact),
              if (report.contractNumber.isNotEmpty)
                _InfoRow('rd_contract_no'.tr(), report.contractNumber),
            ],
          ),
          const SizedBox(height: 12),

          // Intervention
          if (report.interventionType.isNotEmpty ||
              report.sector != SectorTemplate.generic)
            _InfoCard(
              title: 'cr_section_intervention'.tr(),
              icon: Icons.build_outlined,
              children: [
                if (report.sector != SectorTemplate.generic)
                  _InfoRow('rd_sector'.tr(), report.sector.label),
                if (report.interventionType.isNotEmpty)
                  _InfoRow('field_type'.tr(), report.interventionType),
              ],
            ),
          const SizedBox(height: 12),

          // Sector-specific fields
          if (report.sectorFields.isNotEmpty)
            _InfoCard(
              title: 'rd_sector_data'.tr(args: [report.sector.label]),
              icon: Icons.tune_outlined,
              children: report.sectorFields.entries
                  .where((e) =>
                      e.value != null &&
                      e.value.toString().isNotEmpty)
                  .map((e) => _InfoRow(
                      _formatKey(e.key), sectorValueLabel(e.value.toString())))
                  .toList(),
            ),
          const SizedBox(height: 12),

          // Equipment
          if (report.equipmentType.isNotEmpty)
            _InfoCard(
              title: 'cr_section_equipment'.tr(),
              icon: Icons.settings_outlined,
              children: [
                _InfoRow('field_type'.tr(), report.equipmentType),
                if (report.equipmentBrand.isNotEmpty)
                  _InfoRow('cr_brand'.tr(), report.equipmentBrand),
                if (report.equipmentModel.isNotEmpty)
                  _InfoRow('cr_model'.tr(), report.equipmentModel),
                if (report.equipmentSerial.isNotEmpty)
                  _InfoRow('rd_serial_no'.tr(), report.equipmentSerial),
              ],
            ),
          const SizedBox(height: 12),

          // Description
          if (report.description.isNotEmpty)
            _InfoCard(
              title: 'rd_work_done'.tr(),
              icon: Icons.description_outlined,
              children: [
                Text(report.description,
                    style: const TextStyle(height: 1.5)),
              ],
            ),
          const SizedBox(height: 12),

          if (report.observations.isNotEmpty)
            _InfoCard(
              title: 'field_observations'.tr(),
              icon: Icons.info_outline,
              children: [
                Text(report.observations,
                    style: const TextStyle(height: 1.5)),
              ],
            ),
          const SizedBox(height: 12),

          // Billing
          if (report.laborHours != null ||
              report.materials.isNotEmpty)
            _InfoCard(
              title: 'rd_billing'.tr(),
              icon: Icons.receipt_outlined,
              children: [
                if (report.laborHours != null) ...[
                  _InfoRow('cr_labor'.tr(),
                      '${formatQuantity(report.laborHours!)} h × '
                      '${_money(report.laborRate ?? 0)}/h = '
                      '${_money(report.laborHours! * (report.laborRate ?? 0))}'),
                ],
                ...report.materials.map((m) => _InfoRow(
                    m.label,
                    '${formatQuantity(m.quantity)} × ${_money(m.unitPrice)} = '
                    '${_money(m.total)}')),
                const Divider(height: 12),
                _InfoRow(
                  'cr_total_ht'.tr(),
                  _totalStr(report),
                ),
              ],
            ),
          const SizedBox(height: 12),

          // Photos
          if (report.photosPaths.isNotEmpty)
            _InfoCard(
              title: 'rd_photos_count'.tr(args: ['${report.photosPaths.length}']),
              icon: Icons.photo_camera_outlined,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: report.photosPaths.map((path) {
                    return ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: kIsWeb
                          ? Image.network(path,
                              width: 90,
                              height: 90,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) =>
                                  const _PhotoError())
                          : Image.file(File(path),
                              width: 90,
                              height: 90,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) =>
                                  const _PhotoError()),
                    );
                  }).toList(),
                ),
              ],
            ),
          const SizedBox(height: 12),

          // Signatures
          if (report.signatureClientStartData != null ||
              report.signatureTechStartData != null ||
              report.signatureClientData != null ||
              report.signatureTechData != null)
            _InfoCard(
              title: 'cr_nav_signatures'.tr(),
              icon: Icons.draw_outlined,
              children: [
                if (report.signatureClientStartData != null ||
                    report.signatureTechStartData != null) ...[
                  Text('cr_section_signatures_start'.tr(),
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade500, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      if (report.signatureClientStartData != null)
                        Expanded(child: _SignaturePreview(label: 'cr_section_client'.tr(), b64Data: report.signatureClientStartData!)),
                      if (report.signatureClientStartData != null && report.signatureTechStartData != null)
                        const SizedBox(width: 12),
                      if (report.signatureTechStartData != null)
                        Expanded(child: _SignaturePreview(label: 'field_technician'.tr(), b64Data: report.signatureTechStartData!)),
                    ],
                  ),
                  const SizedBox(height: 10),
                ],
                if (report.signatureClientData != null ||
                    report.signatureTechData != null) ...[
                  Text('cr_section_signatures_end'.tr(),
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade500, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      if (report.signatureClientData != null)
                        Expanded(child: _SignaturePreview(label: 'cr_section_client'.tr(), b64Data: report.signatureClientData!)),
                      if (report.signatureClientData != null && report.signatureTechData != null)
                        const SizedBox(width: 12),
                      if (report.signatureTechData != null)
                        Expanded(child: _SignaturePreview(label: 'field_technician'.tr(), b64Data: report.signatureTechData!)),
                    ],
                  ),
                ],
              ],
            ),
          const SizedBox(height: 20),

          // Save as template — (C) réservé Pro (pastille PRO si non abonné).
          OutlinedButton.icon(
            onPressed: () => _showSaveTemplateDialog(context, report),
            icon: Icon(Icons.copy_outlined,
                size: 18,
                color: ref.watch(effectiveSubscriptionProvider)
                    ? null
                    : Colors.grey),
            label: Row(mainAxisSize: MainAxisSize.min, children: [
              Text('rd_save_template_title'.tr(),
                  style: TextStyle(
                      color: ref.watch(effectiveSubscriptionProvider)
                          ? null
                          : Colors.grey.shade600)),
              if (!ref.watch(effectiveSubscriptionProvider)) ...[
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade700,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text('PRO',
                      style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          color: Colors.white)),
                ),
              ],
            ]),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(44),
            ),
          ),
          const SizedBox(height: 8),

          // Partager le PDF — Pro illimité, gratuit limité (1 dépletion par rapport/mois)
          OutlinedButton.icon(
            onPressed: _isGeneratingPdf ? null : _sharePdf,
            icon: const Icon(Icons.share_outlined, size: 18),
            label: Text(_isGeneratingPdf ? 'rd_generating'.tr() : 'rd_share_pdf'.tr()),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(44),
            ),
          ),
          const SizedBox(height: 8),

          // [COMMENTED] "Sauvegarder" button — allows saving PDF locally (bypasses cloud workflow)
          // OutlinedButton.icon(
          //   onPressed: _isSavingPdf ? null : _savePdfLocally,
          //   icon: const Icon(Icons.download_outlined, size: 18),
          //   label: Text(_isSavingPdf ? 'Sauvegarde…' : 'Sauvegarder'),
          // ),

          // [COMMENTED] "Autres formats" button (texte, JSON, HTML) — available behind cloud button for now
          // OutlinedButton.icon(
          //   onPressed: () => _showOtherFormats(context),
          //   icon: const Icon(Icons.more_horiz, size: 18),
          //   label: const Text('Autres formats'),
          // ),

          // "Voir PDF" stays — read-only preview, no share button inside
          OutlinedButton.icon(
            onPressed: (_isPreviewingPdf || _isGeneratingPdf) ? null : _previewPdf,
            icon: _isPreviewingPdf
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.visibility_outlined, size: 18),
            label: Text('rd_view_pdf'.tr()),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(44),
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _showCloudOptions,
            icon: const Icon(Icons.cloud_upload_outlined),
            label: Text('rd_send_cloud'.tr()),
          ),
          const SizedBox(height: 8),
          // Visible to all; free users hit paywall on tap.
          // Disabled (grayed) when no billing data entered.
          OutlinedButton.icon(
            onPressed: (report.laborHours != null || report.materials.isNotEmpty)
                ? (_isGeneratingInvoice ? null : _generateInvoice)
                : null,
            icon: _isGeneratingInvoice
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.receipt_long_outlined, size: 18),
            label: _isGeneratingInvoice
                ? Text('rd_generating'.tr())
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('rd_generate_invoice'.tr()),
                      const SizedBox(width: 6),
                      const _ProBadge(),
                    ],
                  ),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(44),
            ),
          ),
          // Remote client signature
          if (report.signedRemotely) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.green.shade200),
              ),
              child: Row(children: [
                const Icon(Icons.lock_outline, color: Colors.green, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'rd_signed_remotely_banner'.tr(),
                    style: const TextStyle(
                        fontSize: 13,
                        color: Colors.green,
                        fontWeight: FontWeight.w500),
                  ),
                ),
                TextButton(
                  onPressed: () => _requestNewRemoteSignature(context, report),
                  child: Text('rd_new_short'.tr(), style: const TextStyle(fontSize: 12)),
                ),
              ]),
            ),
          ] else if (_pendingSigToken != null) ...[
            // Pending remote sig banner — signature in progress but sheet dismissed
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.orange.shade300),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    const SizedBox(
                      width: 14, height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2,
                          color: Colors.orange),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'rd_awaiting_sig'.tr(),
                        style: const TextStyle(
                            fontSize: 13,
                            color: Colors.orange,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                    IconButton(
                      onPressed: () async {
                        if (_pendingSigToken != null) {
                          try {
                            await RemoteSignatureService
                                .cancelRequest(_pendingSigToken!);
                          } catch (_) {}
                        }
                        _bgSigSub?.cancel();
                        await _clearPendingSig();
                      },
                      icon: const Icon(Icons.close, size: 18),
                      tooltip: 'rd_cancel_request'.tr(),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      color: Colors.red.shade400,
                    ),
                  ]),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _reopenRemoteSignature,
                        icon: const Icon(Icons.open_in_new, size: 15),
                        label: Text('rd_reopen'.tr(),
                            style: const TextStyle(fontSize: 12)),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.orange,
                          side: const BorderSide(color: Colors.orange),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Clipboard.setData(ClipboardData(
                            text:
                                '$_pendingSigUrl\nCode : $_pendingSigCode',
                          ));
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                                content: Text('rd_link_code_copied'.tr())),
                          );
                        },
                        icon: const Icon(Icons.copy_outlined, size: 15),
                        label: Text('rd_copy_link_short'.tr(),
                            style: const TextStyle(fontSize: 12)),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                    ),
                  ]),
                ],
              ),
            ),
          ] else if (report.signatureClientData == null) ...[
            const SizedBox(height: 8),
            _RemoteSigButton(onRequest: () => _requestRemoteSignature(context)),
          ],

          const SizedBox(height: 24),

          // Photo request banner — admin is asking for photos
          if (_photoRequestBy != null) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Icon(Icons.photo_camera_outlined,
                        color: Colors.blue.shade700, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'rd_admin_wants_photos'.tr(),
                        style: const TextStyle(
                            fontSize: 13,
                            color: Colors.blue,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: _clearPhotoRequest,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.blue.shade700,
                        side: BorderSide(color: Colors.blue.shade300),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        visualDensity: VisualDensity.compact,
                      ),
                      child: Text(
                          'rd_will_send_photos'.tr(),
                          style: const TextStyle(fontSize: 13)),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // Rejection banner + resubmit
          if (report.status == ReportStatus.rejected) ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.statusRejected.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: AppColors.statusRejected.withValues(alpha: 0.35)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Icon(Icons.cancel_outlined,
                        color: AppColors.statusRejected, size: 18),
                    const SizedBox(width: 8),
                    Text('rd_rejected_title'.tr(),
                        style: TextStyle(
                            color: AppColors.statusRejected,
                            fontWeight: FontWeight.bold,
                            fontSize: 14)),
                  ]),
                  if (report.rejectionComment != null &&
                      report.rejectionComment!.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text('rd_admin_comment'.tr(),
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey.shade600)),
                    const SizedBox(height: 4),
                    Text(report.rejectionComment!,
                        style: const TextStyle(fontSize: 13)),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: () =>
                      context.push('/create-report?id=${report.id}'),
                  icon: const Icon(Icons.edit_outlined),
                  label: Text('cr_modify'.tr()),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _ResubmitButton(report: report),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],

          if (report.status == ReportStatus.draft)
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.statusSubmitted),
              onPressed: () async {
                await ref
                    .read(reportsProvider.notifier)
                    .submitReport(report);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('rd_marked_sent'.tr()),
                      backgroundColor: AppColors.statusSubmitted,
                    ),
                  );
                }
              },
              icon: const Icon(Icons.send),
              label: Text('rd_mark_sent'.tr()),
            ),
          if (report.status == ReportStatus.submitted) ...[
            const SizedBox(height: 8),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.success),
              onPressed: () async {
                await ref
                    .read(reportsProvider.notifier)
                    .validateReport(report);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('rd_validated'.tr()),
                      backgroundColor: AppColors.success,
                    ),
                  );
                }
              },
              icon: const Icon(Icons.verified_outlined),
              label: Text('rd_validate_report'.tr()),
            ),
          ],
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  String _horaireStr(ReportModel r) {
    String f(DateTime dt) => DateFormat.jm().format(dt); // 24 h ou AM/PM selon locale
    if (r.startTime != null && r.endTime != null) {
      return '${f(r.startTime!)} – ${f(r.endTime!)}';
    } else if (r.startTime != null) {
      return 'rd_start_at'.tr(args: [f(r.startTime!)]);
    } else if (r.endTime != null) {
      return 'rd_end_at'.tr(args: [f(r.endTime!)]);
    }
    return '';
  }

  String _totalStr(ReportModel r) {
    final labor = (r.laborHours ?? 0) * (r.laborRate ?? 0);
    final mats = r.materials.fold<double>(0, (a, m) => a + m.total);
    return _money(labor + mats);
  }

  /// (2026-10-03) Montant dans la devise réglée, au format de la langue — même
  /// logique que le PDF (avant : « € » et point décimal écrits en dur ici, donc
  /// faux dans l'écran, l'export texte et l'export HTML hors zone euro).
  String _money(num v) => formatMoney(v,
      code: resolveCurrencyCode(ref.read(settingsProvider).valueOrNull ?? {},
          region: WidgetsBinding.instance.platformDispatcher.locale.countryCode,
          language: Intl.defaultLocale));

  String _formatKey(String k) =>
      k.replaceAll('_', ' ').split(' ').map((w) {
        if (w.isEmpty) return w;
        return w[0].toUpperCase() + w.substring(1);
      }).join(' ');
}

// ─── Remote signature button (PRO gate) ──────────────────────────────────────

class _RemoteSigButton extends ConsumerWidget {
  final VoidCallback onRequest;
  const _RemoteSigButton({required this.onRequest});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isPro = ref.watch(effectiveSubscriptionProvider);
    return OutlinedButton.icon(
      onPressed: isPro
          ? onRequest
          : () => PaywallBottomSheet.show(
                context,
                reason: 'rd_remote_sig_pro'.tr(),
              ),
      icon: Icon(isPro ? Icons.draw_outlined : Icons.lock_outline, size: 18,
          color: isPro ? null : Colors.grey),
      label: Row(mainAxisSize: MainAxisSize.min, children: [
        Text('rd_remote_sig_btn'.tr(),
            style: TextStyle(color: isPro ? null : Colors.grey)),
        if (!isPro) ...[
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: Colors.amber.shade700,
              borderRadius: BorderRadius.circular(3),
            ),
            child: const Text('PRO',
                style: TextStyle(
                    fontSize: 9,
                    color: Colors.white,
                    fontWeight: FontWeight.bold)),
          ),
        ],
      ]),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(44),
        foregroundColor: isPro ? null : Colors.grey,
        side: BorderSide(color: isPro ? AppColors.primary : Colors.grey.shade300),
      ),
    );
  }
}

// ─── Cloud options sheet ──────────────────────────────────────────────────────

class _CloudOptionsSheet extends StatefulWidget {
  final ReportModel report;
  final VoidCallback? onGoogleDriveTap;
  final VoidCallback? onOneDriveTap;
  final VoidCallback? onDropboxTap;
  final VoidCallback? onShareText;
  final VoidCallback? onShareJson;
  final VoidCallback? onShareHtml;
  final VoidCallback? onCopyText;

  const _CloudOptionsSheet({
    required this.report,
    this.onGoogleDriveTap,
    this.onOneDriveTap,
    this.onDropboxTap,
    this.onShareText,
    this.onShareJson,
    this.onShareHtml,
    this.onCopyText,
  });

  @override
  State<_CloudOptionsSheet> createState() => _CloudOptionsSheetState();
}

class _CloudOptionsSheetState extends State<_CloudOptionsSheet> {
  bool _loading = true;
  String? _googleEmail;
  bool _oneDriveConnected = false;
  String? _oneDriveName;
  bool _dropboxConnected = false;
  String? _dropboxName;

  @override
  void initState() {
    super.initState();
    _loadConnectionState();
  }

  Future<void> _loadConnectionState() async {
    final results = await Future.wait<dynamic>([
      GoogleDriveService.currentEmail,
      OneDriveService.isConnected,
      OneDriveService.displayName,
      DropboxService.isConnected,
      DropboxService.displayName,
    ]);
    if (!mounted) return;
    setState(() {
      _googleEmail = results[0] as String?;
      _oneDriveConnected = results[1] as bool;
      _oneDriveName = results[2] as String?;
      _dropboxConnected = results[3] as bool;
      _dropboxName = results[4] as String?;
      _loading = false;
    });
  }

  void _tap(BuildContext ctx, VoidCallback? cb) {
    if (cb == null) return;
    Navigator.pop(ctx);
    cb();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SafeArea(
        child: Padding(
          padding: EdgeInsets.all(40),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    return SafeArea(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('rd_cloud_save_title'.tr(),
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text('rd_cloud_choose'.tr(),
                  style:
                      TextStyle(color: Colors.grey.shade600, fontSize: 13)),
              const SizedBox(height: 16),

              // ── Google Drive ──────────────────────────────────────────
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.add_to_drive,
                    color: _googleEmail != null ? Colors.green : Colors.blue),
                title: const Text('Google Drive'),
                subtitle: Text(
                  _googleEmail != null
                      ? 'rd_connected_as'.tr(args: [_googleEmail ?? ''])
                      : 'rd_connect_on_first'.tr(),
                  style: TextStyle(
                    fontSize: 11,
                    color: _googleEmail != null
                        ? Colors.green
                        : Colors.grey.shade600,
                  ),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _tap(context, widget.onGoogleDriveTap),
              ),

              // ── OneDrive ──────────────────────────────────────────────
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.cloud_outlined,
                    color: _oneDriveConnected
                        ? const Color(0xFF0078D4)
                        : Colors.grey.shade400),
                title: const Text('OneDrive'),
                subtitle: Text(
                  _oneDriveConnected
                      ? (_oneDriveName != null
                          ? 'rd_connected_as'.tr(args: [_oneDriveName ?? ''])
                          : 'rd_connected'.tr())
                      : 'rd_connect_on_first'.tr(),
                  style: TextStyle(
                    fontSize: 11,
                    color: _oneDriveConnected
                        ? Colors.green
                        : Colors.grey.shade600,
                  ),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _tap(context, widget.onOneDriveTap),
              ),

              // ── Dropbox ───────────────────────────────────────────────
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.folder_outlined,
                    color: _dropboxConnected
                        ? const Color(0xFF0061FF)
                        : Colors.grey.shade400),
                title: const Text('Dropbox'),
                subtitle: Text(
                  _dropboxConnected
                      ? (_dropboxName != null
                          ? 'rd_connected_as'.tr(args: [_dropboxName ?? ''])
                          : 'rd_connected'.tr())
                      : 'rd_connect_on_first'.tr(),
                  style: TextStyle(
                    fontSize: 11,
                    color: _dropboxConnected
                        ? Colors.green
                        : Colors.grey.shade600,
                  ),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _tap(context, widget.onDropboxTap),
              ),

              const Divider(height: 32),

              // ── Autres formats ────────────────────────────────────────
              Text('rd_other_formats'.tr(),
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading:
                    const Icon(Icons.text_snippet_outlined, color: AppColors.primary),
                title: Text('rd_share_text'.tr()),
                subtitle: Text('rd_share_text_sub'.tr(),
                    style: const TextStyle(fontSize: 12)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _tap(context, widget.onShareText),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.data_object, color: AppColors.primary),
                title: Text('rd_export_json'.tr()),
                subtitle: Text('rd_export_json_sub'.tr(),
                    style: const TextStyle(fontSize: 12)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _tap(context, widget.onShareJson),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading:
                    const Icon(Icons.html_outlined, color: AppColors.primary),
                title: Text('rd_export_html'.tr()),
                subtitle: Text('rd_export_html_sub'.tr(),
                    style: const TextStyle(fontSize: 12)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _tap(context, widget.onShareHtml),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading:
                    const Icon(Icons.copy_outlined, color: AppColors.primary),
                title: Text('rd_copy_clipboard'.tr()),
                subtitle: Text('rd_copy_clipboard_sub'.tr(),
                    style: const TextStyle(fontSize: 12)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _tap(context, widget.onCopyText),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Sub-widgets ─────────────────────────────────────────────────────────────

class _SignaturePreview extends StatelessWidget {
  final String label;
  final String b64Data;
  const _SignaturePreview(
      {required this.label, required this.b64Data});

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Text(label,
              style: TextStyle(
                  color: Colors.grey.shade600, fontSize: 12)),
          const SizedBox(height: 4),
          Container(
            height: 70,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(8),
              color: Colors.white,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(7),
              child: Image.memory(base64Decode(b64Data),
                  fit: BoxFit.contain),
            ),
          ),
        ],
      );
}

class _PhotoError extends StatelessWidget {
  const _PhotoError();
  @override
  Widget build(BuildContext context) => Container(
        width: 90,
        height: 90,
        color: Colors.grey.shade200,
        child: const Icon(Icons.broken_image, color: Colors.grey),
      );
}

class _InfoCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;

  const _InfoCard(
      {required this.title,
      required this.icon,
      required this.children});

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, color: AppColors.primary, size: 18),
                  const SizedBox(width: 8),
                  Text(title,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary,
                          fontSize: 14)),
                ],
              ),
              const Divider(height: 16),
              ...children,
            ],
          ),
        ),
      );
}

class _ProBadge extends StatelessWidget {
  const _ProBadge();

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        decoration: BoxDecoration(
          color: Colors.amber.shade700,
          borderRadius: BorderRadius.circular(4),
        ),
        child: const Text(
          'PRO',
          style: TextStyle(
            color: Colors.white,
            fontSize: 9,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
      );
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow(this.label, this.value);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 110,
              child: Text(label,
                  style: TextStyle(
                      color: Colors.grey.shade600, fontSize: 13)),
            ),
            Expanded(
              child: Text(value,
                  style:
                      const TextStyle(fontWeight: FontWeight.w500)),
            ),
          ],
        ),
      );
}

// ─── Resubmit button (rejected reports) ──────────────────────────────────────

class _ResubmitButton extends ConsumerStatefulWidget {
  final ReportModel report;
  const _ResubmitButton({required this.report});

  @override
  ConsumerState<_ResubmitButton> createState() => _ResubmitButtonState();
}

class _ResubmitButtonState extends ConsumerState<_ResubmitButton> {
  bool _loading = false;

  Future<void> _resubmit() async {
    setState(() => _loading = true);
    try {
      final submitted = widget.report.copyWith(
        status: ReportStatus.submitted,
        clearRejectionComment: true,
      );
      await ref.read(reportsProvider.notifier).submitReport(widget.report);

      final team = ref.read(teamStateProvider).valueOrNull;
      if (team?.companyId != null) {
        await TeamService().syncReport(team!.companyId!, submitted);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('rd_resubmitted'.tr()),
            backgroundColor: AppColors.statusSubmitted,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('common_error'.tr(args: ['$e']))),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => FilledButton.icon(
        style: FilledButton.styleFrom(
            backgroundColor: AppColors.statusSubmitted),
        onPressed: _loading ? null : _resubmit,
        icon: _loading
            ? const SizedBox(
                width: 16, height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
            : const Icon(Icons.send),
        label: Text('rd_resubmit'.tr()),
      );
}

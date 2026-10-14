import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../shared/services/pdf_service.dart';
import '../../../shared/utils/error_text.dart';
import '../../../shared/widgets/zoomable_pdf_view.dart';
import '../../settings/providers/settings_provider.dart';
import '../models/currency_options.dart';
import '../models/report_model.dart';
import '../models/sample_reports.dart';

/// Rapports d'EXEMPLE par métier (2026-10-14) : l'utilisateur choisit son
/// métier → voit le PDF qu'il obtiendra (filigrane « EXEMPLE ») → « Créer mon
/// rapport » ouvre le formulaire déjà réglé sur ce métier.
Future<void> showSampleReports(BuildContext context) async {
  final sector = await showModalBottomSheet<SectorTemplate>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(8, 16, 8, 8),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text('ex_sheet_title'.tr(),
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Text('ex_sheet_desc'.tr(),
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
          ),
          for (final s in SampleReports.sectors)
            ListTile(
              leading: Icon(_icon(s), color: AppColors.primary),
              title: Text(s.label),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.pop(ctx, s),
            ),
        ],
      ),
    ),
  );
  if (sector == null || !context.mounted) return;

  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Center(child: CircularProgressIndicator()),
  );
  try {
    final settings = ProviderScope.containerOf(context, listen: false)
            .read(settingsProvider)
            .valueOrNull ??
        <String, String>{};
    final report = await SampleReports.build(sector);
    if (!context.mounted) return;
    final bytes = await PdfService().generateReport(
      report,
      companyName: 'ex_company'.tr(),
      technicianName: 'ex_technician'.tr(),
      pdfTemplate: settings['pdf_template'] ?? 'professionnel',
      currencyCode: resolveCurrencyCode(settings,
          region: WidgetsBinding.instance.platformDispatcher.locale.countryCode,
          language: context.locale.languageCode),
      watermark: 'ex_watermark'.tr(),
    );
    if (!context.mounted) return;
    Navigator.of(context, rootNavigator: true).pop(); // ferme le chargement
    final create = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (viewCtx) => ZoomablePdfView(
        bytes: bytes,
        title: 'ex_preview_title'.tr(args: [sector.label]),
        bottomBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              icon: const Icon(Icons.edit_note),
              label: Text('ex_create_mine'.tr(args: [sector.label])),
              onPressed: () => Navigator.pop(viewCtx, true),
            ),
          ),
        ),
      ),
    ));
    if (create == true && context.mounted) {
      context.push('/create-report', extra: SampleReports.starter(sector));
    }
  } catch (e) {
    if (!context.mounted) return;
    Navigator.of(context, rootNavigator: true).maybePop();
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('common_error'.tr(args: [errorText(e)]))));
  }
}

IconData _icon(SectorTemplate s) => switch (s) {
      SectorTemplate.plomberie => Icons.plumbing,
      SectorTemplate.incendie => Icons.fire_extinguisher,
      SectorTemplate.maintenance => Icons.precision_manufacturing_outlined,
      SectorTemplate.it => Icons.computer,
      SectorTemplate.nettoyage => Icons.cleaning_services_outlined,
      SectorTemplate.btp => Icons.construction,
      SectorTemplate.transport => Icons.local_shipping_outlined,
      SectorTemplate.generic => Icons.description_outlined,
    };

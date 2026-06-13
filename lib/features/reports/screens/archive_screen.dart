import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../subscription/subscription_provider.dart';
import '../../subscription/paywall_bottom_sheet.dart';
import '../models/report_model.dart';
import '../providers/reports_provider.dart';
import '../providers/archive_provider.dart';
import '../../../shared/widgets/status_badge.dart';

/// (B/L) Onglet « Archive » : les rapports supprimés (archivés). On peut les
/// restaurer ou les supprimer DÉFINITIVEMENT. Réservé au Pro.
class ArchiveScreen extends ConsumerWidget {
  const ArchiveScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isPro = ref.watch(effectiveSubscriptionProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Archive')),
      body: !isPro
          ? _ProGate()
          : ref.watch(reportsProvider).when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('Erreur : $e')),
                data: (allReports) {
                  final archivedIds = ref.watch(archivedReportsProvider);
                  final archived = allReports
                      .where((r) => archivedIds.contains(r.id))
                      .toList();
                  return Column(
                    children: [
                      const _LocalStorageWarning(),
                      Expanded(
                        child: archived.isEmpty
                            ? const Center(
                                child: Text('Aucun rapport archivé.',
                                    style: TextStyle(color: Colors.black54)))
                            : ListView.separated(
                                padding: const EdgeInsets.all(16),
                                itemCount: archived.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: 8),
                                itemBuilder: (_, i) =>
                                    _ArchivedTile(report: archived[i]),
                              ),
                      ),
                    ],
                  );
                },
              ),
    );
  }
}

class _ProGate extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inventory_2_outlined, size: 56, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            const Text('L\'archive est réservée au Pro',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(
              'Passez Pro pour retrouver, restaurer et supprimer définitivement '
              'vos rapports supprimés.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () => PaywallBottomSheet.show(context,
                  reason: 'L\'archive des rapports est une fonctionnalité Pro.'),
              icon: const Icon(Icons.workspace_premium_outlined),
              label: const Text('Voir Pro'),
            ),
          ],
        ),
      ),
    );
  }
}

class _LocalStorageWarning extends StatelessWidget {
  const _LocalStorageWarning();
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: Colors.amber.shade50,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(children: [
        Icon(Icons.info_outline, size: 16, color: Colors.amber.shade800),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Vos rapports sont stockés UNIQUEMENT sur cet appareil (l\'appli / le '
            'téléphone) — ils ne sont PAS sauvegardés dans le cloud du développeur '
            'ni liés à votre compte. Une suppression définitive est irréversible. '
            'Pour un rapport d\'ÉQUIPE, la suppression ne retire que VOTRE copie : '
            'la copie de l\'équipe reste visible par le responsable.',
            style: TextStyle(fontSize: 11.5, color: Colors.amber.shade900),
          ),
        ),
      ]),
    );
  }
}

class _ArchivedTile extends ConsumerWidget {
  final ReportModel report;
  const _ArchivedTile({required this.report});

  Future<void> _confirmDeleteForever(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dlg) => AlertDialog(
        icon: const Icon(Icons.delete_forever_outlined, color: Colors.red),
        title: const Text('Supprimer définitivement ?'),
        content: const Text(
          'Ce rapport sera effacé pour de bon de cet appareil. '
          'Cette action est IRRÉVERSIBLE.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dlg, false),
              child: const Text('Annuler')),
          FilledButton(
            onPressed: () => Navigator.pop(dlg, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(reportsProvider.notifier).deleteReport(report.id);
    await ref.read(archivedReportsProvider.notifier).forget(report.id);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dateStr = DateFormat('dd/MM/yyyy').format(report.date);
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    report.clientName.isEmpty ? '(Sans client)' : report.clientName,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 14),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(children: [
                    StatusBadge(status: report.status),
                    const SizedBox(width: 8),
                    Text(dateStr,
                        style: const TextStyle(
                            fontSize: 12, color: Colors.black54)),
                  ]),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.restore, color: AppColors.primary),
              tooltip: 'Restaurer',
              onPressed: () =>
                  ref.read(archivedReportsProvider.notifier).restore(report.id),
            ),
            IconButton(
              icon: const Icon(Icons.delete_forever_outlined, color: Colors.red),
              tooltip: 'Supprimer définitivement',
              onPressed: () => _confirmDeleteForever(context, ref),
            ),
          ],
        ),
      ),
    );
  }
}

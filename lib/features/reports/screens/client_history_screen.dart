import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../shared/services/local_db_service.dart';
import '../models/report_model.dart';

class ClientHistoryScreen extends StatefulWidget {
  final String clientId;
  final String clientName;

  const ClientHistoryScreen({
    super.key,
    required this.clientId,
    required this.clientName,
  });

  @override
  State<ClientHistoryScreen> createState() => _ClientHistoryScreenState();
}

class _ClientHistoryScreenState extends State<ClientHistoryScreen> {
  late Future<List<ReportModel>> _reportsFuture;

  @override
  void initState() {
    super.initState();
    _reportsFuture = LocalDbService().getReportsByClient(widget.clientId);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.clientName, overflow: TextOverflow.ellipsis),
            Text('cl_history_tooltip'.tr(),
                style: const TextStyle(fontSize: 12, color: Colors.white70)),
          ],
        ),
      ),
      body: FutureBuilder<List<ReportModel>>(
        future: _reportsFuture,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('common_error'.tr(args: ['${snap.error}'])));
          }
          final reports = snap.data ?? [];
          if (reports.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.history, size: 72, color: Colors.grey.shade300),
                  const SizedBox(height: 12),
                  Text(
                    'ch_no_interventions'.tr(),
                    style: TextStyle(color: Colors.grey.shade500),
                  ),
                ],
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: reports.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) => _HistoryCard(report: reports[i]),
          );
        },
      ),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  final ReportModel report;

  const _HistoryCard({required this.report});

  @override
  Widget build(BuildContext context) {
    final dateStr =
        '${report.date.day.toString().padLeft(2, '0')}/${report.date.month.toString().padLeft(2, '0')}/${report.date.year}';

    Color statusColor;
    String statusLabel;
    switch (report.status) {
      case ReportStatus.submitted:
        statusColor = AppColors.statusSubmitted;
        statusLabel = 'status_submitted'.tr();
      case ReportStatus.pendingValidation:
        statusColor = AppColors.statusPendingValidation;
        statusLabel = 'status_pending'.tr();
      case ReportStatus.validated:
        statusColor = AppColors.statusValidated;
        statusLabel = 'status_validated'.tr();
      case ReportStatus.draft:
        statusColor = Colors.orange;
        statusLabel = 'status_draft'.tr();
      case ReportStatus.rejected:
        statusColor = AppColors.statusRejected;
        statusLabel = 'status_rejected'.tr();
    }

    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: CircleAvatar(
          backgroundColor: statusColor.withValues(alpha: 0.15),
          child: Icon(Icons.description_outlined, color: statusColor, size: 20),
        ),
        title: Text(
          report.interventionType.isNotEmpty
              ? report.interventionType
              : report.sector.label,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(dateStr,
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
            if (report.description.isNotEmpty)
              Text(
                report.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Colors.grey.shade500, fontSize: 11),
              ),
          ],
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(statusLabel,
              style: TextStyle(
                  color: statusColor,
                  fontSize: 11,
                  fontWeight: FontWeight.w600)),
        ),
        onTap: () => context.push('/report/${report.id}'),
      ),
    );
  }
}

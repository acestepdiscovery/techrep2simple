import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../features/reports/models/report_model.dart';

class StatusBadge extends StatelessWidget {
  final ReportStatus status;

  const StatusBadge({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      ReportStatus.draft => ('En cours', AppColors.statusDraft),
      ReportStatus.submitted => ('Envoyé', AppColors.statusSubmitted),
      ReportStatus.pendingValidation => ('À valider', AppColors.statusPendingValidation),
      ReportStatus.validated => ('Validé', AppColors.statusValidated),
      ReportStatus.rejected => ('Rejeté', AppColors.statusRejected),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

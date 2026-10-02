import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../features/reports/models/report_model.dart';

class StatusBadge extends StatelessWidget {
  final ReportStatus status;

  const StatusBadge({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      ReportStatus.draft => ('sb_draft'.tr(), AppColors.statusDraft),
      ReportStatus.submitted => ('sb_submitted'.tr(), AppColors.statusSubmitted),
      ReportStatus.pendingValidation => ('sb_pending'.tr(), AppColors.statusPendingValidation),
      ReportStatus.validated => ('sb_validated'.tr(), AppColors.statusValidated),
      ReportStatus.rejected => ('sb_rejected'.tr(), AppColors.statusRejected),
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

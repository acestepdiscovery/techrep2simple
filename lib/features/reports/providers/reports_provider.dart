import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../models/report_model.dart';
import '../../../shared/services/local_db_service.dart';

final reportsProvider = AsyncNotifierProvider<ReportsNotifier, List<ReportModel>>(ReportsNotifier.new);

class ReportsNotifier extends AsyncNotifier<List<ReportModel>> {
  final _db = LocalDbService();
  final _uuid = const Uuid();

  @override
  Future<List<ReportModel>> build() => _db.getAllReports();

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _db.getAllReports());
  }

  Future<ReportModel> createReport({
    required String clientName,
    SectorTemplate sector = SectorTemplate.generic,
  }) async {
    final now = DateTime.now();
    final report = ReportModel(
      id: _uuid.v4(),
      clientName: clientName,
      sector: sector,
      date: now,
      status: ReportStatus.draft,
      createdAt: now,
      updatedAt: now,
    );
    await _db.insertReport(report);
    await refresh();
    return report;
  }

  Future<void> saveReport(ReportModel report) async {
    await _db.insertReport(report); // ConflictAlgorithm.replace = upsert (new + edit)
    await refresh();
  }

  /// (A) Upsert SANS flash de chargement — utilisé par l'auto-save du brouillon
  /// pour que la liste reflète le brouillon EN DIRECT (sans passer par
  /// AsyncLoading, qui ferait clignoter la liste).
  Future<void> upsertSilently(ReportModel report) async {
    await _db.insertReport(report);
    state = AsyncData(await _db.getAllReports());
  }

  Future<void> submitReport(ReportModel report) async {
    final updated = report.copyWith(
      status: ReportStatus.submitted,
      clearRejectionComment: true,
    );
    await _db.updateReport(updated);
    await refresh();
  }

  Future<void> validateReport(ReportModel report) async {
    final updated = report.copyWith(status: ReportStatus.validated);
    await _db.updateReport(updated);
    await refresh();
  }

  Future<void> deleteReport(String id) async {
    await _db.deleteReport(id);
    await refresh();
  }

  /// Pulls report statuses from Firestore team namespace and updates local
  /// SQLite if they diverged (e.g. admin validated a report).
  Future<void> syncStatusFromTeam(String companyId, String uid) async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('companies_raptech1')
          .doc(companyId)
          .collection('reports_raptech1')
          .where('technician_id', isEqualTo: uid)
          .get();

      if (snap.docs.isEmpty) return;

      final local = state.valueOrNull;
      if (local == null) return;

      final localMap = {for (final r in local) r.id: r};
      bool changed = false;

      for (final doc in snap.docs) {
        final remoteStatusStr = doc.data()['status'] as String?;
        if (remoteStatusStr == null) continue;
        final localReport = localMap[doc.id];
        if (localReport == null) continue;

        final remoteStatus = ReportStatus.values.firstWhere(
          (s) => s.name == remoteStatusStr,
          orElse: () => localReport.status,
        );

        final remoteComment = doc.data()['rejection_comment'] as String?;
        if (localReport.status != remoteStatus ||
            (remoteStatus == ReportStatus.rejected &&
                localReport.rejectionComment != remoteComment)) {
          await _db.insertReport(localReport.copyWith(
            status: remoteStatus,
            rejectionComment: remoteComment,
            clearRejectionComment: remoteComment == null,
          ));
          changed = true;
        }
      }

      if (changed) await refresh();
    } catch (_) {
      // Non-fatal — offline or not in team
    }
  }
}

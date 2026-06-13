import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../auth/providers/auth_provider.dart';

/// Streams the set of reportIds that have a pending photo request for the
/// current technician. Empty when user has no team.
final photoRequestIdsProvider = StreamProvider<Set<String>>((ref) {
  final teamState = ref.watch(teamStateProvider).valueOrNull;
  final user = ref.watch(firebaseUserProvider).valueOrNull;
  final companyId = teamState?.companyId;
  if (companyId == null || user == null) return Stream.value({});

  return FirebaseFirestore.instance
      .collection('companies_raptech1')
      .doc(companyId)
      .collection('reports_raptech1')
      .where('technician_id', isEqualTo: user.uid)
      .snapshots()
      .map((snap) => snap.docs
          .where((d) =>
              (d.data()['photo_request_by'] as String? ?? '').isNotEmpty)
          .map((d) => d.id)
          .toSet());
});

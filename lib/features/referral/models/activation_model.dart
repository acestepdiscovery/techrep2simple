import 'package:cloud_firestore/cloud_firestore.dart';

enum ActivationStatus { pending, active, dormant }

class ActivationModel {
  final String id;
  final String inviterUid;
  final String inviteeUid;
  final ActivationStatus status;
  final String inviterDisplayName;
  final String inviteeDisplayName;
  final DateTime createdAt;
  final DateTime? confirmAfter;
  final DateTime? activatedAt;
  final DateTime? dormantAt;
  final int creditsEarnedTotal;

  const ActivationModel({
    required this.id,
    required this.inviterUid,
    required this.inviteeUid,
    required this.status,
    required this.inviterDisplayName,
    required this.inviteeDisplayName,
    required this.createdAt,
    this.confirmAfter,
    this.activatedAt,
    this.dormantAt,
    required this.creditsEarnedTotal,
  });

  bool get isPending => status == ActivationStatus.pending;
  bool get isActive  => status == ActivationStatus.active;
  bool get isDormant => status == ActivationStatus.dormant;

  String otherDisplayName(String myUid) =>
      myUid == inviterUid ? inviteeDisplayName : inviterDisplayName;

  String otherUid(String myUid) =>
      myUid == inviterUid ? inviteeUid : inviterUid;

  static DateTime? _toDate(dynamic v) {
    if (v == null) return null;
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    if (v is String) return DateTime.tryParse(v);
    return null;
  }

  factory ActivationModel.fromMap(String id, Map<String, dynamic> m) {
    final statusStr = (m['status'] as String? ?? 'dormant').toLowerCase();
    final status = switch (statusStr) {
      'pending' => ActivationStatus.pending,
      'active'  => ActivationStatus.active,
      _         => ActivationStatus.dormant,
    };
    return ActivationModel(
      id:                   id,
      inviterUid:           m['inviter_uid'] as String? ?? '',
      inviteeUid:           m['invitee_uid'] as String? ?? '',
      status:               status,
      inviterDisplayName:   m['inviter_display_name'] as String? ?? '',
      inviteeDisplayName:   m['invitee_display_name'] as String? ?? '',
      createdAt:            _toDate(m['created_at']) ?? DateTime.now(),
      confirmAfter:         _toDate(m['confirm_after']),
      activatedAt:          _toDate(m['activated_at']),
      dormantAt:            _toDate(m['dormant_at']),
      creditsEarnedTotal:   (m['credits_earned_total'] as int?) ?? 0,
    );
  }
}

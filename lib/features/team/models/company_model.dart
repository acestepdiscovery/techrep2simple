class CompanyModel {
  final String id;
  final String name;
  final String inviteCode;
  final String adminId;
  final DateTime createdAt;

  /// (2026-10-23) true = le serveur a renvoyé l'équipe EXISTANTE de ce responsable au
  /// lieu d'en créer une 2e (règle « un responsable = une équipe », cas Bruno).
  final bool existing;

  const CompanyModel({
    required this.id,
    required this.name,
    required this.inviteCode,
    required this.adminId,
    required this.createdAt,
    this.existing = false,
  });

  factory CompanyModel.fromMap(String id, Map<String, dynamic> m) => CompanyModel(
        id: id,
        name: m['name'] ?? '',
        inviteCode: m['invite_code'] ?? '',
        adminId: m['admin_id'] ?? '',
        // (2026-10-19) Tolérant : une date absente ou au format Firestore
        // faisait planter « Rejoindre une équipe ».
        createdAt: _date(m['created_at']),
      );

  static DateTime _date(Object? v) {
    if (v is DateTime) return v;
    if (v is String) return DateTime.tryParse(v) ?? DateTime.now();
    try {
      return (v as dynamic).toDate() as DateTime; // Timestamp Firestore
    } catch (_) {
      return DateTime.now();
    }
  }

  Map<String, dynamic> toMap() => {
        'name': name,
        'invite_code': inviteCode,
        'admin_id': adminId,
        'created_at': createdAt.toIso8601String(),
      };
}

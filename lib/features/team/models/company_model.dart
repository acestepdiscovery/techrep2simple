class CompanyModel {
  final String id;
  final String name;
  final String inviteCode;
  final String adminId;
  final DateTime createdAt;

  const CompanyModel({
    required this.id,
    required this.name,
    required this.inviteCode,
    required this.adminId,
    required this.createdAt,
  });

  factory CompanyModel.fromMap(String id, Map<String, dynamic> m) => CompanyModel(
        id: id,
        name: m['name'] ?? '',
        inviteCode: m['invite_code'] ?? '',
        adminId: m['admin_id'] ?? '',
        createdAt: DateTime.parse(m['created_at']),
      );

  Map<String, dynamic> toMap() => {
        'name': name,
        'invite_code': inviteCode,
        'admin_id': adminId,
        'created_at': createdAt.toIso8601String(),
      };
}

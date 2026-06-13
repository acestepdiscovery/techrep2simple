class TeamMemberModel {
  final String uid;
  final String email;
  final String displayName;
  final String role; // 'admin' | 'tech'
  final DateTime joinedAt;
  final String status; // 'pending' | 'active' | 'disabled'
  final bool canValidate; // can validate submitted reports
  final bool canInvite; // can see and share the invite code

  const TeamMemberModel({
    required this.uid,
    required this.email,
    required this.displayName,
    required this.role,
    required this.joinedAt,
    this.status = 'active',
    this.canValidate = false,
    this.canInvite = false,
  });

  bool get active => status == 'active';
  bool get isPending => status == 'pending';
  bool get isAdmin => role == 'admin';

  factory TeamMemberModel.fromMap(String uid, Map<String, dynamic> m) {
    // Backward compat: if no status field, derive from legacy active bool
    final String status;
    if (m.containsKey('status')) {
      status = m['status'] as String? ?? 'active';
    } else {
      status = (m['active'] as bool? ?? true) ? 'active' : 'disabled';
    }
    return TeamMemberModel(
      uid: uid,
      email: m['email'] ?? '',
      displayName: m['display_name'] ?? '',
      role: m['role'] ?? 'tech',
      joinedAt: DateTime.tryParse(m['joined_at'] ?? '') ?? DateTime.now(),
      status: status,
      canValidate: m['can_validate'] as bool? ?? false,
      canInvite: m['can_invite'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toMap() => {
        'email': email,
        'display_name': displayName,
        'role': role,
        'joined_at': joinedAt.toIso8601String(),
        'status': status,
        'active': active, // backward compat for memberActiveProvider
        'can_validate': canValidate,
        'can_invite': canInvite,
      };

  TeamMemberModel copyWith({
    String? status,
    bool? canValidate,
    bool? canInvite,
  }) =>
      TeamMemberModel(
        uid: uid,
        email: email,
        displayName: displayName,
        role: role,
        joinedAt: joinedAt,
        status: status ?? this.status,
        canValidate: canValidate ?? this.canValidate,
        canInvite: canInvite ?? this.canInvite,
      );
}

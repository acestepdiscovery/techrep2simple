class ClientModel {
  final String id;
  final String name;
  final String address;
  final String phone;
  final String email;
  final String contactPerson;
  final String contractNumber;
  /// (2026-10-14) SIREN / n° de TVA (si le client est une entreprise).
  final String businessId;
  final String notes;
  final DateTime createdAt;
  final DateTime updatedAt;

  const ClientModel({
    required this.id,
    required this.name,
    this.address = '',
    this.phone = '',
    this.email = '',
    this.contactPerson = '',
    this.contractNumber = '',
    this.businessId = '',
    this.notes = '',
    required this.createdAt,
    required this.updatedAt,
  });

  ClientModel copyWith({
    String? name,
    String? address,
    String? phone,
    String? email,
    String? contactPerson,
    String? contractNumber,
    String? businessId,
    String? notes,
  }) =>
      ClientModel(
        id: id,
        name: name ?? this.name,
        address: address ?? this.address,
        phone: phone ?? this.phone,
        email: email ?? this.email,
        contactPerson: contactPerson ?? this.contactPerson,
        contractNumber: contractNumber ?? this.contractNumber,
        businessId: businessId ?? this.businessId,
        notes: notes ?? this.notes,
        createdAt: createdAt,
        updatedAt: DateTime.now(),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'address': address,
        'phone': phone,
        'email': email,
        'contact_person': contactPerson,
        'contract_number': contractNumber,
        'business_id': businessId,
        'notes': notes,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  factory ClientModel.fromMap(Map<String, dynamic> m) => ClientModel(
        id: m['id'],
        name: m['name'] ?? '',
        address: m['address'] ?? '',
        phone: m['phone'] ?? '',
        email: m['email'] ?? '',
        contactPerson: m['contact_person'] ?? '',
        contractNumber: m['contract_number'] ?? '',
        businessId: m['business_id'] ?? '',
        notes: m['notes'] ?? '',
        createdAt: DateTime.parse(m['created_at']),
        updatedAt: DateTime.parse(m['updated_at']),
      );
}

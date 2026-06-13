import 'package:cloud_firestore/cloud_firestore.dart';
import '../../features/clients/models/client_model.dart';

class SharedClientModel {
  final String id;
  final String name;
  final String address;
  final String phone;
  final String email;
  final String contactPerson;
  final String contractNumber;
  final String notes;
  final String sharedByUid;
  final String sharedByName;

  const SharedClientModel({
    required this.id,
    required this.name,
    this.address = '',
    this.phone = '',
    this.email = '',
    this.contactPerson = '',
    this.contractNumber = '',
    this.notes = '',
    this.sharedByUid = '',
    this.sharedByName = '',
  });

  factory SharedClientModel.fromFirestore(
          String id, Map<String, dynamic> d) =>
      SharedClientModel(
        id: id,
        name: d['name'] ?? '',
        address: d['address'] ?? '',
        phone: d['phone'] ?? '',
        email: d['email'] ?? '',
        contactPerson: d['contact_person'] ?? '',
        contractNumber: d['contract_number'] ?? '',
        notes: d['notes'] ?? '',
        sharedByUid: d['shared_by_uid'] ?? '',
        sharedByName: d['shared_by_name'] ?? '',
      );
}

class SharedClientsService {
  static final SharedClientsService _i = SharedClientsService._();
  factory SharedClientsService() => _i;
  SharedClientsService._();

  FirebaseFirestore get _db => FirebaseFirestore.instance;

  Stream<List<SharedClientModel>> stream(String companyId) => _db
      .collection('companies_raptech1')
      .doc(companyId)
      .collection('shared_clients_raptech1')
      .orderBy('name')
      .snapshots()
      .map((s) => s.docs
          .map((d) => SharedClientModel.fromFirestore(d.id, d.data()))
          .toList());

  Future<void> shareClient(
    String companyId,
    ClientModel client, {
    required String sharedByUid,
    required String sharedByName,
  }) =>
      _db
          .collection('companies_raptech1')
          .doc(companyId)
          .collection('shared_clients_raptech1')
          .doc(client.id)
          .set({
        ...client.toMap(),
        'shared_by_uid': sharedByUid,
        'shared_by_name': sharedByName,
        'shared_at': FieldValue.serverTimestamp(),
      });

  Future<void> unshareClient(String companyId, String clientId) => _db
      .collection('companies_raptech1')
      .doc(companyId)
      .collection('shared_clients_raptech1')
      .doc(clientId)
      .delete();
}

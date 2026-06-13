import 'dart:convert';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import '../../../features/reports/models/report_model.dart';
import '../../../features/team/models/company_model.dart';
import '../../../features/team/models/team_member_model.dart';
import '../../core/config/cf_config.dart';

const _kCfUrl = kCfBaseUrl;

class TeamService {
  static final TeamService _instance = TeamService._internal();
  factory TeamService() => _instance;
  TeamService._internal();

  FirebaseFirestore get _db => FirebaseFirestore.instance;

  // ─── Invite code ──────────────────────────────────────────────────────────

  String _generateCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // no 0/O/1/I confusion
    final rng = Random.secure();
    return List.generate(6, (_) => chars[rng.nextInt(chars.length)]).join();
  }

  // ─── Company ──────────────────────────────────────────────────────────────

  /// Creates a company via the Cloud Function (server-side).
  /// The CF sets admin member doc with active=true, role='admin' — cannot be forged.
  Future<CompanyModel> createCompany({
    required String name,
    required String adminUid,
    required String adminEmail,
    required String adminDisplayName,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('Non authentifié');
    final idToken = await user.getIdToken();

    final response = await http.post(
      Uri.parse('$_kCfUrl/create-company'),
      headers: {
        'Authorization': 'Bearer $idToken',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'name': name.trim(),
        'display_name': adminDisplayName,
      }),
    );

    if (response.statusCode != 200) {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      throw Exception(body['error'] ?? 'Erreur création équipe');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return CompanyModel(
      id: data['id'] as String,
      name: data['name'] as String,
      inviteCode: data['invite_code'] as String,
      adminId: data['admin_id'] as String,
      createdAt: DateTime.tryParse(data['created_at'] as String? ?? '') ?? DateTime.now(),
    );
  }

  /// (#3) Rejoindre une équipe par CODE SEUL (plus de nom requis) : le code est
  /// unique, donc renommer l'équipe ne casse plus le flux de jointure.
  Future<CompanyModel?> joinCompany({
    required String inviteCode,
    required String uid,
    required String email,
    required String displayName,
  }) async {
    final code = inviteCode.trim().toUpperCase();
    if (code.isEmpty) return null;

    final snap = await _db
        .collection('companies_raptech1')
        .where('invite_code', isEqualTo: code)
        .limit(1)
        .get();

    if (snap.docs.isEmpty) return null;
    final matched = snap.docs.first;

    // Seat limit check (best-effort, UX only).
    // (4h) Un non-membre ne peut PAS lister les membres (règles Firestore) :
    // ce pré-contrôle peut donc échouer par PERMISSION_DENIED → on le rend
    // NON BLOQUANT. Le vrai plafond est imposé à l'approbation admin
    // (approveMember), où l'admin (membre actif) peut compter les sièges.
    final sub = matched.data()['subscription'] as Map<String, dynamic>?;
    final seatLimit = sub?['seat_limit'] as int?;
    if (seatLimit != null) {
      try {
        final membersSnap =
            await matched.reference.collection('members_raptech1').get();
        final activeCount = membersSnap.docs
            .where((d) => d.data()['active'] as bool? ?? true)
            .length;
        if (activeCount >= seatLimit) {
          throw Exception('Équipe complète ($activeCount/$seatLimit sièges). '
              'Demandez à l\'administrateur d\'ajouter des sièges.');
        }
      } on FirebaseException {
        // Lecture refusée avant d'être membre → on laisse passer ; l'admin
        // tranchera à l'approbation.
      }
    }

    final company = CompanyModel.fromMap(matched.id, matched.data());

    await matched.reference.collection('members_raptech1').doc(uid).set(
          TeamMemberModel(
            uid: uid,
            email: email,
            displayName: displayName,
            role: 'tech',
            joinedAt: DateTime.now(),
            status: 'pending', // admin must approve before seat is active
          ).toMap(),
        );

    return company;
  }

  Future<CompanyModel?> getCompany(String companyId) async {
    final doc = await _db.collection('companies_raptech1').doc(companyId).get();
    if (!doc.exists) return null;
    return CompanyModel.fromMap(doc.id, doc.data()!);
  }

  Future<String> regenerateInviteCode(String companyId) async {
    final code = _generateCode();
    await _db.collection('companies_raptech1').doc(companyId).update({'invite_code': code});
    return code;
  }

  Future<void> updateCompanyName(String companyId, String newName) async {
    await _db.collection('companies_raptech1').doc(companyId).update({
      'name': newName.trim(),
    });
  }

  /// (identité équipe) Infos entreprise de l'ÉQUIPE (sur les PDF d'équipe).
  /// Champs attendus : company_address, company_phone, company_email,
  /// company_siret, company_tva. Réservé à l'admin (règles Firestore).
  Future<void> updateCompanyInfo(
      String companyId, Map<String, String> fields) async {
    final data = <String, dynamic>{
      for (final e in fields.entries) e.key: e.value.trim(),
    };
    if (data.isEmpty) return;
    await _db.collection('companies_raptech1').doc(companyId).update(data);
  }

  /// (e2) Seuil de rapports au-delà duquel le nom d'équipe se verrouille.
  /// Aligné sur le verrou solo (settings) : 10 rapports.
  static const int kNameLockReports = 10;

  /// Nombre total de rapports produits par TOUTE l'équipe (toutes les
  /// soumissions des techniciens vivent dans companies/{id}/reports_raptech1).
  Future<int> countCompanyReports(String companyId) async {
    final col = _db
        .collection('companies_raptech1')
        .doc(companyId)
        .collection('reports_raptech1');
    try {
      final agg = await col.count().get();
      return agg.count ?? 0;
    } catch (_) {
      final snap = await col.get();
      return snap.docs.length;
    }
  }

  /// Returns null if rename is allowed, or an explanation string if locked.
  /// (e2) Le nom d'équipe se verrouille après [kNameLockReports] rapports
  /// cumulés par TOUTE l'équipe (anti-partage de compte / fraude au nom).
  Future<String?> checkRenameAllowed(String companyId) async {
    final count = await countCompanyReports(companyId);
    if (count >= kNameLockReports) {
      return 'Le nom de l\'équipe est verrouillé : votre équipe a déjà produit '
          '$count rapports sous ce nom.\n'
          'Pour un changement justifié, contactez le support — la modification '
          'n\'est pas garantie (mesure anti-fraude).';
    }
    return null;
  }

  // ─── Members ──────────────────────────────────────────────────────────────

  Future<List<TeamMemberModel>> getMembers(String companyId) async {
    final snap = await _db
        .collection('companies_raptech1')
        .doc(companyId)
        .collection('members_raptech1')
        .get();
    return snap.docs
        .map((d) => TeamMemberModel.fromMap(d.id, d.data()))
        .toList();
  }

  Stream<List<TeamMemberModel>> streamMembers(String companyId) {
    return _db
        .collection('companies_raptech1')
        .doc(companyId)
        .collection('members_raptech1')
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => TeamMemberModel.fromMap(d.id, d.data()))
            .toList());
  }

  /// (#9a) L'activation (qui consomme un SIÈGE) passe par la Cloud Function :
  /// les règles Firestore interdisent désormais au client de passer un membre à
  /// `active:true` directement. La CF vérifie les sièges côté serveur (anti-fraude).
  Future<void> approveMember(String companyId, String uid) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('Non authentifié');
    final idToken = await user.getIdToken();
    final response = await http.post(
      Uri.parse('$_kCfUrl/approve-member'),
      headers: {
        'Authorization': 'Bearer $idToken',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'company_id': companyId, 'member_uid': uid}),
    );
    if (response.statusCode != 200) {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      throw Exception(
          body['message'] ?? body['error'] ?? 'Échec de l\'activation du membre');
    }
  }

  Future<void> setMemberActive(String companyId, String uid, bool active) async {
    // (#9a) Réactiver = consommer un siège → on passe par la CF (contrôle sièges).
    // Désactiver = écriture directe autorisée par les règles.
    if (active) {
      await approveMember(companyId, uid);
      return;
    }
    await _db
        .collection('companies_raptech1')
        .doc(companyId)
        .collection('members_raptech1')
        .doc(uid)
        .update({'status': 'disabled', 'active': false});
  }

  Future<void> setMemberPermissions(
    String companyId,
    String uid, {
    bool? canValidate,
    bool? canInvite,
  }) async {
    final data = <String, dynamic>{};
    if (canValidate != null) data['can_validate'] = canValidate;
    if (canInvite != null) data['can_invite'] = canInvite;
    if (data.isEmpty) return;
    await _db
        .collection('companies_raptech1')
        .doc(companyId)
        .collection('members_raptech1')
        .doc(uid)
        .update(data);
  }

  Stream<TeamMemberModel?> streamCurrentMember(String companyId, String uid) {
    return _db
        .collection('companies_raptech1')
        .doc(companyId)
        .collection('members_raptech1')
        .doc(uid)
        .snapshots()
        .map((snap) =>
            snap.exists ? TeamMemberModel.fromMap(snap.id, snap.data()!) : null);
  }

  Future<void> removeMember(String companyId, String uid) async {
    await _db
        .collection('companies_raptech1')
        .doc(companyId)
        .collection('members_raptech1')
        .doc(uid)
        .delete();
  }

  Future<void> leaveCompany(String companyId, String uid) => removeMember(companyId, uid);

  /// (#2/#3) Dissout l'équipe (supprime le doc company). À n'appeler que par un
  /// admin dont l'équipe n'a plus d'autres membres (les règles l'imposent).
  Future<void> dissolveCompany(String companyId) async {
    await _db.collection('companies_raptech1').doc(companyId).delete();
  }

  // ─── Reports ──────────────────────────────────────────────────────────────

  Future<void> syncReport(String companyId, ReportModel report) async {
    final ref = _db
        .collection('companies_raptech1')
        .doc(companyId)
        .collection('reports_raptech1')
        .doc(report.id);

    final data = <String, dynamic>{
      ...report.toMap(),
      'synced_at': FieldValue.serverTimestamp(),
    };

    if (report.status == ReportStatus.submitted) {
      // Refresh snapshot on every (re)submission so the validator always sees
      // the latest content. Also preserves snapshot if no edit was made by
      // including it explicitly — prevents tx.set from wiping an existing field.
      data['snapshot'] = _buildSnapshot(report);
      await ref.set(data);
    } else {
      await ref.set(data);
    }
  }

  static Map<String, dynamic> _buildSnapshot(ReportModel report) {
    return {
      'client_name': report.clientName,
      'client_address': report.clientAddress,
      'client_phone': report.clientPhone,
      'client_contact': report.clientContact,
      'contract_number': report.contractNumber,
      'intervention_type': report.interventionType,
      'sector': report.sector.name,
      'date': report.date.toIso8601String(),
      'end_date': report.endDate?.toIso8601String(),
      'description': report.description,
      'observations': report.observations,
      'equipment_type': report.equipmentType,
      'equipment_brand': report.equipmentBrand,
      'equipment_model': report.equipmentModel,
      'equipment_serial': report.equipmentSerial,
      'sector_fields': report.sectorFields,
      'photo_count': report.photosPaths.length,
      'photo_names': report.photosPaths.map((p) => p.split('/').last).toList(),
      'labor_hours': report.laborHours,
      'labor_rate': report.laborRate,
      'materials': report.materials.map((m) => m.toMap()).toList(),
      'technician_name': report.technicianName,
      'technician_id': report.technicianId,
      'signature_client': report.signatureClientData,
      'signature_tech': report.signatureTechData,
      'submitted_at': FieldValue.serverTimestamp(),
    };
  }

  Future<void> updateReportStatus(
      String companyId, String reportId, String status,
      {String? rejectionComment}) async {
    final data = <String, dynamic>{
      'status': status,
      'synced_at': FieldValue.serverTimestamp(),
    };
    if (status == 'rejected' && rejectionComment != null && rejectionComment.isNotEmpty) {
      data['rejection_comment'] = rejectionComment;
    }
    // rejection_comment is intentionally NOT cleared on validation — kept as
    // a trace so the tech can review previous feedback.
    await _db
        .collection('companies_raptech1')
        .doc(companyId)
        .collection('reports_raptech1')
        .doc(reportId)
        .update(data);
  }

  Future<void> requestPhotos(
      String companyId, String reportId, String adminName) async {
    await _db
        .collection('companies_raptech1')
        .doc(companyId)
        .collection('reports_raptech1')
        .doc(reportId)
        .update({
      'photo_request_by': adminName.isEmpty ? 'Admin' : adminName,
      'photo_request_at': FieldValue.serverTimestamp(),
    });
  }

  Future<void> clearPhotoRequest(String companyId, String reportId) async {
    await _db
        .collection('companies_raptech1')
        .doc(companyId)
        .collection('reports_raptech1')
        .doc(reportId)
        .update({
      'photo_request_by': FieldValue.delete(),
      'photo_request_at': FieldValue.delete(),
    });
  }

  Future<String?> getPhotoRequest(String companyId, String reportId) async {
    try {
      final doc = await _db
          .collection('companies_raptech1')
          .doc(companyId)
          .collection('reports_raptech1')
          .doc(reportId)
          .get();
      final by = doc.data()?['photo_request_by'] as String?;
      return (by != null && by.isNotEmpty) ? by : null;
    } catch (_) {
      return null;
    }
  }

  /// Stream all reports for admin, or only own reports for tech.
  Stream<List<Map<String, dynamic>>> streamTeamReports(
    String companyId, {
    String? technicianId,
  }) {
    Query<Map<String, dynamic>> query = _db
        .collection('companies_raptech1')
        .doc(companyId)
        .collection('reports_raptech1')
        .orderBy('updated_at', descending: true);

    if (technicianId != null) {
      query = query.where('technician_id', isEqualTo: technicianId);
    }

    return query.snapshots().map(
          (snap) => snap.docs.map((d) => {'id': d.id, ...d.data()}).toList(),
        );
  }
}

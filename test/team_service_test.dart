// Équipe (2026-10-19) avec une base Firestore SIMULÉE (fake_cloud_firestore) :
// ce que l'app écrit / lit pour les équipes, sans toucher au vrai serveur.
// (Les RÈGLES de sécurité ne sont pas testées ici : il faut l'émulateur.)
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reportnew1cld/features/reports/models/report_model.dart';
import 'package:reportnew1cld/features/reports/providers/reports_provider.dart';
import 'package:reportnew1cld/features/team/models/company_model.dart';
import 'package:reportnew1cld/shared/services/local_db_service.dart';
import 'package:reportnew1cld/shared/services/team_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _co = 'co1';

ReportModel _report(String id,
        {ReportStatus status = ReportStatus.submitted, String? tech = 'techA'}) =>
    ReportModel(
      id: id,
      clientName: 'Client $id',
      description: 'Travaux',
      date: DateTime(2026, 10, 1),
      status: status,
      photosPaths: const ['/x/photo1.jpg', '/x/photo2.jpg'],
      technicianId: tech,
      companyId: _co,
      createdAt: DateTime(2026, 10, 1),
      updatedAt: DateTime(2026, 10, 1),
    );

void main() {
  late FakeFirebaseFirestore db;
  final team = TeamService();

  setUp(() async {
    db = FakeFirebaseFirestore();
    TeamService.debugFirestore = db;
    await db.collection('companies_raptech1').doc(_co).set({
      'name': 'ACME',
      'invite_code': 'ABC234',
      'admin_id': 'boss',
      'created_at': '2026-10-01T08:00:00Z',
    });
  });
  tearDown(() => TeamService.debugFirestore = null);

  group('code d\'invitation', () {
    test('trouvé sans tenir compte des espaces ni des minuscules', () async {
      final c = await team.findCompanyByInviteCode('  abc234 ');
      expect(c?.id, _co);
      expect(c?.name, 'ACME');
    });
    test('code inconnu ou vide → aucune équipe (rien n\'est quitté)', () async {
      expect(await team.findCompanyByInviteCode('ZZZ999'), isNull);
      expect(await team.findCompanyByInviteCode('   '), isNull);
    });
    test('rejoindre = demande EN ATTENTE (jamais active d\'office)', () async {
      final c = await team.joinCompany(
          inviteCode: 'abc234', uid: 'u9', email: 'u9@x.fr', displayName: 'Ugo');
      expect(c?.id, _co);
      final m = (await db
              .doc('companies_raptech1/$_co/members_raptech1/u9')
              .get())
          .data()!;
      expect(m['status'], 'pending');
      expect(m['active'], isFalse);
      expect(m['role'], 'tech');
    });
    test('date de création au format Firestore : ne plante plus', () {
      final c = CompanyModel.fromMap('x', {
        'name': 'N', 'invite_code': 'C', 'admin_id': 'a',
        'created_at': Timestamp.fromDate(DateTime(2026, 1, 2)),
      });
      expect(c.createdAt, DateTime(2026, 1, 2));
      expect(CompanyModel.fromMap('y', {'name': 'N'}).name, 'N');
    });
  });

  group('membres', () {
    Future<Map<String, dynamic>> member(String uid) async =>
        (await db.doc('companies_raptech1/$_co/members_raptech1/$uid').get()).data()!;

    setUp(() => db.doc('companies_raptech1/$_co/members_raptech1/t1').set({
          'email': 't1@x.fr', 'display_name': 'Théo', 'role': 'tech',
          'status': 'active', 'active': true,
        }));

    test('droits : valider / inviter', () async {
      await team.setMemberPermissions(_co, 't1', canValidate: true, canInvite: false);
      final m = await member('t1');
      expect(m['can_validate'], isTrue);
      expect(m['can_invite'], isFalse);
    });
    test('désactiver = statut « disabled » et inactif', () async {
      await team.setMemberActive(_co, 't1', false);
      final m = await member('t1');
      expect(m['status'], 'disabled');
      expect(m['active'], isFalse);
    });
    test('retirer / quitter = adhésion supprimée', () async {
      await team.leaveCompany(_co, 't1');
      expect(
          (await db.doc('companies_raptech1/$_co/members_raptech1/t1').get()).exists,
          isFalse);
    });
    test('liste des membres en direct', () async {
      final list = await team.streamMembers(_co).first;
      expect(list.single.displayName, 'Théo');
      expect(list.single.active, isTrue);
    });
  });

  group('rapports d\'équipe', () {
    Future<Map<String, dynamic>> doc(String id) async =>
        (await db.doc('companies_raptech1/$_co/reports_raptech1/$id').get()).data()!;

    test('envoi : copie figée (snapshot) pour le valideur', () async {
      await team.syncReport(_co, _report('r1'));
      final d = await doc('r1');
      expect(d['status'], 'submitted');
      final snap = d['snapshot'] as Map<String, dynamic>;
      expect(snap['client_name'], 'Client r1');
      expect(snap['photo_count'], 2);
      expect(snap['photo_names'], ['photo1.jpg', 'photo2.jpg']);
    });

    test('renvoi avec commentaire ; validation garde la trace', () async {
      await team.syncReport(_co, _report('r2'));
      await team.updateReportStatus(_co, 'r2', 'rejected',
          rejectionComment: 'Photo du compteur manquante');
      expect((await doc('r2'))['rejection_comment'], 'Photo du compteur manquante');
      await team.updateReportStatus(_co, 'r2', 'validated');
      final d = await doc('r2');
      expect(d['status'], 'validated');
      expect(d['rejection_comment'], 'Photo du compteur manquante');
    });

    test('renvoi sans commentaire : aucun commentaire vide écrit', () async {
      await team.syncReport(_co, _report('r3'));
      await team.updateReportStatus(_co, 'r3', 'rejected', rejectionComment: '');
      expect((await doc('r3')).containsKey('rejection_comment') &&
          (await doc('r3'))['rejection_comment'] != null, isFalse);
    });

    test('technicien : seulement SES rapports, du plus récent au plus ancien', () async {
      Future<void> put(String id, String tech, String updated) =>
          db.doc('companies_raptech1/$_co/reports_raptech1/$id').set(
              {'technician_id': tech, 'updated_at': updated, 'status': 'submitted'});
      await put('a', 'techA', '2026-10-01T10:00:00');
      await put('b', 'techB', '2026-10-03T10:00:00');
      await put('c', 'techA', '2026-10-05T10:00:00');
      await put('d', 'techA', '2026-09-20T10:00:00');
      final mine = await team.streamTeamReports(_co, technicianId: 'techA').first;
      expect(mine.map((r) => r['id']), ['c', 'a', 'd']);
      final all = await team.streamTeamReports(_co).first;
      expect(all.map((r) => r['id']), ['c', 'b', 'a', 'd']);
    });
  });

  group('statuts rapatriés sur le téléphone du technicien', () {
    setUpAll(() async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfiNoIsolate;
      await databaseFactory.setDatabasesPath(
          Directory.systemTemp.createTempSync('techreport_team_').path);
    });

    test('validé / renvoyé par le responsable → mis à jour en local', () async {
      final db0 = LocalDbService();
      await db0.insertReport(_report('L1'));
      await db0.insertReport(_report('L2'));
      await team.syncReport(_co, _report('L1'));
      await team.syncReport(_co, _report('L2'));
      await team.updateReportStatus(_co, 'L1', 'validated');
      await team.updateReportStatus(_co, 'L2', 'rejected', rejectionComment: 'Refaire');

      final c = ProviderContainer();
      addTearDown(c.dispose);
      await c.read(reportsProvider.future);
      await c.read(reportsProvider.notifier).syncStatusFromTeam(_co, 'techA');

      final l1 = (await db0.getReport('L1'))!;
      final l2 = (await db0.getReport('L2'))!;
      expect(l1.status, ReportStatus.validated);
      expect(l2.status, ReportStatus.rejected);
      expect(l2.rejectionComment, 'Refaire');
      expect(l1.photosPaths, hasLength(2), reason: 'rien d\'autre ne change');
    });
  });

  // (2026-10-20) Signature à distance reçue APRÈS l'envoi : seule la signature est
  // ajoutée (la copie figée d'un rapport envoyé est verrouillée par les règles —
  // la réécriture complète était refusée : « permission-denied » vu au test).
  test('signature à distance après envoi : signature ajoutée, copie figée intacte', () async {
    final r = _report('r_sig');
    await team.syncReport(_co, r);
    Future<Map<String, dynamic>> read() async => (await db
            .collection('companies_raptech1').doc(_co)
            .collection('reports_raptech1').doc('r_sig').get())
        .data()!;
    final before = await read();
    await team.pushRemoteSignature(
        _co, r.copyWith(signatureClientData: 'iVBORw0KGgo=', signedRemotely: true));
    final after = await read();
    expect(after['signature_client_data'], 'iVBORw0KGgo=');
    expect(after['signed_remotely'], 1);
    expect(after['snapshot'], before['snapshot'], reason: 'copie figée inchangée');
    expect(after['status'], 'submitted');
  });

  test('signature à distance : rapport absent côté équipe → envoi complet', () async {
    final r = _report('r_absent').copyWith(signatureClientData: 'iVBORw0KGgo=', signedRemotely: true);
    await team.pushRemoteSignature(_co, r);
    final d = (await db.collection('companies_raptech1').doc(_co)
            .collection('reports_raptech1').doc('r_absent').get()).data();
    expect(d?['signature_client_data'], 'iVBORw0KGgo=');
    expect(d?['client_name'], 'Client r_absent');
  });
}

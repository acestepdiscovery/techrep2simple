// Base locale (2026-10-19) : historique d'un client, numérotation des rapports,
// numéro déjà pris, modèles.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reportnew1cld/features/reports/models/report_model.dart';
import 'package:reportnew1cld/shared/services/local_db_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

ReportModel _r(String id, {String client = 'Dupont', String? clientId, int number = 0}) =>
    ReportModel(
      id: id,
      reportNumber: number,
      clientId: clientId,
      clientName: client,
      date: DateTime(2026, 10, 1),
      createdAt: DateTime(2026, 10, 1),
      updatedAt: DateTime(2026, 10, 1),
    );

void main() {
  final db = LocalDbService();

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
    await databaseFactory.setDatabasesPath(
        Directory.systemTemp.createTempSync('techreport_db_').path);
  });

  test('historique client : rapports liés + rapports au même nom tapé à la main', () async {
    await db.insertReport(_r('h1', clientId: 'c1'));
    await db.insertReport(_r('h2', client: '  dupont '));       // tapé à la main
    await db.insertReport(_r('h3', client: 'Martin'));          // autre client
    await db.insertReport(_r('h4', client: 'Dupont', clientId: 'c2')); // homonyme lié ailleurs
    final ids = (await db.getReportsByClient('c1', clientName: 'Dupont'))
        .map((r) => r.id)
        .toSet();
    expect(ids, {'h1', 'h2'});
    expect((await db.getReportsByClient('c1')).map((r) => r.id), ['h1'],
        reason: 'sans nom : liens seulement (comportement d\'avant)');
  });

  test('numérotation : suivant = max + 1, jamais sous le numéro de départ', () async {
    await db.insertReport(_r('n1', number: 41));
    expect(await db.getNextReportNumber(), 42);
    await db.setSetting('report_number_start', '100');
    expect(await db.getNextReportNumber(), 100);
    await db.setSetting('report_number_start', '1');
  });

  test('numéro déjà pris par un AUTRE rapport', () async {
    await db.insertReport(_r('t1', number: 7));
    expect(await db.isReportNumberTaken(7, exceptId: 'autre'), isTrue);
    expect(await db.isReportNumberTaken(7, exceptId: 't1'), isFalse);
    expect(await db.isReportNumberTaken(8, exceptId: 'x'), isFalse);
  });

  test('modèles : enregistrer, archiver, supprimer', () async {
    final p = ReportPreset(
        id: 'p1', name: 'Chaudière', createdAt: DateTime(2026),
        data: ReportPreset.fromReport(_r('src')));
    await db.savePreset(p);
    expect((await db.getAllPresets()).map((e) => e.id), contains('p1'));
    await db.archivePreset('p1');
    expect((await db.getAllPresets()).map((e) => e.id), isNot(contains('p1')));
    expect((await db.getArchivedPresets()).map((e) => e.id), contains('p1'));
    await db.deletePreset('p1');
    expect((await db.getArchivedPresets()).map((e) => e.id), isNot(contains('p1')));
  });
}

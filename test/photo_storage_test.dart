// Anti-régression (2026-10-14) : les photos des rapports ne doivent plus vivre
// dans le CACHE (vidé par le système). Vérifie : sauvetage des anciennes photos,
// copie permanente, et suppression seulement quand plus aucun rapport ne les
// utilise (cas du duplicata).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
// ignore: depend_on_referenced_packages
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:reportnew1cld/features/reports/models/report_model.dart';
import 'package:reportnew1cld/shared/services/local_db_service.dart';
import 'package:reportnew1cld/shared/services/photo_storage.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _FakePaths extends PathProviderPlatform with MockPlatformInterfaceMixin {
  _FakePaths(this.root);
  final String root;
  @override
  Future<String?> getApplicationDocumentsPath() async => p.join(root, 'documents');
  @override
  Future<String?> getTemporaryPath() async => p.join(root, 'cache');
}

ReportModel _report(String id, List<String> photos) => ReportModel(
      id: id,
      clientName: 'C',
      date: DateTime(2026, 10, 14),
      photosPaths: photos,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

void main() {
  late Directory root;

  setUpAll(() async {
    root = Directory.systemTemp.createTempSync('techreport_photos_');
    Directory(p.join(root.path, 'documents')).createSync();
    Directory(p.join(root.path, 'cache')).createSync();
    PathProviderPlatform.instance = _FakePaths(root.path);
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await databaseFactory.setDatabasesPath(p.join(root.path, 'db'));
  });

  tearDownAll(() {
    try {
      root.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('photos : sauvetage du cache, copie permanente, suppression sûre', () async {
    // Photo d'un ancien rapport (1.0.0) restée dans le CACHE.
    final cachePhoto = File(p.join(root.path, 'cache', 'scaled_123.jpg'))
      ..writeAsBytesSync([1, 2, 3]);
    final dbs = LocalDbService();
    await dbs.insertReport(_report('old', [cachePhoto.path]));

    await dbs.rescueTemporaryPhotos();
    final rescued = (await dbs.getReport('old'))!.photosPaths.single;
    expect(rescued, isNot(cachePhoto.path));
    expect(await PhotoStorage.isPermanent(rescued), isTrue);
    expect(File(rescued).readAsBytesSync(), [1, 2, 3]);

    // Le système vide le cache → la photo du rapport est toujours là.
    cachePhoto.deleteSync();
    expect(File(rescued).existsSync(), isTrue);

    // Duplicata qui partage la même photo : supprimer l'original ne l'efface pas.
    await dbs.insertReport(_report('copy', [rescued]));
    await dbs.deleteReport('old');
    expect(File(rescued).existsSync(), isTrue, reason: 'encore utilisée par le duplicata');
    await dbs.deleteReport('copy');
    expect(File(rescued).existsSync(), isFalse, reason: 'plus aucun rapport ne l’utilise');

    // Une photo hors de l'app (galerie) n'est jamais supprimée.
    final gallery = File(p.join(root.path, 'galerie.jpg'))..writeAsBytesSync([9]);
    await PhotoStorage.deleteIfOwned(gallery.path);
    expect(gallery.existsSync(), isTrue);
  });
}

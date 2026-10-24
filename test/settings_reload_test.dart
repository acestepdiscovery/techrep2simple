// (2026-10-24) Réglages perdus au redémarrage : devise, taxe par défaut,
// mentions de facture, assurance étaient ENREGISTRÉS mais jamais RECHARGÉS
// (vu en direct sur l'émulateur : GBP → USD après redémarrage).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reportnew1cld/features/settings/providers/settings_provider.dart';
import 'package:reportnew1cld/shared/services/local_db_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  final db = LocalDbService();

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
    await databaseFactory.setDatabasesPath(
        Directory.systemTemp.createTempSync('techreport_settings_').path);
  });

  test('jamais réglés → absents (défaut du pays ; facture : texte par défaut)', () async {
    final s = await loadSettings(db);
    for (final k in kOptionalSettingKeys) {
      expect(s.containsKey(k), isFalse, reason: k);
    }
  });

  test('devise, taxe, mentions, assurance : relus après « redémarrage »', () async {
    await db.setSetting('currency_code', 'GBP');
    await db.setSetting('tax_rate', '10.0');
    await db.setSetting('tax_label', 'TVA');
    await db.setSetting('tax_mention', 'TVA 10 % travaux de rénovation');
    await db.setSetting('invoice_terms', ''); // vidé exprès ≠ jamais réglé
    await db.setSetting('insurance_info', 'RC Pro n° 123');
    final s = await loadSettings(db); // = nouveau démarrage de l'app
    expect(s['currency_code'], 'GBP');
    expect(s['tax_rate'], '10.0');
    expect(s['tax_label'], 'TVA');
    expect(s['tax_mention'], 'TVA 10 % travaux de rénovation');
    expect(s['invoice_terms'], '');
    expect(s['insurance_info'], 'RC Pro n° 123');
    expect(s['pdf_template'], 'professionnel'); // les anciens réglages restent
  });

  test('nom du compte = nom du technicien par défaut (inchangé)', () async {
    final s = await loadSettings(db, accountName: 'Julien Martin');
    expect(s['technician_name'], 'Julien Martin');
    expect(s['team_technician_name'], 'Julien Martin');
  });

  test('garde-fou : toute clé écrite via settingsProvider est relue au démarrage', () async {
    final written = <String>{};
    final set = RegExp(r"\.set\(\s*'([a-z_]+)'");
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      final src = f.readAsStringSync();
      if (!src.contains('settingsProvider')) continue;
      written.addAll(set.allMatches(src).map((m) => m.group(1)!));
    }
    expect(written, contains('currency_code'));
    for (final k in written) {
      await db.setSetting(k, 'x');
    }
    final loaded = (await loadSettings(db)).keys.toSet(); // = redémarrage
    expect(written.difference(loaded), isEmpty,
        reason: 'réglage enregistré mais jamais rechargé → perdu au redémarrage');
  });
}

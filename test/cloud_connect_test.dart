// (2026-10-21) Connexion OneDrive / Dropbox, vue au test sur émulateur :
// 1. Après « Accepter » chez Microsoft, l'onglet de connexion restait devant et l'app
//    restait en arrière-plan (mise en pause par Android) → l'envoi échouait. Cause :
//    android:taskAffinity="" sur MainActivity (doc flutter_web_auth_2 : singleTop et
//    AUCUN taskAffinity).
// 2. Erreur d'envoi OneDrive : le message affiche maintenant le code Microsoft
//    (« 404 itemNotFound ») au lieu du seul numéro.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reportnew1cld/shared/services/onedrive_service.dart';

void main() {
  test('MainActivity : singleTop et aucun taskAffinity (retour après connexion OAuth)', () {
    final m = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    final main = RegExp(r'<activity\s[^>]*android:name="\.MainActivity"[^>]*>').firstMatch(m);
    expect(main, isNotNull);
    expect(main!.group(0), contains('android:launchMode="singleTop"'));
    expect(main.group(0), isNot(contains('taskAffinity')));
  });

  test('CallbackActivity écoute bien le schéma de retour OAuth', () {
    final m = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    final i = m.indexOf('com.linusu.flutter_web_auth_2.CallbackActivity');
    expect(i, greaterThan(0));
    expect(m.substring(i, i + 600), contains('android:scheme="com.tec.reportnew1cld"'));
  });

  test('chemin OneDrive : segments encodés, vides retirés', () {
    expect(OneDriveService.graphPath(['Rapport Technique - Northwind Heating', 'r_1.pdf']),
        'Rapport%20Technique%20-%20Northwind%20Heating/r_1.pdf');
    expect(OneDriveService.graphPath(['', ' A & B ', '2026', 'é.pdf']), 'A%20%26%20B/2026/%C3%A9.pdf');
  });

  test('OneDrive jamais activé (réponse réelle de Microsoft du 21/10) reconnu', () {
    const body = '{"error":{"code":"serviceNotAvailable","message":"User is pending provisioning.",'
        '"innerError":{"code":"itemDisabledDueToPendingProvisioning"}}}';
    expect(OneDriveService.isPendingProvisioning(body), isTrue);
    expect(OneDriveService.isPendingProvisioning('{"error":{"code":"itemNotFound"}}'), isFalse);
  });

  test('message « OneDrive pas encore activé » présent dans les 8 langues', () {
    for (final lg in ['fr', 'en', 'de', 'es', 'it', 'nl', 'pl', 'pt']) {
      final s = File('assets/translations/$lg.json').readAsStringSync();
      expect(s, contains('"cloud_err_onedrive_not_ready"'), reason: lg);
      expect(s, contains('onedrive.live.com'), reason: lg);
    }
  });

  test('code d\'erreur Microsoft Graph lisible', () {
    expect(OneDriveService.graphErrorCode('{"error":{"code":"itemNotFound","message":"x"}}'),
        ' itemNotFound');
    expect(OneDriveService.graphErrorCode('pas du json'), '');
    expect(OneDriveService.graphErrorCode('{"error":"x"}'), '');
    expect(OneDriveService.graphErrorCode(''), '');
  });
}

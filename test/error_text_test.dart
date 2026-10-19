// Messages d'erreur montrés à l'utilisateur (2026-10-19) : jamais de jargon
// technique anglais ni de « Exception: » quand on sait mieux dire.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
// ignore: implementation_imports
import 'package:easy_localization/src/localization.dart';
// ignore: implementation_imports
import 'package:easy_localization/src/translations.dart';
import 'package:firebase_core/firebase_core.dart' show FirebaseException;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' show ClientException;
import 'package:reportnew1cld/shared/utils/error_text.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => Localization.load(const Locale('fr'),
      translations: Translations(json.decode(
              File('assets/translations/fr.json').readAsStringSync())
          as Map<String, dynamic>)));

  FirebaseException fb(String code) =>
      FirebaseException(plugin: 'test', code: code, message: 'technical english');

  test('réseau / délai → « vérifiez votre connexion »', () {
    final net = 'ai_err_network'.tr();
    expect(errorText(const SocketException('x')), net);
    expect(errorText(TimeoutException('x')), net);
    expect(errorText(fb('unavailable')), net);
    expect(errorText(fb('network-request-failed')), net);
    expect(errorText(ClientException('Connection closed')), net);
  });

  test('cas du compte : message clair et traduit', () {
    expect(errorText(fb('requires-recent-login')), 'profile_relogin'.tr());
    expect(errorText(fb('email-already-in-use')), 'auth_err_email_in_use'.tr());
    expect(errorText(fb('invalid-email')), 'auth_err_invalid_email'.tr());
    expect(errorText(fb('too-many-requests')), 'auth_err_too_many'.tr());
  });

  test('inconnu : message générique + code, sans le texte anglais', () {
    final t = errorText(fb('permission-denied'));
    expect(t, contains('permission-denied'));
    expect(t, isNot(contains('technical english')));
    expect(errorText(const FormatException('<html>')), 'common_unknown_error'.tr());
  });

  test('nos propres messages : sans le préfixe « Exception: »', () {
    expect(errorText(Exception('Code d\'invitation incorrect.')),
        'Code d\'invitation incorrect.');
    expect(errorText(StateError('Oups')), 'Oups');
  });
}

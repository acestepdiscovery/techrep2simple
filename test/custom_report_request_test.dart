// (2026-10-21) « Votre rapport sur mesure » (idée du user) : Pro → envoi direct des
// fichiers (PDF / photos, 5 max, 15 Mo max, dossier Storage réservé à cette app) ;
// sinon → adresse e-mail de contact.
import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reportnew1cld/features/auth/providers/auth_provider.dart';
import 'package:reportnew1cld/features/settings/custom_report_request.dart';
import 'package:reportnew1cld/features/settings/screens/custom_report_request_screen.dart';
import 'package:reportnew1cld/features/subscription/subscription_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Loader extends AssetLoader {
  const _Loader(this.fr);
  final Map<String, dynamic> fr;
  @override
  Future<Map<String, dynamic>?> load(String path, Locale locale) async => fr;
}

void main() {
  group('règles des fichiers envoyés', () {
    test('formats acceptés : PDF et photos', () {
      expect(templateContentType('Rapport.PDF'), 'application/pdf');
      expect(templateContentType('photo.jpeg'), 'image/jpeg');
      expect(templateContentType('scan.heic'), 'image/heic');
      expect(templateContentType('devis.docx'), isNull);
      expect(templateContentType('sans_extension'), isNull);
    });

    test('refus : mauvais format ou plus de 15 Mo', () {
      expect(templateFileError('a.pdf', 1000), isNull);
      expect(templateFileError('a.exe', 1000), 'type');
      expect(templateFileError('a.pdf', 15 * 1024 * 1024 + 1), 'size');
    });

    test('chemin Storage : dossier de cette app + UID + horodatage + nom nettoyé', () {
      final p = templateRequestPath('UID42', DateTime(2026, 10, 21, 9, 5, 7), 2, 'Mon rapport été (v2).pdf');
      expect(p, 'raptech1_template_requests/UID42/20261021-090507_2_Mon_rapport__t___v2_.pdf');
      final long = templateRequestPath('u', DateTime(2026), 1, '${'x' * 200}.pdf');
      expect(long.split('/').last.length, lessThan(110));
      expect(long, endsWith('.pdf'));
    });

    test('adresse de contact', () => expect(kContactEmail, 'businessKC123@proton.me'));
  });

  group('écran', () {
    late Map<String, dynamic> fr;
    setUpAll(() async {
      SharedPreferences.setMockInitialValues({});
      await EasyLocalization.ensureInitialized();
      fr = json.decode(File('assets/translations/fr.json').readAsStringSync()) as Map<String, dynamic>;
    });

    Future<void> pump(WidgetTester tester, {required bool pro, required bool signedIn}) async {
      final user = signedIn ? MockUser(uid: 'u1', email: 'tech@example.com') : null;
      await tester.pumpWidget(EasyLocalization(
        supportedLocales: const [Locale('fr')],
        fallbackLocale: const Locale('fr'),
        startLocale: const Locale('fr'),
        saveLocale: false,
        path: 'assets/translations',
        assetLoader: _Loader(fr),
        child: ProviderScope(
          overrides: [
            firebaseUserProvider.overrideWith((ref) => Stream.value(user)),
            effectiveSubscriptionProvider.overrideWith((ref) => pro),
          ],
          child: Builder(
            builder: (context) => MaterialApp(
              locale: context.locale,
              supportedLocales: context.supportedLocales,
              localizationsDelegates: context.localizationDelegates,
              home: const CustomReportRequestScreen(),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('gratuit : adresse e-mail, pas d\'envoi direct', (tester) async {
      await pump(tester, pro: false, signedIn: true);
      expect(find.text('Votre rapport sur mesure'), findsOneWidget);
      expect(find.byKey(const ValueKey('crr_email')), findsOneWidget);
      expect(find.byKey(const ValueKey('crr_pick')), findsNothing);
    });

    testWidgets('Pro connecté : choisir des fichiers + envoyer (désactivé sans fichier)', (tester) async {
      await pump(tester, pro: true, signedIn: true);
      expect(find.byKey(const ValueKey('crr_pick')), findsOneWidget);
      final send = tester.widget<FilledButton>(find.ancestor(
          of: find.text('Envoyer'), matching: find.byWidgetPredicate((w) => w is FilledButton)));
      expect(send.onPressed, isNull, reason: 'rien à envoyer');
      expect(find.byKey(const ValueKey('crr_email')), findsOneWidget, reason: 'e-mail aussi proposé');
    });
  });
}

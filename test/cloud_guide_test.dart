// (2026-10-21) Mini-guide « 1re connexion » aux stockages en ligne (demande du user
// après le test OneDrive / Dropbox sur émulateur) : le lien ouvre les 3 marches à
// suivre, dont le cas « OneDrive jamais ouvert sur ce compte ».
import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reportnew1cld/shared/widgets/cloud_guide.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Loader extends AssetLoader {
  const _Loader(this.fr);
  final Map<String, dynamic> fr;
  @override
  Future<Map<String, dynamic>?> load(String path, Locale locale) async => fr;
}

void main() {
  late Map<String, dynamic> fr;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    fr = json.decode(File('assets/translations/fr.json').readAsStringSync()) as Map<String, dynamic>;
  });

  testWidgets('le lien ouvre le guide des 3 services', (tester) async {
    await tester.pumpWidget(EasyLocalization(
      supportedLocales: const [Locale('fr')],
      fallbackLocale: const Locale('fr'),
      startLocale: const Locale('fr'),
      saveLocale: false,
      path: 'assets/translations',
      assetLoader: _Loader(fr),
      child: Builder(
        builder: (context) => MaterialApp(
          locale: context.locale,
          supportedLocales: context.supportedLocales,
          localizationsDelegates: context.localizationDelegates,
          home: const Scaffold(body: Center(child: CloudGuideLink())),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('cloud_guide_link')));
    await tester.pumpAndSettle();
    expect(find.text('Connecter un stockage en ligne'), findsOneWidget);
    for (final s in ['Google Drive', 'OneDrive', 'Dropbox']) {
      expect(find.text(s), findsOneWidget, reason: s);
    }
    expect(find.textContaining('onedrive.live.com'), findsOneWidget);
  });

  test('textes du guide présents dans les 8 langues', () {
    for (final lg in ['fr', 'en', 'de', 'es', 'it', 'nl', 'pl', 'pt']) {
      final m = json.decode(File('assets/translations/$lg.json').readAsStringSync()) as Map;
      for (final k in ['cloud_guide_link', 'cloud_guide_title', 'cloud_guide_gdrive',
          'cloud_guide_onedrive', 'cloud_guide_dropbox', 'cloud_guide_after']) {
        expect((m[k] as String?)?.isNotEmpty, isTrue, reason: '$lg $k');
      }
    }
  });
}

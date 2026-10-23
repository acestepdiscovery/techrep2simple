// (2026-10-23) Bandeau « message du développeur » v2 (demandes du user après le 1er
// essai) : plus visible, « J'ai lu » au lieu d'une croix, et EN DIRECT (apparaît / change
// sans redémarrer l'app). Lecture de config/app_control testée sans Firestore.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reportnew1cld/shared/widgets/app_banner.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _pump(WidgetTester t) async {
  for (var i = 0; i < 4; i++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await t.pump();
  }
}

void main() {
  group('lecture des champs', () {
    test('rien de réglé / id ou texte vide → aucun bandeau', () {
      expect(bannerFromMap(null), isNull);
      expect(bannerFromMap({'banner_id': '', 'banner_message': 'x'}), isNull);
      expect(bannerFromMap({'banner_id': 'a', 'banner_message': '  '}), isNull);
      expect(bannerFromMap({'banner_message': 'x'}), isNull);
    });
    test('message par langue prioritaire, sinon message général', () {
      final d = {'banner_id': 'm1', 'banner_message': 'Bonjour', 'banner_message_de': 'Hallo'};
      expect(bannerFromMap(d, lang: 'de')!.text, 'Hallo');
      expect(bannerFromMap(d, lang: 'fr')!.text, 'Bonjour');
      expect(bannerFromMap(d, lang: 'it')!.text, 'Bonjour');
    });
    test('style « alert » = rouge ; sinon info', () {
      expect(bannerFromMap({'banner_id': 'a', 'banner_message': 'x', 'banner_style': 'alert'})!.alert, isTrue);
      expect(bannerFromMap({'banner_id': 'a', 'banner_message': 'x'})!.alert, isFalse);
    });
    test('banner_max_build : seulement les versions jusqu\'à ce numéro', () {
      final d = {'banner_id': 'a', 'banner_message': 'x', 'banner_max_build': 27};
      expect(bannerFromMap(d, currentBuild: 27), isNotNull);
      expect(bannerFromMap(d, currentBuild: 28), isNull);
    });
  });

  testWidgets('en direct : apparaît sans redémarrer, « J\'ai lu » le ferme, un nouvel id le ramène',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final ctrl = StreamController<Map<String, dynamic>?>();
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: AppBanner(source: ctrl.stream))));
    await _pump(tester);
    expect(find.byKey(const ValueKey('app_banner')), findsNothing, reason: 'rien de réglé');

    ctrl.add({'banner_id': 'maj_1', 'banner_message': 'Mise à jour à venir'});
    await _pump(tester);
    expect(find.text('Mise à jour à venir'), findsOneWidget, reason: 'apparaît sans redémarrer');

    await tester.tap(find.byKey(const ValueKey('app_banner_read')));
    await _pump(tester);
    expect(find.byKey(const ValueKey('app_banner')), findsNothing);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('dismissed_banner_maj_1'), isTrue, reason: 'mémorisé');

    ctrl.add({'banner_id': 'maj_1', 'banner_message': 'Texte corrigé'});
    await _pump(tester);
    expect(find.byKey(const ValueKey('app_banner')), findsNothing, reason: 'même id déjà lu');

    ctrl.add({'banner_id': 'maj_2', 'banner_message': 'Nouveau message', 'banner_style': 'alert'});
    await _pump(tester);
    expect(find.text('Nouveau message'), findsOneWidget, reason: 'nouvel id → revient');

    ctrl.add({'banner_id': ''});
    await _pump(tester);
    expect(find.byKey(const ValueKey('app_banner')), findsNothing, reason: 'vidé → disparaît');
    await ctrl.close();
  });

  testWidgets('déjà lu avant (ancien bandeau, même clé) → pas réaffiché', (tester) async {
    SharedPreferences.setMockInitialValues({'dismissed_banner_maj_1': true});
    final ctrl = StreamController<Map<String, dynamic>?>();
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: AppBanner(source: ctrl.stream))));
    await _pump(tester);
    ctrl.add({'banner_id': 'maj_1', 'banner_message': 'Mise à jour à venir'});
    await _pump(tester);
    expect(find.byKey(const ValueKey('app_banner')), findsNothing);
    await ctrl.close();
  });
}

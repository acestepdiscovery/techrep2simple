// Coupe-circuit / mises à jour / messages (2026-10-19) : lecture du document
// en ligne `config/app_control`. Une faute de saisie dans ce document touche
// TOUS les utilisateurs → on vérifie chaque cas.
import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
// ignore: implementation_imports
import 'package:easy_localization/src/localization.dart';
// ignore: implementation_imports
import 'package:easy_localization/src/translations.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reportnew1cld/features/gate/gate_screen.dart' show startRoute;
import 'package:reportnew1cld/shared/services/kill_switch_service.dart';

/// Champs au format de l'API REST Firestore.
Map<String, dynamic> f(Map<String, Object> m) => {
      for (final e in m.entries)
        e.key: e.value is int
            ? {'integerValue': '${e.value}'}
            : {'stringValue': e.value},
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => Localization.load(const Locale('fr'),
      translations: Translations(json.decode(
              File('assets/translations/fr.json').readAsStringSync())
          as Map<String, dynamic>)));

  group('coupe-circuit', () {
    test('status ACTIVE → app ouverte', () {
      expect(KillSwitchService.fromFields(f({'status': 'ACTIVE'})).allowed, isTrue);
    });
    test('⚠️ status absent ou mal écrit → app BLOQUÉE pour tous (strict)', () {
      expect(KillSwitchService.fromFields(f({'message': 'x'})).allowed, isFalse);
      expect(KillSwitchService.fromFields(f({'status': 'active'})).allowed, isFalse,
          reason: 'sensible à la casse : écrire ACTIVE');
    });
    test('message de blocage : par langue, le générique (FR) seulement aux francophones', () {
      final m = f({'status': 'OFF', 'message': 'Maintenance', 'message_de': 'Wartung'});
      expect(KillSwitchService.fromFields(m, lang: 'de').message, 'Wartung');
      expect(KillSwitchService.fromFields(m, lang: 'fr').message, 'Maintenance');
      expect(KillSwitchService.fromFields(m, lang: 'it').message,
          isNot('Maintenance'), reason: 'un Italien ne lit pas le français');
    });
  });

  group('mises à jour', () {
    final m = f({'status': 'ACTIVE', 'min_build': 15, 'latest_build': 22});
    test('build sous min_build → mise à jour OBLIGATOIRE', () {
      final r = KillSwitchService.fromFields(m, currentBuild: 14);
      expect(r.forceUpdate, isTrue);
      expect(r.softUpdate, isFalse);
    });
    test('entre les deux → proposée ; à jour → rien', () {
      expect(KillSwitchService.fromFields(m, currentBuild: 20).softUpdate, isTrue);
      final ok = KillSwitchService.fromFields(m, currentBuild: 22);
      expect(ok.forceUpdate || ok.softUpdate, isFalse);
    });
    test('build inconnu (0) → jamais bloqué', () {
      expect(KillSwitchService.fromFields(m).forceUpdate, isFalse);
    });
  });

  group('annonces', () {
    test('broadcast : actif avec id + message, borné par broadcast_max_build', () {
      final m = f({'status': 'ACTIVE', 'broadcast_id': 'b1', 'broadcast_message': 'Bonjour',
        'broadcast_max_build': 20});
      expect(KillSwitchService.fromFields(m, currentBuild: 20).broadcastId, 'b1');
      expect(KillSwitchService.fromFields(m, currentBuild: 21).broadcastId, isNull);
    });
    test('bannière sans message → pas de bannière vide', () {
      final m = f({'status': 'ACTIVE', 'banner_id': 'x'});
      expect(KillSwitchService.fromFields(m).bannerId, isNull);
    });
  });

  group('ouverture de l\'app (bienvenue ou accueil)', () {
    test('connecté via « J\'ai déjà un compte » → accueil (avant : bienvenue à chaque fois)', () {
      expect(startRoute(mode: null, onboardingDone: false, signedIn: true), '/home');
    });
    test('premier lancement, pas de compte → bienvenue', () {
      expect(startRoute(mode: null, onboardingDone: false, signedIn: false), '/welcome');
    });
    test('« Utiliser seul » choisi → accueil, même sans compte', () {
      expect(startRoute(mode: 'offline', onboardingDone: true, signedIn: false), '/home');
    });
    test('« Rejoindre une équipe » puis connexion annulée → bienvenue ; connecté → accueil', () {
      expect(startRoute(mode: 'team', onboardingDone: false, signedIn: false), '/welcome');
      expect(startRoute(mode: 'team', onboardingDone: false, signedIn: true), '/home');
    });
  });
}

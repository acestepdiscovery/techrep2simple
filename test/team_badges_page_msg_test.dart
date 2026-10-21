// (2026-10-21) Deux idées validées par le user :
// 1. Pastilles de la liste d'équipe (📷 photos, ✍️ signé, montant HT), calculées depuis
//    le document Firestore du rapport (JSON en texte pour photos et matériel).
// 2. Message PAR PAGE (page IA d'abord), réglé dans config/app_control, invisible tant
//    que rien n'est réglé, fermable.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:reportnew1cld/features/team/team_report_badges.dart';
import 'package:reportnew1cld/shared/services/kill_switch_service.dart';
import 'package:reportnew1cld/shared/widgets/page_message_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> _s(String v) => {'stringValue': v};

void main() {
  group('pastilles de la liste d\'équipe', () {
    test('photos : liste JSON en texte (format Firestore) ou liste', () {
      expect(teamReportPhotoCount({'photos': jsonEncode(['a.jpg', 'b.jpg', 'c.jpg'])}), 3);
      expect(teamReportPhotoCount({'photos': ['a.jpg']}), 1);
      expect(teamReportPhotoCount({'photos': '[]'}), 0);
      expect(teamReportPhotoCount({}), 0);
      expect(teamReportPhotoCount({'photos': 'pas du json'}), 0);
    });

    test('signé : signature client de début OU de fin', () {
      expect(teamReportSigned({'signature_client_data': 'iVBOR…'}), isTrue);
      expect(teamReportSigned({'signature_client_start_data': 'iVBOR…'}), isTrue);
      expect(teamReportSigned({'signature_tech_data': 'iVBOR…'}), isFalse, reason: 'technicien ≠ client');
      expect(teamReportSigned({'signature_client_data': ''}), isFalse);
      expect(teamReportSigned({}), isFalse);
    });

    test('montant HT : main-d\'œuvre + matériel, lignes arrondies comme la facture', () {
      final d = {
        'labor_hours': 2.5,
        'labor_rate': 45,
        'materials': jsonEncode([
          {'reference': '', 'label': 'Joint', 'quantity': 3, 'unitPrice': 1.333},
          {'reference': '', 'label': 'Flexible', 'quantity': 1, 'unitPrice': 12.4},
        ]),
      };
      expect(teamReportAmount(d), 112.5 + 4.0 + 12.4);
      expect(teamReportAmount({}), 0);
    });
  });

  group('message par page', () {
    test('rien de réglé → aucun message', () {
      expect(KillSwitchService.pageMessageFromFields(null, 'ai'), isNull);
      expect(KillSwitchService.pageMessageFromFields({'page_msg_ai': _s('Bonjour')}, 'ai'), isNull,
          reason: 'sans identifiant, rien');
      expect(KillSwitchService.pageMessageFromFields({'page_msg_ai_id': _s('x')}, 'ai'), isNull,
          reason: 'sans texte, rien');
      expect(KillSwitchService.pageMessageFromFields(
          {'page_msg_ai_id': _s(' '), 'page_msg_ai': _s('Bonjour')}, 'ai'), isNull);
    });

    test('texte dans la langue prioritaire, style, autre page ignorée', () {
      final f = {
        'page_msg_ai_id': _s('m1'),
        'page_msg_ai': _s('Message général'),
        'page_msg_ai_de': _s('Deutsche Nachricht'),
        'page_msg_ai_style': _s('alert'),
      };
      final de = KillSwitchService.pageMessageFromFields(f, 'ai', lang: 'de')!;
      expect(de.text, 'Deutsche Nachricht');
      expect(de.alert, isTrue);
      expect(de.id, 'm1');
      expect(KillSwitchService.pageMessageFromFields(f, 'ai', lang: 'fr')!.text, 'Message général');
      expect(KillSwitchService.pageMessageFromFields(f, 'team'), isNull);
    });

    test('limite de version (max_build)', () {
      final f = {
        'page_msg_ai_id': _s('m1'),
        'page_msg_ai': _s('Mettez à jour'),
        'page_msg_ai_max_build': {'integerValue': '23'},
      };
      expect(KillSwitchService.pageMessageFromFields(f, 'ai', currentBuild: 23), isNotNull);
      expect(KillSwitchService.pageMessageFromFields(f, 'ai', currentBuild: 24), isNull);
    });

    testWidgets('carte affichée puis fermée (ne revient pas pour le même id)', (tester) async {
      SharedPreferences.setMockInitialValues({});
      Intl.defaultLocale = 'fr';
      addTearDown(() {
        Intl.defaultLocale = null;
        KillSwitchService.lastFields = null;
      });
      KillSwitchService.lastFields = {
        'page_msg_ai_id': _s('ia-2026-10'),
        'page_msg_ai_fr': _s('Nouveau : dictée jusqu\'à 15 minutes.'),
      };
      Future<void> pumpCard() async {
        await tester.pumpWidget(const MaterialApp(home: Scaffold(body: PageMessageCard(page: 'ai'))));
        for (var i = 0; i < 5; i++) {
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
          await tester.pump();
        }
      }

      await pumpCard();
      expect(find.text('Nouveau : dictée jusqu\'à 15 minutes.'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('page_msg_close_ai')));
      for (var i = 0; i < 3; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump();
      }
      expect(find.byKey(const ValueKey('page_msg_ai')), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await pumpCard();
      expect(find.byKey(const ValueKey('page_msg_ai')), findsNothing, reason: 'fermée = ne revient pas');
    });
  });
}

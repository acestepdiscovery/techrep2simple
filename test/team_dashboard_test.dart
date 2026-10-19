// Écran Équipe (2026-10-19), sur une base Firestore SIMULÉE : verrouille les
// corrections du 19/10 — le droit « Peut valider » (voir les rapports des autres,
// ne pas valider les siens) et le filtre « À valider » (était toujours vide).
import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reportnew1cld/features/auth/providers/auth_provider.dart';
import 'package:reportnew1cld/features/subscription/subscription_provider.dart';
import 'package:reportnew1cld/features/team/models/team_member_model.dart';
import 'package:reportnew1cld/features/team/screens/team_dashboard_screen.dart';
import 'package:reportnew1cld/shared/services/team_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Team extends TeamStateNotifier {
  @override
  Future<TeamState> build() async => const TeamState(
      companyId: 'co1', companyName: 'ACME', role: 'tech', inviteCode: 'ABC234');
}

class _Loader extends AssetLoader {
  const _Loader(this.fr);
  final Map<String, dynamic> fr;
  @override
  Future<Map<String, dynamic>?> load(String path, Locale locale) async => fr;
}

void main() {
  late Map<String, dynamic> fr;

  setUpAll(() async {
    fr = json.decode(File('assets/translations/fr.json').readAsStringSync())
        as Map<String, dynamic>;
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  Future<void> open(WidgetTester tester, {required bool canValidate, bool canInvite = false}) async {
    final db = FakeFirebaseFirestore();
    TeamService.debugFirestore = db;
    addTearDown(() => TeamService.debugFirestore = null);
    Future<void> rep(String id, String tech, String client, String status, String upd) =>
        db.doc('companies_raptech1/co1/reports_raptech1/$id').set({
          'technician_id': tech, 'client_name': client, 'status': status,
          'updated_at': upd, 'date': '2026-10-01T00:00:00.000',
        });
    await tester.runAsync(() async {
      await rep('r1', 'techA', 'Client A', 'submitted', '2026-10-05');
      await rep('r2', 'me', 'Client Moi', 'submitted', '2026-10-04');
      await rep('r3', 'techA', 'Client Valide', 'validated', '2026-10-03');
    });
    final me = TeamMemberModel(
        uid: 'me', email: 'me@x.fr', displayName: 'Moi', role: 'tech',
        joinedAt: DateTime(2026), canValidate: canValidate, canInvite: canInvite);
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(EasyLocalization(
      supportedLocales: const [Locale('fr')],
      fallbackLocale: const Locale('fr'),
      startLocale: const Locale('fr'),
      saveLocale: false,
      useOnlyLangCode: true,
      path: 'assets/translations',
      assetLoader: _Loader(fr),
      child: ProviderScope(
        overrides: [
          firebaseUserProvider.overrideWith((ref) => Stream.value(MockUser(uid: 'me'))),
          teamStateProvider.overrideWith(_Team.new),
          currentMemberProvider.overrideWith((ref) => Stream.value(me)),
          teamPendingCountProvider.overrideWith((ref) => Stream.value(0)),
          companySeatLimitProvider.overrideWith((ref) => 5),
          // Onglet « Rapports » ouvert directement.
          teamTabRequestProvider.overrideWith((ref) => const TeamTabRequest(tab: 1, nonce: 1)),
        ],
        child: Builder(
          builder: (context) => MaterialApp(
            locale: context.locale,
            supportedLocales: context.supportedLocales,
            localizationsDelegates: context.localizationDelegates,
            home: const TeamDashboardScreen(),
          ),
        ),
      ),
    ));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Finder validateButtons() => find.text('td_validate'.tr());

  testWidgets('« Peut valider » : voit TOUS les rapports, ne valide pas les siens', (tester) async {
    await open(tester, canValidate: true);
    expect(find.text('Client A'), findsOneWidget);
    expect(find.text('Client Moi'), findsOneWidget);
    expect(find.text('Client Valide'), findsOneWidget);
    expect(validateButtons(), findsOneWidget,
        reason: 'seulement le rapport ENVOYÉ d\'un AUTRE (pas le sien, pas le validé)');
  });

  testWidgets('technicien simple : seulement SES rapports, aucun bouton Valider', (tester) async {
    await open(tester, canValidate: false);
    expect(find.text('Client Moi'), findsOneWidget);
    expect(find.text('Client A'), findsNothing);
    expect(validateButtons(), findsNothing);
  });

  testWidgets('filtres « À valider » (= envoyés) et « Rejetés »', (tester) async {
    await open(tester, canValidate: true);
    await tester.tap(find.text('td_filter_to_validate'.tr()));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Client A'), findsOneWidget, reason: 'était toujours vide');
    expect(find.text('Client Moi'), findsOneWidget);
    expect(find.text('Client Valide'), findsNothing);
    await tester.tap(find.text('td_filter_rejected'.tr()));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Client A'), findsNothing);
    expect(find.text('td_no_reports'.tr()), findsOneWidget);
  });

  testWidgets("code d'invitation : caché sans le droit « Peut inviter »", (tester) async {
    await open(tester, canValidate: false);
    expect(find.byTooltip('td_share_invite_code'.tr()), findsNothing);
  });

  testWidgets("code d'invitation : partagé avec le droit « Peut inviter »", (tester) async {
    await open(tester, canValidate: false, canInvite: true);
    expect(find.byTooltip('td_share_invite_code'.tr()), findsOneWidget);
  });
}

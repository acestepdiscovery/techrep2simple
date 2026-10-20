// Anti-régression (2026-10-19) : rouvrir un rapport dans le FORMULAIRE ne doit
// rien lui faire perdre. Bug trouvé le 19/10 (présent depuis la 1.0.0) : les
// photos n'étaient pas rechargées et l'auto-enregistrement (2 s après
// l'ouverture) réécrivait le rapport SANS photos et en « Brouillon ».
import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reportnew1cld/features/auth/providers/auth_provider.dart';
import 'package:reportnew1cld/features/reports/models/report_model.dart';
import 'package:reportnew1cld/features/reports/screens/create_report_screen.dart';
import 'package:reportnew1cld/features/settings/providers/settings_provider.dart';
import 'package:reportnew1cld/features/subscription/subscription_provider.dart';
import 'package:reportnew1cld/shared/services/local_db_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// ── Remplaçants sans Firebase ────────────────────────────────────────────────
class _NoTeam extends TeamStateNotifier {
  @override
  Future<TeamState> build() async => const TeamState();
}

class _Settings extends SettingsNotifier {
  @override
  Future<Map<String, String>> build() async =>
      {'technician_name': 'Tech Test', 'company_name': 'ACME'};
}

class _Loader extends AssetLoader {
  const _Loader(this.fr);
  final Map<String, dynamic> fr;
  @override
  Future<Map<String, dynamic>?> load(String path, Locale locale) async => fr;
}

// PNG 1×1 valide (les miniatures sont de vraies images).
final _png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==');

void main() {
  late Map<String, dynamic> fr;
  late Directory tmp;

  setUpAll(() async {
    sqfliteFfiInit();
    // Sans isolat : la base répond dans le temps simulé des tests d'écran.
    databaseFactory = databaseFactoryFfiNoIsolate;
    tmp = Directory.systemTemp.createTempSync('techreport_form_');
    await databaseFactory.setDatabasesPath(tmp.path);
    fr = json.decode(File('assets/translations/fr.json').readAsStringSync())
        as Map<String, dynamic>;
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  Future<ReportModel> seed(String id) async {
    final photos = [
      for (final n in ['a', 'b'])
        (File('${tmp.path}/${id}_$n.png')..writeAsBytesSync(_png)).path,
    ];
    final r = ReportModel(
      id: id,
      reportNumber: 7,
      clientName: 'Client Test',
      description: 'Remplacement du joint',
      date: DateTime(2026, 10, 1),
      status: ReportStatus.validated,
      photosPaths: photos,
      createdAt: DateTime(2026, 10, 1, 8),
      updatedAt: DateTime(2026, 10, 1, 9),
    );
    await LocalDbService().insertReport(r);
    return r;
  }

  Future<void> openForm(WidgetTester tester, String? id,
      {ReportPreset? preset, bool pro = false, bool phone = false}) async {
    // Écran très haut : toutes les sections sont construites (liste paresseuse).
    // (2026-10-20) `phone` : vraie taille de téléphone (412 × 915).
    tester.view.physicalSize = phone ? const Size(412, 915) : const Size(1200, 24000);
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
          firebaseUserProvider.overrideWith((ref) => Stream.value(null)),
          teamStateProvider.overrideWith(_NoTeam.new),
          settingsProvider.overrideWith(_Settings.new),
          effectiveSubscriptionProvider.overrideWith((ref) => pro),
        ],
        child: Builder(
          builder: (context) => MaterialApp(
            locale: context.locale,
            supportedLocales: context.supportedLocales,
            localizationsDelegates: context.localizationDelegates,
            home: CreateReportScreen(reportId: id, templatePreset: preset),
          ),
        ),
      ),
    ));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// Ferme l'écran (déclenche la sauvegarde de sortie) et laisse la base écrire.
  Future<void> closeForm(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 200));
  }

  testWidgets('rouvrir puis quitter sans rien changer : rapport intact', (tester) async {
    final before = (await tester.runAsync(() => seed('r-intact')))!;
    await openForm(tester, before.id);
    // Le formulaire a bien rechargé les 2 photos.
    expect(find.byType(Image), findsAtLeastNWidgets(2));
    // Laisse passer l'auto-enregistrement (2 s).
    await tester.pump(const Duration(seconds: 3));
    await closeForm(tester);

    final after = (await tester.runAsync(() => LocalDbService().getReport(before.id)))!;
    expect(after.photosPaths, before.photosPaths, reason: 'photos perdues');
    expect(after.status, ReportStatus.validated, reason: 'repassé en brouillon');
    expect(after.updatedAt, before.updatedAt, reason: 'réécrit sans changement');
  });

  testWidgets('modifier un champ : enregistré, photos conservées', (tester) async {
    final before = (await tester.runAsync(() => seed('r-edit')))!;
    await openForm(tester, before.id);
    final client = find.byWidgetPredicate(
        (w) => w is TextFormField && w.controller?.text == 'Client Test');
    expect(client, findsOneWidget);
    await tester.enterText(client, 'Client Modifié');
    await tester.pump(const Duration(seconds: 3)); // auto-enregistrement
    await closeForm(tester);

    final after = (await tester.runAsync(() => LocalDbService().getReport(before.id)))!;
    expect(after.clientName, 'Client Modifié');
    expect(after.photosPaths, before.photosPaths, reason: 'photos perdues');
  });

  testWidgets('nouveau rapport : quitter juste après avoir tapé → brouillon gardé', (tester) async {
    // (2026-10-19) La sauvegarde de sortie n'avait jamais fonctionné (`ref`
    // inutilisable dans dispose) : ce qui était tapé < 2 s avant de quitter
    // était perdu.
    final before = (await tester.runAsync(() => LocalDbService().getAllReports()))!;
    await openForm(tester, null);
    // Section « Client » repliée sur un rapport neuf : on écrit directement dans
    // le champ (mêmes écouteurs qu'une frappe au clavier).
    tester.widget<TextFormField>(find.byType(TextFormField).first).controller!.text =
        'Tapé puis parti';
    await tester.pump(const Duration(milliseconds: 300)); // < 2 s : pas d'auto-save
    await closeForm(tester);

    final after = (await tester.runAsync(() => LocalDbService().getAllReports()))!;
    final added = after.where((r) => !before.any((b) => b.id == r.id)).toList();
    expect(added, hasLength(1));
    expect(added.single.toMap().values.contains('Tapé puis parti'), isTrue);
    expect(added.single.status, ReportStatus.draft);
  });

  // (2026-10-19) Modèles : 2 anciens formats coexistaient et chaque écran n'en
  // lisait qu'un → formulaire VIDE. Les deux doivent remplir le formulaire.
  testWidgets('modèle enregistré depuis le FORMULAIRE (ancien format) → champs remplis',
      (tester) async {
    final preset = ReportPreset(
      id: 'p1', name: 'Entretien chaudière', createdAt: DateTime(2026, 10, 1),
      data: {
        'clientName': 'Résidence Les Tilleuls', 'interventionType': 'Entretien annuel',
        'description': 'Nettoyage du brûleur', 'sector': 'plomberie',
        'sectorFields': {'type_fluide': 'eau'}, 'laborHours': '1,5',
        'startTimeHour': 8, 'startTimeMinute': 30,
      },
    );
    await openForm(tester, null, preset: preset);
    Finder field(String text) => find.byWidgetPredicate(
        (w) => w is TextFormField && w.controller?.text == text);
    expect(field('Résidence Les Tilleuls'), findsOneWidget);
    expect(field('Entretien annuel'), findsOneWidget);
    expect(field('Nettoyage du brûleur'), findsOneWidget);
    expect(field('1.5'), findsOneWidget, reason: 'heures');
    await closeForm(tester);
  });

  testWidgets('modèle enregistré depuis la FICHE du rapport → contenu repris, sans client ni signatures',
      (tester) async {
    final source = ReportModel(
      id: 'src', clientName: 'Cabinet Lefort', description: 'Remplacement du switch',
      date: DateTime(2026, 9, 1), status: ReportStatus.validated,
      signatureClientData: 'AAAA', photosPaths: const ['/x/a.jpg'],
      customFields: const {'Bâtiment': 'B'},
      createdAt: DateTime(2026, 9, 1), updatedAt: DateTime(2026, 9, 1),
    );
    final data = ReportPreset.fromReport(source);
    expect(data.containsKey('signature_client_data'), isFalse);
    expect(data.containsKey('photos'), isFalse);
    expect(data.containsKey('status'), isFalse);
    await openForm(tester, null,
        preset: ReportPreset(id: 'p2', name: 'IT', createdAt: DateTime(2026), data: data));
    // (2026-10-20) Un modèle ne reprend plus le client (annoncé par la fenêtre
    // « Enregistrer comme modèle ») — mais bien le contenu.
    expect(find.byWidgetPredicate(
        (w) => w is TextFormField && w.controller?.text == 'Cabinet Lefort'), findsNothing);
    expect(find.byWidgetPredicate(
        (w) => w is TextFormField && w.controller?.text == 'Remplacement du switch'), findsOneWidget);
    expect(find.byWidgetPredicate(
        (w) => w is TextField && w.controller?.text == 'Bâtiment'), findsOneWidget,
        reason: 'champ libre gardé');
    await closeForm(tester);
  });

  // (2026-10-20) Charger un modèle dans un rapport commencé : le modèle n'a plus
  // d'infos client → le client déjà saisi doit RESTER (avant le correctif, le
  // formulaire remplaçait tous les champs, client compris).
  testWidgets('charger un modèle dans un rapport commencé : le client saisi reste', (tester) async {
    final r = (await tester.runAsync(() => seed('r-preset')))!;
    final old = ReportModel(
      id: 'old', clientName: 'Client du Modèle', clientPhone: '0611',
      interventionType: 'Entretien annuel', description: 'Nettoyage complet',
      date: DateTime(2026, 9, 1), createdAt: DateTime(2026, 9, 1), updatedAt: DateTime(2026, 9, 1),
    );
    // Modèle enregistré AVANT le correctif : il contient encore le client.
    await tester.runAsync(() => LocalDbService().savePreset(ReportPreset(
        id: 'p-old', name: 'Entretien', createdAt: DateTime(2026, 9, 1), data: old.toMap())));
    await openForm(tester, r.id, pro: true);
    await tester.tap(find.byTooltip('cr_load_template'.tr()));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Entretien'));
    await tester.pump(const Duration(milliseconds: 300));
    Finder field(String text) => find.byWidgetPredicate(
        (w) => w is TextFormField && w.controller?.text == text);
    expect(field('Client Test'), findsOneWidget, reason: 'client du rapport gardé');
    expect(field('Client du Modèle'), findsNothing, reason: 'client du modèle ignoré');
    expect(field('Nettoyage complet'), findsOneWidget, reason: 'contenu du modèle chargé');
    await closeForm(tester);
  });

  // (2026-10-20) Sur un vrai téléphone, les boutons de section (Travaux,
  // Signatures…) ne faisaient rien : la liste ne construisait pas les sections
  // lointaines. Corrigé par un cacheExtent large, VÉRIFIÉ SUR ÉMULATEUR (le moteur
  // de test ne reproduit pas ce défilement) ; ce test garde la correction.
  testWidgets('formulaire : toutes les sections sont construites (cacheExtent large)', (tester) async {
    await openForm(tester, null, phone: true);
    final list = tester.widget<ListView>(find.byType(ListView).first);
    expect(list.cacheExtent, greaterThanOrEqualTo(10000));
    await closeForm(tester);
  });

  testWidgets('total de facturation recalculé pendant la saisie', (tester) async {
    await openForm(tester, null);
    TextEditingController ctl(String labelKey) => tester
        .widget<TextField>(find.byWidgetPredicate((w) =>
            w is TextField &&
            (w.decoration?.labelText ?? '').startsWith(labelKey.tr().split('(').first.trim())))
        .controller!;
    ctl('cr_labor_hours').text = '2';
    await tester.pump();
    ctl('cr_hourly_rate').text = '45';
    await tester.pump();
    expect(find.textContaining(RegExp(r'90[,.]00')), findsWidgets, reason: '2 h × 45 = 90');
    ctl('cr_hourly_rate').text = '50';
    await tester.pump();
    expect(find.textContaining(RegExp(r'100[,.]00')), findsWidgets, reason: 'suit la 2e saisie');
    await closeForm(tester);
  });

  testWidgets("rapport créé par l'IA : date, heure et badge IA conservés", (tester) async {
    final before = (await tester.runAsync(() => LocalDbService().getAllReports()))!;
    await openForm(tester, null,
        preset: ReportPreset(id: 'ai', name: 'IA', createdAt: DateTime(2026), data: {
          'client_name': 'Client Dicté',
          'description': 'Fuite réparée',
          'ai_date': DateTime(2026, 10, 12).toIso8601String(),
          'start_time': DateTime(2026, 10, 12, 8, 30).toIso8601String(),
          'ai_enhanced': 1,
        }));
    // Une modification de l'utilisateur → le brouillon est enregistré.
    tester.widget<TextFormField>(find.byWidgetPredicate(
            (w) => w is TextFormField && w.controller?.text == 'Fuite réparée'))
        .controller!
        .text = 'Fuite réparée, joint changé';
    await tester.pump(const Duration(seconds: 3));
    await closeForm(tester);
    final after = (await tester.runAsync(() => LocalDbService().getAllReports()))!;
    final r = after.firstWhere((x) => !before.any((b) => b.id == x.id));
    expect(DateTime(r.date.year, r.date.month, r.date.day), DateTime(2026, 10, 12),
        reason: "date dictée (avant : remplacée par aujourd'hui)");
    expect(r.startTime?.hour, 8);
    expect(r.startTime?.minute, 30);
    expect(r.aiEnhanced, isTrue);
  });
}

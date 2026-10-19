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

  Future<void> openForm(WidgetTester tester, String? id, {ReportPreset? preset}) async {
    // Écran très haut : toutes les sections sont construites (liste paresseuse).
    tester.view.physicalSize = const Size(1200, 24000);
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

  testWidgets('modèle enregistré depuis la FICHE du rapport → champs remplis, sans signatures',
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
    expect(find.byWidgetPredicate(
        (w) => w is TextFormField && w.controller?.text == 'Cabinet Lefort'), findsOneWidget);
    expect(find.byWidgetPredicate(
        (w) => w is TextField && w.controller?.text == 'Bâtiment'), findsOneWidget,
        reason: 'champ libre gardé');
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
}

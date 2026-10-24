import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../features/auth/providers/auth_provider.dart';
import '../../features/reports/models/currency_options.dart';
import '../../features/reports/models/report_model.dart';
import '../../features/reports/models/tax_options.dart';
import '../../features/reports/models/sample_reports.dart';
import '../../features/reports/providers/reports_provider.dart';
import '../../features/settings/providers/settings_provider.dart';
import '../services/local_db_service.dart';
import '../services/photo_storage.dart';

/// (2026-10-24) Données de DÉMO pour les captures d'écran des stores.
///
/// Présent seulement dans un build compilé avec `--dart-define=TR_CAPTURES=true`
/// (la constante est fausse par défaut → bouton absent et code retiré de la
/// version publiée). Bouton : Réglages › 7 appuis sur « Version » › « Démo captures ».
///
/// Crée, dans la langue ACTUELLE de l'app, à partir des rapports d'exemple
/// (noms, villes, devise du pays) :
///  - 4 rapports perso (brouillon, envoyé, validé…) + l'identité solo fictive ;
///  - 3 rapports dans l'équipe (si l'utilisateur en est responsable), signés
///    par des techniciens fictifs, marqués `notified_status` → aucune notification.
/// Relancer après un changement de langue remplace tout (mêmes identifiants).
const bool kCaptureTools = bool.fromEnvironment('TR_CAPTURES');

const _localPrefix = 'capture-local-';
const _teamPrefix = 'capture-team-';

/// Techniciens fictifs de l'équipe, par langue (noms courants).
const _teamTechs = <String, List<String>>{
  'fr': ['Lucas Moreau', 'Emma Petit', 'Hugo Bernard'],
  'en': ['Jack Wilson', 'Emily Turner', 'Oliver Hughes'],
  'de': ['Lukas Becker', 'Anna Fischer', 'Felix Wagner'],
  'es': ['Pablo Ruiz', 'Lucía Martín', 'Diego Torres'],
  'it': ['Luca Ferrari', 'Giulia Russo', 'Matteo Greco'],
  'nl': ['Sem de Boer', 'Emma Visser', 'Lucas Bakker'],
  'pl': ['Jakub Wiśniewski', 'Anna Wójcik', 'Kacper Lewandowski'],
  'pt': ['Tiago Santos', 'Inês Ferreira', 'Rui Oliveira'],
};

/// Adresse fictive de l'entreprise de démo (en-tête des PDF / factures).
const _companyAddress = <String, String>{
  'fr': '8 avenue des Tilleuls, 69007 Lyon',
  'en': '27 Mill Lane, Leeds LS2 7HQ',
  'de': 'Gartenstraße 8, 80333 München',
  'es': 'Calle del Prado 8, 28014 Madrid',
  'it': 'Via Garibaldi 8, 20121 Milano',
  'nl': 'Kerkstraat 8, 3511 LX Utrecht',
  'pl': 'ul. Długa 8, 31-147 Kraków',
  'pt': 'Rua Augusta 8, 1100-053 Lisboa',
};

/// Plan des rapports de démo (testable sans Flutter ni Firebase).
class CaptureDemoItem {
  final SectorTemplate sector;
  final ReportStatus status;
  final int daysAgo;
  final int number;
  final bool signed;
  final bool photos;
  const CaptureDemoItem(this.sector, this.status, this.daysAgo, this.number,
      {this.signed = true, this.photos = true});
}

/// Perso : du plus récent au plus ancien. Le 1er (brouillon, non signé, avec
/// heures + matériel) sert aux captures « formulaire », « signature », « facture ».
const captureLocalPlan = [
  CaptureDemoItem(SectorTemplate.maintenance, ReportStatus.draft, 0, 24,
      signed: false, photos: false),
  CaptureDemoItem(SectorTemplate.plomberie, ReportStatus.submitted, 1, 23),
  CaptureDemoItem(SectorTemplate.incendie, ReportStatus.validated, 2, 22),
  CaptureDemoItem(SectorTemplate.btp, ReportStatus.validated, 4, 21, photos: false),
];

/// Équipe : 2 « envoyés » (boutons Valider / Renvoyer) + 1 validé.
const captureTeamPlan = [
  CaptureDemoItem(SectorTemplate.nettoyage, ReportStatus.submitted, 0, 47),
  CaptureDemoItem(SectorTemplate.transport, ReportStatus.submitted, 0, 46,
      signed: false, photos: false),
  CaptureDemoItem(SectorTemplate.it, ReportStatus.validated, 1, 45),
];

/// Rapport d'exemple [base] décalé de [item.daysAgo] jours, avec le statut,
/// le numéro, les photos et la signature voulus.
ReportModel captureDemoReport(ReportModel base, CaptureDemoItem item,
    {required String id,
    required DateTime now,
    List<String> photos = const [],
    String? technicianId,
    String? technicianName,
    String? companyId}) {
  final shift = Duration(days: item.daysAgo);
  final m = Map<String, dynamic>.of(base.toMap());
  String? back(String k) =>
      m[k] == null ? null : DateTime.parse(m[k] as String).subtract(shift).toIso8601String();
  m['id'] = id;
  m['report_number'] = item.number;
  m['status'] = item.status.name;
  for (final k in ['date', 'end_date', 'start_time', 'end_time']) {
    m[k] = back(k);
  }
  // Ordre de la liste (la plus récente en haut) = numéro le plus grand en haut.
  final stamp = now
      .subtract(shift)
      .subtract(Duration(minutes: 20 + (100 - item.number)))
      .toIso8601String();
  m['created_at'] = stamp;
  m['updated_at'] = stamp;
  m['photos'] = jsonEncode(photos);
  if (!item.signed) {
    m['signature_client_data'] = null;
    m['signature_tech_data'] = null;
  }
  m['technician_id'] = technicianId;
  if (technicianName != null) m['technician_name'] = technicianName;
  m['company_id'] = companyId;
  return ReportModel.fromMap(m);
}

Future<List<String>> _writePhotos(SectorTemplate s) async {
  final dir = Directory(p.join(
      (await getApplicationDocumentsDirectory()).path, PhotoStorage.reportPhotos));
  if (!dir.existsSync()) dir.createSync(recursive: true);
  final out = <String>[];
  for (final i in [1, 2]) {
    final f = File(p.join(dir.path, 'capture_${s.name}_$i.jpg'));
    await f.writeAsBytes(
        (await rootBundle.load('assets/samples/photo_${s.name}_$i.jpg')).buffer.asUint8List());
    out.add(f.path);
  }
  return out;
}

/// Crée (ou remplace) les données de démo dans la langue courante.
/// Renvoie un court compte rendu pour l'écran.
Future<String> seedCaptureDemo(ProviderContainer c, String lang) async {
  final db = LocalDbService();
  final now = DateTime.now();
  await clearCaptureDemo(c, team: false);

  // Identité solo fictive (évite l'avertissement « aucune identité » et nomme
  // l'entreprise sur les PDF / factures).
  final settings = c.read(settingsProvider.notifier);
  await settings.set('company_name', 'ex_company'.tr());
  await settings.set('technician_name', 'ex_technician'.tr());
  await settings.set('company_address', _companyAddress[lang] ?? '');
  // Devise et taxe du pays de la langue (et non de la région de l'émulateur) :
  // adresses anglaises = £ + VAT 20 %, polonaises = zł + VAT 23 %, etc.
  await settings.set('currency_code', defaultCurrencyCode(language: lang));
  final tax = defaultTaxConfig(language: lang);
  await settings.set('tax_rate', tax.rate.toString());
  await settings.set('tax_label', tax.label);
  await settings.set('tax_mention', tax.mention);

  for (final item in captureLocalPlan) {
    final base = await SampleReports.build(item.sector);
    final photos = item.photos ? await _writePhotos(item.sector) : const <String>[];
    await db.insertReport(captureDemoReport(base, item,
        id: '$_localPrefix${item.sector.name}', now: now, photos: photos));
  }
  await c.read(reportsProvider.notifier).refresh();

  var teamCount = 0;
  final team = c.read(teamStateProvider).valueOrNull;
  if (team != null && team.hasTeam && team.isAdmin) {
    final col = FirebaseFirestore.instance
        .collection('companies_raptech1')
        .doc(team.companyId)
        .collection('reports_raptech1');
    final names = _teamTechs[lang] ?? _teamTechs['en']!;
    for (var i = 0; i < captureTeamPlan.length; i++) {
      final item = captureTeamPlan[i];
      final base = await SampleReports.build(item.sector);
      final r = captureDemoReport(base, item,
          id: '$_teamPrefix${item.sector.name}',
          now: now,
          // Nombre de photos seulement (pastille 📷) : chemins fictifs.
          photos: item.photos ? ['photo_1.jpg', 'photo_2.jpg'] : const [],
          technicianId: 'capture-tech-${i + 1}',
          technicianName: names[i % names.length],
          companyId: team.companyId);
      final data = {
        ...r.toMap(),
        'synced_at': FieldValue.serverTimestamp(),
        // Déjà « notifié » → la fonction de notification ne prévient personne.
        'notified_status': r.status.name,
      };
      // Règles en ligne : on ne CRÉE que son propre rapport (brouillon / envoyé) ;
      // le responsable peut ensuite tout modifier → 1) création à son nom,
      // 2) technicien fictif + statut final.
      final ref = col.doc(r.id);
      if (!(await ref.get()).exists) {
        await ref.set({
          ...data,
          'technician_id': FirebaseAuth.instance.currentUser?.uid,
          'status': ReportStatus.submitted.name,
          'notified_status': ReportStatus.submitted.name,
        });
      }
      await ref.set(data);
      teamCount++;
    }
  }
  return 'Démo : ${captureLocalPlan.length} rapports perso, $teamCount équipe ($lang)';
}

/// Retire les données de démo (rapports perso + rapports d'équipe de démo).
Future<void> clearCaptureDemo(ProviderContainer c, {bool team = true}) async {
  final db = LocalDbService();
  for (final r in await db.getAllReports()) {
    if (r.id.startsWith(_localPrefix)) await db.deleteReport(r.id);
  }
  await c.read(reportsProvider.notifier).refresh();
  if (!team) return;
  final t = c.read(teamStateProvider).valueOrNull;
  if (t == null || !t.hasTeam || !t.isAdmin) return;
  final col = FirebaseFirestore.instance
      .collection('companies_raptech1')
      .doc(t.companyId)
      .collection('reports_raptech1');
  for (final item in captureTeamPlan) {
    await col.doc('$_teamPrefix${item.sector.name}').delete();
  }
}

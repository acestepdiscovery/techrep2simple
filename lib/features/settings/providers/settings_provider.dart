import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/services/local_db_service.dart';

final settingsProvider =
    AsyncNotifierProvider<SettingsNotifier, Map<String, String>>(
  SettingsNotifier.new,
);

/// (2026-10-24) Réglages ENREGISTRÉS par `set` mais qui n'étaient jamais
/// RECHARGÉS au démarrage → perdus à chaque redémarrage de l'app (vu en direct :
/// devise GBP → USD après redémarrage ; idem taxe par défaut, mentions de
/// facture, assurance → factures avec le taux du pays au lieu de celui choisi).
/// Ajoutés SEULEMENT s'ils existent : absent = « jamais réglé » → défaut du pays
/// (`invoice_terms` : null = texte par défaut, '' = vidé exprès).
const kOptionalSettingKeys = [
  'currency_code',
  'tax_rate',
  'tax_label',
  'tax_mention',
  'invoice_terms',
  'insurance_info',
];

class SettingsNotifier extends AsyncNotifier<Map<String, String>> {
  @override
  Future<Map<String, String>> build() => loadSettings(LocalDbService(),
      accountName: FirebaseAuth.instance.currentUser?.displayName?.trim() ?? '');

  Future<void> set(String key, String value) async {
    await LocalDbService().setSetting(key, value);
    state = AsyncData({...?state.valueOrNull, key: value});
  }

  String get(String key) => state.valueOrNull?[key] ?? '';
}

/// Tous les réglages de la table `settings` utiles à l'app (testable sans Firebase).
Future<Map<String, String>> loadSettings(LocalDbService db, {String accountName = ''}) async {
    // (prefill) Le nom saisi à l'inscription (displayName du compte) sert de
    // valeur par défaut au « Nom du technicien » — solo ET équipe — tant qu'ils
    // sont VIDES, pour qu'il atterrisse sur les PDF sans double saisie. Persisté
    // → l'utilisateur peut le modifier ensuite. Ne touche PAS aux infos
    // entreprise (le cue « À compléter pour vos PDF » reste affiché).
    var technicianName = await db.getSetting('technician_name') ?? '';
    if (technicianName.isEmpty && accountName.isNotEmpty) {
      technicianName = accountName;
      await db.setSetting('technician_name', accountName);
    }
    var teamTechnicianName = await db.getSetting('team_technician_name') ?? '';
    if (teamTechnicianName.isEmpty && accountName.isNotEmpty) {
      teamTechnicianName = accountName;
      await db.setSetting('team_technician_name', accountName);
    }

    return {
      'company_name': await db.getSetting('company_name') ?? '',
      'technician_name': technicianName,
      // (fix) team_technician_name / team_logo_path étaient ÉCRITS (formulaire
      // d'identité d'équipe) mais jamais RECHARGÉS ici → perdus après un
      // redémarrage. On les charge désormais.
      'team_technician_name': teamTechnicianName,
      'team_logo_path': await db.getSetting('team_logo_path') ?? '',
      'firebase_project_id': await db.getSetting('firebase_project_id') ?? '',
      'logo_path': await db.getSetting('logo_path') ?? '',
      'drive_folder_pattern': await db.getSetting('drive_folder_pattern') ?? '',
      'company_phone': await db.getSetting('company_phone') ?? '',
      'company_email': await db.getSetting('company_email') ?? '',
      'company_address': await db.getSetting('company_address') ?? '',
      'company_siret': await db.getSetting('company_siret') ?? '',
      'company_tva': await db.getSetting('company_tva') ?? '',
      'pdf_template': await db.getSetting('pdf_template') ?? 'professionnel',
      // (1.4) Défaut « Client/Date » (= client/date/numéro) au lieu de {num} seul.
      'report_number_format':
          await db.getSetting('report_number_format') ?? '{client}/{year}/{month}/{day}/{num}',
      'report_number_start': await db.getSetting('report_number_start') ?? '1',
      for (final k in kOptionalSettingKeys)
        if (await db.getSetting(k) case final v?) k: v,
    };
}

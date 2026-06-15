import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/services/local_db_service.dart';

final settingsProvider =
    AsyncNotifierProvider<SettingsNotifier, Map<String, String>>(
  SettingsNotifier.new,
);

class SettingsNotifier extends AsyncNotifier<Map<String, String>> {
  @override
  Future<Map<String, String>> build() async {
    final db = LocalDbService();

    // (prefill) Le nom saisi à l'inscription (displayName du compte) sert de
    // valeur par défaut au « Nom du technicien » — solo ET équipe — tant qu'ils
    // sont VIDES, pour qu'il atterrisse sur les PDF sans double saisie. Persisté
    // → l'utilisateur peut le modifier ensuite. Ne touche PAS aux infos
    // entreprise (le cue « À compléter pour vos PDF » reste affiché).
    final accountName =
        FirebaseAuth.instance.currentUser?.displayName?.trim() ?? '';
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
    };
  }

  Future<void> set(String key, String value) async {
    await LocalDbService().setSetting(key, value);
    state = AsyncData({...?state.valueOrNull, key: value});
  }

  String get(String key) => state.valueOrNull?[key] ?? '';
}

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
    return {
      'company_name': await db.getSetting('company_name') ?? '',
      'technician_name': await db.getSetting('technician_name') ?? '',
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

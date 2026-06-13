import 'package:shared_preferences/shared_preferences.dart';
import 'local_db_service.dart';
import 'google_drive_service.dart';
import 'dropbox_service.dart';
import 'onedrive_service.dart';

/// (4a/4c) Empêche la contamination cross-compte des informations d'entreprise
/// (nom, SIRET, adresse… stockées en base LOCALE et réutilisées sur les PDF)
/// quand un AUTRE utilisateur se connecte sur le même appareil.
///
/// Stratégie : on mémorise le dernier uid connu sur l'appareil. Si l'uid qui se
/// connecte est DIFFÉRENT, on efface l'identité d'entreprise locale du précédent.
/// (L'appartenance équipe est gérée séparément par le garde du teamStateProvider.)
class AccountSwitchGuard {
  static const _keyLastUid = 'device_last_uid';

  /// Champs d'identité entreprise propres à un compte.
  static const _companyKeys = [
    'company_name',
    'company_phone',
    'company_email',
    'company_address',
    'company_siret',
    'company_tva',
    'company_logo',
  ];

  /// À appeler après résolution de l'auth (démarrage de l'app + après login).
  /// Si l'uid courant diffère du dernier uid connu, purge l'identité locale.
  /// Sur déconnexion (uid == null) on ne fait rien : on garde le dernier uid
  /// pour comparer au prochain login (même user → on conserve ses infos).
  static Future<void> ensureCleanFor(String? uid) async {
    if (uid == null) return;
    final prefs = await SharedPreferences.getInstance();
    final last = prefs.getString(_keyLastUid);

    if (last != null && last != uid) {
      final db = LocalDbService();
      for (final k in _companyKeys) {
        await db.setSetting(k, '');
      }
      // (vie privée) Déconnecter les Cloud Drives du compte PRÉCÉDENT : sinon
      // le token OAuth (device-level) reste actif et les PDF du NOUVEAU compte
      // s'enverraient dans le Drive/OneDrive/Dropbox de l'ancien. Le nouvel
      // utilisateur reconnecte ses propres comptes.
      try { await GoogleDriveService.signOut(); } catch (_) {}
      try { await DropboxService.signOut(); } catch (_) {}
      try { await OneDriveService.signOut(); } catch (_) {}
    }

    await prefs.setString(_keyLastUid, uid);
  }
}

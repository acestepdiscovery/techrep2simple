import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import '../../core/config/cf_config.dart';

const _kCfUrl = kCfBaseUrl;

/// (S1 anti-fraude) Journalise côté SERVEUR les changements d'identité
/// d'entreprise (nom / SIRET / adresse), solo ou équipe. Best-effort : ne
/// bloque JAMAIS l'utilisateur. Le serveur écrit dans `identity_audit_raptech1`
/// (collection serveur-only, infalsifiable) — cf. endpoint /log-identity-change.
class IdentityAuditService {
  /// [scope] = 'solo' | 'team'. [changes] = liste de {field, old, new}.
  static Future<void> log({
    required String scope,
    String? companyId,
    required List<Map<String, String>> changes,
  }) async {
    if (changes.isEmpty) return;
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return; // non-connecté → pas de journal serveur
      final token = await user.getIdToken();
      await http
          .post(
            Uri.parse('$_kCfUrl/log-identity-change'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'scope': scope,
              if (companyId != null) 'company_id': companyId,
              'changes': changes,
            }),
          )
          .timeout(const Duration(seconds: 5));
    } catch (_) {
      // fire-and-forget
    }
  }

  /// Helper : un seul champ modifié (ne logue que si réellement changé).
  static Future<void> logField({
    required String scope,
    String? companyId,
    required String field,
    required String oldValue,
    required String newValue,
  }) async {
    if (oldValue.trim() == newValue.trim()) return;
    await log(scope: scope, companyId: companyId, changes: [
      {'field': field, 'old': oldValue, 'new': newValue},
    ]);
  }
}

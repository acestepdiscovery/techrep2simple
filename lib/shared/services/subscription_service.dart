import 'package:easy_localization/easy_localization.dart' show StringTranslateExtension;
import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/config/cf_config.dart';

class SubscriptionService {
  static const _cfUrl = kCfBaseUrl;

  // ── Anti « Pro éternel offline » (dead man's switch) ──────────────────────
  // On mémorise la dernière fois où l'entitlement a été CONFIRMÉ par le SERVEUR
  // (snapshot Firestore frais, pas le cache offline). Si > 31 j sans aucune
  // confirmation (resté offline tout ce temps), on cesse de faire confiance au Pro
  // caché → coupé jusqu'à la prochaine reconnexion. (L'à-vie est exempté ailleurs.)
  static const int entitlementStaleDays = 31;
  static DateTime? _lastConfirmedCache;

  /// À appeler au démarrage de l'app (charge la date persistée).
  static Future<void> loadLastConfirmed() async {
    final prefs = await SharedPreferences.getInstance();
    final ms = prefs.getInt('entitlement_confirmed_at');
    _lastConfirmedCache =
        ms != null ? DateTime.fromMillisecondsSinceEpoch(ms) : null;
  }

  static void _markEntitlementConfirmed() {
    final now = DateTime.now();
    _lastConfirmedCache = now;
    SharedPreferences.getInstance().then(
        (p) => p.setInt('entitlement_confirmed_at', now.millisecondsSinceEpoch));
  }

  /// true si pas confirmé au serveur depuis > 31 j (offline prolongé). null (jamais
  /// confirmé) → false : on ne coupe pas (pas de Pro de toute façon ; le 1er
  /// snapshot frais posera la date).
  static bool get isEntitlementStale {
    final last = _lastConfirmedCache;
    if (last == null) return false;
    return DateTime.now().difference(last).inDays > entitlementStaleDays;
  }

  // ── Firestore stream ──────────────────────────────────────────────────────
  // (snapshot FRAIS du serveur = `metadata.isFromCache == false` → on a joint le
  //  serveur et vu l'état courant → on confirme l'entitlement.)

  static Stream<Map<String, dynamic>?> subscriptionStream(String uid) {
    return FirebaseFirestore.instance
        .collection('users_raptech1')
        .doc(uid)
        .snapshots()
        .map((snap) {
      if (!snap.metadata.isFromCache) _markEntitlementConfirmed();
      return snap.data()?['subscription'] as Map<String, dynamic>?;
    });
  }

  static Stream<Map<String, dynamic>?> companySubscriptionStream(String companyId) {
    return FirebaseFirestore.instance
        .collection('companies_raptech1')
        .doc(companyId)
        .snapshots()
        .map((snap) {
      if (!snap.metadata.isFromCache) _markEntitlementConfirmed();
      return snap.data()?['subscription'] as Map<String, dynamic>?;
    });
  }

  // ── Stripe Cloud Function calls ───────────────────────────────────────────

  static Future<String> createCheckoutSession(
    String plan, {
    int? months,
    int? seats,
    String? companyId,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('settings_not_logged_in'.tr());
    final idToken = await user.getIdToken();

    final body = <String, dynamic>{
      'plan': plan,
      'plan_type': companyId != null ? 'company' : 'individual',
    };
    if (months != null) body['months'] = months;
    if (seats != null) body['seats'] = seats;
    if (companyId != null) body['company_id'] = companyId;

    final response = await http.post(
      Uri.parse('$_cfUrl/create-checkout-session'),
      headers: {
        'Authorization': 'Bearer $idToken',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(body),
    );

    if (response.statusCode != 200) {
      final err =
          (jsonDecode(response.body) as Map<String, dynamic>)['error'] ??
              'common_unknown_error'.tr();
      throw Exception(err);
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return data['stripe_url'] as String;
  }

  static Future<void> modifyTeamSeats(String companyId, int newSeats) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('settings_not_logged_in'.tr());
    final idToken = await user.getIdToken();

    final response = await http.post(
      Uri.parse('$_cfUrl/modify-team-seats'),
      headers: {
        'Authorization': 'Bearer $idToken',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'company_id': companyId, 'new_seats': newSeats}),
    );

    if (response.statusCode != 200) {
      final err =
          (jsonDecode(response.body) as Map<String, dynamic>)['error'] ??
              'common_unknown_error'.tr();
      throw Exception(err);
    }
  }

  /// Manip cachée : code spécial (cadeau OU promo). Retourne (type, message).
  /// type = 'grant' (appliqué immédiatement) | 'promo' (enregistré pour le checkout).
  static Future<(String, String)> redeemCode(String code) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('settings_not_logged_in'.tr());
    final idToken = await user.getIdToken();

    final response = await http.post(
      Uri.parse('$_cfUrl/redeem-code'),
      headers: {
        'Authorization': 'Bearer $idToken',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'code': code.trim().toUpperCase()}),
    );

    Map<String, dynamic> data;
    try {
      data = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      data = const {};
    }
    if (response.statusCode != 200) {
      throw Exception(_redeemErrorText(response.statusCode, data['code'] as String?));
    }
    return (data['type'] as String? ?? 'grant', _redeemSuccessText(data));
  }

  // (2026-10-14) Messages du code spécial dans la LANGUE DE L'APP : la CF répond
  // en français ; elle envoie aussi un `code` stable (erreurs) et `kind` (succès).
  // Ancienne CF sans ces champs → repli sur le statut HTTP / message générique.
  static String _redeemErrorText(int status, String? code) {
    switch (code ?? (status == 429 ? 'too_many' : status == 401 ? 'login' : 'invalid')) {
      case 'expired':
        return 'special_code_err_expired'.tr();
      case 'used_up':
        return 'special_code_err_used_up'.tr();
      case 'already_used':
        return 'special_code_err_already_used'.tr();
      case 'inactive':
        return 'special_code_err_inactive'.tr();
      case 'not_yet_active':
        return 'special_code_err_not_yet_active'.tr();
      case 'team_admin_only':
        return 'special_code_err_team_admin_only'.tr();
      case 'too_many':
        return 'special_code_err_too_many'.tr();
      case 'login':
        return 'settings_not_logged_in'.tr();
      default:
        return 'special_code_invalid'.tr();
    }
  }

  static String _redeemSuccessText(Map<String, dynamic> d) {
    int n(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
    switch (d['kind']) {
      case 'months':
        return 'special_code_gift_months'.plural(n(d['months']));
      case 'lifetime':
        return 'special_code_gift_lifetime'.tr();
      case 'team_seats':
        return 'special_code_gift_seats'.plural(n(d['seats']));
      default:
        return 'special_code_applied'.tr();
    }
  }

  /// [target] : 'personal' ou 'company' pour gérer indépendamment l'un OU
  /// l'autre abonnement quand l'utilisateur a les deux. null = défaut (perso).
  static Future<String> createPortalSession({String? target}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('settings_not_logged_in'.tr());
    final idToken = await user.getIdToken();

    final response = await http.post(
      Uri.parse('$_cfUrl/create-portal-session'),
      headers: {
        'Authorization': 'Bearer $idToken',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(target != null ? {'target': target} : {}),
    );

    if (response.statusCode != 200) {
      final err =
          (jsonDecode(response.body) as Map<String, dynamic>)['error'] ??
              'common_unknown_error'.tr();
      throw Exception(err);
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return data['portal_url'] as String;
  }

  // ── Stripe Checkout — ouvre Chrome/Safari externe (pas Custom Tab)
  //
  // HISTORIQUE : on utilisait flutter_web_auth_2 (FlutterWebAuth2.authenticate)
  // qui ouvre un Chrome Custom Tab sur Android. Le Custom Tab bloque silencieusement
  // toute navigation vers raptech:// (custom scheme) — le bouton sur la page
  // Cloudflare ne faisait rien, aucune erreur. Voir hosting/worker.js pour le
  // détail complet des tentatives.
  //
  // Solution : url_launcher avec LaunchMode.externalApplication ouvre Chrome réel.
  // Chrome passe raptech:// au système d'intents Android → MainActivity reçoit le
  // deep link et l'app revient au premier plan.
  // La fermeture du paywall est gérée par ref.listen(effectiveSubscriptionProvider)
  // dans PaywallBottomSheet — plus besoin d'attendre un retour URL ici.
  static Future<void> openCheckout(String url) async {
    final uri = Uri.parse(url);
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  // ── Generic URL opener (portail Stripe, etc.)
  // Même approche : external browser, pas de callback attendu.
  static Future<void> openUrl(String url) async {
    final uri = Uri.parse(url);
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  // ── PDF export quota (free tier: 5/month) ─────────────────────────────────

  static String _quotaKey() {
    final now = DateTime.now();
    return 'pdf_export_count_${now.year}_${now.month.toString().padLeft(2, '0')}';
  }

  static Future<int> getMonthlyExportCount() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_quotaKey()) ?? 0;
  }

  static Future<void> incrementExportCount() async {
    final prefs = await SharedPreferences.getInstance();
    final key = _quotaKey();
    final count = prefs.getInt(key) ?? 0;
    await prefs.setInt(key, count + 1);
  }

  static const int freeMonthlyExports = 5;

  // ── Compteur d'exports gratuits par COMPTE (Firestore) ────────────────────
  // En plus du compteur DEVICE (SharedPreferences), on tient un compteur par
  // COMPTE dans `quota_raptech1/{uid}`. Règle « DOUBLE NÉGATIVE » : un export
  // gratuit est bloqué si le DEVICE *ou* le COMPTE a atteint la limite. Ainsi :
  //  • même device + nouveau compte → toujours limité (le device se souvient) ;
  //  • même compte + NOUVEAU téléphone → toujours limité (le compte se souvient).
  // Best-effort : si Firestore échoue (offline / règles non posées), on retombe
  // proprement sur le seul compteur device (aucun crash).
  // ⚠️ Nécessite une règle Firestore : `match /quota_raptech1/{uid} { allow
  //    read, write: if request.auth != null && request.auth.uid == uid; }`
  static String _monthKey() {
    final now = DateTime.now();
    return '${now.year}_${now.month.toString().padLeft(2, '0')}';
  }

  /// Compteur du mois côté COMPTE. `null` si indisponible (non connecté / offline
  /// / règles) → l'appelant applique alors le device seul.
  static Future<int?> getAccountMonthlyExportCount() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    try {
      // (2026-10-14) Délai max : hors ligne, l'export ne doit pas attendre.
      final snap = await FirebaseFirestore.instance
          .collection('quota_raptech1')
          .doc(user.uid)
          .get()
          .timeout(const Duration(seconds: 4));
      final v = snap.data()?[_monthKey()];
      return (v as num?)?.toInt() ?? 0;
    } catch (_) {
      return null;
    }
  }

  /// Incrémente le compteur du mois côté COMPTE (best-effort ;
  /// `FieldValue.increment` est mis en file offline et synchronisé au retour réseau).
  static Future<void> incrementAccountExportCount() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      // (2026-10-14) NE PAS attendre : hors ligne, le Future d'une écriture
      // Firestore ne se termine qu'au RETOUR DU RÉSEAU → l'export PDF d'un
      // utilisateur gratuit restait bloqué. L'écriture est mise en file locale
      // et partira toute seule à la reconnexion.
      unawaited(FirebaseFirestore.instance
          .collection('quota_raptech1')
          .doc(user.uid)
          .set({_monthKey(): FieldValue.increment(1)}, SetOptions(merge: true))
          .catchError((_) {}));
    } catch (_) {}
  }
}

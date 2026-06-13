import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import '../../features/referral/models/activation_model.dart';
import '../../core/config/cf_config.dart';

const _kCfUrl = kCfBaseUrl;

/// Referral service — Activation model v8.
/// Spec : REFERRAL_PRICING_PLAN.md § FINAL PICTURE
/// Config A : BASE €3.00, SLOPE = POOL = €0.21, FLOOR €1.50
class ReferralService {
  static final _db = FirebaseFirestore.instance;

  // ── Constantes locales (miroir CF) ────────────────────────────────────────

  static const double kBase  = 3.00;
  static const double kSlope = 0.21;
  static const double kPool  = 0.21;
  static const double kFloor = 1.50;

  // (S6) Récompense « jalon » de parrainage pour une ÉQUIPE.
  /// ⚠️ DOIT rester synchro avec `REWARD_REFERRAL_MILESTONE` dans
  /// `cloud_function/main.py`.
  static const int kRewardMilestone = 100;
  /// Seuil d'apparition du teaser de progression (UI uniquement).
  static const int kRewardTeaserMin = 7;

  /// Prix prévisuel pour le prochain cycle (affichage uniquement — non-authoritative).
  /// [nSeats] = 1 pour solo, N pour équipe.
  /// [activeActivations] = nb d'activations ACTIVE pour cet utilisateur/équipe.
  static double computePreviewPrice(int activeActivations, {int nSeats = 1}) {
    final perSeatDisc = min(kSlope * (nSeats - 1), kFloor);
    final volumeBill  = nSeats * (kBase - perSeatDisc);
    final floorBill   = nSeats * kFloor;
    final bill        = volumeBill - activeActivations * kPool;
    return bill < floorBill ? floorBill : bill;
  }

  /// Nombre d'activations supplémentaires pour atteindre le plancher.
  static int activationsToFloor(int current, {int nSeats = 1}) {
    int n = 0;
    while (computePreviewPrice(current + n, nSeats: nSeats) > nSeats * kFloor + 0.001) {
      n++;
      if (n > 50) break;
    }
    return n;
  }

  // ── Code parrainage ────────────────────────────────────────────────────────

  /// Retourne le code de parrainage de [uid], ou null s'il n'existe pas.
  static Future<String?> getMyCode(String uid) async {
    // Cherche d'abord par champ 'uid', puis par 'owner_uid' (compat ancien système)
    for (final field in ['uid', 'owner_uid']) {
      final snap = await _db
          .collection('referral_codes_raptech1')
          .where(field, isEqualTo: uid)
          .limit(1)
          .get();
      if (snap.docs.isNotEmpty) return snap.docs.first.id;
    }
    return null;
  }

  /// Crée un code parrainage pour [uid] s'il n'en a pas, et le retourne.
  static Future<String> getOrCreateCode(String uid) async {
    final existing = await getMyCode(uid);
    if (existing != null) return existing;

    // (2.4) Le code EST l'ID du document → unicité garantie. On crée dans une
    // TRANSACTION (read+create atomiques) pour fermer toute course (2 users qui
    // tomberaient sur le même code aléatoire au même instant). Espace ≈ 31^6
    // (≈ 887 millions) → collision déjà astronomiquement rare.
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rnd = Random.secure();
    for (var i = 0; i < 10; i++) {
      final code =
          List.generate(6, (_) => chars[rnd.nextInt(chars.length)]).join();
      final ref = _db.collection('referral_codes_raptech1').doc(code);
      final created = await _db.runTransaction<bool>((tx) async {
        final snap = await tx.get(ref);
        if (snap.exists) return false;
        tx.set(ref, {
          'uid': uid,
          'owner_uid': uid,
          'created_at': FieldValue.serverTimestamp(),
        });
        return true;
      });
      if (created) return code;
    }
    throw Exception('Impossible de générer un code unique.');
  }

  // ── Appliquer un code (avant 1ère souscription) ────────────────────────────

  /// Envoie le code au CF pour validation et enregistrement côté serveur.
  /// Retourne le nom de l'inviteur en cas de succès.
  /// Lance une [Exception] avec un message lisible en cas d'erreur.
  static Future<String> applyCode(String code) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('Vous devez être connecté.');
    final token = await user.getIdToken();

    final response = await http.post(
      Uri.parse('$_kCfUrl/apply-referral-code'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'referral_code': code.trim().toUpperCase()}),
    );

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode != 200) {
      throw Exception(body['error'] ?? 'Erreur inconnue.');
    }
    return body['inviter_display_name'] as String? ?? 'votre parrain';
  }

  /// Demande au CF de confirmer les activations matures (à l'ouverture de la page).
  /// Best-effort : ignore les erreurs (l'affichage suit les streams Firestore).
  static Future<void> refreshStatus() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final token = await user.getIdToken();
      await http.post(
        Uri.parse('$_kCfUrl/refresh-referral'),
        headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
        body: '{}',
      );
    } catch (_) {}
  }

  /// (parrainage) Définit où vont les réductions quand on a 2 abos : 'team' ou
  /// 'solo'. Passe par le CF (qui recalcule les coupons).
  static Future<void> setReferralTarget(String target) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('Non connecté');
    final token = await user.getIdToken();
    final res = await http.post(
      Uri.parse('$_kCfUrl/set-referral-target'),
      headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
      body: jsonEncode({'target': target}),
    );
    if (res.statusCode != 200) {
      final err = (jsonDecode(res.body) as Map<String, dynamic>)['error'] ??
          'Erreur inconnue';
      throw Exception(err);
    }
  }

  // ── Streams ───────────────────────────────────────────────────────────────

  /// Stream de toutes les activations où [uid] apparaît (inviteur OU invité).
  /// Combine deux requêtes Firestore (pas de requête OR native).
  static Stream<List<ActivationModel>> streamMyCircle(String uid) {
    late StreamController<List<ActivationModel>> controller;
    List<ActivationModel> asInviter = [];
    List<ActivationModel> asInvitee = [];
    StreamSubscription? sub1, sub2;

    void emit() {
      final seen    = <String>{};
      final merged  = <ActivationModel>[];
      for (final act in [...asInviter, ...asInvitee]) {
        if (seen.add(act.id)) merged.add(act);
      }
      // Tri : ACTIVE d'abord, puis PENDING, puis DORMANT
      merged.sort((a, b) {
        int rank(ActivationStatus s) => switch (s) {
          ActivationStatus.active  => 0,
          ActivationStatus.pending => 1,
          ActivationStatus.dormant => 2,
        };
        return rank(a.status).compareTo(rank(b.status));
      });
      controller.add(merged);
    }

    controller = StreamController<List<ActivationModel>>(
      onListen: () {
        sub1 = _db
            .collection('activations_raptech1')
            .where('inviter_uid', isEqualTo: uid)
            .snapshots()
            .listen((snap) {
          asInviter =
              snap.docs.map((d) => ActivationModel.fromMap(d.id, d.data())).toList();
          emit();
        }, onError: (e) => controller.addError(e));

        sub2 = _db
            .collection('activations_raptech1')
            .where('invitee_uid', isEqualTo: uid)
            .snapshots()
            .listen((snap) {
          asInvitee =
              snap.docs.map((d) => ActivationModel.fromMap(d.id, d.data())).toList();
          emit();
        }, onError: (e) => controller.addError(e));
      },
      onCancel: () {
        sub1?.cancel();
        sub2?.cancel();
      },
    );

    return controller.stream;
  }

  /// Nombre d'activations ACTIVE pour [uid].
  static Stream<int> streamActiveCount(String uid) =>
      streamMyCircle(uid).map((list) => list.where((a) => a.isActive).length);

  /// Nombre de parrainages externes ACTIFS de l'équipe [companyId] (= pool).
  /// Écrit par le CF à chaque recalcul de coupon (`external_referrals_active`).
  static Stream<int> streamTeamPoolCredits(String companyId) =>
      _db
          .collection('companies_raptech1')
          .doc(companyId)
          .snapshots()
          .map((snap) => (snap.data()?['external_referrals_active'] as int?) ?? 0);

  /// (S6) Jalon récompense atteint (100 parrainages actifs) ? Posé par le CF.
  static Stream<bool> streamTeamReward100(String companyId) =>
      _db
          .collection('companies_raptech1')
          .doc(companyId)
          .snapshots()
          .map((snap) => (snap.data()?['reward_100_reached'] as bool?) ?? false);

  // ── Lecture ponctuelle ────────────────────────────────────────────────────

  /// Indique si [uid] a un inviteur gelé (code appliqué + 1er paiement effectué).
  static Future<bool> hasInviter(String uid) async {
    final doc = await _db.collection('users_raptech1').doc(uid).get();
    return (doc.data()?['inviter_uid'] as String?) != null;
  }

  /// Nom de l'inviteur (gelé) lu depuis NOTRE propre document.
  static Future<String?> getInviterName(String uid) async {
    final doc = await _db.collection('users_raptech1').doc(uid).get();
    final data = doc.data();
    if (data == null || data['inviter_uid'] == null) return null;
    return (data['inviter_name'] as String?) ?? 'votre parrain';
  }

  /// Retourne le nom du parrain dont le code est en attente (avant 1er paiement),
  /// ou null si aucun code n'est en attente.
  /// IMPORTANT : on lit le nom dénormalisé sur NOTRE propre doc (`pending_inviter_name`),
  /// car les règles Firestore interdisent de lire le doc d'un autre utilisateur.
  static Future<String?> getPendingInviterName(String uid) async {
    final doc = await _db.collection('users_raptech1').doc(uid).get();
    final data = doc.data();
    if (data == null) return null;
    if (data['pending_inviter_uid'] == null) return null;
    return (data['pending_inviter_name'] as String?) ?? 'votre parrain';
  }
}

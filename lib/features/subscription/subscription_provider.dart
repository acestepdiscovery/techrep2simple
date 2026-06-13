import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../auth/providers/auth_provider.dart';
import '../team/models/team_member_model.dart';
import '../../shared/services/subscription_service.dart';
import '../../shared/services/team_service.dart';

// ── Current member doc stream (for permissions, status) ───────────────────────
final currentMemberProvider = StreamProvider<TeamMemberModel?>((ref) {
  final companyId = ref.watch(teamStateProvider).valueOrNull?.companyId;
  final user = ref.watch(firebaseUserProvider).valueOrNull;
  if (companyId == null || user == null) return Stream.value(null);
  return TeamService().streamCurrentMember(companyId, user.uid);
});

// ── (O) Nb de demandes d'adhésion EN ATTENTE (pour la pastille nav Équipe) ────
// 0 si pas d'équipe ou pas admin (seul l'admin approuve).
final teamPendingCountProvider = StreamProvider<int>((ref) {
  final team = ref.watch(teamStateProvider).valueOrNull;
  final companyId = team?.companyId;
  if (companyId == null || !(team?.isAdmin ?? false)) return Stream.value(0);
  return TeamService()
      .streamMembers(companyId)
      .map((list) => list.where((m) => m.isPending).length);
});

// ── Member active status ───────────────────────────────────────────────────────
// true = solo user, OR team member with status 'active'.
// false = pending approval OR disabled by admin.
final memberActiveProvider = StreamProvider<bool>((ref) {
  final companyId = ref.watch(teamStateProvider).valueOrNull?.companyId;
  final user = ref.watch(firebaseUserProvider).valueOrNull;
  if (companyId == null || user == null) return Stream.value(true);
  return FirebaseFirestore.instance
      .collection('companies_raptech1')
      .doc(companyId)
      .collection('members_raptech1')
      .doc(user.uid)
      .snapshots()
      .map((snap) {
        final data = snap.data();
        if (data == null) return true;
        // Prefer new status field; fall back to legacy active bool
        if (data.containsKey('status')) {
          return data['status'] == 'active';
        }
        return data['active'] as bool? ?? true;
      });
});

// ── Lifetime seats purchased for this company (accumulates, never reset) ──────
// Stored as companies_raptech1/{id}.lifetime_seats, incremented by CF on each purchase.
// Independent from the monthly subscription — both can coexist.
final companyLifetimeSeatsProvider = StreamProvider<int>((ref) {
  final companyId = ref.watch(teamStateProvider).valueOrNull?.companyId;
  if (companyId == null) return Stream.value(0);
  return FirebaseFirestore.instance
      .collection('companies_raptech1')
      .doc(companyId)
      .snapshots()
      .map((snap) => (snap.data()?['lifetime_seats'] as int?) ?? 0);
});

// ── Seat limit for this company (monthly seats + lifetime seats) ───────────────
// null = no active subscription of any kind.
final companySeatLimitProvider = Provider<int?>((ref) {
  final sub = ref.watch(companySubscriptionProvider).valueOrNull;
  final lifetimeSeats = ref.watch(companyLifetimeSeatsProvider).valueOrNull ?? 0;
  final monthlySeats = sub.isActive ? (sub?['seat_limit'] as int? ?? 0) : 0;
  final total = monthlySeats + lifetimeSeats;
  return total > 0 ? total : null;
});

// ── Debug-only override (kDebugMode builds only) ──────────────────────────────
// null = use real Firestore data
// true = force Pro (simulate active subscription)
// false = force Free (simulate no subscription)
final debugSubOverrideProvider = StateProvider<bool?>((ref) => null);

// ── Personal subscription (users_raptech1/{uid}.subscription) ─────────────────
// Null when user not logged in.
final subscriptionProvider = StreamProvider<Map<String, dynamic>?>((ref) {
  final user = ref.watch(firebaseUserProvider).valueOrNull;
  // Stream.value(null) emits immediately so isLoading resolves to false.
  // Stream.empty() would leave AsyncValue stuck in loading state forever.
  if (user == null) return Stream.value(null);
  return SubscriptionService.subscriptionStream(user.uid);
});

// ── Company subscription (companies_raptech1/{companyId}.subscription) ─────────
// Null when user not in a team.
final companySubscriptionProvider = StreamProvider<Map<String, dynamic>?>((ref) {
  final companyId = ref.watch(teamStateProvider).valueOrNull?.companyId;
  // Same reason: Stream.value(null) resolves immediately; Stream.empty() would
  // keep isLoading = true forever for solo users (no team → no companyId).
  if (companyId == null) return Stream.value(null);
  return SubscriptionService.companySubscriptionStream(companyId);
});

// ── Combined: true if personal sub active OR (any company sub active AND seat active) ─
final effectiveSubscriptionProvider = Provider<bool>((ref) {
  if (kDebugMode) {
    final override = ref.watch(debugSubOverrideProvider);
    if (override != null) return override;
  }
  final userSub = ref.watch(subscriptionProvider).valueOrNull;
  final companySub = ref.watch(companySubscriptionProvider).valueOrNull;
  final lifetimeSeats = ref.watch(companyLifetimeSeatsProvider).valueOrNull ?? 0;

  // Pro actif ? (perso, OU équipe active + siège du membre non désactivé)
  bool pro;
  if (userSub.isActive) {
    pro = true;
  } else {
    final companyActive = companySub.isActive || lifetimeSeats > 0;
    final memberActive = ref.watch(memberActiveProvider).valueOrNull ?? true;
    pro = companyActive && memberActive;
  }
  if (!pro) return false;

  // (dead man's switch) Un abo NON à-vie jamais confirmé au SERVEUR depuis > 31 j
  // (device resté offline tout ce temps) → on cesse de faire confiance au Pro caché
  // jusqu'à la prochaine reconnexion. L'à-vie est possédé pour toujours → jamais coupé.
  final lifetime =
      userSub.isLifetime || companySub.isLifetime || lifetimeSeats > 0;
  if (!lifetime && SubscriptionService.isEntitlementStale) return false;

  return true;
});

// ── Extension helpers on a raw subscription map ────────────────────────────

extension SubscriptionX on Map<String, dynamic>? {
  bool get isActive {
    final sub = this;
    if (sub == null) return false;
    final status = sub['status'] as String?;
    if (status == 'lifetime') return true;
    if (status == 'active') {
      final plan = sub['plan'] as String?;
      if (plan == 'custom_months') {
        final end = sub['current_period_end'];
        DateTime? endDate;
        if (end is Timestamp) endDate = end.toDate();
        return endDate != null && endDate.isAfter(DateTime.now());
      }
      // (garde-fou) Abos réguliers (mensuel/annuel/équipe) : EN PLUS de la coupure
      // RTDN (status→canceled), expiration PASSIVE si la date est dépassée — ferme
      // le point de défaillance unique (RTDN ratée → Pro éternel). Grâce de 3 j pour
      // couvrir un renouvellement dont la notif aurait tardé (le restore au démarrage
      // rafraîchit la date à chaque ouverture). Pas de date → on fait confiance au status.
      final end = sub['current_period_end'];
      if (end is Timestamp) {
        return end.toDate().add(const Duration(days: 3)).isAfter(DateTime.now());
      }
      return true;
    }
    return false;
  }

  bool get isLifetime {
    final plan = this?['plan'] as String?;
    return plan == 'lifetime' || plan == 'team_lifetime';
  }

  bool get isRecurring {
    final plan = this?['plan'] as String?;
    // 'team_monthly' = abonnement équipe mensuel (récurrent, gérable).
    return plan == 'monthly' || plan == 'annual' || plan == 'team_monthly';
  }

  String get planLabel {
    final sub = this;
    if (sub == null) return 'Gratuit';
    final plan = sub['plan'] as String?;
    final status = sub['status'] as String?;
    if (status == null || status == 'canceled') return 'Gratuit';
    switch (plan) {
      case 'monthly':
        return 'Mensuel';
      case 'team_monthly':
        return 'Mensuel (équipe)';
      case 'annual':
        return 'Annuel';
      case 'lifetime':
        return 'À vie';
      case 'team_lifetime':
        return 'À vie (équipe)';
      case 'custom_months':
        final months = sub['months_count'];
        return months != null ? '$months mois' : 'Multi-mois';
      default:
        return 'Actif';
    }
  }

  DateTime? get periodEnd {
    final end = this?['current_period_end'];
    if (end is Timestamp) return end.toDate();
    return null;
  }
}

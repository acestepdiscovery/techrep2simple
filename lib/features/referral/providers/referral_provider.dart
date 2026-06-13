import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../auth/providers/auth_provider.dart';
import '../../subscription/subscription_provider.dart';
import '../models/activation_model.dart';
import '../../../shared/services/referral_service.dart';

// ── Parrainage : cible des réductions quand on a 2 abos (solo + équipe) ──────

/// L'utilisateur a-t-il les DEUX abonnements Pro (solo + équipe) ? → seul cas où
/// le choix de cible a du sens (sinon la réduction va sur l'unique compte Pro).
final hasBothProSubsProvider = Provider<bool>((ref) {
  final personalPro = ref.watch(subscriptionProvider).valueOrNull.isActive;
  final companyPro = ref.watch(companySubscriptionProvider).valueOrNull.isActive;
  return personalPro && companyPro;
});

/// Cible actuelle des parrainages ('team' par défaut | 'solo').
final referralTargetProvider = StreamProvider<String>((ref) {
  final user = ref.watch(firebaseUserProvider).valueOrNull;
  if (user == null) return Stream.value('team');
  return FirebaseFirestore.instance
      .collection('users_raptech1')
      .doc(user.uid)
      .snapshots()
      .map((d) =>
          (d.data()?['referral_benefit_target'] as String?) == 'solo'
              ? 'solo'
              : 'team');
});

// ── Mon cercle (activations) ──────────────────────────────────────────────────

final myCircleProvider = StreamProvider<List<ActivationModel>>((ref) {
  final user = ref.watch(firebaseUserProvider).valueOrNull;
  if (user == null) return Stream.value([]);
  return ReferralService.streamMyCircle(user.uid);
});

// ── Nombre d'activations ACTIVE ───────────────────────────────────────────────

final activeActivationsCountProvider = Provider<int>((ref) {
  final circle = ref.watch(myCircleProvider).valueOrNull ?? [];
  return circle.where((a) => a.isActive).length;
});

// ── Crédits pool équipe (admin) ───────────────────────────────────────────────

final teamPoolCreditsProvider = StreamProvider<int>((ref) {
  final companyId = ref.watch(teamStateProvider).valueOrNull?.companyId;
  if (companyId == null) return Stream.value(0);
  return ReferralService.streamTeamPoolCredits(companyId);
});

// (S6) Jalon récompense 100 parrainages atteint (posé par le CF).
final teamReward100Provider = StreamProvider<bool>((ref) {
  final companyId = ref.watch(teamStateProvider).valueOrNull?.companyId;
  if (companyId == null) return Stream.value(false);
  return ReferralService.streamTeamReward100(companyId);
});

// ── Prix prévisuel prochain mois (solo) ───────────────────────────────────────

final nextPricePreviewProvider = Provider<double>((ref) {
  final activeCount = ref.watch(activeActivationsCountProvider);
  return ReferralService.computePreviewPrice(activeCount);
});

// ── Prix prévisuel équipe ─────────────────────────────────────────────────────

final teamNextPricePreviewProvider = Provider<double>((ref) {
  final poolCredits = ref.watch(teamPoolCreditsProvider).valueOrNull ?? 0;
  final nSeats      = ref.watch(companySeatLimitProvider) ?? 1;
  return ReferralService.computePreviewPrice(poolCredits, nSeats: nSeats);
});

// ── Activations restantes avant le plancher (solo) ───────────────────────────

final activationsToFloorProvider = Provider<int>((ref) {
  final active = ref.watch(activeActivationsCountProvider);
  return ReferralService.activationsToFloor(active);
});

// ── Mon code parrainage ───────────────────────────────────────────────────────

final myReferralCodeProvider = FutureProvider<String?>((ref) async {
  final user = ref.watch(firebaseUserProvider).valueOrNull;
  if (user == null) return null;
  return ReferralService.getOrCreateCode(user.uid);
});

// Abonnement, quota gratuit et sièges d'équipe (2026-10-19) : la logique qui
// décide « Pro ou pas », « cet export est-il permis », « combien de sièges ».
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reportnew1cld/features/subscription/subscription_provider.dart';
import 'package:reportnew1cld/shared/services/subscription_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

Timestamp _in(Duration d) => Timestamp.fromDate(DateTime.now().add(d));

/// Conteneur Riverpod avec les 4 sources de données simulées (pas de Firebase).
Future<ProviderContainer> _container({
  Map<String, dynamic>? personal,
  Map<String, dynamic>? company,
  int lifetimeSeats = 0,
  bool memberActive = true,
}) async {
  final c = ProviderContainer(overrides: [
    subscriptionProvider.overrideWith((ref) => Stream.value(personal)),
    companySubscriptionProvider.overrideWith((ref) => Stream.value(company)),
    companyLifetimeSeatsProvider.overrideWith((ref) => Stream.value(lifetimeSeats)),
    memberActiveProvider.overrideWith((ref) => Stream.value(memberActive)),
  ]);
  // Laisse les flux émettre leur première valeur.
  await c.read(subscriptionProvider.future);
  await c.read(companySubscriptionProvider.future);
  await c.read(companyLifetimeSeatsProvider.future);
  await c.read(memberActiveProvider.future);
  return c;
}

void main() {
  group('isActive (état d\'un abonnement)', () {
    test('aucun abonnement / annulé → inactif', () {
      expect((null as Map<String, dynamic>?).isActive, isFalse);
      expect(<String, dynamic>{'status': 'canceled', 'plan': 'monthly'}.isActive, isFalse);
    });
    test('à vie → actif', () {
      expect(<String, dynamic>{'status': 'lifetime', 'plan': 'lifetime'}.isActive, isTrue);
    });
    test('mensuel : actif tant que la date + 3 jours de grâce n\'est pas passée', () {
      Map<String, dynamic> m(Duration d) =>
          {'status': 'active', 'plan': 'monthly', 'current_period_end': _in(d)};
      expect(m(const Duration(days: 10)).isActive, isTrue);
      expect(m(const Duration(days: -2)).isActive, isTrue, reason: 'grâce de 3 j');
      expect(m(const Duration(days: -4)).isActive, isFalse, reason: 'notification ratée');
      expect(<String, dynamic>{'status': 'active', 'plan': 'monthly'}.isActive, isTrue,
          reason: 'pas de date → on fait confiance au statut');
    });
    test('code cadeau N mois : actif seulement jusqu\'à la date, sans grâce', () {
      expect(<String, dynamic>{'status': 'active', 'plan': 'custom_months',
        'current_period_end': _in(const Duration(days: 1))}.isActive, isTrue);
      expect(<String, dynamic>{'status': 'active', 'plan': 'custom_months',
        'current_period_end': _in(const Duration(days: -1))}.isActive, isFalse);
      expect(<String, dynamic>{'status': 'active', 'plan': 'custom_months'}.isActive, isFalse);
    });
    test('à vie / récurrent', () {
      expect(<String, dynamic>{'plan': 'team_lifetime'}.isLifetime, isTrue);
      expect(<String, dynamic>{'plan': 'team_monthly'}.isRecurring, isTrue);
      expect(<String, dynamic>{'plan': 'lifetime'}.isRecurring, isFalse);
    });
  });

  group('export PDF : qui couvre ce rapport ?', () {
    final active = <String, dynamic>{'status': 'active', 'plan': 'monthly'};
    test('rapport perso : abonnement solo → illimité, sinon exports gratuits', () {
      expect(exportCoverage(isTeamReport: false, companySub: null, lifetimeSeats: 0,
          memberActive: true, personalSub: active), ExportCoverage.covered);
      expect(exportCoverage(isTeamReport: false, companySub: active, lifetimeSeats: 3,
          memberActive: true, personalSub: null), ExportCoverage.freeQuota,
          reason: "l'abonnement d'équipe ne couvre pas un rapport perso");
    });
    test('rapport d\'équipe : abonnement équipe + siège actif seulement', () {
      expect(exportCoverage(isTeamReport: true, companySub: active, lifetimeSeats: 0,
          memberActive: true, personalSub: null), ExportCoverage.covered);
      expect(exportCoverage(isTeamReport: true, companySub: null, lifetimeSeats: 2,
          memberActive: true, personalSub: null), ExportCoverage.covered,
          reason: 'sièges à vie');
      expect(exportCoverage(isTeamReport: true, companySub: active, lifetimeSeats: 0,
          memberActive: false, personalSub: null), ExportCoverage.seatInactive,
          reason: 'membre désactivé');
      expect(exportCoverage(isTeamReport: true, companySub: null, lifetimeSeats: 0,
          memberActive: true, personalSub: active), ExportCoverage.seatInactive,
          reason: "l'abonnement solo ne couvre pas un rapport d'équipe (anti-fraude)");
    });
    test('quota gratuit : appareil OU compte à la limite', () {
      final l = SubscriptionService.freeMonthlyExports;
      expect(freeQuotaReached(l - 1, null), isFalse);
      expect(freeQuotaReached(l, null), isTrue);
      expect(freeQuotaReached(0, l), isTrue, reason: 'nouveau téléphone, même compte');
      expect(freeQuotaReached(l - 1, l - 1), isFalse);
    });
  });

  group('compteur d\'exports de l\'appareil', () {
    test('compte par mois et repart de 0', () async {
      SharedPreferences.setMockInitialValues({});
      expect(await SubscriptionService.getMonthlyExportCount(), 0);
      await SubscriptionService.incrementExportCount();
      await SubscriptionService.incrementExportCount();
      expect(await SubscriptionService.getMonthlyExportCount(), 2);
      // Le mois précédent ne compte pas.
      final now = DateTime.now();
      final prev = DateTime(now.year, now.month - 1);
      SharedPreferences.setMockInitialValues({
        'pdf_export_count_${prev.year}_${prev.month.toString().padLeft(2, '0')}': 5,
      });
      expect(await SubscriptionService.getMonthlyExportCount(), 0);
    });
  });

  group('Pro effectif et sièges (providers)', () {
    final active = <String, dynamic>{'status': 'active', 'plan': 'team_monthly', 'seat_limit': 5};
    test('solo actif → Pro', () async {
      final c = await _container(personal: {'status': 'active', 'plan': 'monthly'});
      expect(c.read(effectiveSubscriptionProvider), isTrue);
    });
    test('équipe active + siège actif → Pro ; siège désactivé → pas Pro', () async {
      expect((await _container(company: active)).read(effectiveSubscriptionProvider), isTrue);
      expect((await _container(company: active, memberActive: false))
          .read(effectiveSubscriptionProvider), isFalse);
    });
    test('rien → pas Pro', () async {
      expect((await _container()).read(effectiveSubscriptionProvider), isFalse);
    });
    test('sièges = mensuels (si actif) + à vie ; aucun → null', () async {
      expect((await _container(company: active, lifetimeSeats: 2))
          .read(companySeatLimitProvider), 7);
      expect((await _container(company: {'status': 'canceled', 'seat_limit': 5}))
          .read(companySeatLimitProvider), isNull);
      expect((await _container(lifetimeSeats: 3)).read(companySeatLimitProvider), 3);
    });
    test('nombre de sièges écrit « 5.0 » → 5 (plantait la page Équipe)', () async {
      final c = await _container(
          company: {'status': 'active', 'plan': 'team_monthly', 'seat_limit': 5.0});
      expect(c.read(companySeatLimitProvider), 5);
    });
  });

  group('coupure « Pro hors ligne depuis > 31 jours »', () {
    test('confirmé il y a 40 jours → périmé ; il y a 10 jours → OK', () async {
      final old = DateTime.now().subtract(const Duration(days: 40));
      SharedPreferences.setMockInitialValues(
          {'entitlement_confirmed_at': old.millisecondsSinceEpoch});
      await SubscriptionService.loadLastConfirmed();
      expect(SubscriptionService.isEntitlementStale, isTrue);
      final recent = DateTime.now().subtract(const Duration(days: 10));
      SharedPreferences.setMockInitialValues(
          {'entitlement_confirmed_at': recent.millisecondsSinceEpoch});
      await SubscriptionService.loadLastConfirmed();
      expect(SubscriptionService.isEntitlementStale, isFalse);
    });
  });
}

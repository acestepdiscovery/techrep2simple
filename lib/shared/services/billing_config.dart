// Billing configuration — IAP-only model (2026-06-08 simple pivot).
//
// Single source of truth for the In-App Purchase catalogue. No dynamic pricing,
// no referral: prices are FIXED store products. Team uses "up to N" brackets
// (IAP can't do per-seat dynamic pricing), the degressive feel is baked into the
// bracket prices.
//
// [PAUSED-STRIPE]   The Stripe checkout/portal flow is commented out app-wide.
// [PAUSED-REFERRAL] The referral/points system is commented out app-wide.
// Flip kBillingChannel back to stripe (and uncomment the paused code) to revive it.

enum BillingChannel { iap, stripe }

/// The app bills through the stores. Keep IAP unless reviving the paused Stripe flow.
const BillingChannel kBillingChannel = BillingChannel.iap;

/// A purchasable store product.
class IapProduct {
  /// Store product identifier (must match App Store Connect + Google Play Console).
  final String id;
  final String label;
  final String subtitle;

  /// false = solo (1 seat) ; true = team bracket.
  final bool isTeam;

  /// true  = non-consumable / one-time (lifetime).
  /// false = auto-renewable subscription (monthly / annual).
  final bool isLifetime;

  /// Solo = 1. Team = the MAX number of seats this bracket covers.
  final int seats;

  /// Shown while the real localized store price is loading (or in dev).
  final String fallbackPrice;

  const IapProduct({
    required this.id,
    required this.label,
    required this.subtitle,
    required this.fallbackPrice,
    this.isTeam = false,
    this.isLifetime = false,
    this.seats = 1,
  });
}

// ── Solo products ───────────────────────────────────────────────────────────
const IapProduct kProMonthly = IapProduct(
  id: 'pro_monthly',
  label: 'Mensuel',
  subtitle: 'Résiliable à tout moment',
  fallbackPrice: '2,99 €/mois',
);

const IapProduct kProAnnual = IapProduct(
  id: 'pro_annual',
  label: 'Annuel',
  subtitle: 'Le plus avantageux — économisez ~30 %',
  fallbackPrice: '24,99 €/an',
);

const IapProduct kProLifetime = IapProduct(
  id: 'pro_lifetime',
  label: 'À vie',
  subtitle: 'Accès permanent — payez une fois',
  fallbackPrice: '149,99 €',
  isLifetime: true,
);

const List<IapProduct> kSoloProducts = [kProMonthly, kProAnnual, kProLifetime];

// ── Team products (fixed "up to N" brackets, degressive per seat) ────────────
const List<IapProduct> kTeamProducts = [
  IapProduct(
    id: 'team_upto_2',
    label: 'Jusqu\'à 2 membres',
    subtitle: '3,00 €/siège',
    fallbackPrice: '5,99 €/mois',
    isTeam: true,
    seats: 2,
  ),
  IapProduct(
    id: 'team_upto_5',
    label: 'Jusqu\'à 5 membres',
    subtitle: '2,40 €/siège',
    fallbackPrice: '11,99 €/mois',
    isTeam: true,
    seats: 5,
  ),
  IapProduct(
    id: 'team_upto_10',
    label: 'Jusqu\'à 10 membres',
    subtitle: '2,00 €/siège',
    fallbackPrice: '19,99 €/mois',
    isTeam: true,
    seats: 10,
  ),
  IapProduct(
    id: 'team_upto_20',
    label: 'Jusqu\'à 20 membres',
    subtitle: '1,50 €/siège',
    fallbackPrice: '29,99 €/mois',
    isTeam: true,
    seats: 20,
  ),
];

const List<IapProduct> kAllProducts = [...kSoloProducts, ...kTeamProducts];

/// All store identifiers to query in one shot.
Set<String> get kAllProductIds => kAllProducts.map((p) => p.id).toSet();

/// Lookup by store id (null if unknown).
IapProduct? productById(String id) {
  for (final p in kAllProducts) {
    if (p.id == id) return p;
  }
  return null;
}

/// Smallest team bracket that covers [memberCount] (falls back to the largest).
IapProduct bracketForSeats(int memberCount) {
  for (final p in kTeamProducts) {
    if (memberCount <= p.seats) return p;
  }
  return kTeamProducts.last;
}

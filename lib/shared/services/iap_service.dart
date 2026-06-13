// In-App Purchase service — IAP-only billing (2026-06-08 simple pivot).
//
// Flow:
//   buy()  →  store native sheet  →  purchaseStream emits  →  verify on our CF
//          →  CF validates the receipt (Apple/Google) and writes `subscription`
//          →  effectiveSubscriptionProvider (Firestore stream) flips to Pro
//          →  the paywall closes itself (it already listens to that provider).
//
// We keep the SAME Cloud Function as Stripe (it just gains an /iap/verify-purchase
// endpoint). Entitlement detection stays Firestore-based and source-agnostic.

import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart'
    show ReplacementMode;

import 'billing_config.dart';
import '../../core/config/cf_config.dart';

class IapService {
  IapService._();
  static final IapService instance = IapService._();

  static const _cfUrl = kCfBaseUrl;

  final InAppPurchase _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _sub;

  /// true while a purchase is in flight (UI spinner).
  final ValueNotifier<bool> busy = ValueNotifier(false);

  /// last user-facing error (null when none). Cleared on a new buy().
  final ValueNotifier<String?> lastError = ValueNotifier(null);

  /// Incrémenté après qu'un achat FRAIS a été validé (200). Permet au paywall de
  /// confirmer + se fermer MÊME si l'utilisateur était DÉJÀ Pro (cas où
  /// effectiveSubscription ne "transitionne" pas false→true). Agnostique solo/équipe.
  final ValueNotifier<int> purchaseSuccess = ValueNotifier(0);

  /// Cache of loaded store products (id → details).
  final Map<String, ProductDetails> _products = {};

  /// companyId to attach when verifying a team purchase (keyed by product id).
  final Map<String, String> _pendingCompanyByProduct = {};

  /// Active (non-lifetime) subscriptions seen this session, by product id.
  /// Used to REPLACE an existing team bracket instead of stacking a 2nd sub (#1).
  final Map<String, PurchaseDetails> _activeSubs = {};

  bool _initialized = false;

  /// Call once at app startup (after Firebase init).
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    _sub = _iap.purchaseStream.listen(
      _onPurchaseUpdated,
      onError: (e) => debugPrint('[IAP] purchaseStream error: $e'),
    );
    // Best-effort restore at startup: re-delivers active purchases →
    //   (a) populates _activeSubs (needed to upgrade/downgrade team brackets, #1),
    //   (b) auto-recovers a purchase whose validation failed transiently (#3).
    // Idempotent server-side. (Could be throttled later to spare CF calls.)
    try {
      await _iap.restorePurchases();
    } catch (_) {}
  }

  void dispose() {
    _sub?.cancel();
  }

  /// Loads localized store products. Returns id → ProductDetails (may be partial
  /// in dev / when products aren't configured yet).
  Future<Map<String, ProductDetails>> loadProducts() async {
    final available = await _iap.isAvailable();
    if (!available) {
      debugPrint('[IAP] store not available');
      return _products;
    }
    final resp = await _iap.queryProductDetails(kAllProductIds);
    if (resp.error != null) {
      debugPrint('[IAP] queryProductDetails error: ${resp.error}');
    }
    if (resp.notFoundIDs.isNotEmpty) {
      debugPrint('[IAP] not found IDs: ${resp.notFoundIDs}');
    }
    for (final pd in resp.productDetails) {
      _products[pd.id] = pd;
    }
    return _products;
  }

  /// Localized store price for [productId], or the config fallback.
  String priceLabel(String productId) {
    final pd = _products[productId];
    if (pd != null) return pd.price;
    return productById(productId)?.fallbackPrice ?? '';
  }

  /// Starts a purchase. [companyId] is required for team brackets.
  /// Returns false immediately if it can't start (not logged in / no product).
  Future<bool> buy(IapProduct product, {String? companyId}) async {
    lastError.value = null;
    if (FirebaseAuth.instance.currentUser == null) {
      lastError.value = 'Connectez-vous pour vous abonner.';
      return false;
    }
    if (product.isTeam && (companyId == null || companyId.isEmpty)) {
      lastError.value = 'Aucune équipe sélectionnée.';
      return false;
    }

    // Make sure products are loaded.
    if (_products.isEmpty) await loadProducts();
    final pd = _products[product.id];
    if (pd == null) {
      lastError.value =
          'Produit indisponible (${product.id}). Réessayez plus tard.';
      return false;
    }

    if (companyId != null) _pendingCompanyByProduct[product.id] = companyId;

    final param = _buildPurchaseParam(product, pd);
    busy.value = true;
    try {
      // Both subscriptions and non-consumables go through buyNonConsumable
      // in the in_app_purchase unified API.
      final started = await _iap.buyNonConsumable(purchaseParam: param);
      if (!started) {
        busy.value = false;
        lastError.value = 'Achat non démarré. Réessayez.';
      }
      return started;
    } catch (e) {
      busy.value = false;
      lastError.value = e.toString();
      return false;
    }
  }

  /// Builds the purchase param. For a TEAM bracket change on Android, REPLACES the
  /// existing team subscription (the store prorates) instead of stacking a second
  /// one. iOS crossgrade is handled natively within one subscription group. (#1)
  PurchaseParam _buildPurchaseParam(IapProduct product, ProductDetails pd) {
    // Remplacement d'abonnement (Android) : si on achète un ABO (pas l'à-vie) et
    // qu'il existe déjà un abo actif de la MÊME catégorie (solo↔solo ou équipe↔équipe),
    // on le REMPLACE au lieu d'en empiler un 2e → évite la double facturation
    // (ex. mensuel→annuel en solo, ou changement de palier en équipe).
    if (Platform.isAndroid && !product.isLifetime) {
      PurchaseDetails? old;
      for (final e in _activeSubs.values) {
        final ep = productById(e.productID);
        if (ep != null &&
            !ep.isLifetime &&
            ep.isTeam == product.isTeam &&
            e.productID != product.id) {
          old = e;
          break;
        }
      }
      if (old is GooglePlayPurchaseDetails) {
        final ReplacementMode mode;
        if (product.isTeam) {
          final oldSeats = productById(old.productID)?.seats ?? 0;
          // Upgrade palier → immédiat + prorata facturé ; downgrade → différé.
          mode = oldSeats < product.seats
              ? ReplacementMode.chargeProratedPrice
              : ReplacementMode.deferred;
        } else {
          // Solo (mensuel↔annuel) : bascule immédiate, temps restant proraté.
          mode = ReplacementMode.withTimeProration;
        }
        return GooglePlayPurchaseParam(
          productDetails: pd,
          changeSubscriptionParam: ChangeSubscriptionParam(
            oldPurchaseDetails: old,
            replacementMode: mode,
          ),
        );
      }
    }
    return PurchaseParam(productDetails: pd);
  }

  /// Restores previous purchases (mandatory "Restaurer mes achats" button).
  Future<void> restore() async {
    lastError.value = null;
    try {
      await _iap.restorePurchases();
    } catch (e) {
      lastError.value = e.toString();
    }
  }

  // ── Purchase stream handling ───────────────────────────────────────────────
  Future<void> _onPurchaseUpdated(List<PurchaseDetails> purchases) async {
    for (final p in purchases) {
      switch (p.status) {
        case PurchaseStatus.pending:
          busy.value = true;
          break;
        case PurchaseStatus.error:
          busy.value = false;
          lastError.value = p.error?.message ?? 'Erreur d\'achat.';
          if (p.pendingCompletePurchase) await _iap.completePurchase(p);
          break;
        case PurchaseStatus.canceled:
          busy.value = false;
          if (p.pendingCompletePurchase) await _iap.completePurchase(p);
          break;
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          final prod = productById(p.productID);
          if (prod == null) {
            // Produit INCONNU / vide (ex. ancien achat test d'un produit retiré, ou
            // event sans productID) → on NE valide PAS (évite un 400 CF + le message
            // rouge « validation en cours »). On finit juste la transaction pour que
            // le store arrête de la re-livrer.
            if (p.pendingCompletePurchase) await _iap.completePurchase(p);
            busy.value = false;
            break;
          }
          // Cache active subscriptions (not the lifetime non-consumable) so a
          // later bracket/plan change can REPLACE instead of stacking (#1).
          if (!prod.isLifetime) _activeSubs[p.productID] = p;
          await _verify(p);
          // Always finish the transaction so the store stops re-delivering it.
          if (p.pendingCompletePurchase) await _iap.completePurchase(p);
          busy.value = false;
          break;
      }
    }
  }

  /// Sends the receipt to our Cloud Function for server-side validation.
  /// The CF validates with Apple/Google and writes the entitlement.
  Future<void> _verify(PurchaseDetails p) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    // Only surface errors for a FRESH purchase; silent/startup restores recover
    // quietly (Pro appears if it works; no error spam otherwise).
    final showErrors = p.status == PurchaseStatus.purchased;
    final companyId = _pendingCompanyByProduct.remove(p.productID);
    try {
      final idToken = await user.getIdToken();
      final body = <String, dynamic>{
        'product_id': p.productID,
        'store': p.verificationData.source, // 'app_store' | 'google_play'
        'purchase_id': p.purchaseID ?? '',
        'status': p.status.name,
        'server_verification_data': p.verificationData.serverVerificationData,
        'local_verification_data': p.verificationData.localVerificationData,
        'verification_source': p.verificationData.source,
        if (companyId != null) 'company_id': companyId,
      };
      final resp = await http.post(
        Uri.parse('$_cfUrl/iap/verify-purchase'),
        headers: {
          'Authorization': 'Bearer $idToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(body),
      );
      if (resp.statusCode != 200) {
        debugPrint('[IAP] verify failed ${resp.statusCode}: ${resp.body}');
        // 424 = receipt stored, validation pending (no live entitlement yet).
        if (resp.statusCode != 424 && showErrors) {
          lastError.value =
              'Validation de l\'achat en cours. Si l\'accès ne s\'active pas, '
              'utilisez « Restaurer mes achats ».';
        }
      } else if (showErrors) {
        // Achat FRAIS validé (200) → signale le succès pour que le paywall se ferme
        // + confirme, MÊME si l'utilisateur était déjà Pro (pas de transition
        // d'effectiveSubscription dans ce cas). (showErrors = vrai achat, pas restore.)
        purchaseSuccess.value++;
      }
      // On 200 the CF wrote `subscription`; the Firestore stream flips Pro and
      // the paywall closes itself. Nothing else to do here.
    } catch (e) {
      debugPrint('[IAP] verify error: $e');
      if (showErrors) {
        lastError.value =
            'Réseau indisponible pour valider l\'achat. Réessayez « Restaurer ».';
      }
    }
  }
}

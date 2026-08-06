import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Product IDs — must match exactly what is set up in Google Play Console
const String kProductMonthly = 'closer_premium_monthly';
const String kProductYearly = 'closer_premium_yearly';
const String kProductLifetime = 'closer_premium_lifetime';

const Set<String> _kProductIds = {
  kProductMonthly,
  kProductYearly,
  kProductLifetime,
};

/// Key used in SharedPreferences to cache premium status so we know
/// the user is premium even before the billing connection resolves on launch.
const String _kPremiumCacheKey = 'closer_premium_active';

/// Singleton service that manages Google Play Billing for Closer Premium.
///
/// Usage:
///   await SubscriptionService.instance.init();
///   SubscriptionService.instance.isPremium  // ValueNotifier<bool>
class SubscriptionService {
  SubscriptionService._internal();
  static final SubscriptionService instance = SubscriptionService._internal();

  final InAppPurchase _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _purchaseSubscription;

  /// Reactive premium status — listen to this throughout the app.
  final ValueNotifier<bool> isPremium = ValueNotifier(false);

  /// All available products fetched from the Play Store.
  final ValueNotifier<List<ProductDetails>> availableProducts =
      ValueNotifier([]);

  bool _initialized = false;

  // ─── Init ────────────────────────────────────────────────────────────────────

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    // 1. Restore cached status immediately so the UI doesn't flash on launch
    final prefs = await SharedPreferences.getInstance();
    isPremium.value = prefs.getBool(_kPremiumCacheKey) ?? false;

    // 2. Check if billing is available on this device
    final bool available = await _iap.isAvailable();
    if (!available) {
      debugPrint('[SubscriptionService] Play Billing not available.');
      return;
    }

    // 3. Listen to purchase updates
    _purchaseSubscription = _iap.purchaseStream.listen(
      _onPurchaseUpdated,
      onError: (error) {
        debugPrint('[SubscriptionService] Purchase stream error: $error');
      },
    );

    // 4. Load products from Play Store
    await _loadProducts();

    // 5. Restore existing purchases (handles reinstalls)
    await _iap.restorePurchases();
  }

  // ─── Load Products ───────────────────────────────────────────────────────────

  Future<void> _loadProducts() async {
    try {
      final ProductDetailsResponse response =
          await _iap.queryProductDetails(_kProductIds);

      if (response.error != null) {
        debugPrint(
            '[SubscriptionService] Error loading products: ${response.error}');
        return;
      }

      if (response.productDetails.isEmpty) {
        debugPrint(
            '[SubscriptionService] No products found. Check Play Console setup.');
        return;
      }

      // Sort so Monthly → Yearly → Lifetime
      final sorted = response.productDetails.toList()
        ..sort((a, b) {
          const order = [kProductMonthly, kProductYearly, kProductLifetime];
          return order
              .indexOf(a.id)
              .compareTo(order.indexOf(b.id));
        });

      availableProducts.value = sorted;
      debugPrint(
          '[SubscriptionService] Loaded ${sorted.length} products: ${sorted.map((p) => p.id)}');
    } catch (e) {
      debugPrint('[SubscriptionService] Exception loading products: $e');
    }
  }

  // ─── Purchase ────────────────────────────────────────────────────────────────

  /// Initiates a purchase flow for the given [productDetails].
  Future<void> purchase(ProductDetails productDetails) async {
    final PurchaseParam param = PurchaseParam(productDetails: productDetails);
    try {
      if (productDetails.id == kProductLifetime) {
        // Lifetime is a non-consumable one-time purchase
        await _iap.buyNonConsumable(purchaseParam: param);
      } else {
        // Monthly / Yearly are subscriptions
        await _iap.buyNonConsumable(purchaseParam: param);
      }
    } catch (e) {
      debugPrint('[SubscriptionService] Purchase error: $e');
      rethrow;
    }
  }

  /// Manually trigger a restore (e.g. user taps "Restore Purchases")
  Future<void> restorePurchases() async {
    await _iap.restorePurchases();
  }

  // ─── Purchase Updates ────────────────────────────────────────────────────────

  void _onPurchaseUpdated(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      switch (purchase.status) {
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          await _handleValidPurchase(purchase);
          break;

        case PurchaseStatus.error:
          debugPrint(
              '[SubscriptionService] Purchase error: ${purchase.error?.message}');
          break;

        case PurchaseStatus.canceled:
          debugPrint('[SubscriptionService] Purchase cancelled by user.');
          break;

        case PurchaseStatus.pending:
          debugPrint('[SubscriptionService] Purchase pending...');
          break;
      }

      // Always complete the purchase to avoid it re-appearing
      if (purchase.pendingCompletePurchase) {
        await _iap.completePurchase(purchase);
      }
    }
  }

  Future<void> _handleValidPurchase(PurchaseDetails purchase) async {
    // In production you would verify the receipt server-side here.
    // For now we trust the Play Store response and grant premium locally.
    if (_kProductIds.contains(purchase.productID)) {
      await _grantPremium();
    }
  }

  // ─── Premium State ───────────────────────────────────────────────────────────

  Future<void> _grantPremium() async {
    isPremium.value = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kPremiumCacheKey, true);
    debugPrint('[SubscriptionService] ✨ Premium granted!');
  }

  /// Called if you need to manually revoke premium (e.g. subscription expired).
  /// In production this would be driven by a server-side receipt check.
  Future<void> revokePremium() async {
    isPremium.value = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kPremiumCacheKey, false);
    debugPrint('[SubscriptionService] Premium revoked.');
  }

  // ─── Cleanup ─────────────────────────────────────────────────────────────────

  void dispose() {
    _purchaseSubscription?.cancel();
    isPremium.dispose();
    availableProducts.dispose();
  }
}

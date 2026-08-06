import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import '../../core/services/subscription_service.dart';

/// Provides the SubscriptionService singleton.
final subscriptionServiceProvider = Provider<SubscriptionService>((ref) {
  return SubscriptionService.instance;
});

/// Reactive stream of whether the current user has an active premium subscription.
/// Rebuilds any widget that watches it whenever premium status changes.
final isPremiumProvider = StreamProvider<bool>((ref) async* {
  final service = ref.watch(subscriptionServiceProvider);
  // Emit the current value immediately
  yield service.isPremium.value;
  // Then yield every future change
  await for (final _ in Stream.periodic(const Duration(seconds: 1))) {
    yield service.isPremium.value;
  }
});

/// Provides the list of available subscription products fetched from Play Store.
final availableProductsProvider = StreamProvider<List<ProductDetails>>((ref) async* {
  final service = ref.watch(subscriptionServiceProvider);
  yield service.availableProducts.value;
  await for (final _ in Stream.periodic(const Duration(seconds: 2))) {
    yield service.availableProducts.value;
  }
});

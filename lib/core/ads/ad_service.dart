import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../services/subscription_service.dart';

class AdService {
  static final AdService instance = AdService._internal();
  AdService._internal();

  InterstitialAd? _interstitialAd;
  bool _isInterstitialAdLoading = false;
  int _interstitialAdCount = 0;
  DateTime? _lastInterstitialTime;

  RewardedAd? _rewardedAd;
  bool _isRewardedAdLoading = false;
  int _rewardedAdFailedAttempts = 0;

  // Max 10 interstitials per session
  static const int _maxAdsPerSession = 10;
  // 3 minutes cooldown between interstitials
  static const Duration _cooldown = Duration(minutes: 3);

  /// Banner Ad Unit IDs
  String get bannerAdUnitId {
    if (kDebugMode) {
      return 'ca-app-pub-3940256099942544/6300978111'; // Test ID for debug
    }
    if (Platform.isAndroid) {
      return 'ca-app-pub-4025737666505759/1342059296'; // Production ID
    } else if (Platform.isIOS) {
      return 'ca-app-pub-3940256099942544/2934735716'; // Test ID fallback
    }
    throw UnsupportedError('Unsupported platform');
  }

  /// Interstitial Ad Unit IDs
  String get interstitialAdUnitId {
    if (kDebugMode) {
      return 'ca-app-pub-3940256099942544/1033173712'; // Test ID for debug
    }
    if (Platform.isAndroid) {
      return 'ca-app-pub-4025737666505759/4201971017'; // Production ID
    } else if (Platform.isIOS) {
      return 'ca-app-pub-3940256099942544/4411468910'; // Test ID fallback
    }
    throw UnsupportedError('Unsupported platform');
  }

  /// Rewarded Ad Unit IDs
  String get rewardedAdUnitId {
    if (kDebugMode) {
      return 'ca-app-pub-3940256099942544/5224354917'; // Test ID for debug
    }
    if (Platform.isAndroid) {
      return 'ca-app-pub-4025737666505759/7566500957'; // Production ID
    } else if (Platform.isIOS) {
      return 'ca-app-pub-3940256099942544/1712485313'; // Test ID fallback
    }
    throw UnsupportedError('Unsupported platform');
  }

  /// Initialize Mobile Ads SDK. Call this in main().
  Future<void> init() async {
    await MobileAds.instance.initialize();
    _preloadInterstitial();
    _preloadRewarded();
  }

  // ─── Interstitial ──────────────────────────────────────────────────────────

  void _preloadInterstitial() {
    if (_interstitialAd != null || _isInterstitialAdLoading) return;
    if (_interstitialAdCount >= _maxAdsPerSession) return;
    _isInterstitialAdLoading = true;
    InterstitialAd.load(
      adUnitId: interstitialAdUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _interstitialAd = ad;
          _isInterstitialAdLoading = false;
          ad.fullScreenContentCallback = FullScreenContentCallback(
            onAdDismissedFullScreenContent: (ad) {
              ad.dispose();
              _interstitialAd = null;
              _preloadInterstitial();
            },
            onAdFailedToShowFullScreenContent: (ad, error) {
              ad.dispose();
              _interstitialAd = null;
              _preloadInterstitial();
            },
          );
        },
        onAdFailedToLoad: (error) {
          _isInterstitialAdLoading = false;
          _interstitialAd = null;
        },
      ),
    );
  }

  void showInterstitialIfReady() {
    // Premium users never see ads
    if (SubscriptionService.instance.isPremium.value) return;
    if (_interstitialAdCount >= _maxAdsPerSession) return;
    if (_interstitialAd == null) {
      _preloadInterstitial();
      return;
    }
    if (_lastInterstitialTime != null) {
      final elapsed = DateTime.now().difference(_lastInterstitialTime!);
      if (elapsed < _cooldown) return;
    }
    _interstitialAd!.show();
    _interstitialAdCount++;
    _lastInterstitialTime = DateTime.now();
    _interstitialAd = null;
  }

  // ─── Rewarded ──────────────────────────────────────────────────────────────

  void _preloadRewarded() {
    if (_rewardedAd != null || _isRewardedAdLoading) return;
    _isRewardedAdLoading = true;
    RewardedAd.load(
      adUnitId: rewardedAdUnitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          _rewardedAd = ad;
          _isRewardedAdLoading = false;
          _rewardedAdFailedAttempts = 0;
          debugPrint('[AdService] Rewarded ad loaded.');
        },
        onAdFailedToLoad: (error) {
          _isRewardedAdLoading = false;
          _rewardedAd = null;
          _rewardedAdFailedAttempts++;
          debugPrint('[AdService] Rewarded ad failed to load: $error');
        },
      ),
    );
  }

  /// Shows a rewarded ad. Calls [onReward] only if the user earns the reward.
  /// Calls [onNotReady] if the ad isn't loaded yet.
  void showRewardedAd({
    required VoidCallback onReward,
    void Function(bool suspectedAdblock)? onNotReady,
    VoidCallback? onDismissed,
  }) {
    // Premium users get reward instantly — they've already paid
    if (SubscriptionService.instance.isPremium.value) {
      onReward();
      return;
    }
    if (_rewardedAd == null) {
      debugPrint('[AdService] Rewarded ad not ready yet, preloading...');
      _preloadRewarded();
      bool suspectedAdblock = _rewardedAdFailedAttempts >= 2;
      onNotReady?.call(suspectedAdblock);
      return;
    }

    _rewardedAd!.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _rewardedAd = null;
        _preloadRewarded();
        onDismissed?.call();
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        _rewardedAd = null;
        _preloadRewarded();
        debugPrint('[AdService] Rewarded ad failed to show: $error');
      },
    );

    _rewardedAd!.show(
      onUserEarnedReward: (ad, reward) {
        debugPrint('[AdService] User earned reward.');
        onReward();
      },
    );
    _rewardedAd = null;
  }

  /// Whether a rewarded ad is preloaded and ready to show immediately.
  bool get isRewardedAdReady => _rewardedAd != null;
}

/// Helper Widget to display a Banner Ad anywhere in the app.
class AdBannerWidget extends StatefulWidget {
  final AdSize adSize;
  const AdBannerWidget({super.key, this.adSize = AdSize.banner});

  @override
  State<AdBannerWidget> createState() => _AdBannerWidgetState();
}

class _AdBannerWidgetState extends State<AdBannerWidget> {
  BannerAd? _bannerAd;
  bool _isLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadAd();
  }

  void _loadAd() {
    _bannerAd = BannerAd(
      adUnitId: AdService.instance.bannerAdUnitId,
      size: widget.adSize,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          if (mounted) setState(() => _isLoaded = true);
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          debugPrint('[AdBannerWidget] Failed to load banner ad: $error');
        },
      ),
    )..load();
  }

  @override
  void dispose() {
    _bannerAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Premium users never see banner ads
    if (SubscriptionService.instance.isPremium.value) return const SizedBox.shrink();
    if (!_isLoaded || _bannerAd == null) return const SizedBox.shrink();
    return SizedBox(
      width: _bannerAd!.size.width.toDouble(),
      height: _bannerAd!.size.height.toDouble(),
      child: AdWidget(ad: _bannerAd!),
    );
  }
}

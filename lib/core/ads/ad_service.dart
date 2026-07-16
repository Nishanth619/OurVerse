import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

class AdService {
  static final AdService instance = AdService._internal();
  AdService._internal();

  InterstitialAd? _interstitialAd;
  bool _isInterstitialAdLoading = false;
  int _interstitialAdCount = 0; // Session count
  DateTime? _lastInterstitialTime;

  // Max 3 ads per session
  static const int _maxAdsPerSession = 3;
  // 5 minutes cooldown
  static const Duration _cooldown = Duration(minutes: 5);

  /// Test Interstitial Ad Unit IDs
  String get interstitialAdUnitId {
    if (Platform.isAndroid) {
      return 'ca-app-pub-3940256099942544/1033173712'; // Test ID
    } else if (Platform.isIOS) {
      return 'ca-app-pub-3940256099942544/4411468910'; // Test ID
    }
    throw UnsupportedError("Unsupported platform");
  }

  /// Initialize Mobile Ads SDK. Call this in main().
  Future<void> init() async {
    await MobileAds.instance.initialize();
    _preloadInterstitial();
  }

  /// Silently loads the next interstitial in the background.
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
              _preloadInterstitial(); // Load the next one
            },
            onAdFailedToShowFullScreenContent: (ad, error) {
              ad.dispose();
              _interstitialAd = null;
              _preloadInterstitial(); // Retry loading
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

  /// Shows an interstitial ad if it's ready and cooldowns are respected.
  /// Does NOT block UI if ad is not ready.
  void showInterstitialIfReady() {
    if (_interstitialAdCount >= _maxAdsPerSession) return;
    if (_interstitialAd == null) {
      _preloadInterstitial(); // Try to load one for next time
      return;
    }

    // Check cooldown
    if (_lastInterstitialTime != null) {
      final elapsed = DateTime.now().difference(_lastInterstitialTime!);
      if (elapsed < _cooldown) return;
    }

    // Show the ad
    _interstitialAd!.show();
    _interstitialAdCount++;
    _lastInterstitialTime = DateTime.now();
    _interstitialAd = null;
  }
}

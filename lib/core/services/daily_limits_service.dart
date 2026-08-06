import 'package:shared_preferences/shared_preferences.dart';
import '../utils/app_utils.dart';
import 'subscription_service.dart';

/// Tracks local daily limits using SharedPreferences.
/// Keys are date-stamped so they auto-reset every new day.
/// Premium users bypass all limits automatically.
class DailyLimitsService {
  // ─── Per-Game Play Limits ───────────────────────────────────────────────────

  static const int _playsPerDay = 5;
  static const int _playsPerAd = 5;

  /// Supported game IDs: 'ludo', 'snakesladders', 'bingo', 'uno', 'wordhunt'
  static String _gamePlayKey(String gameId) =>
      'game_plays_${gameId}_${AppUtils.todayKey()}';

  /// Returns how many free plays this game has left today.
  /// Premium users always get 999 (unlimited).
  static Future<int> getGamePlaysLeft(String gameId) async {
    if (SubscriptionService.instance.isPremium.value) return 999;
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_gamePlayKey(gameId)) ?? _playsPerDay;
  }

  /// Call this when the player actually STARTS or RESTARTS a game session.
  /// Returns false if out of plays (should show ad gate).
  /// Premium users always return true.
  static Future<bool> consumeGamePlay(String gameId) async {
    if (SubscriptionService.instance.isPremium.value) return true;
    final prefs = await SharedPreferences.getInstance();
    final key = _gamePlayKey(gameId);
    final current = prefs.getInt(key) ?? _playsPerDay;
    if (current <= 0) return false;
    await prefs.setInt(key, current - 1);
    return true;
  }

  /// Called after user watches a rewarded ad to top up plays for a specific game.
  static Future<void> addGamePlaysFromAd(String gameId) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _gamePlayKey(gameId);
    final current = prefs.getInt(key) ?? 0;
    await prefs.setInt(key, current + _playsPerAd);
  }

  // ─── Streaming Minutes ─────────────────────────────────────────────────────

  static const int _streamingMinutesPerDay = 30;
  static const int _streamingMinutesPerAd = 30;

  static String _streamingMinutesKey() =>
      'streaming_minutes_${AppUtils.todayKey()}';

  /// Returns streaming minutes left. Premium users always get 9999.
  static Future<int> getStreamingMinutesLeft() async {
    if (SubscriptionService.instance.isPremium.value) return 9999;
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_streamingMinutesKey()) ?? _streamingMinutesPerDay;
  }

  /// Deduct one minute of streaming. Returns remaining minutes.
  /// Premium users always return 9999 without deducting.
  static Future<int> deductStreamingMinute() async {
    if (SubscriptionService.instance.isPremium.value) return 9999;
    final prefs = await SharedPreferences.getInstance();
    final key = _streamingMinutesKey();
    final current = prefs.getInt(key) ?? _streamingMinutesPerDay;
    final updated = (current - 1).clamp(0, 9999);
    await prefs.setInt(key, updated);
    return updated;
  }

  /// Called after user (either partner) watches a rewarded ad to extend time.
  static Future<int> addStreamingMinutesFromAd() async {
    final prefs = await SharedPreferences.getInstance();
    final key = _streamingMinutesKey();
    final current = prefs.getInt(key) ?? 0;
    final updated = current + _streamingMinutesPerAd;
    await prefs.setInt(key, updated);
    return updated;
  }
}

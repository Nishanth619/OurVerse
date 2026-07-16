import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/constants/app_constants.dart';

/// Bridges Flutter data to the native Android App Widget via [home_widget].
///
/// The native [CloserWidgetProvider.kt] reads these SharedPreferences keys
/// whenever [HomeWidget.updateWidget()] is called.
///
/// KEY LAYOUT:
///   widget_mode            → "question" | "mood"
///   widget_question        → Today's question text string
///   widget_my_emoji        → The current user's selected mood emoji
///   widget_partner_emoji   → The partner's selected mood emoji (from Firestore)
///
/// Package ID must match [android:name] in AndroidManifest.xml exactly.
class HomeWidgetService {
  /// Must match the actual Android package name in build.gradle / AndroidManifest.
  static const String _androidPackageId = 'site.nexaaradhya.bondly';

  /// Name of the Kotlin AppWidgetProvider class (without package prefix).
  static const String _widgetAndroidName = 'CloserWidgetProvider';

  // ─── Init ──────────────────────────────────────────────────────────────────

  static Future<void> init() async {
    // setAppGroupId is only relevant on iOS (for sharing data between the app
    // and the Widget extension via App Groups). On Android this is a no-op
    // but we call it to keep the API symmetric for future iOS support.
    await HomeWidget.setAppGroupId(_androidPackageId);
  }

  // ─── Question ──────────────────────────────────────────────────────────────

  static Future<void> updateQuestion(String questionText) async {
    await HomeWidget.saveWidgetData<String>(
      AppConstants.widgetQuestionKey,
      questionText,
    );
    await _refresh();
  }

  // ─── Mood (new split API) ──────────────────────────────────────────────────

  /// Call this when the current user selects their own emoji in the app.
  /// Writes [myEmoji] to the "widget_my_emoji" slot and optionally carries
  /// the partner's last-known emoji through unchanged.
  static Future<void> updateMyEmoji(String myEmoji) async {
    await HomeWidget.saveWidgetData<String>(
      AppConstants.widgetMyEmojiKey,
      myEmoji,
    );
    await _refresh();
  }

  /// Call this when the partner's mood changes (detected via Firestore snapshot).
  /// Writes [partnerEmoji] to the "widget_partner_emoji" slot.
  static Future<void> updatePartnerEmoji(String partnerEmoji) async {
    await HomeWidget.saveWidgetData<String>(
      AppConstants.widgetPartnerEmojiKey,
      partnerEmoji,
    );
    await _refresh();
  }

  /// Legacy combined update — still used internally to keep native widget
  /// refreshed with a comma-joined summary. Safe to call alongside the new API.
  static Future<void> updateMood(String moodSummary) async {
    await HomeWidget.saveWidgetData<String>(
      AppConstants.widgetMoodKey,
      moodSummary,
    );
    // No extra _refresh() here — callers above will trigger it.
  }

  // ─── Partner Flash Photo (for widget display) ──────────────────────────────

  /// Called when the partner uploads a new Flash photo.
  /// Decodes the [base64Photo] string, writes it to a local cache file that
  /// the native Kotlin widget can load as a Bitmap, saves the file path via
  /// HomeWidget.saveWidgetData, and triggers a widget refresh.
  ///
  /// Heavy decode work runs on a background isolate via [compute] so the UI
  /// thread is never blocked.
  static Future<void> savePartnerFlashPhoto(
      String base64Photo, String dateKey) async {
    try {
      // Decode base64 → bytes on a background isolate (heavy work)
      final bytes = await compute(_decodeBase64, base64Photo);

      // Write to a predictable file in the app's cache directory.
      // The filename is stable so the widget always reads the same path.
      final dir = await getApplicationCacheDirectory();
      final file = File('${dir.path}/widget_partner_flash.jpg');
      await file.writeAsBytes(bytes, flush: true);

      // Save the path and date so the native widget knows what to load
      await HomeWidget.saveWidgetData<String>(
        AppConstants.widgetPartnerFlashPathKey,
        file.path,
      );
      await HomeWidget.saveWidgetData<String>(
        AppConstants.widgetFlashDateKey,
        dateKey,
      );

      await _refresh();
    } catch (e) {
      debugPrint('[HomeWidgetService] savePartnerFlashPhoto failed: $e');
    }
  }

  /// Clears the stored partner flash photo (call at midnight / new day).
  static Future<void> clearPartnerFlashPhoto() async {
    try {
      final dir = await getApplicationCacheDirectory();
      final file = File('${dir.path}/widget_partner_flash.jpg');
      if (await file.exists()) await file.delete();

      await HomeWidget.saveWidgetData<String>(
          AppConstants.widgetPartnerFlashPathKey, '');
      await HomeWidget.saveWidgetData<String>(
          AppConstants.widgetFlashDateKey, '');
      await _refresh();
    } catch (_) {}
  }

  /// Top-level function for compute() — must not be a closure or instance method.
  static List<int> _decodeBase64(String b64) => base64Decode(b64);

  static Future<void> _refresh() async {
    await HomeWidget.updateWidget(
      androidName: _widgetAndroidName,
    );
  }

  // ─── Partner ID (for native widget ping) ───────────────────────────────────

  /// Saves the partner's device ID so the native Kotlin widget can read it
  /// directly from SharedPreferences to send a background ping without
  /// opening the Flutter app.
  static Future<void> savePartnerId(String partnerId) async {
    await HomeWidget.saveWidgetData<String>('widget_partner_device_id', partnerId);
  }

  // ─── Widget Mode ───────────────────────────────────────────────────────────

  static Future<String> getWidgetMode() async {
    // Read from standard preferences for Flutter UI state
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(AppConstants.widgetModeKey) ?? 'question';
  }

  static Future<void> setWidgetMode(String mode) async {
    // 1. Save for Flutter UI
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(AppConstants.widgetModeKey, mode);

    // 2. Save for Native Android Widget
    await HomeWidget.saveWidgetData<String>(
      AppConstants.widgetModeKey,
      mode,
    );
    await _refresh();
  }
}

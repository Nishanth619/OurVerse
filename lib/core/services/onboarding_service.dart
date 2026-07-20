import 'package:shared_preferences/shared_preferences.dart';

/// Tracks first-run state for onboarding slides and coach marks.
/// Both are shown exactly once, keyed in SharedPreferences.
class OnboardingService {
  static const _kOnboardingDone = 'onboarding_done_v1';
  static const _kCoachMarksDone = 'coach_marks_done_v1';

  static Future<bool> isOnboardingDone() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kOnboardingDone) ?? false;
  }

  static Future<void> markOnboardingDone() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kOnboardingDone, true);
  }

  static Future<bool> isCoachMarksDone() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kCoachMarksDone) ?? false;
  }

  static Future<void> markCoachMarksDone() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kCoachMarksDone, true);
  }

  // Debug helper: reset everything (useful for testing)
  static Future<void> resetAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kOnboardingDone);
    await prefs.remove(_kCoachMarksDone);
  }
}

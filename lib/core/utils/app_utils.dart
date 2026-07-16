import 'dart:math';
import 'package:intl/intl.dart';

class AppUtils {
  static String todayKey() {
    return DateFormat('yyyy-MM-dd').format(DateTime.now());
  }

  static String formatDate(DateTime date) {
    return DateFormat('MMM d, yyyy').format(date);
  }

  static String generateInviteCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // no confusable chars
    final rng = Random.secure();
    return List.generate(6, (_) => chars[rng.nextInt(chars.length)]).join();
  }

  static bool isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  static String timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  static bool _isDnsResolutionFailure(Object error) {
    final msg = error.toString();
    return msg.contains('UnknownHostException') ||
        msg.contains('Unable to resolve host') ||
        msg.contains('EAI_NODATA');
  }

  static String getFriendlyErrorMessage(Object error) {
    if (_isDnsResolutionFailure(error)) {
      return 'Could not reach sync servers. If you use a custom Private DNS '
          '(Settings → Network → Private DNS), try turning it off and retry.';
    }
    // Do NOT expose raw error.toString() to users — it can leak internal paths,
    // SDK class names, or Firestore collection details.
    return 'Something went wrong. Please check your connection and try again.';
  }
}

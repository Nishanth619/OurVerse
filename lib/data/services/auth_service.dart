import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/constants/app_constants.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Returns the stable anonymous device ID (Firebase UID).
  /// Signs in silently on first launch; subsequent calls reuse the same UID.
  Future<String> getOrCreateDeviceId() async {
    User? user = _auth.currentUser;
    if (user == null) {
      final cred = await _auth.signInAnonymously();
      user = cred.user!;
    }
    return user.uid;
  }

  Future<String> getDeviceName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(AppConstants.deviceNameKey) ?? 'Someone';
  }

  Future<void> setDeviceName(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(AppConstants.deviceNameKey, name.trim());
  }

  Future<String?> getSavedSpaceId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(AppConstants.spaceIdKey);
  }

  Future<void> saveSpaceId(String spaceId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(AppConstants.spaceIdKey, spaceId);
  }

  Future<void> clearSpaceId() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(AppConstants.spaceIdKey);
  }
}

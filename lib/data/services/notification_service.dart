import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import '../../core/constants/app_constants.dart';
import 'auth_service.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();

  final data = message.data;
  final type = data['type'];
  final spaceId = data['spaceId'];
  final callerName = data['callerName'];

  if (type == 'call' && spaceId != null) {
    final name = callerName ?? 'Partner';
    final encodedName = Uri.encodeComponent(name);
    final avatarUrl =
        'https://ui-avatars.com/api/?name=$encodedName&background=E8647A&color=fff&rounded=true&size=200';

    final params = CallKitParams(
      id: spaceId,
      nameCaller: name,
      appName: 'OurVerse',
      avatar: avatarUrl,
      handle: 'Incoming Call',
      type: 0, // Audio call
      duration: 30000,
      textAccept: 'Accept',
      textDecline: 'Decline',
      missedCallNotification: const NotificationParams(
        showNotification: true,
        isShowCallback: false,
        subtitle: 'Missed call',
        callbackText: 'Call back',
      ),
      extra: <String, dynamic>{'spaceId': spaceId},
      headers: <String, dynamic>{'apiKey': 'closer_app'},
      android: AndroidParams(
        isCustomNotification: true,
        isShowLogo: false,
        ringtonePath: 'system_ringtone_default',
        backgroundColor: '#E8647A',
        backgroundUrl: avatarUrl,
        actionColor: '#4CAF50',
      ),
      ios: const IOSParams(
        iconName: 'CallKitIcon',
        handleType: 'generic',
        supportsVideo: false,
        maximumCallGroups: 2,
        maximumCallsPerCallGroup: 1,
        audioSessionMode: 'default',
        audioSessionActive: true,
        audioSessionPreferredSampleRate: 44100.0,
        audioSessionPreferredIOBufferDuration: 0.005,
        supportsDTMF: true,
        supportsHolding: true,
        supportsGrouping: false,
        supportsUngrouping: false,
        ringtonePath: 'system_ringtone_default',
      ),
    );
    await FlutterCallkitIncoming.showCallkitIncoming(params);
  } else if (type == 'end_call' && spaceId != null) {
    await FlutterCallkitIncoming.endAllCalls();
  } else if (type == 'mood_ping') {
    // Data-only FCM messages are silent — we must show the notification ourselves.
    // This fires when the app is killed or backgrounded on Android 14+.
    final emoji = data['emoji'] ?? '';
    final title = data['title'] ?? 'Your partner updated their mood $emoji';
    final body =
        data['body'] ?? 'Open OurVerse to see how they are feeling today 💞';

    final plugin = FlutterLocalNotificationsPlugin();
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    await plugin.initialize(const InitializationSettings(android: android));

    // Ensure the channel exists in this background isolate too
    final androidImpl = plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidImpl?.createNotificationChannel(
      AndroidNotificationChannel(
        AppConstants.notifPingChannelId,
        AppConstants.notifPingChannelName,
        description: 'Instant ping when your partner updates their mood',
        importance: Importance.high,
        playSound: true,
        vibrationPattern: Int64List.fromList([0, 250, 100, 250]),
        enableVibration: true,
      ),
    );

    await plugin.show(
      AppConstants.moodPingNotifId,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          AppConstants.notifPingChannelId,
          AppConstants.notifPingChannelName,
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
          vibrationPattern: Int64List.fromList([0, 250, 100, 250]),
          enableVibration: true,
          playSound: true,
        ),
      ),
    );
  }
}

class NotificationService {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  // ─── Init ──────────────────────────────────────────────────────────────────

  static Future<void> init() async {
    if (_initialized) return;

    // Init timezone DB using the device's actual IANA timezone
    tz.initializeTimeZones();
    final localTz = (await FlutterTimezone.getLocalTimezone()).identifier;
    tz.setLocalLocation(tz.getLocation(localTz));

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: android);
    await _plugin.initialize(settings);

    final androidImpl = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();

    // Daily reminder channel
    await androidImpl?.createNotificationChannel(
      const AndroidNotificationChannel(
        AppConstants.notifChannelId,
        AppConstants.notifChannelName,
        description: 'Daily check-in reminders',
        importance: Importance.defaultImportance,
      ),
    );

    // Partner mood ping channel (high priority + vibration)
    await androidImpl?.createNotificationChannel(
      AndroidNotificationChannel(
        AppConstants.notifPingChannelId,
        AppConstants.notifPingChannelName,
        description: 'Instant ping when your partner updates their mood',
        importance: Importance.high,
        playSound: true,
        vibrationPattern: Int64List.fromList([0, 250, 100, 250]),
        enableVibration: true,
      ),
    );

    // Register background handler
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // Handle mood_ping data messages when app is in FOREGROUND
    // (background/killed is handled by _firebaseMessagingBackgroundHandler above)
    FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
      final type = message.data['type'];
      if (type == 'mood_ping') {
        final emoji = message.data['emoji'] ?? '';
        final title =
            message.data['title'] ?? 'Your partner updated their mood $emoji';
        final body = message.data['body'] ??
            'Open OurVerse to see how they are feeling today 💞';
        await showMoodPing(emoji, title: title, body: body);
      }
    });

    _initialized = true;
  }

  // ─── Permission & Token ───────────────────────────────────────────────────

  /// Requests the POST_NOTIFICATIONS permission and saves the FCM token to Firestore.
  /// On Android 13+ (API 33), we MUST use permission_handler to show the system dialog.
  static Future<bool> requestPermission(String deviceId) async {
    // Step 1: Android 13+ explicit runtime permission (POST_NOTIFICATIONS)
    // This is the system dialog. Without it, no notifications appear on Android 13+.
    final permStatus = await Permission.notification.request();
    final grantedSystem = permStatus.isGranted;

    // Step 2: FCM auth (needed for cloud messaging token)
    final messaging = FirebaseMessaging.instance;
    await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    // Step 3: Also request via flutter_local_notifications (belt & suspenders)
    final plugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (plugin != null) {
      await plugin.requestNotificationsPermission();
    }

    // Step 4: Always try to save the FCM token regardless of result
    // (token may exist even if permission was previously denied)
    try {
      final token = await messaging.getToken();
      if (token != null) {
        await FirebaseFirestore.instance
            .collection('deviceTokens')
            .doc(deviceId)
            .set(
          {'fcmToken': token, 'updatedAt': FieldValue.serverTimestamp()},
          SetOptions(merge: true),
        );
      }
    } catch (e) {
      print('Error saving FCM token: $e');
    }

    // Also listen for token refreshes and re-save
    messaging.onTokenRefresh.listen((newToken) async {
      try {
        await FirebaseFirestore.instance
            .collection('deviceTokens')
            .doc(deviceId)
            .set(
          {'fcmToken': newToken, 'updatedAt': FieldValue.serverTimestamp()},
          SetOptions(merge: true),
        );
      } catch (_) {}
    });

    return grantedSystem;
  }

  // ─── Enable / Disable ──────────────────────────────────────────────────────

  static Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(AppConstants.notificationsEnabledKey) ?? true;
  }

  static Future<bool> isMoodPingsEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(AppConstants.moodPingsEnabledKey) ?? true;
  }

  static Future<void> setEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(AppConstants.notificationsEnabledKey, value);
    if (value) {
      await scheduleDailyReminder();
    } else {
      await cancelAll();
    }
  }

  static Future<void> setMoodPingsEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(AppConstants.moodPingsEnabledKey, value);

    // Also update this preference in Firestore so the sender knows NOT to ping Vercel
    final auth = AuthService();
    final deviceId = await auth.getOrCreateDeviceId();
    try {
      await FirebaseFirestore.instance
          .collection('deviceTokens')
          .doc(deviceId)
          .set({'receiveMoodPings': value}, SetOptions(merge: true));
    } catch (e) {
      print('Error saving receiveMoodPings preference: $e');
    }
  }

  // ─── Schedule ──────────────────────────────────────────────────────────────

  static Future<void> scheduleDailyReminder({
    int hour = AppConstants.defaultReminderHour,
  }) async {
    if (!_initialized) await init();

    // Check permission first
    final enabled = await isEnabled();
    if (!enabled) return;

    // Cancel existing so we don't stack duplicates
    await _plugin.cancel(AppConstants.dailyReminderNotifId);

    final now = tz.TZDateTime.now(tz.local);
    var scheduledDate = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      hour,
    );
    // If the time already passed today, schedule for tomorrow
    if (scheduledDate.isBefore(now)) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    }

    await _plugin.zonedSchedule(
      AppConstants.dailyReminderNotifId,
      'Time to check in 💬',
      "Don't break the streak — answer today's question!",
      scheduledDate,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          AppConstants.notifChannelId,
          AppConstants.notifChannelName,
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
          icon: '@mipmap/ic_launcher',
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  static Future<void> cancelAll() async {
    await _plugin.cancelAll();
  }

  /// Called when the user answers today's question.
  /// Cancels today's pending notification and reschedules for tomorrow.
  static Future<void> cancelTodayReminder() async {
    await _plugin.cancel(AppConstants.dailyReminderNotifId);
    // Reschedule for tomorrow same time
    await scheduleDailyReminder();
  }

  // ─── Partner Mood Ping (Vercel Backend) ──────────────────────────────────

  /// Returns the current user's Firebase ID token for authenticating Vercel calls.
  /// Returns null if the user is not signed in (anonymous auth may not be active yet).
  static Future<String?> _getIdToken() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return null;
      return await user.getIdToken();
    } catch (e) {
      debugPrint('[NotificationService] Failed to get ID token: $e');
      return null;
    }
  }

  /// Calls the Vercel backend to send a true OS-level push notification
  /// to the partner's device when you update your mood.
  static Future<void> pingPartnerViaVercel(
    String emoji,
    String partnerDeviceId, {
    required String spaceId,
  }) async {
    const vercelUrl = 'https://closerbackend-1.vercel.app/api/mood_ping';
    final idToken = await _getIdToken();
    if (idToken == null) {
      debugPrint('[NotificationService] Skipping mood ping — no auth token');
      return;
    }
    try {
      await http.post(
        Uri.parse(vercelUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $idToken',
        },
        body: jsonEncode({
          'emoji': emoji,
          'partnerDeviceId': partnerDeviceId,
          'spaceId': spaceId,
        }),
      );
    } catch (e) {
      debugPrint('[NotificationService] Failed to ping Vercel backend: $e');
    }
  }

  /// Calls the Vercel backend to send a push notification
  /// to the partner's device when you upload a Flash photo.
  static Future<void> pingPartnerFlashViaVercel(String partnerDeviceId) async {
    const vercelUrl = 'https://closerbackend-1.vercel.app/api/flash_ping';
    final idToken = await _getIdToken();
    if (idToken == null) {
      debugPrint('[NotificationService] Skipping flash ping — no auth token');
      return;
    }
    try {
      await http.post(
        Uri.parse(vercelUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $idToken',
        },
        body: jsonEncode({
          'partnerDeviceId': partnerDeviceId,
        }),
      );
    } catch (e) {
      debugPrint(
          '[NotificationService] Failed to ping Vercel flash backend: $e');
    }
  }

  /// Fires an immediate high-priority notification with vibration locally
  /// when the partner updates their mood emoji (if app is running/backgrounded).
  static Future<void> showMoodPing(String emoji,
      {String? title, String? body}) async {
    if (!await isMoodPingsEnabled()) return;

    if (!_initialized) await init();

    await _plugin.show(
      AppConstants.moodPingNotifId,
      title ?? 'Your partner updated their mood $emoji',
      body ?? 'Open OurVerse to see how they are feeling today 💜',
      NotificationDetails(
        android: AndroidNotificationDetails(
          AppConstants.notifPingChannelId,
          AppConstants.notifPingChannelName,
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
          vibrationPattern: Int64List.fromList([0, 250, 100, 250]),
          enableVibration: true,
          playSound: true,
        ),
      ),
    );
  }

  // ─── Native Call Ping (Vercel Backend) ───────────────────────────────────

  static Future<void> pingPartnerForCall(
      String partnerDeviceId, String spaceId, String callerName) async {
    const url = 'https://closerbackend-1.vercel.app/api/call_ping';
    final idToken = await _getIdToken();
    if (idToken == null) {
      debugPrint('[NotificationService] Skipping call ping — no auth token');
      return;
    }
    try {
      await http.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $idToken',
        },
        body: jsonEncode({
          'partnerDeviceId': partnerDeviceId,
          'spaceId': spaceId,
          'callerName': callerName,
        }),
      );
    } catch (e) {
      debugPrint('[NotificationService] Failed to ping partner for call: $e');
    }
  }

  static Future<void> pingPartnerForEndCall(
      String partnerDeviceId, String spaceId) async {
    const url = 'https://closerbackend-1.vercel.app/api/end_call_ping';
    final idToken = await _getIdToken();
    if (idToken == null) {
      debugPrint(
          '[NotificationService] Skipping end-call ping — no auth token');
      return;
    }
    try {
      await http.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $idToken',
        },
        body: jsonEncode({
          'partnerDeviceId': partnerDeviceId,
          'spaceId': spaceId,
        }),
      );
    } catch (e) {
      debugPrint(
          '[NotificationService] Failed to ping partner for end call: $e');
    }
  }

  static Future<void> pingPartnerForChatMessage(
      String partnerDeviceId, String senderName, String messagePreview) async {
    const url = 'https://closerbackend-1.vercel.app/api/chat_ping';
    final idToken = await _getIdToken();
    if (idToken == null) {
      debugPrint('[NotificationService] Skipping chat ping — no auth token');
      return;
    }
    try {
      await http.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $idToken',
        },
        body: jsonEncode({
          'partnerDeviceId': partnerDeviceId,
          'senderName': senderName,
          'messagePreview': messagePreview,
        }),
      );
    } catch (e) {
      debugPrint(
          '[NotificationService] Failed to ping partner for chat message: $e');
    }
  }
}

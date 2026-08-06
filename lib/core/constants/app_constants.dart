class AppConstants {
  // Firestore collection names
  static const String spacesCollection       = 'spaces';
  static const String dailyAnswersCollection  = 'dailyAnswers';
  static const String moodsCollection         = 'moods';
  static const String questionsCollection     = 'questions';
  static const String questionsFriendsCollection = 'questions_friends';
  static const String wyrSessionsCollection   = 'wyrSessions';
  static const String fcmPingsCollection      = 'fcmPings'; // partner mood pings

  // SharedPreferences keys
  static const String spaceIdKey = 'space_id';
  static const String deviceIdKey = 'device_id';
  static const String deviceNameKey = 'device_name';
  static const String notificationsEnabledKey = 'notifications_enabled';
  static const String moodPingsEnabledKey = 'mood_pings_enabled';
  static const String widgetModeKey = 'widget_mode'; // 'question' | 'mood'

  // Home widget keys (for native layer)
  static const String widgetQuestionKey = 'widget_question';
  static const String widgetMoodKey = 'widget_mood'; // legacy — kept for compatibility
  static const String widgetMyEmojiKey = 'widget_my_emoji';      // my own mood emoji
  static const String widgetPartnerEmojiKey = 'widget_partner_emoji'; // partner's mood emoji
  static const String widgetPartnerFlashPathKey = 'widget_partner_flash_path'; // local file path of partner flash photo
  static const String widgetFlashDateKey = 'widget_flash_date'; // date key of the stored flash

  // Notification
  static const int dailyReminderNotifId = 100;
  static const int moodPingNotifId      = 101;   // partner mood ping
  static const String notifChannelId     = 'closer_daily';
  static const String notifChannelName   = 'Daily Reminders';
  static const String notifPingChannelId   = 'closer_mood_ping';
  static const String notifPingChannelName = 'Partner Mood Updates';
  static const int defaultReminderHour = 20; // 8 PM

  // Invite code
  static const int inviteCodeLength = 6;

  // Question categories
  static const List<String> questionCategories = [
    'fun',
    'deep',
    'spicy',
    'friends',
    'ldr',
  ];
}

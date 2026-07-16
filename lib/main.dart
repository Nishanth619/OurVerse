import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'core/theme/app_theme.dart';
import 'core/utils/app_utils.dart';
import 'data/services/notification_service.dart';
import 'data/services/home_widget_service.dart';
import 'data/services/auth_service.dart';
import 'router.dart';
import 'firebase_options.dart';
import 'shared/providers/app_providers.dart';
import 'features/call/presentation/widgets/incoming_call_handler.dart';
import 'features/call/providers/call_providers.dart';
import 'core/ads/ad_service.dart';

void main() async {
  debugPrint('🚀 [STARTUP] main() called');
  WidgetsFlutterBinding.ensureInitialized();
  debugPrint('🚀 [STARTUP] WidgetsFlutterBinding initialized');

  // ── Performance tuning ────────────────────────────────────────────────────
  // Enables pointer-event resampling: smooths out touch input on high-refresh
  // rate displays (90 Hz / 120 Hz) by aligning pointer events to frame
  // boundaries — reduces jank on fast swipes.
  GestureBinding.instance.resamplingEnabled = true;

  // Increase the image cache so decoded images stay in memory longer.
  // Default: 100 images / 10 MB. Raised to 150 images / 75 MB.
  PaintingBinding.instance.imageCache
    ..maximumSize = 150
    ..maximumSizeBytes = 75 << 20; // 75 MB

  // Lock to portrait
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  debugPrint('🚀 [STARTUP] Orientation locked');

  // Status bar style — dark icons on the light blush-white background
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,   // dark icons for light bg
    statusBarBrightness: Brightness.light,       // iOS equivalent
    systemNavigationBarColor: Colors.white,
    systemNavigationBarIconBrightness: Brightness.dark,
  ));

  // Firebase init — with full debug output so we can see EXACTLY what fails
  debugPrint('🚀 [STARTUP] Calling Firebase.initializeApp...');
  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    debugPrint('✅ [STARTUP] Firebase initialized successfully!');
  } catch (e, st) {
    // Show a visible error screen — not a black screen!
    debugPrint('❌ [STARTUP] Firebase init FAILED: $e');
    debugPrint('❌ [STARTUP] Stack: $st');
    runApp(_DebugErrorApp(
      title: 'Firebase Init Failed',
      error: e.toString(),
      stack: st.toString(),
    ));
    return; // stop here
  }

  debugPrint('🚀 [STARTUP] Calling runApp...');
  // Launch the app immediately. All non-critical services are initialised
  // in the background AFTER runApp() so that a failure in any of them
  // (notifications, home widget, permissions) can NEVER cause a black screen.
  runApp(const ProviderScope(child: CloserApp()));
  debugPrint('🚀 [STARTUP] runApp complete — kicking off background services');

  // Non-critical startup services — each individually guarded so one failure
  // does not stop the others.
  _initBackgroundServices();
}

/// Debug error screen — shown when Firebase (or any critical service) fails.
/// Makes the crash VISIBLE instead of showing a black/white screen.
class _DebugErrorApp extends StatelessWidget {
  final String title;
  final String error;
  final String stack;
  const _DebugErrorApp({required this.title, required this.error, required this.stack});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: true,
      home: Scaffold(
        backgroundColor: const Color(0xFF1A0A2E),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('🔥 STARTUP ERROR', style: TextStyle(color: Colors.red, fontSize: 22, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                Text(title, style: const TextStyle(color: Colors.orange, fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(8)),
                  child: SelectableText(error, style: const TextStyle(color: Colors.white, fontFamily: 'monospace', fontSize: 12)),
                ),
                const SizedBox(height: 12),
                const Text('Stack Trace:', style: TextStyle(color: Colors.orange, fontSize: 14)),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(8)),
                  child: SelectableText(stack, style: const TextStyle(color: Colors.white70, fontFamily: 'monospace', fontSize: 10)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}


/// Runs all non-critical startup services after the app is already on screen.
/// Every service is individually try/caught so failures are silently ignored.
Future<void> _initBackgroundServices() async {
  // Get device ID (needed for notification token registration)
  String deviceId = '';
  try {
    deviceId = await AuthService().getOrCreateDeviceId();
  } catch (_) {}

  // ── Ads Init ──────────────────────────────────────────────────────────────
  await AdService.instance.init();

  // Notification service — can fail on some Android OEMs / in release builds
  try {
    await NotificationService.init();
    if (deviceId.isNotEmpty) {
      await NotificationService.requestPermission(deviceId);
    }
    await NotificationService.scheduleDailyReminder();
  } catch (_) {}

  // Home widget service
  try {
    await HomeWidgetService.init();
  } catch (_) {}
}


class CloserApp extends ConsumerStatefulWidget {
  const CloserApp({super.key});

  @override
  ConsumerState<CloserApp> createState() => _CloserAppState();
}

class _CloserAppState extends ConsumerState<CloserApp>
    with WidgetsBindingObserver {
  Timer? _midnightTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Eagerly initialize CallManager to catch CallKit events on cold start
    Future.microtask(() => ref.read(callManagerProvider));

    // Schedule a one-shot timer that fires at the next midnight boundary.
    // This ensures daily providers (Flash, WYR, Question) reset even when
    // the user keeps the app open overnight without backgrounding it.
    _scheduleMidnightRefresh();
  }

  @override
  void dispose() {
    _midnightTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Schedules a [Timer] that fires at the next calendar midnight.
  /// When it fires it updates [todayKeyProvider] and reschedules for the
  /// FOLLOWING midnight so continuous overnight use is handled correctly.
  void _scheduleMidnightRefresh() {
    final now = DateTime.now();
    final nextMidnight = DateTime(now.year, now.month, now.day + 1);
    final untilMidnight = nextMidnight.difference(now);
    _midnightTimer = Timer(untilMidnight, () {
      if (!mounted) return;
      final newKey = AppUtils.todayKey();
      final storedKey = ref.read(todayKeyProvider);
      if (newKey != storedKey) {
        ref.read(todayKeyProvider.notifier).state = newKey;
        HomeWidgetService.clearPartnerFlashPhoto();
      }
      // Reschedule for the following midnight
      _scheduleMidnightRefresh();
    });
  }

  /// Called whenever the app lifecycle changes.
  /// On resume, check if the date has rolled over — if so, refresh all
  /// date-keyed providers (question, mood, answers) by updating todayKeyProvider.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final currentKey = AppUtils.todayKey();
      final storedKey = ref.read(todayKeyProvider);
      if (currentKey != storedKey) {
        ref.read(todayKeyProvider.notifier).state = currentKey;
        HomeWidgetService.clearPartnerFlashPhoto();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    return IncomingCallHandler(
      child: MaterialApp.router(
        title: 'OurVerse',
        theme: AppTheme.light,
        // Explicitly force light mode — prevents system dark mode from
        // bleeding in and overriding NavigationBar, AppBar, Dialog colors.
        themeMode: ThemeMode.light,
        routerConfig: router,
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}

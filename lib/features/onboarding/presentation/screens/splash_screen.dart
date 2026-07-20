import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:video_player/video_player.dart';
import '../../../../core/services/onboarding_service.dart';
import '../../../../shared/providers/app_providers.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  late final VideoPlayerController _videoCtrl;
  bool _videoReady = false;
  bool _videoFinished = false;
  bool _appReady = false;
  String _destination = '/';

  @override
  void initState() {
    super.initState();
    // Hide status bar for truly immersive full-screen experience.
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _initVideo();
    _loadApp();
  }

  Future<void> _initVideo() async {
    try {
      _videoCtrl = VideoPlayerController.asset(
        'assets/splash_video.mp4',
        videoPlayerOptions: VideoPlayerOptions(
          // Allows audio to mix with other app audio (doesn't cut music).
          mixWithOthers: false,
          // Allow video to play in highest available quality.
          allowBackgroundPlayback: false,
        ),
      );

      await _videoCtrl.initialize();

      if (!mounted) return;

      _videoCtrl.setLooping(false);
      _videoCtrl.setVolume(1.0);
      _videoCtrl.addListener(_onVideoProgress);

      setState(() => _videoReady = true);

      // Dismiss native splash NOW — video frame is painted instantly after this.
      FlutterNativeSplash.remove();

      await _videoCtrl.play();
    } catch (e) {
      debugPrint('Video init error: $e');
      FlutterNativeSplash.remove();
      _videoFinished = true;
      _maybeNavigate();
    }
  }

  void _onVideoProgress() {
    if (!_videoCtrl.value.isInitialized) return;
    final pos = _videoCtrl.value.position;
    final dur = _videoCtrl.value.duration;
    if (dur.inMilliseconds > 0 && pos >= dur && !_videoFinished) {
      _videoFinished = true;
      _maybeNavigate();
    }
  }

  Future<void> _loadApp() async {
    try {
      final results = await Future.wait([
        Future.delayed(const Duration(milliseconds: 1500)),
        ref.read(savedSpaceIdProvider.future),
        OnboardingService.isOnboardingDone(),
      ]);

      if (!mounted) return;
      final savedSpaceId = results[1] as String?;
      final onboardingDone = results[2] as bool;

      if (!onboardingDone) {
        // Brand-new user — show onboarding slides
        _destination = '/onboarding';
      } else if (savedSpaceId != null) {
        ref.read(activeSpaceIdProvider.notifier).state = savedSpaceId;
        _destination = '/home';
      } else {
        _destination = '/';
      }

      _appReady = true;
      _maybeNavigate();
    } catch (e, st) {
      debugPrint('App load error: $e\n$st');
      _destination = '/';
      _appReady = true;
      _maybeNavigate();
    }
  }

  /// Navigate only when BOTH the video is done AND the app is initialised.
  void _maybeNavigate() {
    if (!_appReady || !_videoFinished) return;
    if (!mounted) return;
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    context.go(_destination);
  }

  @override
  void dispose() {
    if (_videoReady) {
      _videoCtrl.removeListener(_onVideoProgress);
      _videoCtrl.dispose();
    }
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_videoReady) return const SizedBox.shrink();

    final size = MediaQuery.of(context).size;
    final videoAspect = _videoCtrl.value.aspectRatio;
    final screenAspect = size.width / size.height;

    // Compute scale so video covers the screen edge-to-edge (cover behaviour)
    // without relying on FittedBox which can cause visual softness.
    double scaleX = 1.0;
    double scaleY = 1.0;
    if (videoAspect > screenAspect) {
      // Video is wider than screen — fit height, let width overflow.
      scaleX = videoAspect / screenAspect;
    } else {
      // Video is taller than screen — fit width, let height overflow.
      scaleY = screenAspect / videoAspect;
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: ClipRect(
        child: OverflowBox(
          maxWidth: size.width * scaleX,
          maxHeight: size.height * scaleY,
          child: AspectRatio(
            aspectRatio: videoAspect,
            child: VideoPlayer(_videoCtrl),
          ),
        ),
      ),
    );
  }
}

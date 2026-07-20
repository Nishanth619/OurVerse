import 'dart:convert';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../data/services/notification_service.dart';
import '../../data/stream_repository.dart';


// ─────────────────────────────────────────────────────────────────────────────
// Agora App ID — console.agora.io (Testing mode = no token needed)
// ─────────────────────────────────────────────────────────────────────────────
const _agoraAppId = '9e7e99c6c83b46b1b8d7c6ac5fd10d9c';

enum _ShareMode { camera, screen }

/// Full streaming screen — supports both camera and screen share.
/// The host can toggle between modes live without ending the stream.
///
/// [isHost]      true  = broadcasting (start capture + publish)
///               false = viewing partner's stream (subscribe only)
/// [streamType]  initial mode: 'camera' | 'screen'
class StreamScreen extends ConsumerStatefulWidget {
  final String spaceId;
  final String deviceId;
  final String partnerId;
  final bool isHost;
  final String streamType;

  const StreamScreen({
    super.key,
    required this.spaceId,
    required this.deviceId,
    required this.partnerId,
    required this.isHost,
    this.streamType = 'camera',
  });

  @override
  ConsumerState<StreamScreen> createState() => _StreamScreenState();
}

class _StreamScreenState extends ConsumerState<StreamScreen> {
  late final RtcEngine _engine;
  late final StreamRepository _repo;

  bool _engineReady = false;
  bool _isMuted = false;
  bool _isCameraOff = false;
  bool _isFrontCamera = true;
  int? _remoteUid;
  bool _streamEnded = false;
  bool _cleaned = false; // guard against double-cleanup

  // Current share mode — can be switched live
  late _ShareMode _shareMode;

  // Agora UID derived from deviceId hash (unique per device, stable)
  int get _myUid => widget.deviceId.hashCode.abs() % 100000 + 1;

  @override
  void initState() {
    super.initState();
    _shareMode = widget.streamType == 'screen' ? _ShareMode.screen : _ShareMode.camera;
    _repo = StreamRepository();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    // Keep screen awake for BOTH host (sharing) and viewer (watching)
    WakelockPlus.enable();
    _initAgora();
  }

  @override
  void dispose() {
    // Use unawaited fire-and-forget — dispose() is synchronous.
    // The _cleaned guard prevents double-release if _endStream() was called first.
    if (!_cleaned) _cleanup();
    // Release wake lock when leaving the stream screen
    WakelockPlus.disable();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  // ─── Agora init ───────────────────────────────────────────────────────────

  Future<void> _initAgora() async {
    // Host needs camera + mic; viewer only needs mic
    if (widget.isHost) {
      await [Permission.camera, Permission.microphone].request();
    } else {
      await Permission.microphone.request();
    }

    _engine = createAgoraRtcEngine();
    await _engine.initialize(RtcEngineContext(appId: _agoraAppId));

    _engine.registerEventHandler(RtcEngineEventHandler(
      onJoinChannelSuccess: (connection, elapsed) {
        debugPrint('[Stream] Joined channel: ${connection.channelId}');
        if (mounted) setState(() {});
      },
      onUserJoined: (connection, remoteUid, elapsed) {
        debugPrint('[Stream] Partner joined uid=$remoteUid');
        if (mounted) setState(() => _remoteUid = remoteUid);
      },
      onUserOffline: (connection, remoteUid, reason) {
        debugPrint('[Stream] Partner left uid=$remoteUid reason=$reason');
        if (mounted) setState(() => _remoteUid = null);
        if (!widget.isHost) _handleStreamEnded();
      },
      // Fires when the remote video track changes state — catches screen share
      // becoming available even when the host joined AFTER the viewer.
      onRemoteVideoStateChanged: (connection, remoteUid, state, reason, elapsed) {
        debugPrint('[Stream] Remote video state uid=$remoteUid state=$state');
        if ((state == RemoteVideoState.remoteVideoStateDecoding ||
                state == RemoteVideoState.remoteVideoStateStarting) &&
            mounted) {
          setState(() => _remoteUid = remoteUid);
        }
      },
      onError: (err, msg) => debugPrint('[Stream] Error $err: $msg'),
    ));

    // Enable video for both roles
    await _engine.enableVideo();

    // Viewer does not broadcast — disable local video/audio capture to save battery
    if (!widget.isHost) {
      await _engine.enableLocalVideo(false);
      await _engine.enableLocalAudio(false);
    }

    // Set role
    await _engine.setClientRole(
      role: widget.isHost
          ? ClientRoleType.clientRoleBroadcaster
          : ClientRoleType.clientRoleAudience,
    );

    // Fetch token from our Vercel backend server
    String token = '';
    try {
      final user = FirebaseAuth.instance.currentUser;
      final idToken = await user?.getIdToken();
      if (idToken != null) {
        final response = await http.post(
          Uri.parse('https://closerbackend-1.vercel.app/api/agora_token'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $idToken',
          },
          body: jsonEncode({
            'channelName': widget.spaceId,
            'uid': _myUid,
          }),
        );
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          token = data['token'] ?? '';
          debugPrint('[Stream] Got token from server: ${token.substring(0, 10)}...');
        } else {
          debugPrint('[Stream] Token server returned ${response.statusCode}: ${response.body}');
        }
      }
    } catch (e) {
      debugPrint('[Stream] Failed to fetch token, continuing without: $e');
    }

    await _engine.joinChannel(
      token: token,
      channelId: widget.spaceId,
      uid: _myUid,
      options: ChannelMediaOptions(
        channelProfile: ChannelProfileType.channelProfileLiveBroadcasting,
        clientRoleType: widget.isHost
            ? ClientRoleType.clientRoleBroadcaster
            : ClientRoleType.clientRoleAudience,
        // HOST: join with camera track off initially — we switch to screen
        // AFTER capture is started to avoid the partner seeing a black screen.
        publishCameraTrack: widget.isHost && _shareMode == _ShareMode.camera,
        publishMicrophoneTrack: widget.isHost,
        publishScreenTrack: false,
        publishScreenCaptureVideo: false,
        publishScreenCaptureAudio: false,
        // VIEWER: MUST explicitly subscribe to video and audio.
        // In live broadcasting profile, audience does NOT auto-subscribe —
        // without these flags the partner sees a permanent black screen.
        autoSubscribeVideo: !widget.isHost,
        autoSubscribeAudio: !widget.isHost,
      ),
    );

    // Make UI ready
    if (mounted) setState(() => _engineReady = true);

    // Now start the appropriate capture mode
    if (widget.isHost && _shareMode == _ShareMode.screen) {
      // 1. Start screen capture FIRST (so there's actual content to stream)
      await _startScreenCapture();
      // 2. Small wait for the capture pipeline to warm up
      await Future.delayed(const Duration(milliseconds: 500));
      // 3. NOW tell Agora to publish the screen track (not before!)
      await _engine.updateChannelMediaOptions(const ChannelMediaOptions(
        publishCameraTrack: false,
        publishMicrophoneTrack: true,
        publishScreenTrack: true,
        publishScreenCaptureVideo: true,
        publishScreenCaptureAudio: true,
      ));
      // 4. Show persistent notification so host knows screen is being shared
      await _showScreenShareNotification();
    } else if (widget.isHost && _shareMode == _ShareMode.camera) {
      await _engine.startPreview();
    }

    // Signal to Firebase that stream is live
    if (widget.isHost) {
      await _repo.startStream(
        spaceId: widget.spaceId,
        hostId: widget.deviceId,
        streamType: widget.streamType,
      );

      // Push notification to partner
      try {
        await NotificationService.pingPartnerViaVercel('📺', widget.partnerId);
      } catch (_) {}
    }
  }

  // ─── Screen capture ───────────────────────────────────────────────────────

  Future<void> _startScreenCapture() async {
    await _engine.startScreenCapture(
      const ScreenCaptureParameters2(
        captureAudio: true,
        captureVideo: true,
        videoParams: ScreenVideoParameters(
          dimensions: VideoDimensions(width: 1280, height: 720),
          frameRate: 15,
          bitrate: 1000,
        ),
        audioParams: ScreenAudioParameters(
          sampleRate: 16000,
          channels: 2,
          captureSignalVolume: 100,
        ),
      ),
    );
  }

  Future<void> _stopScreenCapture() async {
    await _engine.stopScreenCapture();
  }

  // ─── Toggle between camera and screen share ────────────────────────────────

  Future<void> _toggleShareMode() async {
    if (_shareMode == _ShareMode.camera) {
      // Switch TO screen share
      await _engine.stopPreview();
      await _startScreenCapture();
      await _engine.updateChannelMediaOptions(const ChannelMediaOptions(
        publishCameraTrack: false,
        publishMicrophoneTrack: true,
        publishScreenTrack: true,
        publishScreenCaptureVideo: true,
        publishScreenCaptureAudio: true,
      ));
      setState(() => _shareMode = _ShareMode.screen);

      // Update Firebase so partner sees the mode change
      await _repo.startStream(
        spaceId: widget.spaceId,
        hostId: widget.deviceId,
        streamType: 'screen',
      );
      // Show persistent notification — host needs to know they're sharing
      await _showScreenShareNotification();
    } else {
      // Switch TO camera
      await _stopScreenCapture();
      await _engine.startPreview();
      await _engine.updateChannelMediaOptions(const ChannelMediaOptions(
        publishCameraTrack: true,
        publishMicrophoneTrack: true,
        publishScreenTrack: false,
        publishScreenCaptureVideo: false,
        publishScreenCaptureAudio: false,
      ));
      setState(() => _shareMode = _ShareMode.camera);
      // Cancel the sharing notification when back on camera
      await _cancelScreenShareNotification();

      await _repo.startStream(
        spaceId: widget.spaceId,
        hostId: widget.deviceId,
        streamType: 'camera',
      );
    }
  }

  // ─── Cleanup ──────────────────────────────────────────────────────────────

  // ─── Persistent "Sharing" notification for host ──────────────────────────

  static const _shareNotifId = 9901;

  Future<void> _showScreenShareNotification() async {
    final plugin = FlutterLocalNotificationsPlugin();
    const androidInit = AndroidInitializationSettings('@drawable/ic_launcher');
    await plugin.initialize(const InitializationSettings(android: androidInit));

    final androidImpl = plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await androidImpl?.createNotificationChannel(
      const AndroidNotificationChannel(
        'stream_share_active',
        'Screen Sharing Active',
        description: 'Shown while you are sharing your screen',
        importance: Importance.low,
        playSound: false,
        enableVibration: false,
      ),
    );

    await plugin.show(
      _shareNotifId,
      '📺 You are sharing your screen',
      'Your partner is watching your screen live. Tap to return to OurVerse.',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'stream_share_active',
          'Screen Sharing Active',
          importance: Importance.low,
          priority: Priority.low,
          ongoing: true,           // Cannot be dismissed by swipe
          autoCancel: false,
          icon: '@drawable/ic_launcher',
          color: Color(0xFFE8647A),
          showWhen: true,
          playSound: false,
          enableVibration: false,
        ),
      ),
    );
  }

  Future<void> _cancelScreenShareNotification() async {
    final plugin = FlutterLocalNotificationsPlugin();
    await plugin.cancel(_shareNotifId);
  }

  // ─── Cleanup ──────────────────────────────────────────────────────────────

  Future<void> _cleanup() async {
    if (_cleaned) return; // prevent double-release
    _cleaned = true;
    if (widget.isHost) {
      if (_shareMode == _ShareMode.screen) {
        await _engine.stopScreenCapture();
        await _cancelScreenShareNotification();
      }
      await _repo.endStream(widget.spaceId);
    }
    await _engine.leaveChannel();
    await _engine.release();
  }

  void _handleStreamEnded() {
    if (_streamEnded) return;
    _streamEnded = true;
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Stream ended by your partner'),
          backgroundColor: AppTheme.primary,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) Navigator.of(context).pop();
      });
    }
  }

  // ─── Controls ─────────────────────────────────────────────────────────────

  Future<void> _toggleMute() async {
    await _engine.muteLocalAudioStream(!_isMuted);
    setState(() => _isMuted = !_isMuted);
  }

  Future<void> _toggleCamera() async {
    await _engine.muteLocalVideoStream(!_isCameraOff);
    setState(() => _isCameraOff = !_isCameraOff);
  }

  Future<void> _switchCamera() async {
    await _engine.switchCamera();
    setState(() => _isFrontCamera = !_isFrontCamera);
  }

  Future<void> _endStream() async {
    await _cleanup(); // _cleaned flag ensures dispose() won't double-release
    if (mounted) Navigator.of(context).pop();
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SizedBox.expand(
        child: Stack(
          children: [
          // ── Video / Screen area ──────────────────────────────────────────
          if (_engineReady) _buildVideoArea() else _buildLoadingState(),

          // ── Top bar ─────────────────────────────────────────────────────
          _buildTopBar(),

          // ── Bottom controls ──────────────────────────────────────────────
          if (widget.isHost)
            _buildHostControls()
          else if (_remoteUid != null)
            _buildViewerControls(),

          // ── Viewer: waiting for host ─────────────────────────────────────
          if (!widget.isHost && _remoteUid == null && _engineReady)
            _buildWaitingForHost(),
        ],
      ),
    ),
    );
  }

  // ─── Video area ───────────────────────────────────────────────────────────

  Widget _buildVideoArea() {
    if (widget.isHost) {
      if (_shareMode == _ShareMode.screen) {
        // While screen sharing, show an overlay indicator —
        // the host's own screen IS what's being streamed.
        return const SizedBox.shrink();
      }
      // Camera mode: show local preview
      return SizedBox.expand(
        child: _isCameraOff
            ? const ColoredBox(
                color: Color(0xFF1A1A2E),
                child: Center(
                  child: Icon(Icons.videocam_off, color: Colors.white38, size: 64),
                ),
              )
            : AgoraVideoView(
                controller: VideoViewController(
                  rtcEngine: _engine,
                  canvas: const VideoCanvas(uid: 0), // 0 = local camera
                ),
              ),
      );
    }

    // Viewer side — remote stream (camera OR screen, same remote UID)
    if (_remoteUid == null) return const SizedBox.shrink();
    return SizedBox.expand(
      child: AgoraVideoView(
        controller: VideoViewController.remote(
          rtcEngine: _engine,
          canvas: VideoCanvas(uid: _remoteUid),
          connection: RtcConnection(channelId: widget.spaceId),
        ),
      ),
    );
  }

  Widget _buildLoadingState() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(color: AppTheme.primary),
          SizedBox(height: 16),
          Text('Connecting...', style: TextStyle(color: Colors.white70, fontSize: 16)),
        ],
      ),
    );
  }

  // ─── Top bar ─────────────────────────────────────────────────────────────

  Widget _buildTopBar() {
    final modeLabel = _shareMode == _ShareMode.screen ? 'Screen Share' : 'Camera';
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            // LIVE badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.redAccent.shade700,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8, height: 8,
                    decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 6),
                  const Text('LIVE',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800,
                          fontSize: 12, letterSpacing: 1)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Mode label
            if (widget.isHost)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white24),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _shareMode == _ShareMode.screen ? Icons.screen_share : Icons.videocam,
                      color: Colors.white70, size: 14,
                    ),
                    const SizedBox(width: 5),
                    Text(modeLabel,
                        style: const TextStyle(color: Colors.white70, fontSize: 12)),
                  ],
                ),
              ),
            const Spacer(),
            // End/Leave button
            GestureDetector(
              onTap: _endStream,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white24),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.call_end, color: Colors.redAccent, size: 18),
                    const SizedBox(width: 6),
                    Text(widget.isHost ? 'End' : 'Leave',
                        style: const TextStyle(color: Colors.white, fontSize: 14)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Host controls ────────────────────────────────────────────────────────

  Widget _buildHostControls() {
    final isScreenMode = _shareMode == _ShareMode.screen;
    return Positioned(
      bottom: 0, left: 0, right: 0,
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [Colors.black87, Colors.transparent],
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Screen share active indicator
            if (isScreenMode)
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white24),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.screen_share, color: Colors.greenAccent, size: 18),
                    SizedBox(width: 8),
                    Text(
                      'Your screen is being shared',
                      style: TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                  ],
                ),
              ),

            // Control row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _ControlButton(
                  icon: _isMuted ? Icons.mic_off : Icons.mic,
                  label: _isMuted ? 'Unmute' : 'Mute',
                  onTap: _toggleMute,
                  active: !_isMuted,
                ),
                // Camera on/off (only in camera mode)
                if (!isScreenMode)
                  _ControlButton(
                    icon: _isCameraOff ? Icons.videocam_off : Icons.videocam,
                    label: _isCameraOff ? 'Cam Off' : 'Cam On',
                    onTap: _toggleCamera,
                    active: !_isCameraOff,
                  ),
                // Flip camera (only in camera mode)
                if (!isScreenMode)
                  _ControlButton(
                    icon: Icons.flip_camera_android,
                    label: 'Flip',
                    onTap: _switchCamera,
                    active: true,
                  ),
                // Toggle screen/camera
                _ControlButton(
                  icon: isScreenMode ? Icons.videocam : Icons.screen_share,
                  label: isScreenMode ? 'Camera' : 'Share Screen',
                  onTap: _toggleShareMode,
                  active: true,
                  highlight: !isScreenMode, // highlight "Share Screen" to draw attention
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ─── Viewer controls (volume indicator etc.) ──────────────────────────────

  Widget _buildViewerControls() {
    return Positioned(
      bottom: 0, left: 0, right: 0,
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 36),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [Colors.black87, Colors.transparent],
          ),
        ),
        child: const Center(
          child: Text(
            'Watching your partner\'s stream',
            style: TextStyle(color: Colors.white54, fontSize: 13),
          ),
        ),
      ),
    );
  }

  Widget _buildWaitingForHost() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.live_tv, color: Colors.white38, size: 64),
          SizedBox(height: 16),
          Text(
            'Waiting for your partner\nto start streaming...',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white60, fontSize: 16, height: 1.5),
          ),
        ],
      ),
    );
  }
}

// ─── Control Button ───────────────────────────────────────────────────────────

class _ControlButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;
  final bool highlight;

  const _ControlButton({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.active,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    final bg = !active
        ? Colors.red.withValues(alpha: 0.3)
        : highlight
            ? AppTheme.primary.withValues(alpha: 0.35)
            : Colors.white.withValues(alpha: 0.15);
    final border = !active
        ? Colors.red.withValues(alpha: 0.5)
        : highlight
            ? AppTheme.primary.withValues(alpha: 0.6)
            : Colors.white24;

    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: bg,
              shape: BoxShape.circle,
              border: Border.all(color: border),
            ),
            child: Icon(icon, color: Colors.white, size: 26),
          ),
          const SizedBox(height: 8),
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11)),
        ],
      ),
    );
  }
}

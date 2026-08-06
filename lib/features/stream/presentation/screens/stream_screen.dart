import 'dart:async';
import 'dart:convert';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../data/stream_model.dart';
import '../../data/stream_repository.dart';
import '../../providers/stream_providers.dart';
import '../../../vibe/presentation/widgets/streaming_timer_gate.dart';

const _bg = Color(0xFF1E1F22);
const _card = Color(0xFF2B2D31);
const _controlBar = Color(0xFF232428);
const _blurple = Color(0xFF5865F2);
const _green = Color(0xFF57F287);
const _red = Color(0xFFED4245);
const _textPrimary = Color(0xFFFFFFFF);
const _textSecondary = Color(0xFFB5BAC1);

class StreamScreen extends ConsumerStatefulWidget {
  final String spaceId;
  final String deviceId;
  final String partnerId;
  final bool isHost; // kept for backward compat
  final String streamType; // kept for backward compat

  const StreamScreen({
    super.key,
    required this.spaceId,
    required this.deviceId,
    required this.partnerId,
    required this.isHost,
    required this.streamType,
  });

  @override
  ConsumerState<StreamScreen> createState() => _StreamScreenState();
}

class _StreamScreenState extends ConsumerState<StreamScreen> {
  static RtcEngineEx? _engine;
  static RtcConnection? _screenShareConnection; // secondary connection for screen share

  bool _engineReady = false;
  bool _isMuted = false;
  bool _isCameraOn = false;
  bool _isScreenSharing = false;
  bool _isScreenShareExpanded = false;
  bool _isCameraExpanded = false;
  int? _expandedUid;

  final Map<int, bool> _remoteUsers = {}; // uid -> hasCameraOn
  int? _remoteScreenUid;


  // Use a stable hash of spaceId+deviceId so each device always gets
  // the same UID in the same channel — no collision, no dependency on partnerId.
  static int _stableUid(String spaceId, String deviceId) {
    final combined = '$spaceId:$deviceId';
    var hash = 0;
    for (final c in combined.codeUnits) {
      hash = (hash * 31 + c) & 0x7FFFFFFF;
    }
    return (hash % 99998) + 1; // always 1..99999
  }

  int get _myUid => _stableUid(widget.spaceId, widget.deviceId);
  int get _partnerUid => widget.partnerId.isNotEmpty
      ? _stableUid(widget.spaceId, widget.partnerId)
      : (_myUid == 1 ? 2 : 1); // safe fallback
  int get _myScreenUid => _myUid + 100000;

  late final StreamRepository _repo;
  late StreamSubscription<List<RoomMember>> _membersSub;
  List<RoomMember> _members = [];

  final String _appId = '9e7e99c6c83b46b1b8d7c6ac5fd10d9c';
  final String _tokenUrl = 'https://closerbackend-1.vercel.app/api/agora_token';

  @override
  void initState() {
    super.initState();
    _repo = ref.read(streamRepositoryProvider);
    WakelockPlus.enable();

    // 1. Join Firebase Room
    _repo.joinRoom(
      spaceId: widget.spaceId,
      deviceId: widget.deviceId,
      displayName: 'You',
    );

    // Watch room members
    _membersSub = _repo.watchRoomMembers(widget.spaceId).listen((members) {
      if (mounted) setState(() => _members = members);
    });

    // Notify state provider
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(screenShareStateProvider.notifier).joinRoom(
        spaceId: widget.spaceId,
        deviceId: widget.deviceId,
        partnerId: widget.partnerId,
      );
    });

    // Send notification (removed as sendPushNotification isn't implemented)

    _initAgora();
  }

  @override
  void dispose() {
    _membersSub.cancel();
    // Do not dispose Agora here. We want it to persist if user navigates away.
    // Agora cleanup happens ONLY on explicit disconnect.
    super.dispose();
  }

  Future<String> _fetchToken(int uid) async {
    try {
      final url = '$_tokenUrl?channelName=${widget.spaceId}&uid=$uid';
      debugPrint('[Stream] Fetching token: $url');
      final response = await http.get(Uri.parse(url));
      debugPrint('[Stream] Token status: ${response.statusCode}');
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['token'] as String;
      } else {
        debugPrint('[Stream] Token error body: ${response.body}');
      }
    } catch (e) {
      debugPrint('[Stream] Token fetch error: $e');
    }
    return '';
  }

  Future<void> _initAgora() async {
    debugPrint('[Stream] myUid=$_myUid partnerUid=$_partnerUid spaceId=${widget.spaceId} partnerId=${widget.partnerId}');
    await [Permission.microphone, Permission.camera].request();

    if (_engine == null) {
      _engine = createAgoraRtcEngineEx();
      await _engine!.initialize(RtcEngineContext(appId: _appId));
    }

    // Always re-register event handlers (important if engine was reused from a previous session)
    _engine!.registerEventHandler(
      RtcEngineEventHandler(
        onJoinChannelSuccess: (RtcConnection connection, int elapsed) {
          debugPrint("local user ${connection.localUid} joined");
          if (mounted) setState(() {});
        },
        onUserJoined: (RtcConnection connection, int remoteUid, int elapsed) {
          debugPrint("remote user $remoteUid joined");
          if (mounted) setState(() {
            if (remoteUid > 100000) {
              _remoteScreenUid = remoteUid;
            } else {
              _remoteUsers[remoteUid] = false;
            }
          });
        },
        onUserOffline: (RtcConnection connection, int remoteUid, UserOfflineReasonType reason) {
          debugPrint("remote user $remoteUid left");
          if (mounted) setState(() {
            if (remoteUid > 100000) {
              if (_remoteScreenUid == remoteUid) {
                _remoteScreenUid = null;
                _isScreenShareExpanded = false;
              }
            } else {
              _remoteUsers.remove(remoteUid);
              if (_expandedUid == remoteUid) {
                _isCameraExpanded = false;
                _expandedUid = null;
              }
            }
          });
        },
        onRemoteVideoStateChanged: (RtcConnection connection, int remoteUid, RemoteVideoState state, RemoteVideoStateReason reason, int elapsed) {
          if (remoteUid < 100000 && mounted) {
            setState(() {
              _remoteUsers[remoteUid] = (state == RemoteVideoState.remoteVideoStateStarting || state == RemoteVideoState.remoteVideoStateDecoding);
            });
          }
        },
      ),
    );

    await _engine!.enableAudio();
    await _engine!.enableVideo();
    await _engine!.setClientRole(role: ClientRoleType.clientRoleBroadcaster);

    final token = await _fetchToken(_myUid);
    await _engine!.joinChannel(
      token: token,
      channelId: widget.spaceId,
      uid: _myUid,
      options: const ChannelMediaOptions(
        publishMicrophoneTrack: true,
        publishCameraTrack: false,
        clientRoleType: ClientRoleType.clientRoleBroadcaster,
      ),
    );

    if (mounted) {
      setState(() {
        _engineReady = true;
      });
    }
  }

  Future<void> _toggleMic() async {
    if (_engine == null) return;
    setState(() => _isMuted = !_isMuted);
    await _engine!.muteLocalAudioStream(_isMuted);
    await _repo.updateMemberState(spaceId: widget.spaceId, deviceId: widget.deviceId, isMicOn: !_isMuted);
  }

  Future<void> _toggleCamera() async {
    if (_engine == null) return;
    if (!_isCameraOn) {
      await _engine!.startPreview();
      await _engine!.updateChannelMediaOptions(const ChannelMediaOptions(publishCameraTrack: true));
      await _repo.updateMemberState(spaceId: widget.spaceId, deviceId: widget.deviceId, isCameraOn: true);
    } else {
      await _engine!.stopPreview();
      await _engine!.updateChannelMediaOptions(const ChannelMediaOptions(publishCameraTrack: false));
      await _repo.updateMemberState(spaceId: widget.spaceId, deviceId: widget.deviceId, isCameraOn: false);
    }
    setState(() => _isCameraOn = !_isCameraOn);
  }

  Future<void> _startScreenShare() async {
    if (_engine == null) return;
    String screenToken = await _fetchToken(_myScreenUid);

    await _engine!.startScreenCapture(const ScreenCaptureParameters2(captureVideo: true, captureAudio: true));
    await Future.delayed(const Duration(milliseconds: 500));

    _screenShareConnection = RtcConnection(channelId: widget.spaceId, localUid: _myScreenUid);
    await _engine!.joinChannelEx(
      token: screenToken,
      connection: _screenShareConnection!,
      options: const ChannelMediaOptions(
        publishScreenTrack: true,
        publishScreenCaptureVideo: true,
        publishScreenCaptureAudio: true,
        publishCameraTrack: false,
        publishMicrophoneTrack: false,
        autoSubscribeVideo: false,
        autoSubscribeAudio: false,
      ),
    );

    setState(() => _isScreenSharing = true);
    await _repo.updateMemberState(spaceId: widget.spaceId, deviceId: widget.deviceId, isScreenSharing: true);
    ref.read(screenShareStateProvider.notifier).startSharing(
      spaceId: widget.spaceId, deviceId: widget.deviceId, partnerId: widget.partnerId,
    );
    await _showScreenShareNotification();
  }

  Future<void> _stopScreenShare() async {
    if (_engine == null) return;
    await _engine!.stopScreenCapture();
    if (_screenShareConnection != null) {
      await _engine!.leaveChannelEx(connection: _screenShareConnection!);
      _screenShareConnection = null;
    }
    setState(() {
      _isScreenSharing = false;
      _isScreenShareExpanded = false;
    });
    await _repo.updateMemberState(spaceId: widget.spaceId, deviceId: widget.deviceId, isScreenSharing: false);
    ref.read(screenShareStateProvider.notifier).stopSharing();
    await _cancelScreenShareNotification();
  }

  Future<void> _disconnect() async {
    if (_isScreenSharing) {
      await _stopScreenShare();
    }
    await _repo.leaveRoom(spaceId: widget.spaceId, deviceId: widget.deviceId);
    
    if (_engine != null) {
      await _engine!.leaveChannel();
      await _engine!.release();
      _engine = null;
    }
    
    ref.read(screenShareStateProvider.notifier).leaveRoom();
    WakelockPlus.disable();
    if (mounted) context.pop();
  }

  Future<void> _showScreenShareNotification() async {
    final plugin = FlutterLocalNotificationsPlugin();
    const androidDetails = AndroidNotificationDetails(
      'screen_share',
      'Screen Sharing',
      channelDescription: 'Ongoing screen share notification',
      importance: Importance.low,
      priority: Priority.low,
      ongoing: true,
      autoCancel: false,
      icon: '@mipmap/ic_launcher',
    );
    const iosDetails = DarwinNotificationDetails();
    const details = NotificationDetails(android: androidDetails, iOS: iosDetails);
    await plugin.show(9901, 'Screen Share Active', 'You are sharing your screen', details);
  }

  Future<void> _cancelScreenShareNotification() async {
    final plugin = FlutterLocalNotificationsPlugin();
    await plugin.cancel(9901);
  }

  @override
  Widget build(BuildContext context) {
    if (!_engineReady) {
      return const Scaffold(
        backgroundColor: _bg,
        body: Center(child: CircularProgressIndicator(color: _blurple)),
      );
    }

    return StreamingTimerGate(
      label: 'Private Room',
      child: Scaffold(
        backgroundColor: _bg,
        body: Stack(
          children: [
            Column(
              children: [
                _buildTopBar(),
                Expanded(child: _buildMainArea()),
                _buildBottomControlBar(),
              ],
            ),
            if (_isScreenShareExpanded && _remoteScreenUid != null) _buildFullscreenScreenShare(),
            if (_isCameraExpanded && _expandedUid != null) _buildFullscreenCamera(),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Container(
      color: _card,
      height: 64, // Made slightly taller to fit safe area better
      padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top, left: 8, right: 16),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: _textPrimary),
            onPressed: () => context.pop(),
          ),
          Expanded(
            child: Text(
              'Private Room',
              style: GoogleFonts.inter(
                color: _textPrimary,
                fontWeight: FontWeight.w600,
                fontSize: 16,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          Row(
            children: [
              const Icon(Icons.group, color: _textSecondary, size: 16),
              const SizedBox(width: 4),
              Text(
                '${_members.length}',
                style: GoogleFonts.inter(color: _textSecondary, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMainArea() {
    bool hasScreenShare = _members.any((m) => m.isScreenSharing) && _remoteScreenUid != null;
    
    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: _buildMemberGrid(),
          ),
        ),
        if (hasScreenShare) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: _buildScreenShareCard(),
          ),
        ],
      ],
    );
  }

  Widget _buildMemberGrid() {
    // Find partner's Firebase state (for mic/camera/screen status badges)
    final partnerMember = _members.where((m) => m.deviceId != widget.deviceId).firstOrNull;
    final partnerInRoom = partnerMember != null || _remoteUsers.containsKey(_partnerUid);

    final tiles = [
      // Self tile — always show
      _buildMemberTile(
        uid: 0, // 0 = local preview in Agora
        displayName: 'You',
        isCameraOn: _isCameraOn,
        isMicOn: !_isMuted,
        isScreenSharing: _isScreenSharing,
      ),
      // Partner tile — show if they're in Firebase room OR Agora
      if (partnerInRoom)
        _buildMemberTile(
          uid: _partnerUid, // always 1 or 2 — deterministic, no collision
          displayName: partnerMember?.displayName ?? 'Partner',
          isCameraOn: partnerMember?.isCameraOn ?? (_remoteUsers[_partnerUid] ?? false),
          isMicOn: partnerMember?.isMicOn ?? true,
          isScreenSharing: partnerMember?.isScreenSharing ?? false,
        ),
    ];

    return GridView.count(
      crossAxisCount: 2,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 0.75,
      children: tiles,
    );
  }

  Widget _buildMemberTile({
    required int uid,
    required String displayName,
    required bool isCameraOn,
    required bool isMicOn,
    required bool isScreenSharing,
  }) {
    return GestureDetector(
      onTap: () {
        if (isCameraOn) {
          setState(() {
            _isCameraExpanded = true;
            _expandedUid = uid;
          });
        }
      },
      child: Container(
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(12),
        ),
        clipBehavior: Clip.hardEdge,
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (isCameraOn && uid >= 0)
              SizedBox.expand(
                child: uid == 0 
                  ? AgoraVideoView(controller: VideoViewController(rtcEngine: _engine!, canvas: const VideoCanvas(uid: 0)))
                  : AgoraVideoView(controller: VideoViewController.remote(rtcEngine: _engine!, canvas: VideoCanvas(uid: uid), connection: RtcConnection(channelId: widget.spaceId))),
              )
            else
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: const BoxDecoration(
                      color: _bg,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      displayName.isNotEmpty ? displayName[0].toUpperCase() : '?',
                      style: GoogleFonts.inter(fontSize: 24, fontWeight: FontWeight.bold, color: _textPrimary),
                    ),
                  ),
                ],
              ),
            
            Positioned(
              bottom: 8,
              left: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isMicOn ? Icons.mic : Icons.mic_off,
                      color: isMicOn ? _green : _red,
                      size: 14,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      displayName,
                      style: GoogleFonts.inter(color: _textPrimary, fontSize: 12, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
            ),

            if (isScreenSharing)
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: _red,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.monitor, color: _textPrimary, size: 14),
                ),
              )
          ],
        ),
      ),
    );
  }

  Widget _buildScreenShareCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _green, width: 2),
      ),
      child: Row(
        children: [
          const Icon(Icons.monitor, color: _green, size: 28),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              'Partner is sharing their screen',
              style: GoogleFonts.inter(color: _textPrimary, fontWeight: FontWeight.w500),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() => _isScreenShareExpanded = true);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: _blurple,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Watch', style: TextStyle(color: _textPrimary, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomControlBar() {
    return Container(
      color: _controlBar,
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom + 16, top: 16, left: 16, right: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildControlButton(
            icon: _isMuted ? Icons.mic_off : Icons.mic,
            label: _isMuted ? 'Unmute' : 'Mute',
            isActive: !_isMuted,
            activeColor: _green,
            inactiveColor: _red, // red for muted
            onTap: _toggleMic,
          ),
          _buildControlButton(
            icon: Icons.videocam,
            label: 'Camera',
            isActive: _isCameraOn,
            activeColor: _blurple,
            inactiveColor: _card,
            onTap: _toggleCamera,
          ),
          _buildControlButton(
            icon: Icons.monitor,
            label: 'Share',
            isActive: _isScreenSharing,
            activeColor: _green,
            inactiveColor: _card,
            onTap: _isScreenSharing ? _stopScreenShare : _startScreenShare,
          ),
          _buildControlButton(
            icon: Icons.call_end,
            label: 'Leave',
            isActive: true,
            activeColor: _red, // Always red
            inactiveColor: _red,
            onTap: _disconnect,
          ),
        ],
      ),
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required String label,
    required bool isActive,
    required Color activeColor,
    required Color inactiveColor,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: isActive ? activeColor : inactiveColor,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: _textPrimary),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: GoogleFonts.inter(color: _textPrimary, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildFullscreenScreenShare() {
    return Positioned.fill(
      child: Container(
        color: Colors.black,
        child: Stack(
          children: [
            SizedBox.expand(
              child: AgoraVideoView(
                controller: VideoViewController.remote(
                  rtcEngine: _engine!,
                  canvas: VideoCanvas(uid: _remoteScreenUid!),
                  connection: RtcConnection(channelId: widget.spaceId),
                ),
              ),
            ),
            Positioned(
              top: MediaQuery.of(context).padding.top + 16,
              right: 16,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 32),
                onPressed: () => setState(() => _isScreenShareExpanded = false),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFullscreenCamera() {
    return Positioned.fill(
      child: Container(
        color: Colors.black,
        child: Stack(
          children: [
            SizedBox.expand(
              child: _expandedUid == 0
                ? AgoraVideoView(controller: VideoViewController(rtcEngine: _engine!, canvas: const VideoCanvas(uid: 0)))
                : AgoraVideoView(controller: VideoViewController.remote(rtcEngine: _engine!, canvas: VideoCanvas(uid: _expandedUid!), connection: RtcConnection(channelId: widget.spaceId))),
            ),
            Positioned(
              top: MediaQuery.of(context).padding.top + 16,
              right: 16,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 32),
                onPressed: () => setState(() {
                  _isCameraExpanded = false;
                  _expandedUid = null;
                }),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

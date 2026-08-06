import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:youtube_player_iframe/youtube_player_iframe.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../../data/vibe_models.dart';
import '../../data/vibe_repository.dart';
import '../../providers/vibe_providers.dart';
import '../widgets/streaming_timer_gate.dart';

// ─── Floating Emoji Model ─────────────────────────────────────────────────────

class _FloatingEmoji {
  final String emoji;
  final double x;
  final double startY;
  final int id;
  _FloatingEmoji({
    required this.emoji,
    required this.x,
    required this.startY,
    required this.id,
  });
}

// ─── Screen ───────────────────────────────────────────────────────────────────

/// Watch Together — YouTube sync screen.
///
/// One partner pastes a YouTube URL. The [YoutubePlayerController] is controlled
/// by writing play/pause/seek state to RTDB under spaces/{spaceId}/ytSync/session.
/// Both devices listen to that node and drive their local player accordingly.
///
/// Sync loop is prevented by the [_suppressBroadcast] flag: when we are applying
/// a remote update we temporarily ignore local controller state changes.
class YoutubeSyncScreen extends ConsumerStatefulWidget {
  final String spaceId;
  final String deviceId;
  final String partnerId;

  const YoutubeSyncScreen({
    super.key,
    required this.spaceId,
    required this.deviceId,
    required this.partnerId,
  });

  @override
  ConsumerState<YoutubeSyncScreen> createState() => _YoutubeSyncScreenState();
}

class _YoutubeSyncScreenState extends ConsumerState<YoutubeSyncScreen>
    with TickerProviderStateMixin {
  // ── YouTube player ──────────────────────────────────────────────────────────
  late final YoutubePlayerController _ytController;

  // ── Sync engine ─────────────────────────────────────────────────────────────
  int _serverTimeOffsetMs = 0;
  StreamSubscription<int>? _offsetSub;
  StreamSubscription<YtSyncSession?>? _sessionSub;
  StreamSubscription<VibeReaction>? _reactionSub;

  // Current video state (local cache to detect changes)
  String _loadedVideoId = '';
  bool _suppressBroadcast = false; // true while applying a remote RTDB update

  // ── UI state ────────────────────────────────────────────────────────────────
  final _urlController = TextEditingController();
  bool _loadingVideo = false;
  String? _loadError;
  String _currentTitle = '';
  bool _isPlaying = false;
  double _positionSec = 0;
  double _durationSec = 0;
  bool _isSeeking = false;

  // Position polling timer
  Timer? _positionTimer;

  // ── Emoji reactions ──────────────────────────────────────────────────────────
  final List<_FloatingEmoji> _floatingEmojis = [];
  int _emojiIdCounter = 0;
  static const _reactionEmojis = ['❤️', '🔥', '😍', '🎬', '✨', '😂', '💜', '👏'];

  // ── Helpers ──────────────────────────────────────────────────────────────────
  int get _serverNow =>
      DateTime.now().millisecondsSinceEpoch + _serverTimeOffsetMs;

  VibeRepository get _repo => ref.read(vibeRepositoryProvider);

  // ─────────────────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();

    _ytController = YoutubePlayerController(
      params: const YoutubePlayerParams(
        showControls: false,
        playsInline: true,
        showFullscreenButton: false,
        mute: false,
        loop: false,
        enableCaption: false,
        strictRelatedVideos: true,
      ),
    );

    _ytController.listen(_onYtControllerChange);

    _initSync();
  }

  Future<void> _initSync() async {
    // 1. Subscribe to RTDB server clock offset
    _offsetSub = _repo.watchServerTimeOffset().listen((offset) {
      _serverTimeOffsetMs = offset;
    });

    // 2. Subscribe to YouTube session stream
    _sessionSub = _repo.watchYtSession(widget.spaceId).listen(_onRemoteSession);

    // 3. Subscribe to emoji reactions
    _reactionSub = _repo.watchReactions(widget.spaceId).listen((reaction) {
      if (reaction.sentBy == widget.deviceId) return; // only partner reactions
      _spawnEmoji(reaction.emoji);
    });
  }

  // ── Remote session handler (RTDB → player) ──────────────────────────────────

  bool _handledInitialSession = false;

  Future<void> _onRemoteSession(YtSyncSession? session) async {
    if (session == null || !mounted) return;

    // On first load, BOTH partners (including the one who started the session)
    // should load the video. After the first load we skip our own events to
    // avoid feedback loops from our own play/pause broadcasts.
    final isOwnEvent = session.startedBy == widget.deviceId;
    if (isOwnEvent && _handledInitialSession) return;
    _handledInitialSession = true;

    _suppressBroadcast = true;

    try {
      // If video changed → load new video
      if (session.videoId != _loadedVideoId) {
        if (mounted) {
          setState(() {
            _loadedVideoId = session.videoId;
            _currentTitle = session.videoTitle;
            _loadingVideo = true;
          });
        }

        // Load the video directly into the controller
        await _ytController.loadVideoById(videoId: session.videoId);
        // Give the WebView time to start buffering
        await Future.delayed(const Duration(milliseconds: 1800));
        if (mounted) setState(() => _loadingVideo = false);
      }

      // Compute target position using server-clock-anchored math
      final targetPos = session.computePosition(_serverNow);
      final targetSec = targetPos.inMilliseconds / 1000.0;

      await _ytController.seekTo(seconds: targetSec, allowSeekAhead: true);

      if (session.isPlaying) {
        WakelockPlus.enable();
        await _ytController.playVideo();
      } else {
        WakelockPlus.disable();
        await _ytController.pauseVideo();
      }

      if (mounted) {
        setState(() {
          _isPlaying = session.isPlaying;
          _currentTitle = session.videoTitle;
          if (!_isSeeking) _positionSec = targetSec;
        });
      }
    } catch (e) {
      debugPrint('[YtSync] _onRemoteSession error: $e');
    }

    // Allow a window before re-enabling local event broadcasting
    await Future.delayed(const Duration(milliseconds: 600));
    _suppressBroadcast = false;
  }

  // ── Local controller listener (player → RTDB) ────────────────────────────────

  PlayerState? _lastBroadcastedState;

  void _onYtControllerChange(YoutubePlayerValue value) {
    if (_suppressBroadcast) return;
    if (!mounted) return;

    final state = value.playerState;

    // Only broadcast on actual state TRANSITIONS to avoid spamming RTDB
    if (state == _lastBroadcastedState) return;
    if (state != PlayerState.playing && state != PlayerState.paused) return;

    if (state == PlayerState.playing || state == PlayerState.paused) {
      if (state == PlayerState.playing) {
        WakelockPlus.enable();
      } else {
        WakelockPlus.disable();
      }
    }

    _lastBroadcastedState = state;

    _broadcastPlayState(isPlaying: state == PlayerState.playing);
  }

  Future<void> _broadcastPlayState({required bool isPlaying}) async {
    if (_loadedVideoId.isEmpty) return;
    final posMs = (_positionSec * 1000).round();
    try {
      await _repo.updateYtPlayState(
        spaceId: widget.spaceId,
        isPlaying: isPlaying,
        currentPositionMs: posMs,
        deviceId: widget.deviceId,
      );
    } catch (_) {}
  }

  // ── Position polling (updates UI seek bar) ───────────────────────────────────

  void _startPositionTimer() {
    _positionTimer?.cancel();
    _positionTimer =
        Timer.periodic(const Duration(milliseconds: 500), (_) async {
      if (!mounted || _isSeeking) return;
      try {
        final pos = await _ytController.currentTime;
        final dur = await _ytController.duration;
        if (mounted) {
          setState(() {
            _positionSec = pos;
            _durationSec = dur;
          });
        }
      } catch (_) {}
    });
  }

  // ── User actions ─────────────────────────────────────────────────────────────

  Future<void> _loadVideoFromUrl() async {
    final raw = _urlController.text.trim();
    if (raw.isEmpty) return;

    final videoId = YtSyncSession.extractVideoId(raw);
    if (videoId == null) {
      setState(() => _loadError = 'Could not find a YouTube video ID in that link. Try copying the URL directly from YouTube.');
      return;
    }

    setState(() {
      _loadingVideo = true;
      _loadError = null;
    });

    // Fetch title via free YouTube oEmbed API — no API key required
    String title = 'YouTube Video';
    try {
      final res = await http.get(
        Uri.parse(
            'https://www.youtube.com/oembed?url=https://www.youtube.com/watch?v=$videoId&format=json'),
      ).timeout(const Duration(seconds: 6));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        title = data['title'] as String? ?? title;
      }
    } catch (_) {}

    // Load in local player first
    _loadedVideoId = videoId;
    _suppressBroadcast = true;
    _ytController.loadVideoById(videoId: videoId);
    WakelockPlus.enable();

    // Write session to RTDB so partner's player also loads
    try {
      await _repo.startYtSession(
        widget.spaceId,
        YtSyncSession(
          videoId: videoId,
          videoTitle: title,
          isPlaying: true,
          startedAt: 0, // ServerValue.timestamp fills this server-side
          startPositionMs: 0,
          startedBy: widget.deviceId,
        ),
      );
    } catch (_) {}

    await Future.delayed(const Duration(milliseconds: 600));
    _suppressBroadcast = false;

    _urlController.clear();
    if (mounted) {
      setState(() {
        _currentTitle = title;
        _isPlaying = true;
        _loadingVideo = false;
        _positionSec = 0;
      });
    }
  }

  Future<void> _togglePlayPause() async {
    if (_loadedVideoId.isEmpty) return;
    final willPlay = !_isPlaying;
    final posMs = (_positionSec * 1000).round();

    setState(() => _isPlaying = willPlay);

    _suppressBroadcast = true;
    if (willPlay) {
      WakelockPlus.enable();
      await _ytController.playVideo();
    } else {
      WakelockPlus.disable();
      await _ytController.pauseVideo();
    }

    try {
      await _repo.updateYtPlayState(
        spaceId: widget.spaceId,
        isPlaying: willPlay,
        currentPositionMs: posMs,
        deviceId: widget.deviceId,
      );
    } catch (_) {}

    await Future.delayed(const Duration(milliseconds: 600));
    _suppressBroadcast = false;
  }

  Future<void> _onSeekEnd(double value) async {
    if (_loadedVideoId.isEmpty) return;
    setState(() {
      _isSeeking = false;
      _positionSec = value;
    });

    final posMs = (value * 1000).round();
    _suppressBroadcast = true;

    await _ytController.seekTo(seconds: value, allowSeekAhead: true);

    try {
      await _repo.seekYt(
        spaceId: widget.spaceId,
        positionMs: posMs,
        isPlaying: _isPlaying,
        deviceId: widget.deviceId,
      );
    } catch (_) {}

    await Future.delayed(const Duration(milliseconds: 600));
    _suppressBroadcast = false;
  }

  Future<void> _sendReaction(String emoji) async {
    _spawnEmoji(emoji);
    HapticFeedback.lightImpact();
    try {
      await _repo.sendReaction(
        widget.spaceId,
        VibeReaction(
          emoji: emoji,
          sentBy: widget.deviceId,
          sentAt: _serverNow,
        ),
      );
    } catch (_) {}
  }

  void _spawnEmoji(String emoji) {
    final id = _emojiIdCounter++;
    final x = Random().nextDouble();
    final startY = 0.8 - Random().nextDouble() * 0.2;
    setState(() {
      _floatingEmojis.add(_FloatingEmoji(
        emoji: emoji,
        x: x,
        startY: startY,
        id: id,
      ));
    });
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() => _floatingEmojis.removeWhere((e) => e.id == id));
      }
    });
  }

  // ─────────────────────────────────────────────────────────────────────────────

  @override
  void dispose() {
    _offsetSub?.cancel();
    _sessionSub?.cancel();
    _reactionSub?.cancel();
    _positionTimer?.cancel();
    _ytController.close();
    _urlController.dispose();
    WakelockPlus.disable(); // Ensure wakelock is released
    // If we were the host (loaded a video), clear the session from RTDB
    // so the partner's auto-navigation listener doesn't re-fire on reconnect.
    if (_loadedVideoId.isNotEmpty) {
      _repo.clearYtSession(widget.spaceId).catchError((_) {});
    }
    super.dispose();
  }

  // ─── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final videoHeight = size.width * 9 / 16;

    return StreamingTimerGate(
      label: 'Watch Together',
      child: Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded,
              color: Colors.white.withValues(alpha: 0.7), size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            'Watch Together',
            style: GoogleFonts.inter(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 18,
            ),
          ),
        ),
        actions: [
          // Sync indicator
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Row(
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _loadedVideoId.isNotEmpty
                        ? const Color(0xFF4CAF50)
                        : Colors.grey,
                  ),
                ),
                SizedBox(width: 6),
                Text(
                  _loadedVideoId.isNotEmpty ? 'In Sync' : 'No video',
                  style: GoogleFonts.inter(
                    color: Colors.white.withValues(alpha: 0.54),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          // ── Main content ───────────────────────────────────────────────────
          SingleChildScrollView(
            physics: const ClampingScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── YouTube player ────────────────────────────────────────────
                _PlayerBox(
                  controller: _ytController,
                  videoHeight: videoHeight,
                  width: size.width,
                  isLoading: _loadingVideo,
                  hasVideo: _loadedVideoId.isNotEmpty,
                  onReady: () {
                    if (mounted) {
                      _startPositionTimer();
                    }
                  },
                ),

                // ── Video title ───────────────────────────────────────────────
                if (_currentTitle.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                    child: Text(
                      _currentTitle,
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),

                // ── Seek bar + time ───────────────────────────────────────────
                if (_loadedVideoId.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                    child: SliderTheme(
                      data: SliderThemeData(
                        trackHeight: 3,
                        thumbShape:
                            const RoundSliderThumbShape(enabledThumbRadius: 6),
                        overlayShape:
                            const RoundSliderOverlayShape(overlayRadius: 14),
                        activeTrackColor: const Color(0xFFFF0000),
                        inactiveTrackColor: Colors.white.withValues(alpha: 0.12),
                        thumbColor: Colors.white,
                        overlayColor: Colors.white.withValues(alpha: 0.12),
                      ),
                      child: Slider(
                        value: _durationSec > 0
                            ? _positionSec.clamp(0, _durationSec)
                            : 0,
                        max: _durationSec > 0 ? _durationSec : 1,
                        onChangeStart: (_) =>
                            setState(() => _isSeeking = true),
                        onChanged: (v) =>
                            setState(() => _positionSec = v),
                        onChangeEnd: _onSeekEnd,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _formatDuration(_positionSec),
                          style: GoogleFonts.inter(
                              color: Colors.white.withValues(alpha: 0.54), fontSize: 11),
                        ),
                        Text(
                          _formatDuration(_durationSec),
                          style: GoogleFonts.inter(
                              color: Colors.white.withValues(alpha: 0.54), fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ],

                // ── Play/Pause button ─────────────────────────────────────────
                if (_loadedVideoId.isNotEmpty) ...[
                  SizedBox(height: 8),
                  Center(
                    child: GestureDetector(
                      onTap: _togglePlayPause,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: 60,
                        height: 60,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFFFF0000).withValues(alpha: 0.15),
                          border: Border.all(
                              color: const Color(0xFFFF0000), width: 2),
                        ),
                        child: Icon(
                          _isPlaying
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          color: Colors.white,
                          size: 32,
                        ),
                      ),
                    ),
                  ),
                ],

                SizedBox(height: 24),

                // ── URL input ─────────────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _loadedVideoId.isEmpty
                            ? 'Paste a YouTube link to watch together'
                            : 'Load a different video',
                        style: GoogleFonts.inter(
                          color: Colors.white.withValues(alpha: 0.7),
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _urlController,
                              style: GoogleFonts.inter(
                                  color: Colors.white, fontSize: 14),
                              decoration: InputDecoration(
                                hintText: 'https://youtube.com/watch?v=...',
                                hintStyle: GoogleFonts.inter(
                                    color: Colors.white.withValues(alpha: 0.3), fontSize: 13),
                                filled: true,
                                fillColor: Colors.white.withValues(alpha: 0.07),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: BorderSide.none,
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 14),
                                prefixIcon: Icon(Icons.link_rounded,
                                    color: Colors.white.withValues(alpha: 0.38), size: 20),
                              ),
                              onSubmitted: (_) => _loadVideoFromUrl(),
                            ),
                          ),
                          SizedBox(width: 10),
                          GestureDetector(
                            onTap: _loadingVideo ? null : _loadVideoFromUrl,
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: _loadingVideo
                                    ? Colors.white.withValues(alpha: 0.12)
                                    : const Color(0xFFFF0000),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: _loadingVideo
                                  ? SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : Icon(Icons.play_circle_outline_rounded,
                                      color: Colors.white, size: 22),
                            ),
                          ),
                        ],
                      ),
                      if (_loadError != null) ...[
                        SizedBox(height: 8),
                        Text(
                          _loadError!,
                          style: GoogleFonts.inter(
                              color: const Color(0xFFFF5252), fontSize: 12),
                        ),
                      ],
                    ],
                  ),
                ),

                SizedBox(height: 24),

                // ── Emoji reactions ───────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'React together',
                        style: GoogleFonts.inter(
                          color: Colors.white.withValues(alpha: 0.54),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 0.6,
                        ),
                      ),
                      SizedBox(height: 10),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: _reactionEmojis.map((emoji) {
                          return GestureDetector(
                            onTap: () => _sendReaction(emoji),
                            child: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.07),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.12), width: 1),
                              ),
                              child: Text(emoji,
                                  style: TextStyle(fontSize: 24)),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),

                SizedBox(height: 40),
              ],
            ),
          ),

          // ── Floating emoji layer ─────────────────────────────────────────────
          IgnorePointer(
            child: Stack(
              children: _floatingEmojis.map((fe) {
                return _FloatingEmojiWidget(
                  key: ValueKey(fe.id),
                  emoji: fe.emoji,
                  x: fe.x,
                  startY: fe.startY,
                );
              }).toList(),
            ),
          ),
        ],
      ),
      ), // end Scaffold
    ); // end StreamingTimerGate
  }


  String _formatDuration(double seconds) {
    final dur = Duration(seconds: seconds.round());
    final h = dur.inHours;
    final m = dur.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = dur.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }
}

// ─── Player Box ───────────────────────────────────────────────────────────────

class _PlayerBox extends StatelessWidget {
  final YoutubePlayerController controller;
  final double videoHeight;
  final double width;
  final bool isLoading;
  final bool hasVideo;
  final VoidCallback onReady;

  const _PlayerBox({
    required this.controller,
    required this.videoHeight,
    required this.width,
    required this.isLoading,
    required this.hasVideo,
    required this.onReady,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: videoHeight,
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // YouTube player — always mounted so the controller has a WebView.
          // The placeholder is shown as an overlay on top when no video is loaded.
          YoutubePlayerControllerProvider(
            controller: controller,
            child: SizedBox(
              width: width,
              height: videoHeight,
              child: YoutubePlayer(
                controller: controller,
                aspectRatio: width / videoHeight,
              ),
            ),
          ),

          // Placeholder overlay when no video yet
          if (!hasVideo)
            Container(
              width: width,
              height: videoHeight,
              color: Theme.of(context).scaffoldBackgroundColor,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.smart_display_outlined,
                      color: Colors.white.withValues(alpha: 0.24), size: 64),
                  SizedBox(height: 12),
                  Text(
                    'Paste a YouTube link below\nto start watching together',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                        color: Colors.white.withValues(alpha: 0.38), fontSize: 14, height: 1.5),
                  ),
                ],
              ),
            ),

          // Loading overlay
          if (isLoading)
            Container(
              color: Theme.of(context).scaffoldBackgroundColor.withValues(alpha: 0.54),
              child: Center(
                child: CircularProgressIndicator(
                  color: Color(0xFFFF0000),
                  strokeWidth: 2.5,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Floating Emoji Widget ────────────────────────────────────────────────────

class _FloatingEmojiWidget extends StatefulWidget {
  final String emoji;
  final double x;
  final double startY;

  const _FloatingEmojiWidget({
    super.key,
    required this.emoji,
    required this.x,
    required this.startY,
  });

  @override
  State<_FloatingEmojiWidget> createState() => _FloatingEmojiWidgetState();
}

class _FloatingEmojiWidgetState extends State<_FloatingEmojiWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _opacity;
  late final Animation<double> _slide;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2500));
    _opacity = TweenSequence([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 15),
      TweenSequenceItem(
          tween: Tween(begin: 1.0, end: 1.0).chain(CurveTween(curve: Curves.linear)),
          weight: 60),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 25),
    ]).animate(_ctrl);
    _slide =
        Tween(begin: 0.0, end: -120.0).animate(
            CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) => Positioned(
        left: widget.x * (size.width - 48),
        top: widget.startY * size.height + _slide.value,
        child: Opacity(
          opacity: _opacity.value,
          child: Text(widget.emoji, style: TextStyle(fontSize: 36)),
        ),
      ),
    );
  }
}

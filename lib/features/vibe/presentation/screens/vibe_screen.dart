import 'package:closer/core/utils/app_utils.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:audio_service/audio_service.dart' show MediaItem;
import '../../data/vibe_models.dart';
import '../../data/vibe_audio_handler.dart';
import '../../providers/vibe_providers.dart';
import '../widgets/sync_status_chip.dart';
import '../widgets/local_song_picker_sheet.dart';
import 'song_history_screen.dart';

/// Main Vibe Together screen.
/// Shows the player controls, album art, seek bar, queue, and emoji reactions.
/// Both partners share full play/pause/seek control.
class VibeScreen extends ConsumerStatefulWidget {
  final String spaceId;
  final String deviceId;
  final String partnerId;

  const VibeScreen({
    super.key,
    required this.spaceId,
    required this.deviceId,
    required this.partnerId,
  });

  @override
  ConsumerState<VibeScreen> createState() => _VibeScreenState();
}

class _VibeScreenState extends ConsumerState<VibeScreen>
    with WidgetsBindingObserver {
  VibeAudioHandler? _handler;

  // Server time offset — corrects local clock vs Firebase server clock
  int _serverTimeOffsetMs = 0;
  StreamSubscription<int>? _offsetSub;
  StreamSubscription<VibeSession?>? _sessionSub;
  StreamSubscription<String>? _playbackErrorSub;
  StreamSubscription<void>? _completionSub;
  Timer? _driftCorrectionTimer;

  // Current loaded video ID (avoid redundant URL fetches)
  String? _loadedVideoId;
  String? _loadingVideoId;
  String? _localFilePath; // local file path for local_sync mode (this device only)

  // UI state
  bool _seeking = false;        // user is dragging seek bar
  double _seekValue = 0.0;      // seek bar thumb position (0.0 – 1.0)
  bool _isLoading = false;      // loading a new song URL
  String? _loadError;

  // Reactions
  final List<_FloatingEmoji> _floatingEmojis = [];
  static const _reactionEmojis = ['❤️', '🔥', '😍', '🎵', '✨', '😂', '💜'];
  StreamSubscription<VibeReaction>? _reactionSub;
  StreamSubscription<List<VibeQueueItem>>? _queueSub;
  StreamSubscription<Duration>? _positionSub;

  // Queue
  List<VibeQueueItem> _queue = [];
  bool _queueLoaded = false;

  // Cached session for build (avoids ref.watch on a stream after dispose)

  int get _serverNow =>
      DateTime.now().millisecondsSinceEpoch + _serverTimeOffsetMs;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initAudio();
  }

  Future<void> _initAudio() async {
    _handler = VibeAudioHandler();
    if (!mounted) return;
    setState(() {});
    final repo = ref.read(vibeRepositoryProvider);

    // On boot, if partner is NOT currently in the vibe screen, clear the stale session.
    // This forces the screen to start fresh and not auto-play the last song from yesterday.
    final partnerPresent = await repo.isPartnerPresent(widget.spaceId, widget.partnerId);
    if (!partnerPresent) {
      await repo.clearSession(widget.spaceId);
      await repo.clearQueue(widget.spaceId);
      if (mounted) {
        // Auto-open picker
        _pickLocalSong();
      }
    }

    _offsetSub = repo.watchServerTimeOffset().listen((offset) {
      _serverTimeOffsetMs = offset;
    });
    _sessionSub = repo.watchSession(widget.spaceId).listen(_onSessionChanged);
    _reactionSub = repo.watchReactions(widget.spaceId).listen(_onReactionReceived);
    _queueSub = repo.watchQueue(widget.spaceId).listen((q) {
      debugPrint('[VibeScreen] queue updated: ${q.length} items -> ${q.map((i) => i.title).toList()}');
      if (mounted) setState(() {
        _queue = q;
        _queueLoaded = true;
      });
    });
    await repo.setPresent(widget.spaceId, widget.deviceId);

    _driftCorrectionTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      _correctDrift();
    });
    _positionSub = _handler!.positionStream.listen((_) {
      if (mounted && !_seeking) setState(() {});
    });

    // NEW: surface mid-playback failures instead of silently going dead.
    _playbackErrorSub = _handler!.playbackErrorStream.listen((err) {
      if (!mounted) return;
      debugPrint('[VibeScreen] Playback error: $err');
    });

    _completionSub = _handler!.completionStream.listen((_) {
      final session = ref.read(vibeSessionProvider(widget.spaceId)).value;
      if (session == null) return;
      // Only the device that started/last-controlled this session auto-advances,
      // to avoid both partners' devices racing to pop the queue simultaneously.
      if (session.updatedBy != widget.deviceId) return;
      debugPrint('[VibeScreen] song completed, attempting auto-advance');
      _playNext();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Re-sync position when app comes back to foreground
      _correctDrift();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _offsetSub?.cancel();
    _sessionSub?.cancel();
    _playbackErrorSub?.cancel();
    _completionSub?.cancel();
    _reactionSub?.cancel();
    _queueSub?.cancel();
    _positionSub?.cancel();
    _driftCorrectionTimer?.cancel();
    ref.read(vibeRepositoryProvider).setAbsent(widget.spaceId, widget.deviceId);
    super.dispose();
  }

  // ── Session sync ──────────────────────────────────────────────────────────

  Future<void> _onSessionChanged(VibeSession? session) async {
    if (!mounted || session == null || _handler == null) return;

    final isNewSong = session.videoId != _loadedVideoId;
    if (isNewSong) {
      final success = await _loadSong(session);
      if (!mounted || _handler == null) return;

      if (success && session.isPlaying && session.startPositionMs == 0) {
        await ref.read(vibeRepositoryProvider).updatePlayState(
              spaceId: widget.spaceId,
              isPlaying: true,
              currentPositionMs: 0,
              deviceId: widget.deviceId,
            );
        return; // updated session re-triggers this listener with a fresh startedAt
      }
    }

    final targetPos = session.computePosition(_serverNow);
    try {
      if (session.isPlaying) {
        final currentPos = _handler!.position;
        final drift = (targetPos - currentPos).abs();
        if (drift > const Duration(milliseconds: 800)) {
          await _handler!.seek(targetPos);
        }
        await _handler!.play();
      } else {
        await _handler!.seek(targetPos);
        await _handler!.pause();
      }
    } catch (e) {
      debugPrint('[VibeScreen] playback control error: $e');
      if (mounted) setState(() => _loadError = AppUtils.getFriendlyErrorMessage(e));
    }
    if (mounted) setState(() {});
  }

  Future<bool> _loadSong(VibeSession session) async {
    if (_handler == null) return false;
    if (_loadingVideoId == session.videoId || _loadedVideoId == session.videoId) return false;
    
    _loadingVideoId = session.videoId;
    if (mounted) setState(() { _isLoading = true; _loadError = null; });
    
    try {
      final mediaItem = MediaItem(
        id: session.videoId,
        title: session.videoTitle,
        artUri: session.videoThumb.isNotEmpty ? Uri.parse(session.videoThumb) : null,
        duration: Duration(milliseconds: session.videoDurationMs),
      );

      if (session.sourceType == 'local_upload') {
        // ── Firebase Storage URL — both devices stream from it ───────────
        await _handler!.loadLocalOrUrl(
          source: session.localStorageUrl,
          item: mediaItem,
        );
      } else if (session.sourceType == 'local_sync') {
        // ── Local file — use the stored path (only meaningful for uploader)
        // The partner will see a banner asking them to open their own file.
        final path = _localFilePath ?? session.localStorageUrl;
        if (path.isNotEmpty && !path.startsWith('local_')) {
          await _handler!.loadLocalOrUrl(source: path, item: mediaItem);
        } else {
          // Partner doesn't have the file path — show banner, don't try to load
          _loadedVideoId = session.videoId;
          _loadingVideoId = null;
          if (mounted) setState(() => _isLoading = false);
          return false;
        }
      }

      _loadedVideoId = session.videoId;
      _loadingVideoId = null;
      if (mounted) setState(() => _isLoading = false);

      // Record history only for non-sync-missing sessions
      ref.read(vibeRepositoryProvider).recordHistory(
        widget.spaceId,
        VibeHistoryItem(
          pushId: '',
          videoId: session.videoId,
          title: session.videoTitle,
          thumb: session.videoThumb,
          durationMs: session.videoDurationMs,
          playedAt: DateTime.now().millisecondsSinceEpoch,
        ),
      );
      return true;
    } catch (e) {
      debugPrint('[VibeScreen] _loadSong error: $e');
      _loadingVideoId = null;
      if (mounted) {
        setState(() {
          _isLoading = false;
          _loadError = AppUtils.getFriendlyErrorMessage(e);
        });
      }
      _loadedVideoId = session.videoId;
      return false;
    }
  }

  // ── Drift correction ──────────────────────────────────────────────────────

  Future<void> _correctDrift() async {
    if (_handler == null) return;
    final session = ref.read(vibeSessionProvider(widget.spaceId)).value;
    if (session == null || !session.isPlaying) {
      await _handler!.setSpeed(1.0);
      return;
    }
    
    final targetPos = session.computePosition(_serverNow);
    final currentPos = _handler!.position;
    final diff = targetPos - currentPos; // positive = we are behind target
    final driftMs = diff.inMilliseconds.abs();

    if (driftMs > 1500) {
      // Macro-drift: hard seek.
      await _handler!.setSpeed(1.0);
      await _handler!.seek(targetPos);
    } else if (driftMs > 50) {
      // Micro-drift: smooth speed correction.
      if (diff.isNegative) {
        // We are ahead of target (diff is negative), slow down
        await _handler!.setSpeed(0.95);
      } else {
        // We are behind target (diff is positive), speed up
        await _handler!.setSpeed(1.05);
      }
    } else {
      // In sync
      await _handler!.setSpeed(1.0);
    }
  }

  // ── Controls ──────────────────────────────────────────────────────────────

  Future<void> _togglePlayPause() async {
    if (_handler == null) return;
    final session = ref.read(vibeSessionProvider(widget.spaceId)).value;
    if (session == null) return;
    HapticFeedback.lightImpact();
    final nowPlaying = session.isPlaying;
    await ref.read(vibeRepositoryProvider).updatePlayState(
          spaceId: widget.spaceId,
          isPlaying: !nowPlaying,
          currentPositionMs: _handler!.position.inMilliseconds,
          deviceId: widget.deviceId,
        );
  }

  Future<void> _onSeekEnd(double value) async {
    final session = ref.read(vibeSessionProvider(widget.spaceId)).value;
    if (session == null) return;
    final posMs = (value * session.videoDurationMs).toInt();
    setState(() => _seeking = false);
    await ref.read(vibeRepositoryProvider).seek(
          spaceId: widget.spaceId,
          positionMs: posMs,
          isPlaying: session.isPlaying,
          deviceId: widget.deviceId,
        );
  }

  /// Opens the local song picker sheet.
  Future<void> _pickLocalSong() async {
    final session = await showLocalSongPicker(
      context: context,
      spaceId: widget.spaceId,
      deviceId: widget.deviceId,
    );
    if (session == null || !mounted) return;
    // For local_sync, remember the file path on this device only
    if (session.sourceType == 'local_sync') {
      _localFilePath = session.localStorageUrl;
    }
    setState(() { _isLoading = true; _loadError = null; });
    try {
      await ref.read(vibeRepositoryProvider).startSession(widget.spaceId, session);
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _loadError = AppUtils.getFriendlyErrorMessage(e);
        });
      }
    }
  }

  Future<void> _addToQueue() async {
    final session = await showLocalSongPicker(
      context: context,
      spaceId: widget.spaceId,
      deviceId: widget.deviceId,
    );
    if (session == null || !mounted) return;
    final item = VibeQueueItem(
      pushId: '',
      videoId: session.videoId,
      title: session.videoTitle,
      thumb: session.videoThumb,
      durationMs: session.videoDurationMs,
      addedBy: widget.deviceId,
      sourceType: session.sourceType,
      localStorageUrl: session.localStorageUrl,
    );
    await ref.read(vibeRepositoryProvider).addToQueue(widget.spaceId, item);
  }

  Future<void> _playNext() async {
    debugPrint('[VibeScreen] _playNext called. queueLoaded=$_queueLoaded queueLen=${_queue.length}');
    if (!_queueLoaded || _queue.isEmpty) {
      debugPrint('[VibeScreen] _playNext BLOCKED by guard');
      return;
    }
    final next = _queue.first;
    debugPrint('[VibeScreen] _playNext proceeding with videoId=${next.videoId} title=${next.title}');
    try {
      await ref.read(vibeRepositoryProvider).removeFromQueue(widget.spaceId, next.pushId);
      debugPrint('[VibeScreen] removeFromQueue done');
      final session = VibeSession(
        videoId: next.videoId,
        videoTitle: next.title,
        videoThumb: next.thumb,
        videoDurationMs: next.durationMs,
        isPlaying: true,
        sourceType: next.sourceType,
        localStorageUrl: next.localStorageUrl,
        startedAt: DateTime.now().millisecondsSinceEpoch,
        startPositionMs: 0,
        updatedBy: widget.deviceId,
      );
      await ref.read(vibeRepositoryProvider).startSession(widget.spaceId, session);
      debugPrint('[VibeScreen] startSession done');
    } catch (e, st) {
      debugPrint('[VibeScreen] _playNext ERROR: $e');
      debugPrint('$st');
      if (mounted) setState(() => _loadError = AppUtils.getFriendlyErrorMessage(e));
    }
  }

  // ── Reactions ─────────────────────────────────────────────────────────────

  void _onReactionReceived(VibeReaction r) {
    if (!mounted) return;
    final id = DateTime.now().millisecondsSinceEpoch;
    setState(() {
      _floatingEmojis.add(_FloatingEmoji(
        emoji: r.emoji,
        id: id,
      ));
    });
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() =>
            _floatingEmojis.removeWhere((e) => e.id == id));
      }
    });
  }

  Future<void> _sendReaction(String emoji) async {
    HapticFeedback.mediumImpact();
    final reaction = VibeReaction(
      emoji: emoji,
      sentBy: widget.deviceId,
      sentAt: DateTime.now().millisecondsSinceEpoch,
    );
    await ref.read(vibeRepositoryProvider).sendReaction(widget.spaceId, reaction);
  }

  // \u2500\u2500 Build \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500

  @override
  Widget build(BuildContext context) {
    final sessionAsync = ref.watch(vibeSessionProvider(widget.spaceId));
    final _sessionLoading = sessionAsync.isLoading;
    final _currentSession = sessionAsync.valueOrNull;

    final partnerPresentAsync = ref.watch(
      vibePartnerPresentProvider((spaceId: widget.spaceId, partnerId: widget.partnerId))
    );
    final _partnerPresent = partnerPresentAsync.valueOrNull ?? false;

    return Scaffold(
      backgroundColor: const Color(0xFF0F0F14),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F0F14),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          'Vibe Together \u{1F3B5}',
          style: GoogleFonts.outfit(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.history_rounded, color: Colors.white70),
            tooltip: 'Recently played',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => SongHistoryScreen(spaceId: widget.spaceId),
              ),
            ),
          ),
          if (_currentSession != null)
            IconButton(
              icon: const Icon(Icons.stop_circle_outlined, color: Colors.white70),
              tooltip: 'End Session',
              onPressed: () => ref.read(vibeRepositoryProvider).clearSession(widget.spaceId),
            ),
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: SyncStatusChip(
              state: _partnerPresent
                  ? SyncState.inSync
                  : SyncState.partnerLeft,
            ),
          ),
        ],
      ),
      body: (_handler == null || _sessionLoading)
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFFB388FF)))
          : _currentSession == null
              ? _NoSessionView(
                  onPickLocalSong: _pickLocalSong,
                )
              : _PlayerView(
                  session: _currentSession,
                  handler: _handler!,
                  queueLoaded: _queueLoaded,
                  isLoading: _isLoading,
                  loadError: _loadError,
                  seeking: _seeking,
                  seekValue: _seekValue,
                  floatingEmojis: _floatingEmojis,
                  reactionEmojis: _reactionEmojis,
                  queue: _queue,
                  onTogglePlay: _togglePlayPause,
                  onSeekStart: (v) => setState(() {
                    _seeking = true;
                    _seekValue = v;
                  }),
                  onSeekUpdate: (v) => setState(() => _seekValue = v),
                  onSeekEnd: _onSeekEnd,
                  onPickLocalSong: _pickLocalSong,
                  onPlayNext: _playNext,
                  onSendReaction: _sendReaction,
                  onAddToQueue: _addToQueue,
                ),
    );
  }
}


// ── No-session view ───────────────────────────────────────────────────────────

class _NoSessionView extends StatelessWidget {
  final VoidCallback onPickLocalSong;
  const _NoSessionView({
    required this.onPickLocalSong,
  });

  @override
  Widget build(BuildContext context) => Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 24),
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(colors: [
                    const Color(0xFFB388FF).withValues(alpha: 0.3),
                    Colors.transparent,
                  ]),
                ),
                child: const Icon(Icons.headphones_rounded,
                    size: 56, color: Color(0xFFB388FF)),
              ),
              const SizedBox(height: 24),
              Text(
                'Nothing playing yet',
                style: GoogleFonts.outfit(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Pick a song and listen together 🎶',
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5), fontSize: 15),
              ),
              const SizedBox(height: 32),
              // Pick local song button — primary action
              GestureDetector(
                onTap: onPickLocalSong,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFB388FF).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(
                        color: const Color(0xFFB388FF).withValues(alpha: 0.35)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.audio_file_rounded,
                          color: Color(0xFFB388FF)),
                      const SizedBox(width: 12),
                      Text(
                        'Pick a song to play together...',
                        style: GoogleFonts.outfit(
                          color: const Color(0xFFB388FF),
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      );
}


// ── Player view ───────────────────────────────────────────────────────────────

class _PlayerView extends StatelessWidget {
  final VibeSession session;
  final VibeAudioHandler handler;
  final bool queueLoaded;
  final bool isLoading;
  final String? loadError;
  final bool seeking;
  final double seekValue;
  final List<_FloatingEmoji> floatingEmojis;
  final List<String> reactionEmojis;
  final List<VibeQueueItem> queue;
  final VoidCallback onTogglePlay;
  final ValueChanged<double> onSeekStart;
  final ValueChanged<double> onSeekUpdate;
  final ValueChanged<double> onSeekEnd;
  final VoidCallback onPickLocalSong;
  final VoidCallback onPlayNext;
  final ValueChanged<String> onSendReaction;
  final VoidCallback onAddToQueue;

  const _PlayerView({
    required this.session,
    required this.handler,
    required this.queueLoaded,
    required this.isLoading,
    required this.loadError,
    required this.seeking,
    required this.seekValue,
    required this.floatingEmojis,
    required this.reactionEmojis,
    required this.queue,
    required this.onTogglePlay,
    required this.onSeekStart,
    required this.onSeekUpdate,
    required this.onSeekEnd,
    required this.onPickLocalSong,
    required this.onPlayNext,
    required this.onSendReaction,
    required this.onAddToQueue,
  });


  String _fmtMs(int ms) {
    final d = Duration(milliseconds: ms);
    final m = d.inMinutes;
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final dur = session.videoDurationMs;
    final pos = handler.position.inMilliseconds.clamp(0, dur);
    final sliderVal = seeking
        ? seekValue
        : (dur > 0 ? (pos / dur).clamp(0.0, 1.0) : 0.0);

    return Stack(
      children: [
        // Main scrollable content
        SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
          child: Column(
            children: [
              const SizedBox(height: 16),

              // ── Album art ──────────────────────────────────────────────
              Hero(
                tag: 'vibe_art_${session.videoId}',
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: session.videoThumb.isNotEmpty
                      ? Image.network(
                          session.videoThumb,
                          width: double.infinity,
                          height: 240,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) =>
                              _ArtPlaceholder(isPlaying: session.isPlaying),
                        )
                      : _ArtPlaceholder(isPlaying: session.isPlaying),
                ),
              ),

              const SizedBox(height: 24),

              // ── Title + source badge ──────────────────────────────────
              Text(
                session.videoTitle,
                style: GoogleFonts.outfit(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 20,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),
              // Source badge
              if (session.sourceType != 'youtube')
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: session.sourceType == 'local_upload'
                        ? const Color(0xFF69F0AE).withValues(alpha: 0.15)
                        : const Color(0xFFFFD740).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: session.sourceType == 'local_upload'
                          ? const Color(0xFF69F0AE).withValues(alpha: 0.4)
                          : const Color(0xFFFFD740).withValues(alpha: 0.4),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        session.sourceType == 'local_upload'
                            ? Icons.cloud_done_rounded
                            : Icons.smartphone_rounded,
                        size: 12,
                        color: session.sourceType == 'local_upload'
                            ? const Color(0xFF69F0AE)
                            : const Color(0xFFFFD740),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        session.sourceType == 'local_upload'
                            ? 'Shared file — both streaming'
                            : 'Offline sync — controls only',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: session.sourceType == 'local_upload'
                              ? const Color(0xFF69F0AE)
                              : const Color(0xFFFFD740),
                        ),
                      ),
                    ],
                  ),
                ),

              const SizedBox(height: 4),

              // local_sync banner — tells partner to open their own copy
              if (session.sourceType == 'local_sync')
                GestureDetector(
                  onTap: onPickLocalSong,
                  child: Container(
                    margin: const EdgeInsets.only(top: 8),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFD740).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: const Color(0xFFFFD740).withValues(alpha: 0.4)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.folder_open_rounded,
                            color: Color(0xFFFFD740), size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Tap to open your own copy of this song',
                            style: const TextStyle(
                                color: Color(0xFFFFD740),
                                fontSize: 12,
                                fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              const SizedBox(height: 8),

              if (loadError != null)
                Text(loadError!,
                    style: const TextStyle(
                        color: Color(0xFFFF6E6E), fontSize: 13))
              else if (isLoading)
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Color(0xFFB388FF)),
                  ),
                ),

              const SizedBox(height: 16),

              // ── Seek bar ─────────────────────────────────────────────
              SliderTheme(
                data: SliderThemeData(
                  activeTrackColor: const Color(0xFFB388FF),
                  inactiveTrackColor: Colors.white12,
                  thumbColor: Colors.white,
                  overlayColor: const Color(0xFFB388FF).withValues(alpha: 0.2),
                  trackHeight: 4,
                ),
                child: Slider(
                  value: sliderVal,
                  onChangeStart: onSeekStart,
                  onChanged: onSeekUpdate,
                  onChangeEnd: onSeekEnd,
                ),
              ),

              // Timestamp row
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(_fmtMs(seeking
                        ? (seekValue * dur).toInt()
                        : pos),
                        style: const TextStyle(
                            color: Colors.white60, fontSize: 12)),
                    Text(_fmtMs(dur),
                        style: const TextStyle(
                            color: Colors.white60, fontSize: 12)),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // ── Playback controls ────────────────────────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Previous: change song
                  IconButton(
                    icon: const Icon(Icons.skip_previous_rounded,
                        size: 36, color: Colors.white70),
                    onPressed: onPickLocalSong,
                    tooltip: 'Change song',
                  ),
                  const SizedBox(width: 16),

                  // Play / Pause — big button
                  GestureDetector(
                    onTap: onTogglePlay,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const LinearGradient(
                          colors: [Color(0xFFB388FF), Color(0xFF7C4DFF)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFB388FF).withValues(alpha: 0.5),
                            blurRadius: 20,
                            spreadRadius: 2,
                          )
                        ],
                      ),
                      child: isLoading
                          ? const Center(
                              child: SizedBox(
                                width: 28,
                                height: 28,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2.5,
                                ),
                              ),
                            )
                          : Icon(
                              session.isPlaying
                                  ? Icons.pause_rounded
                                  : Icons.play_arrow_rounded,
                              color: Colors.white,
                              size: 40,
                            ),
                    ),
                  ),
                  const SizedBox(width: 16),

                  // Next: play from queue or add
                  IconButton(
                    icon: Icon(
                      Icons.skip_next_rounded,
                      size: 36,
                      color: (queueLoaded && queue.isNotEmpty)
                          ? Colors.white
                          : Colors.white38,
                    ),
                    onPressed: (queueLoaded && queue.isNotEmpty) ? onPlayNext : null,
                    tooltip: 'Next in queue',
                  ),
                ],
              ),

              const SizedBox(height: 28),

              // ── Reaction bar ─────────────────────────────────────────
              SizedBox(
                height: 44,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: reactionEmojis.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (_, i) {
                    final emoji = reactionEmojis[i];
                    return GestureDetector(
                      onTap: () => onSendReaction(emoji),
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: Colors.white.withValues(alpha: 0.1)),
                        ),
                        child: Center(
                          child: Text(emoji,
                              style: const TextStyle(fontSize: 22)),
                        ),
                      ),
                    );
                  },
                ),
              ),

              const SizedBox(height: 28),

              // ── Queue ────────────────────────────────────────────────
              _QueueSection(
                queue: queue,
                onAddToQueue: onAddToQueue,
              ),
            ],
          ),
        ),

        // ── Floating emoji reactions ─────────────────────────────────────
        ...floatingEmojis.map(
          (e) => _FloatingEmojiWidget(key: ValueKey(e.id), emoji: e.emoji),
        ),
      ],
    );
  }
}

// ── Art placeholder ────────────────────────────────────────────────────────────

class _ArtPlaceholder extends StatelessWidget {
  final bool isPlaying;
  const _ArtPlaceholder({required this.isPlaying});

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        height: 240,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              const Color(0xFFB388FF).withValues(alpha: 0.3),
              const Color(0xFF7C4DFF).withValues(alpha: 0.15),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(24),
        ),
        child: Center(
          child: Icon(
            isPlaying
                ? Icons.graphic_eq_rounded
                : Icons.music_note_rounded,
            size: 72,
            color: const Color(0xFFB388FF).withValues(alpha: 0.7),
          ),
        ),
      );
}

// ── Queue section ─────────────────────────────────────────────────────────────

class _QueueSection extends StatelessWidget {
  final List<VibeQueueItem> queue;
  final VoidCallback onAddToQueue;

  const _QueueSection({required this.queue, required this.onAddToQueue});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Up Next',
                style: GoogleFonts.outfit(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
              TextButton.icon(
                onPressed: onAddToQueue,
                icon: const Icon(Icons.add_rounded,
                    color: Color(0xFFB388FF), size: 18),
                label: const Text('Add',
                    style: TextStyle(
                        color: Color(0xFFB388FF), fontSize: 13)),
              ),
            ],
          ),
          if (queue.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'Queue is empty — add songs!',
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.4),
                    fontSize: 13),
              ),
            )
          else
            ...queue.take(5).map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.network(
                            item.thumb,
                            width: 48,
                            height: 36,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                                width: 48,
                                height: 36,
                                color: Colors.white12,
                                child: const Icon(Icons.music_note,
                                    color: Colors.white54, size: 18)),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            item.title,
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 13),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
        ],
      );
}

// ── Floating emoji animation ───────────────────────────────────────────────────

class _FloatingEmoji {
  final String emoji;
  final int id;
  const _FloatingEmoji({required this.emoji, required this.id});
}

class _FloatingEmojiWidget extends StatefulWidget {
  final String emoji;
  const _FloatingEmojiWidget({super.key, required this.emoji});

  @override
  State<_FloatingEmojiWidget> createState() => _FloatingEmojiWidgetState();
}

class _FloatingEmojiWidgetState extends State<_FloatingEmojiWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _opacity;
  late final Animation<double> _offset;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2500))
      ..forward();
    _opacity = Tween(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _ctrl, curve: const Interval(0.6, 1.0)),
    );
    _offset = Tween(begin: 0.0, end: -120.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return Positioned(
      bottom: 200,
      left: size.width / 2 - 24,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, __) => Opacity(
          opacity: _opacity.value,
          child: Transform.translate(
            offset: Offset(0, _offset.value),
            child: Text(widget.emoji,
                style: const TextStyle(fontSize: 44)),
          ),
        ),
      ),
    );
  }
}

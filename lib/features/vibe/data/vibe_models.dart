// ignore_for_file: avoid_dynamic_calls

/// Represents the current state of a shared listening session stored in RTDB.
class VibeSession {
  final String videoId;
  final String videoTitle;
  final String videoThumb;
  final int videoDurationMs;
  final bool isPlaying;

  /// 'local_upload' | 'local_sync'
  final String sourceType;

  /// Populated when sourceType == 'local_upload'.
  /// Firebase Storage download URL that both devices stream from.
  final String localStorageUrl;

  /// Firebase ServerValue.TIMESTAMP (ms) recorded when play was last pressed.
  final int startedAt;

  /// Playback position (ms) at the moment [startedAt] was recorded.
  final int startPositionMs;

  /// Device ID of whoever triggered the last state change.
  final String updatedBy;

  const VibeSession({
    required this.videoId,
    required this.videoTitle,
    required this.videoThumb,
    required this.videoDurationMs,
    required this.isPlaying,
    this.sourceType = 'local_upload',
    this.localStorageUrl = '',
    required this.startedAt,
    required this.startPositionMs,
    required this.updatedBy,
  });

  /// Computes the current playback position using the server-anchored timestamp.
  /// [serverNowMs] must be adjusted by serverTimeOffset from RTDB.
  Duration computePosition(int serverNowMs) {
    if (!isPlaying) return Duration(milliseconds: startPositionMs);
    final elapsed = serverNowMs - startedAt;
    final pos = (startPositionMs + elapsed).clamp(0, videoDurationMs);
    return Duration(milliseconds: pos);
  }

  Map<String, dynamic> toMap() => {
        'vid': videoId,
        'vt': videoTitle,
        'vth': videoThumb,
        'vd': videoDurationMs,
        'pl': isPlaying,
        'st': sourceType,
        'lsu': localStorageUrl,
        'sa': startedAt,
        'sp': startPositionMs,
        'by': updatedBy,
      };

  factory VibeSession.fromMap(Map<dynamic, dynamic> m) => VibeSession(
        videoId: m['vid'] as String? ?? '',
        videoTitle: m['vt'] as String? ?? 'Unknown',
        videoThumb: m['vth'] as String? ?? '',
        videoDurationMs: (m['vd'] as num?)?.toInt() ?? 0,
        isPlaying: m['pl'] as bool? ?? false,
        sourceType: m['st'] as String? ?? 'local_upload',
        localStorageUrl: m['lsu'] as String? ?? '',
        startedAt: (m['sa'] as num?)?.toInt() ?? 0,
        startPositionMs: (m['sp'] as num?)?.toInt() ?? 0,
        updatedBy: m['by'] as String? ?? '',
      );

  VibeSession copyWith({
    bool? isPlaying,
    int? startedAt,
    int? startPositionMs,
    String? updatedBy,
  }) =>
      VibeSession(
        videoId: videoId,
        videoTitle: videoTitle,
        videoThumb: videoThumb,
        videoDurationMs: videoDurationMs,
        isPlaying: isPlaying ?? this.isPlaying,
        sourceType: sourceType,
        localStorageUrl: localStorageUrl,
        startedAt: startedAt ?? this.startedAt,
        startPositionMs: startPositionMs ?? this.startPositionMs,
        updatedBy: updatedBy ?? this.updatedBy,
      );
}

/// A song in the shared queue (Phase 2).
class VibeQueueItem {
  final String pushId;
  final String videoId;
  final String title;
  final String thumb;
  final int durationMs;
  final String addedBy;
  final String sourceType;        // 'local_upload' | 'local_sync'
  final String localStorageUrl;   // only set for local_upload

  const VibeQueueItem({
    required this.pushId,
    required this.videoId,
    required this.title,
    required this.thumb,
    required this.durationMs,
    required this.addedBy,
    this.sourceType = 'local_upload',
    this.localStorageUrl = '',
  });

  Map<String, dynamic> toMap() => {
        'vid': videoId,
        'vt': title,
        'vth': thumb,
        'vd': durationMs,
        'by': addedBy,
        'st': sourceType,
        'lsu': localStorageUrl,
      };

  factory VibeQueueItem.fromMap(String id, Map<dynamic, dynamic> m) =>
      VibeQueueItem(
        pushId: id,
        videoId: m['vid'] as String? ?? '',
        title: m['vt'] as String? ?? '',
        thumb: m['vth'] as String? ?? '',
        durationMs: (m['vd'] as num?)?.toInt() ?? 0,
        addedBy: m['by'] as String? ?? '',
        sourceType: m['st'] as String? ?? 'local_upload',
        localStorageUrl: m['lsu'] as String? ?? '',
      );
}

/// An emoji reaction burst sent during playback (Phase 2).
class VibeReaction {
  final String emoji;
  final String sentBy;
  final int sentAt;

  const VibeReaction({
    required this.emoji,
    required this.sentBy,
    required this.sentAt,
  });

  Map<String, dynamic> toMap() => {
        'e': emoji,
        'by': sentBy,
        'at': sentAt,
      };

  factory VibeReaction.fromMap(Map<dynamic, dynamic> m) => VibeReaction(
        emoji: m['e'] as String? ?? 'heart',
        sentBy: m['by'] as String? ?? '',
        sentAt: (m['at'] as num?)?.toInt() ?? 0,
      );
}

/// A song that was played, kept for "recently played" / replay.
class VibeHistoryItem {
  final String pushId;
  final String videoId;
  final String title;
  final String thumb;
  final int durationMs;
  final int playedAt;
  const VibeHistoryItem({
    required this.pushId,
    required this.videoId,
    required this.title,
    required this.thumb,
    required this.durationMs,
    required this.playedAt,
  });
  Map<String, dynamic> toMap() => {
        'vid': videoId,
        'vt': title,
        'vth': thumb,
        'vd': durationMs,
        'pa': playedAt,
      };
  factory VibeHistoryItem.fromMap(String id, Map<dynamic, dynamic> m) =>
      VibeHistoryItem(
        pushId: id,
        videoId: m['vid'] as String? ?? '',
        title: m['vt'] as String? ?? '',
        thumb: m['vth'] as String? ?? '',
        durationMs: (m['vd'] as num?)?.toInt() ?? 0,
        playedAt: (m['pa'] as num?)?.toInt() ?? 0,
      );
}

// ─── YouTube Sync Session ─────────────────────────────────────────────────────

/// Represents a shared YouTube watch session stored in RTDB under
/// spaces/{spaceId}/ytSync/session.
///
/// Uses the same server-timestamp anchoring trick as [VibeSession] so both
/// devices compute the exact same playback position regardless of clock skew.
class YtSyncSession {
  /// YouTube video ID (11-character string).
  final String videoId;

  /// Human-readable title fetched via YouTube oEmbed (no API key required).
  final String videoTitle;

  /// Whether the video is currently playing.
  final bool isPlaying;

  /// Firebase ServerValue.TIMESTAMP recorded at the last play/seek event.
  final int startedAt;

  /// Playback position in milliseconds at the moment [startedAt] was recorded.
  final int startPositionMs;

  /// Device ID of whoever triggered the last state change.
  final String startedBy;

  const YtSyncSession({
    required this.videoId,
    required this.videoTitle,
    required this.isPlaying,
    required this.startedAt,
    required this.startPositionMs,
    required this.startedBy,
  });

  /// Computes the current playback position using the server-anchored timestamp.
  /// [serverNowMs] must be server-clock-adjusted via serverTimeOffset.
  Duration computePosition(int serverNowMs) {
    if (!isPlaying) return Duration(milliseconds: startPositionMs);
    final elapsed = serverNowMs - startedAt;
    final pos = (startPositionMs + elapsed).clamp(0, 99999999);
    return Duration(milliseconds: pos);
  }

  Map<String, dynamic> toMap() => {
        'vid': videoId,
        'vt': videoTitle,
        'pl': isPlaying,
        'sa': startedAt,
        'sp': startPositionMs,
        'by': startedBy,
      };

  factory YtSyncSession.fromMap(Map<dynamic, dynamic> m) => YtSyncSession(
        videoId: m['vid'] as String? ?? '',
        videoTitle: m['vt'] as String? ?? '',
        isPlaying: m['pl'] as bool? ?? false,
        startedAt: (m['sa'] as num?)?.toInt() ?? 0,
        startPositionMs: (m['sp'] as num?)?.toInt() ?? 0,
        startedBy: m['by'] as String? ?? '',
      );

  YtSyncSession copyWith({
    bool? isPlaying,
    int? startedAt,
    int? startPositionMs,
    String? startedBy,
  }) =>
      YtSyncSession(
        videoId: videoId,
        videoTitle: videoTitle,
        isPlaying: isPlaying ?? this.isPlaying,
        startedAt: startedAt ?? this.startedAt,
        startPositionMs: startPositionMs ?? this.startPositionMs,
        startedBy: startedBy ?? this.startedBy,
      );

  /// Extracts a YouTube video ID from any common YouTube URL format.
  /// Also accepts a bare 11-character video ID directly.
  static String? extractVideoId(String raw) {
    final url = raw.trim();
    final patterns = [
      RegExp(r'[?&]v=([a-zA-Z0-9_-]{11})'),
      RegExp(r'youtu\.be/([a-zA-Z0-9_-]{11})'),
      RegExp(r'youtube\.com/embed/([a-zA-Z0-9_-]{11})'),
      RegExp(r'youtube\.com/shorts/([a-zA-Z0-9_-]{11})'),
    ];
    for (final pattern in patterns) {
      final match = pattern.firstMatch(url);
      if (match != null) return match.group(1);
    }
    // Accept bare video ID
    if (RegExp(r'^[a-zA-Z0-9_-]{11}$').hasMatch(url)) return url;
    return null;
  }
}


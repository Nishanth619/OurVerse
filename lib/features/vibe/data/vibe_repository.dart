import 'dart:async';
import 'dart:io';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'vibe_models.dart';

/// Handles all Firebase RTDB read/write operations for the Vibe Together feature.
///
/// RTDB schema:
///   spaces/{spaceId}/vibe/
///     session/    — current playback state
///     queue/      — ordered list of upcoming songs
///     reactions/  — recent emoji bursts (TTL ~5s, cleared by sender)
///     presence/
///       {deviceId} — true when device is in the vibe screen
class VibeRepository {
  final FirebaseDatabase _rtdb;

  VibeRepository({FirebaseDatabase? rtdb})
      : _rtdb = rtdb ?? FirebaseDatabase.instance;

  // ── Refs ──────────────────────────────────────────────────────────────────

  DatabaseReference _sessionRef(String spaceId) =>
      _rtdb.ref('spaces/$spaceId/vibe/session');

  DatabaseReference _queueRef(String spaceId) =>
      _rtdb.ref('spaces/$spaceId/vibe/queue');

  DatabaseReference _reactionsRef(String spaceId) =>
      _rtdb.ref('spaces/$spaceId/vibe/reactions');

  DatabaseReference _historyRef(String spaceId) =>
      _rtdb.ref('spaces/$spaceId/vibe/history');

  DatabaseReference _presenceRef(String spaceId, String deviceId) =>
      _rtdb.ref('spaces/$spaceId/vibe/presence/$deviceId');

  // ── Server time offset ────────────────────────────────────────────────────

  /// Streams the difference between server clock and local clock in ms.
  /// Use this to compute accurate playback positions regardless of device
  /// clock skew.
  Stream<int> watchServerTimeOffset() =>
      _rtdb.ref('.info/serverTimeOffset').onValue.map(
            (e) => (e.snapshot.value as num?)?.toInt() ?? 0,
          );

  // ── Session ───────────────────────────────────────────────────────────────

  /// Streams the current vibe session. Emits null when no session is active.
  Stream<VibeSession?> watchSession(String spaceId) =>
      _sessionRef(spaceId).onValue.map((event) {
        final snap = event.snapshot;
        if (!snap.exists || snap.value == null) return null;
        return VibeSession.fromMap(snap.value as Map<dynamic, dynamic>);
      });

  /// Starts a new session or replaces the current one.
  Future<void> startSession(String spaceId, VibeSession session) =>
      _sessionRef(spaceId).set({
        ...session.toMap(),
        'sa': ServerValue.timestamp, // server fills startedAt
      });

  /// Clears the current session.
  Future<void> clearSession(String spaceId) => _sessionRef(spaceId).remove();

  // ── Local file upload ─────────────────────────────────────────────────────

  /// Uploads a local audio [file] to Firebase Storage under this space.
  /// Returns a [Stream<TaskSnapshot>] so the caller can show upload progress.
  ///
  /// Typical usage:
  /// ```dart
  /// final stream = repo.uploadLocalSong(spaceId, file, fileName);
  /// await for (final snap in stream) {
  ///   final progress = snap.bytesTransferred / snap.totalBytes;
  /// }
  /// final url = await stream.last.ref.getDownloadURL();
  /// ```
  Stream<TaskSnapshot> uploadLocalSong(
    String spaceId,
    File file,
    String fileName,
  ) {
    final storageRef = FirebaseStorage.instance
        .ref('vibe/$spaceId/${DateTime.now().millisecondsSinceEpoch}_$fileName');
    final task = storageRef.putFile(
      file,
      SettableMetadata(contentType: 'audio/mpeg'),
    );
    return task.snapshotEvents;
  }

  /// Updates play/pause state + re-anchors the server timestamp.
  Future<void> updatePlayState({
    required String spaceId,
    required bool isPlaying,
    required int currentPositionMs,
    required String deviceId,
  }) =>
      _sessionRef(spaceId).update({
        'pl': isPlaying,
        'sa': ServerValue.timestamp,
        'sp': currentPositionMs,
        'by': deviceId,
      });

  /// Seeks to a new position (both play and pause supported).
  Future<void> seek({
    required String spaceId,
    required int positionMs,
    required bool isPlaying,
    required String deviceId,
  }) =>
      _sessionRef(spaceId).update({
        'sa': ServerValue.timestamp,
        'sp': positionMs,
        'pl': isPlaying,
        'by': deviceId,
      });

  /// Clears the session (end of listening).
  Future<void> endSession(String spaceId) => _sessionRef(spaceId).remove();

  // ── Queue (Phase 2) ───────────────────────────────────────────────────────

  /// Streams the current song queue ordered by push time.
  Stream<List<VibeQueueItem>> watchQueue(String spaceId) =>
      _queueRef(spaceId).onValue.map((event) {
        final snap = event.snapshot;
        if (!snap.exists || snap.value == null) return <VibeQueueItem>[];
        final raw = snap.value as Map<dynamic, dynamic>;
        final items = raw.entries
            .map((e) => VibeQueueItem.fromMap(
                e.key.toString(),
                e.value as Map<dynamic, dynamic>))
            .toList();
        items.sort((a, b) => a.pushId.compareTo(b.pushId));
        return items;
      });

  /// Adds a song to the end of the queue.
  Future<void> addToQueue(String spaceId, VibeQueueItem item) =>
      _queueRef(spaceId).push().set(item.toMap());

  /// Removes a song from the queue by its push ID.
  Future<void> removeFromQueue(String spaceId, String pushId) =>
      _queueRef(spaceId).child(pushId).remove();

  /// Clears the entire queue.
  Future<void> clearQueue(String spaceId) => _queueRef(spaceId).remove();

  // ── History ───────────────────────────────────────────────────────────────

  static const int _maxHistoryItems = 50;

  /// Records a song as played. Call this once playback actually starts.
  Future<void> recordHistory(String spaceId, VibeHistoryItem item) async {
    final ref = _historyRef(spaceId).push();
    await ref.set(item.toMap());

    // Trim to last _maxHistoryItems, oldest first removed.
    final snapshot = await _historyRef(spaceId).get();
    if (snapshot.value == null) return;
    final raw = snapshot.value as Map<dynamic, dynamic>;
    if (raw.length <= _maxHistoryItems) return;

    final entries = raw.entries.toList()
      ..sort((a, b) {
        final pa = (a.value as Map)['pa'] as num? ?? 0;
        final pb = (b.value as Map)['pa'] as num? ?? 0;
        return pa.compareTo(pb); // oldest first
      });
    final toRemove = entries.length - _maxHistoryItems;
    for (var i = 0; i < toRemove; i++) {
      await _historyRef(spaceId).child(entries[i].key.toString()).remove();
    }
  }

  /// Streams history, most-recently-played first.
  Stream<List<VibeHistoryItem>> watchHistory(String spaceId) {
    return _historyRef(spaceId).onValue.map((event) {
      final raw = event.snapshot.value;
      if (raw == null) return <VibeHistoryItem>[];
      final map = raw as Map<dynamic, dynamic>;
      final items = map.entries
          .map((e) => VibeHistoryItem.fromMap(e.key as String, e.value as Map))
          .toList()
        ..sort((a, b) => b.playedAt.compareTo(a.playedAt)); // newest first
      return items;
    });
  }

  // ── Reactions (Phase 2) ───────────────────────────────────────────────────

  /// Sends an emoji reaction visible to the partner for ~3 seconds.
  Future<void> sendReaction(
      String spaceId, VibeReaction reaction) async {
    final ref = _reactionsRef(spaceId).push();
    await ref.set(reaction.toMap());
    // Auto-delete after 4 seconds so RTDB doesn't accumulate stale reactions
    Future.delayed(const Duration(seconds: 4), () => ref.remove());
  }

  /// Streams incoming emoji reactions.
  Stream<VibeReaction> watchReactions(String spaceId) =>
      _reactionsRef(spaceId).onChildAdded.map(
            (e) => VibeReaction.fromMap(
                e.snapshot.value as Map<dynamic, dynamic>),
          );

  // ── Presence ──────────────────────────────────────────────────────────────

  /// Marks this device as present in the vibe screen.
  Future<void> setPresent(String spaceId, String deviceId) =>
      _presenceRef(spaceId, deviceId).set(true);

  /// Marks this device as absent (left the screen).
  Future<void> setAbsent(String spaceId, String deviceId) =>
      _presenceRef(spaceId, deviceId).remove();

  /// Streams partner presence (true = partner is in vibe screen).
  Stream<bool> watchPartnerPresence(String spaceId, String partnerId) =>
      _presenceRef(spaceId, partnerId).onValue.map(
            (e) => e.snapshot.value as bool? ?? false,
          );

  /// Checks if partner is currently present (one-time read).
  Future<bool> isPartnerPresent(String spaceId, String partnerId) async {
    final snap = await _presenceRef(spaceId, partnerId).get();
    return snap.value == true;
  }

  // ── YouTube Sync ──────────────────────────────────────────────────────────

  DatabaseReference _ytSessionRef(String spaceId) =>
      _rtdb.ref('spaces/$spaceId/ytSync/session');

  /// Streams the current YouTube watch session. Emits null when no session is active.
  Stream<YtSyncSession?> watchYtSession(String spaceId) =>
      _ytSessionRef(spaceId).onValue.map((event) {
        final snap = event.snapshot;
        if (!snap.exists || snap.value == null) return null;
        return YtSyncSession.fromMap(snap.value as Map<dynamic, dynamic>);
      });

  /// Starts a new YouTube sync session (or replaces the current one).
  Future<void> startYtSession(String spaceId, YtSyncSession session) =>
      _ytSessionRef(spaceId).set({
        ...session.toMap(),
        'sa': ServerValue.timestamp, // server fills startedAt precisely
      });

  /// Updates play/pause state and re-anchors the server timestamp.
  Future<void> updateYtPlayState({
    required String spaceId,
    required bool isPlaying,
    required int currentPositionMs,
    required String deviceId,
  }) =>
      _ytSessionRef(spaceId).update({
        'pl': isPlaying,
        'sa': ServerValue.timestamp,
        'sp': currentPositionMs,
        'by': deviceId,
      });

  /// Seeks to a new position and re-anchors the server timestamp.
  Future<void> seekYt({
    required String spaceId,
    required int positionMs,
    required bool isPlaying,
    required String deviceId,
  }) =>
      _ytSessionRef(spaceId).update({
        'sa': ServerValue.timestamp,
        'sp': positionMs,
        'pl': isPlaying,
        'by': deviceId,
      });

  /// Clears the YouTube watch session.
  Future<void> clearYtSession(String spaceId) =>
      _ytSessionRef(spaceId).remove();
}


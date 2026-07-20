import 'package:firebase_database/firebase_database.dart';
import 'stream_model.dart';

/// Manages stream session state in Firebase RTDB.
/// Path: /streams/{spaceId}/session
class StreamRepository {
  final FirebaseDatabase _db = FirebaseDatabase.instance;

  DatabaseReference _ref(String spaceId) =>
      _db.ref('streams/$spaceId/session');

  /// Start a live stream session.
  Future<void> startStream({
    required String spaceId,
    required String hostId,
    required String streamType,
  }) async {
    await _ref(spaceId).set({
      'hostId': hostId,
      'streamType': streamType,
      'isLive': true,
      'startedAt': ServerValue.timestamp,
    });
  }

  /// End the stream — set isLive = false so the viewer knows it stopped.
  Future<void> endStream(String spaceId) async {
    await _ref(spaceId).update({'isLive': false});
    // Clean up after 3 seconds to let viewer react
    await Future.delayed(const Duration(seconds: 3));
    await _ref(spaceId).remove();
  }

  /// Watch the stream session in real time.
  Stream<StreamSession?> watchSession(String spaceId) {
    return _ref(spaceId).onValue.map((event) {
      final data = event.snapshot.value;
      if (data == null) return null;
      return StreamSession.fromMap(data as Map<dynamic, dynamic>);
    });
  }

  /// One-time read — is anyone currently live?
  Future<StreamSession?> getSession(String spaceId) async {
    final snap = await _ref(spaceId).get();
    if (!snap.exists || snap.value == null) return null;
    return StreamSession.fromMap(snap.value as Map<dynamic, dynamic>);
  }
}

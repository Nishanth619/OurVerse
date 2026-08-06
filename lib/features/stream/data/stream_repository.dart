import 'package:firebase_database/firebase_database.dart';
import 'stream_model.dart';

class StreamRepository {
  final FirebaseDatabase _db = FirebaseDatabase.instance;

  // ─── OLD stream session (kept for backward compat) ─────────────────────────
  DatabaseReference _sessionRef(String spaceId) =>
      _db.ref('streams/$spaceId/session');

  Future<void> startStream({required String spaceId, required String hostId, required String streamType}) async {
    await _sessionRef(spaceId).set({'hostId': hostId, 'streamType': streamType, 'isLive': true, 'startedAt': ServerValue.timestamp});
  }

  Future<void> endStream(String spaceId) async {
    await _sessionRef(spaceId).update({'isLive': false});
    await Future.delayed(const Duration(seconds: 3));
    await _sessionRef(spaceId).remove();
  }

  Stream<StreamSession?> watchSession(String spaceId) {
    return _sessionRef(spaceId).onValue.map((event) {
      final data = event.snapshot.value;
      if (data == null) return null;
      return StreamSession.fromMap(data as Map<dynamic, dynamic>);
    });
  }

  Future<StreamSession?> getSession(String spaceId) async {
    final snap = await _sessionRef(spaceId).get();
    if (!snap.exists || snap.value == null) return null;
    return StreamSession.fromMap(snap.value as Map<dynamic, dynamic>);
  }

  // ─── NEW: Private Room Membership ──────────────────────────────────────────
  DatabaseReference _roomRef(String spaceId) => _db.ref('rooms/$spaceId/members');

  Future<void> joinRoom({required String spaceId, required String deviceId, required String displayName}) async {
    await _roomRef(spaceId).child(deviceId).set({
      'displayName': displayName,
      'isMicOn': true,
      'isCameraOn': false,
      'isScreenSharing': false,
      'joinedAt': ServerValue.timestamp,
    });
    // Auto-remove on disconnect (Firebase onDisconnect)
    await _roomRef(spaceId).child(deviceId).onDisconnect().remove();
  }

  Future<void> leaveRoom({required String spaceId, required String deviceId}) async {
    await _roomRef(spaceId).child(deviceId).remove();
  }

  Future<void> updateMemberState({
    required String spaceId,
    required String deviceId,
    bool? isMicOn,
    bool? isCameraOn,
    bool? isScreenSharing,
  }) async {
    final updates = <String, dynamic>{};
    if (isMicOn != null) updates['isMicOn'] = isMicOn;
    if (isCameraOn != null) updates['isCameraOn'] = isCameraOn;
    if (isScreenSharing != null) updates['isScreenSharing'] = isScreenSharing;
    if (updates.isNotEmpty) {
      await _roomRef(spaceId).child(deviceId).update(updates);
    }
  }

  Stream<List<RoomMember>> watchRoomMembers(String spaceId) {
    return _roomRef(spaceId).onValue.map((event) {
      try {
        final data = event.snapshot.value;
        if (data == null) return <RoomMember>[];
        // Firebase RTDB can return either a Map or a List depending on key types.
        if (data is! Map) return <RoomMember>[];
        final map = data;
        final result = <RoomMember>[];
        for (final entry in map.entries) {
          if (entry.key is String && entry.value is Map) {
            result.add(RoomMember.fromMap(
              entry.key as String,
              entry.value as Map<dynamic, dynamic>,
            ));
          }
        }
        return result;
      } catch (_) {
        return <RoomMember>[];
      }
    });
  }
}

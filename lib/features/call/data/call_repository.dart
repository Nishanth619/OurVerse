import 'package:firebase_database/firebase_database.dart';
import 'call_signal.dart';

/// Handles all Firebase RTDB signaling for WebRTC voice calls.
///
/// RTDB Schema:
///   spaces/{spaceId}/call/signal      → CallSignal node
///   spaces/{spaceId}/call/ice/{deviceId}/{candidateId}  → ICE candidates
class CallRepository {
  final FirebaseDatabase _rtdb;

  CallRepository({FirebaseDatabase? rtdb})
      : _rtdb = rtdb ?? FirebaseDatabase.instance;

  DatabaseReference _signalRef(String spaceId) =>
      _rtdb.ref('spaces/$spaceId/call/signal');

  DatabaseReference _iceRef(String spaceId, String deviceId) =>
      _rtdb.ref('spaces/$spaceId/call/ice/$deviceId');

  // ── Signaling ──────────────────────────────────────────────────────────────

  /// Caller: write the offer SDP and put state to 'ringing'.
  Future<void> startCall({
    required String spaceId,
    required String callerId,
    required String callerName,
    required String offerSdp,
  }) async {
    final signal = CallSignal(
      callerId: callerId,
      callerName: callerName,
      state: CallState.ringing,
      offerSdp: offerSdp,
      startedAt: DateTime.now().millisecondsSinceEpoch,
    );
    await _signalRef(spaceId).set(signal.toMap());
  }

  /// Callee: write the answer SDP and put state to 'active'.
  Future<void> answerCall({
    required String spaceId,
    required String answerSdp,
  }) async {
    await _signalRef(spaceId).update({
      'answerSdp': answerSdp,
      'state': CallState.active.name,
    });
  }

  /// Either peer: decline before pickup.
  Future<void> declineCall(String spaceId) async {
    await _signalRef(spaceId).update({'state': CallState.declined.name});
  }

  /// Either peer: end the call and clean up the node.
  Future<void> endCall(String spaceId) async {
    await _signalRef(spaceId).update({'state': CallState.ended.name});
    // Small delay then remove so the other side sees the 'ended' state.
    await Future<void>.delayed(const Duration(milliseconds: 500));
    await _rtdb.ref('spaces/$spaceId/call').remove();
  }

  /// Stream of the current call signal — drives the UI state machine.
  Stream<CallSignal?> watchSignal(String spaceId) {
    return _signalRef(spaceId).onValue.map((event) {
      if (!event.snapshot.exists || event.snapshot.value == null) return null;
      final raw = event.snapshot.value;
      if (raw is! Map) return null;
      return CallSignal.fromMap(raw);
    });
  }

  Future<CallSignal?> getCallSignalOnce(String spaceId) async {
    final snapshot = await _signalRef(spaceId).get();
    if (!snapshot.exists || snapshot.value == null) return null;
    final raw = snapshot.value;
    if (raw is! Map) return null;
    return CallSignal.fromMap(raw);
  }

  // ── ICE Candidates ─────────────────────────────────────────────────────────

  /// Push a new ICE candidate from [fromDeviceId] so the peer can consume it.
  Future<void> sendIceCandidate({
    required String spaceId,
    required String fromDeviceId,
    required Map<String, dynamic> candidateMap,
  }) async {
    await _iceRef(spaceId, fromDeviceId).push().set(candidateMap);
  }

  /// Stream of ICE candidates from [fromDeviceId] (i.e., the remote peer).
  Stream<Map<String, dynamic>> watchIceCandidates(
      String spaceId, String fromDeviceId) {
    return _iceRef(spaceId, fromDeviceId).onChildAdded.map((event) {
      final raw = event.snapshot.value;
      if (raw is Map) return Map<String, dynamic>.from(raw);
      return <String, dynamic>{};
    });
  }

  /// Remove ICE candidate nodes for a device (cleanup after call).
  Future<void> clearIce(String spaceId, String deviceId) async {
    await _iceRef(spaceId, deviceId).remove();
  }
}

import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/constants/app_constants.dart';
import '../../core/utils/app_utils.dart';
import '../models/models.dart';

/// Repository for the "Would You Rather" multiplayer game sessions.
///
/// Each session lives at:
///   spaces/{spaceId}/wyrSessions/{dateKey}_{questionIndex}
///
/// Flow:
///   1. Both users pick A or B → written to choices map.
///   2. When all memberIds have a choice, [revealed] flips to true.
///   3. Both clients see the same reveal simultaneously via the stream.
class WyrRepository {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  CollectionReference _sessions(String spaceId) => _db
      .collection(AppConstants.spacesCollection)
      .doc(spaceId)
      .collection(AppConstants.wyrSessionsCollection);

  String _sessionId(int questionIndex) =>
      '${AppUtils.todayKey()}_$questionIndex';

  // ─── Watch ─────────────────────────────────────────────────────────────────

  /// Streams the session document for [questionIndex] today.
  /// Emits null if the session doesn't exist yet.
  Stream<WyrSession?> watchSession(String spaceId, int questionIndex) {
    return _sessions(spaceId)
        .doc(_sessionId(questionIndex))
        .snapshots()
        .map((snap) {
      if (!snap.exists) return null;
      return WyrSession.fromFirestore(snap);
    });
  }

  // ─── Write ─────────────────────────────────────────────────────────────────

  /// Records this device's choice ('A' or 'B') for [questionIndex].
  /// Creates the session document if it doesn't exist yet (merge).
  /// Auto-reveals when every member in [allMemberIds] has chosen.
  Future<void> submitChoice({
    required String spaceId,
    required int questionIndex,
    required String deviceId,
    required String choice, // 'A' or 'B'
    required List<String> allMemberIds,
  }) async {
    final ref = _sessions(spaceId).doc(_sessionId(questionIndex));

    // Write this player's choice. 
    // SetOptions(merge: true) safely deep-merges the 'choices' map, preserving the partner's choice
    // and creates the document if it doesn't exist yet.
    await ref.set({
      'questionIndex': questionIndex,
      'choices': {deviceId: choice},
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    // Check if all members have now answered → auto-reveal
    final snap = await ref.get();
    final data = snap.data() as Map<String, dynamic>? ?? {};
    final choices = Map<String, String>.from(data['choices'] ?? {});

    final allAnswered = allMemberIds.every((id) => choices.containsKey(id));
    if (allAnswered) {
      await ref.update({'revealed': true});
    }
  }

  // ─── Reset ─────────────────────────────────────────────────────────────────

  /// Clears choices for [questionIndex] today so both players can repick.
  Future<void> resetSession(String spaceId, int questionIndex) async {
    final ref = _sessions(spaceId).doc(_sessionId(questionIndex));
    await ref.update({'choices': {}, 'revealed': false});
  }
}

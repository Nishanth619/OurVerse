import 'package:cloud_firestore/cloud_firestore.dart';
import 'chat_message.dart';

// ─── Chat Repository ──────────────────────────────────────────────────────────

class ChatRepository {
  final FirebaseFirestore _db;

  ChatRepository({FirebaseFirestore? db})
      : _db = db ?? FirebaseFirestore.instance;

  CollectionReference _messagesRef(String spaceId) =>
      _db.collection('spaces').doc(spaceId).collection('messages');

  DocumentReference _presenceRef(String spaceId) =>
      _db.collection('spaces').doc(spaceId).collection('presence').doc('typing');

  // ── Messages ──────────────────────────────────────────────────────────────

  /// Real-time stream of all messages, ordered by timestamp ascending.
  Stream<List<ChatMessage>> watchMessages(String spaceId) {
    return _messagesRef(spaceId)
        .orderBy('timestamp', descending: false)
        .snapshots()
        .map((snap) => snap.docs.map(ChatMessage.fromFirestore).toList());
  }

  /// Sends a new message to the conversation.
  Future<void> sendMessage({
    required String spaceId,
    required String senderId,
    required String senderName,
    required String text,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    await _messagesRef(spaceId).add(ChatMessage(
      id: '',
      senderId: senderId,
      senderName: senderName,
      text: trimmed,
      timestamp: DateTime.now(),
    ).toMap());
  }

  /// Sends a call history message to the conversation.
  Future<void> sendCallMessage({
    required String spaceId,
    required String senderId,
    required String senderName,
    required String callState,
    int? callDuration,
  }) async {
    await _messagesRef(spaceId).add(ChatMessage(
      id: '',
      senderId: senderId,
      senderName: senderName,
      text: '', // Empty text for call messages
      timestamp: DateTime.now(),
      type: 'call',
      callState: callState,
      callDuration: callDuration,
    ).toMap());
  }

  // ── Typing Presence ────────────────────────────────────────────────────────

  /// Sets whether the current user is typing.
  Future<void> setTyping(String spaceId, String deviceId, bool isTyping) async {
    await _presenceRef(spaceId).set(
      {deviceId: isTyping},
      SetOptions(merge: true),
    );
  }

  /// Stream of whether the partner is currently typing.
  Stream<bool> watchPartnerTyping(String spaceId, String partnerId) {
    return _presenceRef(spaceId).snapshots().map((snap) {
      if (!snap.exists) return false;
      return (snap.data() as Map<String, dynamic>?)?[partnerId] as bool? ??
          false;
    });
  }
}

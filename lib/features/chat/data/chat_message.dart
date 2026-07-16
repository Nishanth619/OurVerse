import 'package:cloud_firestore/cloud_firestore.dart';

// ─── ChatMessage Model ────────────────────────────────────────────────────────

class ChatMessage {
  final String id;
  final String senderId;
  final String senderName;
  final String text;
  final DateTime timestamp;
  final String type; // 'text' or 'call'
  final int? callDuration;
  final String? callState; // 'missed', 'completed', 'declined'

  const ChatMessage({
    required this.id,
    required this.senderId,
    required this.senderName,
    required this.text,
    required this.timestamp,
    this.type = 'text',
    this.callDuration,
    this.callState,
  });

  factory ChatMessage.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return ChatMessage(
      id: doc.id,
      senderId: data['senderId'] as String? ?? '',
      senderName: data['senderName'] as String? ?? 'Partner',
      text: data['text'] as String? ?? '',
      timestamp: (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
      type: data['type'] as String? ?? 'text',
      callDuration: data['callDuration'] as int?,
      callState: data['callState'] as String?,
    );
  }

  Map<String, dynamic> toMap() => {
        'senderId': senderId,
        'senderName': senderName,
        'text': text,
        'timestamp': FieldValue.serverTimestamp(),
        'type': type,
        if (callDuration != null) 'callDuration': callDuration,
        if (callState != null) 'callState': callState,
      };
}

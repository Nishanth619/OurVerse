/// Represents the state of an active stream session stored in Firebase RTDB.
class StreamSession {
  final String hostId;       // device ID of the streamer
  final String streamType;   // 'camera' | 'screen'
  final bool isLive;
  final int startedAt;       // epoch ms

  const StreamSession({
    required this.hostId,
    required this.streamType,
    required this.isLive,
    required this.startedAt,
  });

  factory StreamSession.fromMap(Map<dynamic, dynamic> map) => StreamSession(
        hostId: map['hostId'] as String? ?? '',
        streamType: map['streamType'] as String? ?? 'camera',
        isLive: map['isLive'] as bool? ?? false,
        startedAt: map['startedAt'] as int? ?? 0,
      );

  Map<String, dynamic> toMap() => {
        'hostId': hostId,
        'streamType': streamType,
        'isLive': isLive,
        'startedAt': startedAt,
      };
}

/// A member in the private room, stored under /rooms/{spaceId}/members/{deviceId}
class RoomMember {
  final String deviceId;
  final String displayName;
  final bool isMicOn;
  final bool isCameraOn;
  final bool isScreenSharing;
  final int joinedAt;

  const RoomMember({
    required this.deviceId,
    required this.displayName,
    this.isMicOn = true,
    this.isCameraOn = false,
    this.isScreenSharing = false,
    required this.joinedAt,
  });

  factory RoomMember.fromMap(String deviceId, Map<dynamic, dynamic> map) =>
      RoomMember(
        deviceId: deviceId,
        displayName: map['displayName'] as String? ?? 'User',
        isMicOn: map['isMicOn'] as bool? ?? true,
        isCameraOn: map['isCameraOn'] as bool? ?? false,
        isScreenSharing: map['isScreenSharing'] as bool? ?? false,
        joinedAt: map['joinedAt'] as int? ?? 0,
      );

  Map<String, dynamic> toMap() => {
        'displayName': displayName,
        'isMicOn': isMicOn,
        'isCameraOn': isCameraOn,
        'isScreenSharing': isScreenSharing,
        'joinedAt': joinedAt,
      };

  RoomMember copyWith({
    bool? isMicOn,
    bool? isCameraOn,
    bool? isScreenSharing,
  }) =>
      RoomMember(
        deviceId: deviceId,
        displayName: displayName,
        isMicOn: isMicOn ?? this.isMicOn,
        isCameraOn: isCameraOn ?? this.isCameraOn,
        isScreenSharing: isScreenSharing ?? this.isScreenSharing,
        joinedAt: joinedAt,
      );
}

/// Old StreamSession — keep for backward compat (stream_screen.dart may still use it)
class StreamSession {
  final String hostId;
  final String streamType;
  final bool isLive;
  final int startedAt;

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

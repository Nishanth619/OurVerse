import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/stream_model.dart';
import '../data/stream_repository.dart';

final streamRepositoryProvider = Provider<StreamRepository>((_) => StreamRepository());

final streamSessionProvider = StreamProvider.family<StreamSession?, String>((ref, spaceId) {
  return ref.watch(streamRepositoryProvider).watchSession(spaceId);
});

final roomMembersProvider = StreamProvider.family<List<RoomMember>, String>((ref, spaceId) {
  return ref.watch(streamRepositoryProvider).watchRoomMembers(spaceId);
});

// ─── ScreenShare floating bar state ──────────────────────────────────────────
class ScreenShareState {
  final bool isSharing;
  final bool isInRoom; // true when user is in voice room (even without sharing)
  final String spaceId;
  final String deviceId;
  final String partnerId;

  const ScreenShareState({
    this.isSharing = false,
    this.isInRoom = false,
    this.spaceId = '',
    this.deviceId = '',
    this.partnerId = '',
  });

  ScreenShareState copyWith({bool? isSharing, bool? isInRoom, String? spaceId, String? deviceId, String? partnerId}) =>
      ScreenShareState(
        isSharing: isSharing ?? this.isSharing,
        isInRoom: isInRoom ?? this.isInRoom,
        spaceId: spaceId ?? this.spaceId,
        deviceId: deviceId ?? this.deviceId,
        partnerId: partnerId ?? this.partnerId,
      );
}

class ScreenShareNotifier extends StateNotifier<ScreenShareState> {
  ScreenShareNotifier() : super(const ScreenShareState());

  void joinRoom({required String spaceId, required String deviceId, required String partnerId}) {
    state = state.copyWith(isInRoom: true, spaceId: spaceId, deviceId: deviceId, partnerId: partnerId);
  }

  void startSharing({required String spaceId, required String deviceId, required String partnerId}) {
    state = state.copyWith(isSharing: true, isInRoom: true, spaceId: spaceId, deviceId: deviceId, partnerId: partnerId);
  }

  void stopSharing() {
    state = state.copyWith(isSharing: false);
  }

  void leaveRoom() {
    state = const ScreenShareState();
  }
}

final screenShareStateProvider = StateNotifierProvider<ScreenShareNotifier, ScreenShareState>(
  (ref) => ScreenShareNotifier(),
);

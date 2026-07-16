import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/vibe_models.dart';
import '../data/vibe_repository.dart';
import '../../../shared/providers/app_providers.dart';

// ── Repository ────────────────────────────────────────────────────────────────

final vibeRepositoryProvider = Provider<VibeRepository>(
  (ref) => VibeRepository(),
);


// ── Server time offset ────────────────────────────────────────────────────────

/// Streams the RTDB server time offset (ms). Use to compute correct playback
/// positions across devices with different local clocks.
final serverTimeOffsetProvider = StreamProvider<int>((ref) {
  final repo = ref.watch(vibeRepositoryProvider);
  return repo.watchServerTimeOffset();
});

// ── Session ───────────────────────────────────────────────────────────────────

final vibeSessionProvider = StreamProvider.family<VibeSession?, String>(
  (ref, spaceId) {
    final repo = ref.watch(vibeRepositoryProvider);
    return repo.watchSession(spaceId);
  },
);

// ── Queue ─────────────────────────────────────────────────────────────────────

final vibeQueueProvider =
    StreamProvider.family<List<VibeQueueItem>, String>((ref, spaceId) {
  final repo = ref.watch(vibeRepositoryProvider);
  return repo.watchQueue(spaceId);
});

// ── Partner presence ──────────────────────────────────────────────────────────

final vibePartnerPresentProvider =
    StreamProvider.family<bool, ({String spaceId, String partnerId})>(
  (ref, args) {
    final repo = ref.watch(vibeRepositoryProvider);
    return repo.watchPartnerPresence(args.spaceId, args.partnerId);
  },
);

// ── Convenience: space + device context ──────────────────────────────────────

final vibeSpaceContextProvider = Provider<({String spaceId, String deviceId, String partnerId})?>((ref) {
  final spaceAsync = ref.watch(spaceStreamProvider);
  final deviceIdAsync = ref.watch(deviceIdProvider);
  final space = spaceAsync.value;
  final deviceId = deviceIdAsync.value;
  if (space == null || deviceId == null) return null;
  final partnerId =
      space.memberDeviceIds.firstWhere((id) => id != deviceId, orElse: () => '');
  return (spaceId: space.id, deviceId: deviceId, partnerId: partnerId);
});

// ── History ───────────────────────────────────────────────────────────────────

final vibeHistoryProvider =
    StreamProvider.family<List<VibeHistoryItem>, String>((ref, spaceId) {
  final repo = ref.watch(vibeRepositoryProvider);
  return repo.watchHistory(spaceId);
});

// ── YouTube Sync ──────────────────────────────────────────────────────────────

final ytSessionProvider = StreamProvider.family<YtSyncSession?, String>(
  (ref, spaceId) {
    final repo = ref.watch(vibeRepositoryProvider);
    return repo.watchYtSession(spaceId);
  },
);


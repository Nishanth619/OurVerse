import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:closer/features/call/call_manager.dart';
import 'package:closer/features/call/data/call_repository.dart';
import 'package:closer/features/call/data/call_signal.dart';
import 'package:closer/shared/providers/app_providers.dart';

// ─── Core Providers ───────────────────────────────────────────────────────────

/// Singleton CallRepository — shared across the app.
final callRepositoryProvider = Provider<CallRepository>((ref) {
  return CallRepository();
});

/// Singleton CallManager — persisted for the lifetime of the app.
/// Disposed automatically when ProviderScope is torn down.
final callManagerProvider = Provider<CallManager>((ref) {
  final repo = ref.watch(callRepositoryProvider);
  final chatRepo = ref.watch(chatRepositoryProvider);
  final manager = CallManager(repo: repo, chatRepo: chatRepo);
  ref.onDispose(manager.dispose);
  return manager;
});

// ─── State Streams ────────────────────────────────────────────────────────────

/// Streams the current CallManagerState.
final callStateProvider = StreamProvider<CallManagerState>((ref) {
  final manager = ref.watch(callManagerProvider);
  return manager.stateStream;
});

/// Streams the elapsed call duration.
final callDurationProvider = StreamProvider<Duration>((ref) {
  final manager = ref.watch(callManagerProvider);
  return manager.durationStream;
});

// ─── Incoming Call Watcher ────────────────────────────────────────────────────

/// Watches the RTDB for an incoming ringing call for this space.
/// Returns the [CallSignal] if someone is calling, null otherwise.
final incomingCallSignalProvider =
    StreamProvider.family<CallSignal?, String>((ref, spaceId) {
  if (spaceId.isEmpty) return Stream.value(null);
  final repo = ref.watch(callRepositoryProvider);
  return repo.watchSignal(spaceId).map((signal) {
    if (signal == null) return null;
    if (signal.state == CallState.ringing) return signal;
    return null;
  });
});

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/utils/app_utils.dart';
import '../../data/models/models.dart';
import '../../data/repositories/space_repository.dart';
import '../../data/repositories/question_repository.dart';
import '../../data/repositories/wyr_repository.dart';
import '../../data/services/auth_service.dart';
import '../../features/games/data/word_hunt_repository.dart';
import '../../features/games/data/word_hunt_model.dart';
import '../../features/games/data/flash_repository.dart';
import '../../features/chat/data/chat_repository.dart';
import '../../features/chat/data/chat_message.dart';
import '../data/presence_repository.dart';

export '../../features/games/data/wyr_questions.dart' show wyrQuestionsProvider, WyrEntry;
export '../../features/games/data/doodle_repository.dart' show DoodleRepository, DoodlePoint;
export '../../features/chat/data/chat_repository.dart' show ChatRepository;
export '../../features/chat/data/chat_message.dart' show ChatMessage;
export '../data/presence_repository.dart' show PresenceRepository;
export '../../features/games/data/word_hunt_repository.dart' show WordHuntRepository;
export '../../features/games/data/word_hunt_model.dart' show WordHuntModel;
export '../../features/games/data/flash_repository.dart' show FlashRepository, FlashDay;

// ─── Services ──────────────────────────────────────────────────────────────

final authServiceProvider = Provider<AuthService>((ref) => AuthService());
final spaceRepositoryProvider =
    Provider<SpaceRepository>((ref) => SpaceRepository());
final questionRepositoryProvider =
    Provider<QuestionRepository>((ref) => QuestionRepository());
final wyrRepositoryProvider =
    Provider<WyrRepository>((ref) => WyrRepository());

// ─── Device Identity ───────────────────────────────────────────────────────

final deviceIdProvider = FutureProvider<String>((ref) async {
  final auth = ref.read(authServiceProvider);
  return auth.getOrCreateDeviceId();
});

final deviceNameProvider = FutureProvider<String>((ref) async {
  final auth = ref.read(authServiceProvider);
  return auth.getDeviceName();
});

// ─── Space ─────────────────────────────────────────────────────────────────

/// The persisted space ID from SharedPreferences — loaded once at startup.
final savedSpaceIdProvider = FutureProvider<String?>((ref) async {
  final auth = ref.read(authServiceProvider);
  return auth.getSavedSpaceId();
});

/// The currently active space ID — writable by onboarding/settings flows.
/// Starts null; SplashScreen initializes it from [savedSpaceIdProvider].
final activeSpaceIdProvider = StateProvider<String?>((ref) => null);

/// Live Firestore stream of the active space document.
final spaceStreamProvider = StreamProvider<SpaceModel?>((ref) {
  final spaceId = ref.watch(activeSpaceIdProvider);
  if (spaceId == null) return Stream.value(null);
  return ref.watch(spaceRepositoryProvider).watchSpace(spaceId);
});

// ─── Presence ──────────────────────────────────────────────────────────────

final presenceRepositoryProvider =
    Provider<PresenceRepository>((ref) => PresenceRepository());

final featurePresenceProvider =
    StreamProvider.family<bool, ({String spaceId, String featureId, String partnerId})>(
        (ref, args) {
  final repo = ref.watch(presenceRepositoryProvider);
  return repo.watchPartnerPresence(args.spaceId, args.featureId, args.partnerId);
});

// ─── Date Key ──────────────────────────────────────────────────────────────

/// Holds today's date key (e.g. '2024-06-22').
/// Reset this provider's state when the date changes (e.g. on app resume)
/// to force all date-keyed providers to rebuild.
final todayKeyProvider = StateProvider<String>((ref) => AppUtils.todayKey());

// ─── Question of the Day ───────────────────────────────────────────────────

/// Today's question — fetched once per day-key change.
/// Using FutureProvider since the question is fetched once and doesn't stream.
final todayQuestionProvider = FutureProvider<QuestionModel?>((ref) async {
  final spaceId = ref.watch(activeSpaceIdProvider);
  // Rebuild when the date key changes (midnight rollover)
  ref.watch(todayKeyProvider);
  if (spaceId == null) return null;
  return ref.read(questionRepositoryProvider).getTodayQuestion(spaceId);
});

/// Live stream of today's answer doc (for waiting/reveal state).
final todayAnswersProvider = StreamProvider<DailyAnswerModel?>((ref) {
  final spaceId = ref.watch(activeSpaceIdProvider);
  // Watch the date key so the stream path rebuilds on a new day
  ref.watch(todayKeyProvider);
  if (spaceId == null) return Stream.value(null);
  return ref.watch(questionRepositoryProvider).watchTodayAnswers(spaceId);
});

/// Live stream of today's moods.
final todayMoodsProvider = StreamProvider<DailyMoodModel?>((ref) {
  final spaceId = ref.watch(activeSpaceIdProvider);
  // Watch the date key so the stream path rebuilds on a new day
  ref.watch(todayKeyProvider);
  if (spaceId == null) return Stream.value(null);
  return ref.watch(questionRepositoryProvider).watchTodayMoods(spaceId);
});

// ─── WYR Game ────────────────────────────────────────────────────────────────

/// SharedPreferences key for today's WYR index (format: "wyr_index_2026-07-02")
String _wyrPrefsKey() {
  final today = AppUtils.todayKey();
  return 'wyr_index_$today';
}

/// The index of the current WYR question.
/// Persists in SharedPreferences keyed by today's date, so it:
///   - Survives app backgrounding
///   - Auto-resets to 0 on a new day
class WyrCurrentIndexNotifier extends Notifier<int> {
  @override
  int build() {
    // Initialize synchronously to 0; load from prefs async and update.
    _load();
    return 0;
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getInt(_wyrPrefsKey()) ?? 0;
      state = saved;
    } catch (_) {
      // Silently default to 0 if prefs unavailable.
    }
  }

  Future<void> setIndex(int index) async {
    state = index;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_wyrPrefsKey(), index);
    } catch (_) {}
  }
}

final wyrCurrentIndexProvider = NotifierProvider<WyrCurrentIndexNotifier, int>(
  WyrCurrentIndexNotifier.new,
);

/// Streams the Firestore WYR session for the current question index.
final wyrSessionProvider = StreamProvider<WyrSession?>((ref) {
  final spaceId = ref.watch(activeSpaceIdProvider);
  final index = ref.watch(wyrCurrentIndexProvider);
  if (spaceId == null) return Stream.value(null);
  return ref.watch(wyrRepositoryProvider).watchSession(spaceId, index);
});

// ─── Chat ──────────────────────────────────────────────────────────────────

/// Single-instance chat repository — avoids re-constructing on every build.
final chatRepositoryProvider =
    Provider<ChatRepository>((_) => ChatRepository());

/// Live stream of chat messages for a given space.
final chatMessagesProvider =
    StreamProvider.family<List<ChatMessage>, String>((ref, spaceId) {
  return ref.watch(chatRepositoryProvider).watchMessages(spaceId);
});

/// Live stream of partner's typing state.
final chatPartnerTypingProvider =
    StreamProvider.family<bool, ({String spaceId, String partnerId})>(
        (ref, args) {
  return ref
      .watch(chatRepositoryProvider)
      .watchPartnerTyping(args.spaceId, args.partnerId);
});

// ─── Word Hunt ─────────────────────────────────────────────────────────────

/// Single-instance word hunt repository.
final wordHuntRepositoryProvider =
    Provider<WordHuntRepository>((ref) => WordHuntRepository());

/// Live stream of the current word hunt game for a given space.
final wordHuntStreamProvider =
    StreamProvider.family<WordHuntModel?, String>((ref, spaceId) {
  return ref.watch(wordHuntRepositoryProvider).watchCurrentGame(spaceId);
});

// ─── Flash ─────────────────────────────────────────────────────────────────

/// Single-instance flash repository.
final flashRepositoryProvider =
    Provider<FlashRepository>((ref) => FlashRepository());

/// Live stream of today's flash day document for a given space.
final flashTodayProvider =
    StreamProvider.family<FlashDay, String>((ref, spaceId) {
  return ref.watch(flashRepositoryProvider).watchToday(spaceId);
});

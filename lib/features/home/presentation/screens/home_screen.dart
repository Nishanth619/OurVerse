import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:animated_emoji/animated_emoji.dart';
import 'package:home_widget/home_widget.dart';
import 'package:flutter/services.dart';
import 'package:showcaseview/showcaseview.dart';
import '../../../../core/services/onboarding_service.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/app_utils.dart';
import '../../../../data/models/models.dart';
import '../../../../data/services/home_widget_service.dart';
import '../../../../data/services/notification_service.dart';
import '../../../../shared/providers/app_providers.dart';
import '../../../vibe/providers/vibe_providers.dart';
import '../../../stream/providers/stream_providers.dart';

const _hapticsChannel = MethodChannel('site.nexaaradhya.bondly/haptics');

/// Vibrates using native MethodChannel with USAGE_ALARM to bypass ColorOS restrictions
Future<void> _vibrate({int duration = 80}) async {
  try {
    await _hapticsChannel.invokeMethod('forceVibrate', {'duration': duration});
  } catch (_) {}
}

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

// ── GlobalKeys for coach marks (created once at class level) ─────────────────
final _keyMood       = GlobalKey();
final _keyQuestion   = GlobalKey();
final _keyStreak     = GlobalKey();
final _keyStream     = GlobalKey();

class _HomeScreenState extends ConsumerState<HomeScreen> {
  StreamSubscription<Uri?>? _widgetClickedSub;
  // Holds manual listener subscriptions so they fire exactly ONCE per event,
  // not once per rebuild (which happens when ref.listen is inside build()).
  final List<ProviderSubscription<dynamic>> _listeners = [];

  @override
  void initState() {
    super.initState();
    // Register the home widget click listener ONCE — not on every build.
    _widgetClickedSub = HomeWidget.widgetClicked.listen(_handleWidgetClick);

    // All side-effect listeners MUST live here, not inside build().
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _registerListeners();
      _maybeStartCoachMarks();
    });

    ShowcaseView.register(
      onFinish: () => OnboardingService.markCoachMarksDone(),
      blurValue: 2,
    );
  }

  Future<void> _maybeStartCoachMarks() async {
    if (!mounted) return;
    final done = await OnboardingService.isCoachMarksDone();
    if (!mounted || done) return;
    // Small delay so the home content is fully rendered before the spotlight starts
    await Future.delayed(const Duration(milliseconds: 800));
    if (!mounted) return;
    ShowcaseView.get().startShowCase([
      _keyMood,
      _keyQuestion,
      _keyStreak,
      _keyStream,
    ]);
  }

  void _registerListeners() {
    // ── Partner joined / partner ID widget save ───────────────────────────────
    _listeners.add(
      ref.listenManual<AsyncValue<SpaceModel?>>(spaceStreamProvider, (previous, next) {
        final prevSpace = previous?.value;
        final nextSpace = next.value;

        // Partner joined banner
        if (prevSpace != null && nextSpace != null &&
            nextSpace.memberDeviceIds.length > prevSpace.memberDeviceIds.length) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Row(
                children: [
                  Text('🎉', style: TextStyle(fontSize: 24)),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Your partner just joined the space!',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                    ),
                  ),
                ],
              ),
              backgroundColor: AppTheme.accent,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              margin: const EdgeInsets.all(16),
              duration: const Duration(seconds: 5),
            ),
          );
        }

        // Save partner device ID for native widget
        next.whenData((space) {
          if (!mounted) return;
          final myId = ref.read(deviceIdProvider).valueOrNull;
          if (space == null || myId == null) return;
          final partnerId = space.memberDeviceIds.where((id) => id != myId).firstOrNull;
          if (partnerId != null) HomeWidgetService.savePartnerId(partnerId);
        });
      }),
    );

    // ── Mood change notifications + widget updates ────────────────────────────
    _listeners.add(
      ref.listenManual<AsyncValue<DailyMoodModel?>>(todayMoodsProvider, (previous, next) {
        final prevMoods = previous?.valueOrNull?.entries ?? {};
        final nextMoods = next.valueOrNull?.entries ?? {};
        final myId = ref.read(deviceIdProvider).valueOrNull;
        final space = ref.read(spaceStreamProvider).valueOrNull;

        // Partner mood ping
        if (myId != null && space != null) {
          final partnerIds = space.memberDeviceIds.where((id) => id != myId);
          for (final pId in partnerIds) {
            final prevPartnerMood = prevMoods[pId]?.emoji;
            final nextPartnerMood = nextMoods[pId]?.emoji;
            if (nextPartnerMood != null &&
                nextPartnerMood != prevPartnerMood &&
                prevMoods.isNotEmpty) {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Row(
                      children: [
                        Text(nextPartnerMood, style: const TextStyle(fontSize: 24)),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text(
                            'Your partner updated their mood!',
                            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                          ),
                        ),
                      ],
                    ),
                    backgroundColor: AppTheme.primary,
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    margin: const EdgeInsets.all(16),
                    duration: const Duration(seconds: 4),
                  ),
                );
              }
              NotificationService.showMoodPing(nextPartnerMood);
            }
          }
        }

        // Widget emoji update
        next.whenData((moods) {
          if (!mounted) return;
          if (moods == null) return;
          final id = ref.read(deviceIdProvider).valueOrNull;
          if (id == null) return;
          final myEmoji = moods.entries[id]?.emoji;
          final partnerEmoji = moods.entries.entries
              .where((e) => e.key != id)
              .map((e) => e.value.emoji)
              .firstOrNull;
          if (myEmoji != null) HomeWidgetService.updateMyEmoji(myEmoji);
          if (partnerEmoji != null) HomeWidgetService.updatePartnerEmoji(partnerEmoji);
        });
      }),
    );

    // ── Question widget update ────────────────────────────────────────────────
    _listeners.add(
      ref.listenManual<AsyncValue<QuestionModel?>>(todayQuestionProvider, (_, next) {
        next.whenData((q) {
          if (q != null) HomeWidgetService.updateQuestion(q.text);
        });
      }),
    );

    // ── Partner Flash Photo → widget update ─────────────────────────────────────
    // When the partner uploads their daily Flash photo, decode it from
    // base64 and write it to a local file so the home-screen widget can
    // display it as a Bitmap without any network call.
    _listeners.add(
      ref.listenManual<AsyncValue<SpaceModel?>>(spaceStreamProvider,
          (_, spaceNext) {
        final spaceId = spaceNext.valueOrNull?.id;
        if (spaceId == null) return;

        final myId = ref.read(deviceIdProvider).valueOrNull;
        if (myId == null) return;

        // Re-subscribe to the flash stream for the current space
        final flashAsync = ref.read(flashTodayProvider(spaceId));
        flashAsync.whenData((flashDay) {
          final space = spaceNext.valueOrNull;
          if (space == null) return;
          final partnerId = space.memberDeviceIds
              .firstWhere((id) => id != myId, orElse: () => '');
          if (partnerId.isEmpty) return;

          final partnerEntry = flashDay.entryFor(partnerId);
          if (partnerEntry == null) return;

          // Save partner flash photo to disk for the widget
          final todayKey = AppUtils.todayKey();
          HomeWidgetService.savePartnerFlashPhoto(
              partnerEntry.photoUrl, todayKey);
        });
      }),
    );

    // ── Partner Flash stream — direct watcher ────────────────────────────────
    // This covers the case where the space is already loaded when the
    // partner uploads — i.e. the user is already on the home screen.
    final spaceId = ref.read(activeSpaceIdProvider);
    final myId = ref.read(deviceIdProvider).valueOrNull;
    if (spaceId != null && myId != null) {
      _listeners.add(
        ref.listenManual<AsyncValue<FlashDay>>(
          flashTodayProvider(spaceId),
          (previous, next) {
            next.whenData((flashDay) {
              final space = ref.read(spaceStreamProvider).valueOrNull;
              if (space == null) return;
              final partnerId = space.memberDeviceIds
                  .firstWhere((id) => id != myId, orElse: () => '');
              if (partnerId.isEmpty) return;

              final prevEntry =
                  previous?.valueOrNull?.entryFor(partnerId);
              final nextEntry = flashDay.entryFor(partnerId);

              // Only update when partner's entry is NEW (wasn't there before)
              if (nextEntry != null && prevEntry == null) {
                final todayKey = AppUtils.todayKey();
                HomeWidgetService.savePartnerFlashPhoto(
                    nextEntry.photoUrl, todayKey);
              }
            });
          },
        ),
      );
    }

    // ── Watch Together: auto-navigate partner when a session starts ──────────
    final watchSpaceId = ref.read(activeSpaceIdProvider);
    final watchMyId = ref.read(deviceIdProvider).valueOrNull;
    if (watchSpaceId != null && watchMyId != null) {
      _listeners.add(
        ref.listenManual<AsyncValue<dynamic>>(
          ytSessionProvider(watchSpaceId),
          (previous, next) {
            final prevSession = previous?.valueOrNull;
            final nextSession = next.valueOrNull;

            // Fire only when a NEW session appears (wasn't there before)
            // AND it was started by the partner (not us)
            if (nextSession != null &&
                prevSession == null &&
                nextSession.startedBy != watchMyId) {
              if (!mounted) return;

              // Only auto-navigate if not already on the watch screen
              final loc = GoRouterState.of(context).uri.toString();
              if (loc.contains('youtube-sync')) return;

              // Show a banner and auto-navigate after a short delay
              ScaffoldMessenger.of(context).showMaterialBanner(
                MaterialBanner(
                  backgroundColor: const Color(0xFF1A0A2E),
                  leading: const Text('🎬', style: TextStyle(fontSize: 28)),
                  content: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Partner started Watch Together!',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                      Text(
                        nextSession.videoTitle.isNotEmpty
                            ? nextSession.videoTitle
                            : 'Tap to join',
                        style: TextStyle(color: Colors.white60, fontSize: 12),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                  actions: [
                    TextButton(
                      onPressed: () {
                        ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
                      },
                      child: const Text('Dismiss',
                          style: TextStyle(color: Colors.white38)),
                    ),
                    TextButton(
                      onPressed: () {
                        ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
                        context.push('/youtube-sync');
                      },
                      child: const Text('Join Now',
                          style: TextStyle(
                              color: Color(0xFFFF0000),
                              fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              );

              // Also auto-navigate after 3 seconds if they don't tap
              Future.delayed(const Duration(seconds: 3), () {
                if (!mounted) return;
                ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
                final currentLoc = GoRouterState.of(context).uri.toString();
                if (!currentLoc.contains('youtube-sync')) {
                  context.push('/youtube-sync');
                }
              });
            }
          },
        ),
      );
    }

    // ── Screen Share: auto-navigate partner when host goes live ──────────────
    final streamSpaceId = ref.read(activeSpaceIdProvider);
    final streamMyId = ref.read(deviceIdProvider).valueOrNull;
    if (streamSpaceId != null && streamMyId != null) {
      _listeners.add(
        ref.listenManual<AsyncValue<dynamic>>(
          streamSessionProvider(streamSpaceId),
          (previous, next) {
            final prevSession = previous?.valueOrNull;
            final nextSession = next.valueOrNull;

            // Fire only when a NEW live session appears (host went live)
            // AND it's the partner who started it (not us)
            if (nextSession != null &&
                nextSession.isLive == true &&
                (prevSession == null || prevSession.isLive != true) &&
                nextSession.hostId != streamMyId) {
              if (!mounted) return;

              // Don't navigate if already on the stream screen
              final loc = GoRouterState.of(context).uri.toString();
              if (loc.contains('stream')) return;

              // Get space info to open the stream as viewer
              final space = ref.read(spaceStreamProvider).valueOrNull;
              if (space == null) return;

              ScaffoldMessenger.of(context).showMaterialBanner(
                MaterialBanner(
                  backgroundColor: const Color(0xFF0D0D1A),
                  leading: const Text('📺', style: TextStyle(fontSize: 28)),
                  content: const Text(
                    'Partner started a live stream!',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () {
                        ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
                      },
                      child: const Text('Dismiss',
                          style: TextStyle(color: Colors.white38)),
                    ),
                    TextButton(
                      onPressed: () {
                        ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
                        context.push('/stream');
                      },
                      child: const Text('Join Live',
                          style: TextStyle(
                              color: Colors.redAccent,
                              fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              );

              // Auto-navigate after 5 seconds
              Future.delayed(const Duration(seconds: 5), () {
                if (!mounted) return;
                ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
                final currentLoc = GoRouterState.of(context).uri.toString();
                if (!currentLoc.contains('stream')) {
                  context.push('/stream');
                }
              });
            }
          },
        ),
      );
    }
  }

  Future<void> _handleWidgetClick(Uri? uri) async {
    // Guard: don't use ref after disposal
    if (!mounted) return;
    final spaceId = ref.read(spaceStreamProvider).value?.id;
    final deviceId = ref.read(deviceIdProvider).value;
    if (spaceId == null || deviceId == null) return;

    final emoji = await HomeWidget.getWidgetData<String>('widget_tapped_emoji');
    if (emoji == null || emoji.isEmpty) return;

    // Guard again after the await gap
    if (!mounted) return;
    final repo = ref.read(questionRepositoryProvider);
    await repo.submitMood(spaceId: spaceId, deviceId: deviceId, emoji: emoji);
    await HomeWidget.saveWidgetData<String>('widget_tapped_emoji', '');
  }

  @override
  void dispose() {
    _widgetClickedSub?.cancel();
    // Close all manual listeners to prevent memory leaks
    for (final sub in _listeners) {
      sub.close();
    }
    try {
      ShowcaseView.get().unregister();
    } catch (_) {}
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final spaceAsync = ref.watch(spaceStreamProvider);
    final deviceIdAsync = ref.watch(deviceIdProvider);
    final questionAsync = ref.watch(todayQuestionProvider);
    final answersAsync = ref.watch(todayAnswersProvider);
    final moodsAsync = ref.watch(todayMoodsProvider);

    return Scaffold(
      body: SafeArea(
        child: spaceAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => _ErrorView(message: AppUtils.getFriendlyErrorMessage(e)),
          data: (space) {
            if (space == null) {
              return const _ErrorView(message: 'No space found. Restart the app.');
            }
            return deviceIdAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => _ErrorView(message: AppUtils.getFriendlyErrorMessage(e)),
              data: (deviceId) => _HomeBody(
                space: space,
                deviceId: deviceId,
                questionAsync: questionAsync,
                answersAsync: answersAsync,
                moodsAsync: moodsAsync,
              ),
            );
          },
        ),
      ),
    );
  }
}

// ─── Body ─────────────────────────────────────────────────────────────────────

class _HomeBody extends ConsumerWidget {
  final SpaceModel space;
  final String deviceId;
  final AsyncValue<QuestionModel?> questionAsync;
  final AsyncValue<DailyAnswerModel?> answersAsync;
  final AsyncValue<DailyMoodModel?> moodsAsync;

  const _HomeBody({
    required this.space,
    required this.deviceId,
    required this.questionAsync,
    required this.answersAsync,
    required this.moodsAsync,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return CustomScrollView(
      slivers: [
        SliverAppBar(
          floating: true,
          title: Row(
            children: [
              Text(
                space.spaceName.isNotEmpty ? space.spaceName : 'OurVerse',
              ),
              const Spacer(),
              Showcase(
                key: _keyStreak,
                title: '🔥 Your Streak',
                description: 'Open the app every day together to keep\nyour streak alive. Don\'t break the chain!',
                titleTextStyle: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15),
                descTextStyle: const TextStyle(
                  color: Colors.white70, fontSize: 13, height: 1.5),
                tooltipBackgroundColor: const Color(0xFF1A1A2E),
                targetShapeBorder: const CircleBorder(),
                child: _StreakBadge(streak: space.currentStreak),
              ),
            ],
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Mood Section ──────────────────────────────────────────
                Text(
                  'How are you feeling today?',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                Showcase(
                  key: _keyMood,
                  title: '😊 Mood Check-in',
                  description: 'Tap an emoji to share how you\'re feeling.\nYour partner sees it instantly.',
                  titleTextStyle: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15),
                  descTextStyle: const TextStyle(
                    color: Colors.white70, fontSize: 13, height: 1.5),
                  tooltipBackgroundColor: const Color(0xFF1A1A2E),
                  child: moodsAsync.when(
                    loading: () => const _MoodRowSkeleton(),
                    error: (_, __) => const SizedBox(),
                    data: (moods) => _MoodRow(
                      deviceId: deviceId,
                      members: space.memberDeviceIds,
                      moods: moods,
                      spaceId: space.id,
                    ),
                  ),
                ),

                const SizedBox(height: 28),

                // ── Question Section ──────────────────────────────────────
                Text(
                  AppUtils.formatDate(DateTime.now()),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        letterSpacing: 1,
                      ),
                ),
                const SizedBox(height: 8),
                Showcase(
                  key: _keyQuestion,
                  title: '❓ Daily Question',
                  description: 'A new question every single day.\nAnswer it — see each other\'s reply once both have answered.',
                  titleTextStyle: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15),
                  descTextStyle: const TextStyle(
                    color: Colors.white70, fontSize: 13, height: 1.5),
                  tooltipBackgroundColor: const Color(0xFF1A1A2E),
                  child: questionAsync.when(
                    loading: () => const _QuestionCardSkeleton(),
                    error: (e, __) => _QuestionErrorCard(onRetry: () => ref.invalidate(todayQuestionProvider)),
                    data: (question) {
                      if (question == null) return _QuestionErrorCard(onRetry: () => ref.invalidate(todayQuestionProvider));
                      return answersAsync.when(
                        loading: () => const _QuestionCardSkeleton(),
                        error: (_, __) => const SizedBox(),
                        data: (answers) => _QuestionCard(
                          questionText: question.text,
                          hasAnswered: answers?.hasAnswered(deviceId) ?? false,
                          revealed: answers?.revealed ?? false,
                          answeredCount: answers?.answers.length ?? 0,
                          totalCount: space.memberDeviceIds.length,
                          onTap: () => context.push('/question'),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 24),

                // ── Stream Banner ─────────────────────────────────────────
                Showcase(
                  key: _keyStream,
                  title: '📹 Go Live Together',
                  description: 'Stream your camera or share your screen\nlive to your partner in real time.',
                  titleTextStyle: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15),
                  descTextStyle: const TextStyle(
                    color: Colors.white70, fontSize: 13, height: 1.5),
                  tooltipBackgroundColor: const Color(0xFF1A1A2E),
                  child: GestureDetector(
                    onTap: () => context.push('/stream'),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            AppTheme.primary.withValues(alpha: 0.85),
                            AppTheme.accent.withValues(alpha: 0.85),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(Icons.live_tv, color: Colors.white, size: 24),
                          ),
                          const SizedBox(width: 14),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Go Live',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 16,
                                  ),
                                ),
                                Text(
                                  'Stream your camera to your partner',
                                  style: TextStyle(color: Colors.white70, fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                          const Icon(Icons.chevron_right, color: Colors.white70),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Streak Badge ─────────────────────────────────────────────────────────────

class _StreakBadge extends StatelessWidget {
  final int streak;
  const _StreakBadge({required this.streak});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.accent.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('🔥', style: TextStyle(fontSize: 16)),
          const SizedBox(width: 4),
          Text(
            '$streak',
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              color: AppTheme.accent,
              fontSize: 15,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Mood Row ─────────────────────────────────────────────────────────────────

class _MoodRow extends ConsumerWidget {
  final String deviceId;
  final List<String> members;
  final DailyMoodModel? moods;
  final String spaceId;

  const _MoodRow({
    required this.deviceId,
    required this.members,
    required this.moods,
    required this.spaceId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final myMood = moods?.entries[deviceId];
    final partnerIds = members.where((id) => id != deviceId).toList();
    final partnerMood = partnerIds.isNotEmpty ? moods?.entries[partnerIds.first] : null;
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: 0.85),
            AppTheme.primary.withValues(alpha: 0.06),
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: AppTheme.primary.withValues(alpha: 0.25),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primary.withValues(alpha: 0.08),
            blurRadius: 20,
            spreadRadius: 0,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  'TODAY\'S MOOD',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: AppTheme.primary,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
              const Spacer(),
              if (myMood != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.check_circle, color: AppTheme.primary, size: 12),
                      const SizedBox(width: 4),
                      Text(
                        'Logged',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: AppTheme.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),

          // Emoji selector
          if (myMood != null) ...[
            // Big selected mood
            Center(
              child: AppTheme.animatedMoods[myMood.emoji] != null
                  ? AnimatedEmoji(
                      AppTheme.animatedMoods[myMood.emoji]!,
                      size: 80,
                    )
                  : Text(
                      myMood.emoji,
                      style: const TextStyle(fontSize: 80),
                    ),
            ),
            const SizedBox(height: 16),
            Center(
              child: Text(
                'Change mood',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: AppTheme.onSurfaceMuted,
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
          SizedBox(
            width: double.infinity,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: AppTheme.moodEmojis.map((emoji) {
                final isSelected = myMood?.emoji == emoji;
                if (isSelected) return const SizedBox.shrink(); // Hide from the options list if it's currently the big selected one

                return _PressableButton(
                  onTap: () async {
                    _vibrate();
                    final repo = ref.read(questionRepositoryProvider);
                    await repo.submitMood(
                      spaceId: spaceId,
                      deviceId: deviceId,
                      emoji: emoji,
                    );
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOutBack,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceAlt,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppTheme.divider, width: 1.5),
                    ),
                    child: AppTheme.animatedMoods[emoji] != null
                        ? AnimatedEmoji(
                            AppTheme.animatedMoods[emoji]!,
                            size: 28,
                          )
                        : Text(
                            emoji,
                            style: const TextStyle(fontSize: 28),
                          ),
                  ),
                );
              }).toList(),
            ),
          ),

          // Partner mood section
          if (members.length > 1) ...[
            const SizedBox(height: 20),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: AppTheme.surfaceAlt.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: AppTheme.divider,
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Partner\'s mood',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: AppTheme.onSurfaceMuted,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        partnerMood != null
                            ? 'Feeling it today 💞'
                            : 'Not checked in yet',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: partnerMood != null
                              ? AppTheme.onSurface
                              : AppTheme.onSurfaceMuted,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  if (partnerMood != null &&
                      AppTheme.animatedMoods[partnerMood.emoji] != null)
                    AnimatedEmoji(
                      AppTheme.animatedMoods[partnerMood.emoji]!,
                      size: 44,
                    )
                  else
                    Text(
                      partnerMood != null ? partnerMood.emoji : '⏳',
                      style: const TextStyle(fontSize: 40),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Question Card ────────────────────────────────────────────────────────────

class _QuestionCard extends StatelessWidget {
  final String questionText;
  final bool hasAnswered;
  final bool revealed;
  final int answeredCount;
  final int totalCount;
  final VoidCallback onTap;

  const _QuestionCard({
    required this.questionText,
    required this.hasAnswered,
    required this.revealed,
    required this.answeredCount,
    required this.totalCount,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    String statusText;
    IconData statusIcon;
    Color statusColor;

    if (revealed) {
      statusText = 'Tap to see answers';
      statusIcon = Icons.visibility;
      statusColor = AppTheme.primary;
    } else if (hasAnswered) {
      statusText = 'Waiting ($answeredCount/$totalCount answered)';
      statusIcon = Icons.hourglass_top;
      statusColor = AppTheme.accent;
    } else {
      statusText = "Answer today's question";
      statusIcon = Icons.arrow_forward;
      statusColor = AppTheme.primary;
    }

    return _PressableButton(
      onTap: () {
        _vibrate(duration: 60);
        onTap();
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppTheme.primary.withValues(alpha: 0.08),
              AppTheme.primary.withValues(alpha: 0.02),
            ],
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: AppTheme.primary.withValues(alpha: 0.3), width: 1.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                "TODAY'S QUESTION",
                style: theme.textTheme.labelSmall?.copyWith(
                  color: AppTheme.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              questionText,
              style: theme.textTheme.headlineMedium?.copyWith(height: 1.3),
              maxLines: 5,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Icon(statusIcon, color: statusColor, size: 16),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    statusText,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: statusColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Pressable Button ──────────────────────────────────────────────────────────
// Scale-down press animation + vibration wrapper. Drop-in replacement for
// GestureDetector that gives physical feedback on all Android devices.
class _PressableButton extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;

  const _PressableButton({required this.child, required this.onTap});

  @override
  State<_PressableButton> createState() => _PressableButtonState();
}

class _PressableButtonState extends State<_PressableButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 90),
      reverseDuration: const Duration(milliseconds: 180),
      lowerBound: 0,
      upperBound: 1,
    );
    _scale = Tween<double>(begin: 1.0, end: 0.93).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _onTapDown(_) => _ctrl.forward();
  void _onTapUp(_) {
    _ctrl.reverse();
    widget.onTap();
  }
  void _onTapCancel() => _ctrl.reverse();

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: _onTapDown,
      onTapUp: _onTapUp,
      onTapCancel: _onTapCancel,
      child: AnimatedBuilder(
        animation: _scale,
        builder: (_, child) => Transform.scale(scale: _scale.value, child: child),
        child: widget.child,
      ),
    );
  }
}

// ─── Skeletons ────────────────────────────────────────────────────────────────

class _MoodRowSkeleton extends StatelessWidget {
  const _MoodRowSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 80,
      decoration: BoxDecoration(
        color: AppTheme.surfaceAlt,
        borderRadius: BorderRadius.circular(20),
      ),
    );
  }
}

class _QuestionCardSkeleton extends StatelessWidget {
  const _QuestionCardSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 160,
      decoration: BoxDecoration(
        color: AppTheme.surfaceAlt,
        borderRadius: BorderRadius.circular(20),
      ),
    );
  }
}

// ─── Error View ────────────────────────────────────────────────────────────────

class _ErrorView extends StatelessWidget {
  final String message;
  const _ErrorView({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(message, style: Theme.of(context).textTheme.bodyMedium),
      ),
    );
  }
}

// ─── Question Error Card ───────────────────────────────────────────────────────

class _QuestionErrorCard extends StatelessWidget {
  final VoidCallback onRetry;
  const _QuestionErrorCard({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppTheme.primary.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('🌐', style: TextStyle(fontSize: 32)),
          const SizedBox(height: 12),
          Text(
            'Couldn\'t load today\'s question',
            style: theme.textTheme.titleSmall?.copyWith(
              color: AppTheme.onSurfaceMuted,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded, size: 16),
            label: const Text('Retry'),
            style: TextButton.styleFrom(
              foregroundColor: AppTheme.primary,
            ),
          ),
        ],
      ),
    );
  }
}


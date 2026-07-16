import 'package:closer/core/utils/app_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../data/models/models.dart';
import '../../../../data/services/notification_service.dart';
import '../../../../shared/providers/app_providers.dart';
import '../../../../core/ads/ad_service.dart';

class QuestionDetailScreen extends ConsumerStatefulWidget {
  const QuestionDetailScreen({super.key});

  @override
  ConsumerState<QuestionDetailScreen> createState() =>
      _QuestionDetailScreenState();
}

class _QuestionDetailScreenState extends ConsumerState<QuestionDetailScreen>
    with SingleTickerProviderStateMixin {
  final _controller = TextEditingController();
  bool _submitting = false;
  bool _justSubmitted = false; // drives the success micro-animation

  late final AnimationController _successCtrl;
  late final Animation<double> _successScale;

  @override
  void initState() {
    super.initState();
    _successCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _successScale = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _successCtrl, curve: Curves.elasticOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _successCtrl.dispose();
    super.dispose();
  }

  Future<void> _submitAnswer(
    String spaceId,
    String deviceId,
    List<String> memberIds,
  ) async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    // Dismiss keyboard
    FocusScope.of(context).unfocus();

    setState(() => _submitting = true);
    try {
      final repo = ref.read(questionRepositoryProvider);
      await repo.submitAnswer(
        spaceId: spaceId,
        deviceId: deviceId,
        answerText: text,
        allMemberIds: memberIds,
      );

      // Cancel today's reminder — user already answered
      await NotificationService.cancelTodayReminder();

      // Update streak
      await ref.read(spaceRepositoryProvider).updateStreak(spaceId);

      // Show interstitial ad if ready (natural transition)
      AdService.instance.showInterstitialIfReady();

      // Show success animation
      if (mounted) {
        setState(() => _justSubmitted = true);
        _successCtrl.forward(from: 0);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to submit: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final spaceAsync = ref.watch(spaceStreamProvider);
    final deviceIdAsync = ref.watch(deviceIdProvider);
    final deviceNameAsync = ref.watch(deviceNameProvider);
    final questionAsync = ref.watch(todayQuestionProvider);
    final answersAsync = ref.watch(todayAnswersProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text("Today's Question")),
      body: SafeArea(
        child: spaceAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text(AppUtils.getFriendlyErrorMessage(e), textAlign: TextAlign.center,)),
          data: (space) {
            if (space == null) return const SizedBox();
            return deviceIdAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text(AppUtils.getFriendlyErrorMessage(e), textAlign: TextAlign.center,)),
              data: (deviceId) => questionAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text(AppUtils.getFriendlyErrorMessage(e), textAlign: TextAlign.center,)),
                data: (question) {
                  if (question == null) return const SizedBox();
                  return answersAsync.when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (e, _) => Center(child: Text(AppUtils.getFriendlyErrorMessage(e), textAlign: TextAlign.center,)),
                    data: (answers) {
                      final hasAnswered =
                          answers?.hasAnswered(deviceId) ?? false;
                      final revealed = answers?.revealed ?? false;

                      return SingleChildScrollView(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // ── Question text ──────────────────────────────
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(24),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    AppTheme.primary.withValues(alpha: 0.1),
                                    AppTheme.primary.withValues(alpha: 0.03),
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                    color: AppTheme.primary
                                        .withValues(alpha: 0.2)),
                              ),
                              child: Text(
                                question.text,
                                style: theme.textTheme.headlineMedium,
                                textAlign: TextAlign.center,
                              ),
                            ),

                            const SizedBox(height: 32),

                            // ── Revealed state ────────────────────────────
                            if (revealed) ...[
                              _buildRevealSection(
                                context,
                                answers!,
                                space.memberDeviceIds,
                                deviceId,
                                deviceNameAsync.value ?? 'You',
                              ),
                            ]

                            // ── Just submitted animation ──────────────────
                            else if (_justSubmitted || hasAnswered) ...[
                              _buildWaitingState(
                                context,
                                answers?.answers.length ?? 0,
                                space.memberDeviceIds.length,
                                justSubmitted: _justSubmitted,
                                successScale: _successScale,
                              ),
                            ]

                            // ── Answer input ──────────────────────────────
                            else ...[
                              Text(
                                'Your answer',
                                style: theme.textTheme.titleLarge,
                              ),
                              const SizedBox(height: 12),
                              TextField(
                                controller: _controller,
                                maxLines: 5,
                                textCapitalization:
                                    TextCapitalization.sentences,
                                decoration: const InputDecoration(
                                  hintText: 'Write your honest answer...',
                                  alignLabelWithHint: true,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'Your answer is hidden until everyone has replied.',
                                style: theme.textTheme.bodyMedium,
                              ),
                              const SizedBox(height: 20),
                              ElevatedButton(
                                onPressed: _submitting
                                    ? null
                                    : () => _submitAnswer(
                                          space.id,
                                          deviceId,
                                          space.memberDeviceIds,
                                        ),
                                child: _submitting
                                    ? const SizedBox(
                                        height: 20,
                                        width: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Text('Submit answer'),
                              ),
                            ],
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildWaitingState(
    BuildContext context,
    int answered,
    int total, {
    required bool justSubmitted,
    required Animation<double> successScale,
  }) {
    final theme = Theme.of(context);
    return Column(
      children: [
        if (justSubmitted) ...[
          ScaleTransition(
            scale: successScale,
            child: Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
                border: Border.all(color: AppTheme.primary, width: 2),
              ),
              child: const Center(
                child: Text('✅', style: TextStyle(fontSize: 36)),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Answer submitted!',
            style: theme.textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
        ] else ...[
          const Text('⏳', style: TextStyle(fontSize: 48)),
          const SizedBox(height: 16),
          Text(
            'Waiting for everyone to answer...',
            style: theme.textTheme.headlineMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
        ],
        Text(
          '$answered of $total answered',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        LinearProgressIndicator(
          value: total > 0 ? answered / total : 0,
          backgroundColor: AppTheme.surfaceAlt,
          valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.primary),
          minHeight: 8,
          borderRadius: BorderRadius.circular(4),
        ),
      ],
    );
  }

  Widget _buildRevealSection(
    BuildContext context,
    DailyAnswerModel answers,
    List<String> memberIds,
    String myDeviceId,
    String myName,
  ) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('✨', style: TextStyle(fontSize: 24)),
            const SizedBox(width: 8),
            Text('Everyone answered!', style: theme.textTheme.titleLarge),
          ],
        ),
        const SizedBox(height: 20),
        ...memberIds.map((id) {
          final entry = answers.answers[id];
          if (entry == null) return const SizedBox();
          final isMe = id == myDeviceId;
          final label = isMe ? myName : 'Partner';
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isMe
                    ? AppTheme.primary.withValues(alpha: 0.08)
                    : Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isMe
                      ? AppTheme.primary.withValues(alpha: 0.3)
                      : AppTheme.divider,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: isMe ? AppTheme.primary : AppTheme.onSurfaceMuted,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(entry.text, style: theme.textTheme.bodyLarge),
                  const SizedBox(height: 4),
                  Text(
                    '${entry.submittedAt.hour.toString().padLeft(2, '0')}:${entry.submittedAt.minute.toString().padLeft(2, '0')}',
                    style: theme.textTheme.bodyMedium?.copyWith(fontSize: 11),
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }
}

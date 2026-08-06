import 'package:closer/core/utils/app_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/providers/app_providers.dart';
import '../../../vibe/presentation/widgets/sync_status_chip.dart';
import '../../../../core/ads/ad_service.dart';

class WyrGameScreen extends ConsumerStatefulWidget {
  final String spaceId;
  final List<String> memberIds;
  final String deviceId;

  const WyrGameScreen({
    super.key,
    required this.spaceId,
    required this.memberIds,
    required this.deviceId,
  });

  @override
  ConsumerState<WyrGameScreen> createState() => _WyrGameScreenState();
}

class _WyrGameScreenState extends ConsumerState<WyrGameScreen> {
  late final PresenceRepository _presenceRepo;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _presenceRepo = ref.read(presenceRepositoryProvider);
      _presenceRepo.setPresent(widget.spaceId, 'wyr', widget.deviceId);
    });
  }

  @override
  void dispose() {
    _presenceRepo.setAbsent(widget.spaceId, 'wyr', widget.deviceId);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final questions = ref.watch(wyrQuestionsProvider);
    final currentIndex = ref.watch(wyrCurrentIndexProvider);
    final sessionAsync = ref.watch(wyrSessionProvider);
    final theme = Theme.of(context);
    final isSinglePlayer = widget.memberIds.length == 1;

    final partnerId = widget.memberIds.firstWhere((id) => id != widget.deviceId, orElse: () => '');
    final partnerPresentAsync = partnerId.isEmpty
        ? const AsyncData(false)
        : ref.watch(featurePresenceProvider(
            (spaceId: widget.spaceId, featureId: 'wyr', partnerId: partnerId)));
    final partnerPresent = partnerPresentAsync.valueOrNull ?? false;

    if (currentIndex >= questions.length) {
      return Scaffold(
        appBar: AppBar(
          title: const FittedBox(fit: BoxFit.scaleDown, child: Text('Would You Rather')),
          actions: [
            Center(
              child: SyncStatusChip(
                state: partnerPresent ? SyncState.inSync : SyncState.partnerLeft,
              ),
            ),
            const SizedBox(width: 16),
          ],
        ),
        bottomNavigationBar: const SafeArea(
          child: SizedBox(
            height: 50,
            child: Center(child: AdBannerWidget()),
          ),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('🎉', style: TextStyle(fontSize: 48)),
              const SizedBox(height: 16),
              Text(
                "You've answered all 10 questions for today!",
                style: theme.textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                "Come back tomorrow for a new set.",
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () {
                  AdService.instance.showInterstitialIfReady();
                  Navigator.pop(context);
                },
                child: const Text('Back to Games'),
              ),
            ],
          ),
        ),
      );
    }

    final current = questions[currentIndex];

    return Scaffold(
      appBar: AppBar(
        title: const FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text('Would You Rather'),
        ),
        actions: [
          Center(
            child: SyncStatusChip(
              state: partnerPresent ? SyncState.inSync : SyncState.partnerLeft,
            ),
          ),
          const SizedBox(width: 16),
        ],
      ),
      bottomNavigationBar: const SafeArea(
        child: SizedBox(
          height: 50,
          child: Center(child: AdBannerWidget()),
        ),
      ),
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverFillRemaining(
              hasScrollBody: false,
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    const Spacer(),
                    Text('Pick one...', style: theme.textTheme.bodyMedium),
                    const SizedBox(height: 24),

                    // ── Session-driven UI ──────────────────────────────────────
                    sessionAsync.when(
                      loading: () =>
                          const Center(child: CircularProgressIndicator()),
                      error: (e, _) => Center(child: Text(AppUtils.getFriendlyErrorMessage(e), textAlign: TextAlign.center,)),
                      data: (session) {
                        final myChoice = session?.choices[widget.deviceId];
                        final revealed = session?.revealed ?? false;
                        final effectivelyRevealed =
                            revealed || (isSinglePlayer && myChoice != null);

                        return Column(
                          children: [
                            // Option A
                            _WyrOption(
                              text: current.optionA,
                              label: 'A',
                              selected: myChoice == 'A',
                              dimmed: effectivelyRevealed && myChoice != 'A',
                              partnerChose: effectivelyRevealed &&
                                  _partnerChose(session, widget.deviceId, widget.memberIds) == 'A',
                              color: AppTheme.primary,
                              onTap: myChoice == null
                                  ? () => _pick(ref, 'A', currentIndex)
                                  : null,
                            ),

                            const SizedBox(height: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 6),
                              decoration: BoxDecoration(
                                color: AppTheme.surfaceAlt,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                'OR',
                                style: theme.textTheme.labelSmall
                                    ?.copyWith(fontWeight: FontWeight.w800),
                              ),
                            ),
                            const SizedBox(height: 4),

                            // Option B
                            _WyrOption(
                              text: current.optionB,
                              label: 'B',
                              selected: myChoice == 'B',
                              dimmed: effectivelyRevealed && myChoice != 'B',
                              partnerChose: effectivelyRevealed &&
                                  _partnerChose(session, widget.deviceId, widget.memberIds) == 'B',
                              color: const Color(0xFF5B8AF5),
                              onTap: myChoice == null
                                  ? () => _pick(ref, 'B', currentIndex)
                                  : null,
                            ),

                            // ── Waiting state ──────────────────────────────────
                            if (myChoice != null && !effectivelyRevealed) ...[
                              const SizedBox(height: 24),
                              _WaitingBanner(
                                answered: session?.choices.length ?? 0,
                                total: widget.memberIds.length,
                              ),
                            ],

                            // ── Reveal state ───────────────────────────────────
                            if (effectivelyRevealed) ...[
                              const SizedBox(height: 24),
                              _RevealBanner(
                                session: session,
                                myId: widget.deviceId,
                                members: widget.memberIds,
                                optionA: current.optionA,
                                optionB: current.optionB,
                                isSinglePlayer: isSinglePlayer,
                              ),
                              if (session != null && session.revealed && !isSinglePlayer) ...[
                                const Spacer(),
                                ElevatedButton(
                                  onPressed: () => ref
                                      .read(wyrCurrentIndexProvider.notifier)
                                      .setIndex(currentIndex + 1),
                                  child: Text(
                                    currentIndex + 1 >= questions.length
                                        ? 'Finish 🎉'
                                        : 'Next question →',
                                  ),
                                ),
                              ],
                            ],
                          ],
                        );
                      },
                    ),

                    const Spacer(),

                    // ── Counter ───────────────────────────────────────────────
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '${currentIndex + 1} / ${questions.length}',
                          style: theme.textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _pick(WidgetRef ref, String choice, int index) {
    ref.read(wyrRepositoryProvider).submitChoice(
          spaceId: widget.spaceId,
          questionIndex: index,
          deviceId: widget.deviceId,
          choice: choice,
          allMemberIds: widget.memberIds,
        );
  }

  String? _partnerChose(dynamic session, String myId, List<String> members) {
    if (session == null) return null;
    final choices = session.choices as Map<String, dynamic>;
    for (final id in members) {
      if (id != myId && choices.containsKey(id)) {
        return choices[id];
      }
    }
    return null;
  }
}

// ─── Waiting Banner ───────────────────────────────────────────────────────────

class _WaitingBanner extends StatelessWidget {
  final int answered;
  final int total;
  const _WaitingBanner({required this.answered, required this.total});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.accent.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.accent.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Text(
            '⏳ Waiting for your partner...',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: AppTheme.accent,
                ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: total > 0 ? answered / total : 0,
            backgroundColor: AppTheme.surfaceAlt,
            valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.accent),
            borderRadius: BorderRadius.circular(4),
          ),
        ],
      ),
    );
  }
}

// ─── Reveal Banner ────────────────────────────────────────────────────────────

class _RevealBanner extends StatelessWidget {
  final dynamic session;
  final String myId;
  final List<String> members;
  final String optionA;
  final String optionB;
  final bool isSinglePlayer;

  const _RevealBanner({
    required this.session,
    required this.myId,
    required this.members,
    required this.optionA,
    required this.optionB,
    required this.isSinglePlayer,
  });

  String _label(String? choice) {
    if (choice == null || choice.isEmpty) return '—';
    return choice == 'A' ? optionA : optionB;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final choices = session?.choices as Map<String, dynamic>? ?? {};
    final myChoice = choices[myId] as String? ?? '';
    
    bool allAgree = false;
    if (members.length > 1 && myChoice.isNotEmpty) {
      allAgree = members.every((id) => choices[id] == myChoice);
    }

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 400),
      opacity: 1,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: allAgree
              ? AppTheme.primary.withValues(alpha: 0.08)
              : AppTheme.surfaceAlt,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: allAgree
                  ? AppTheme.primary.withValues(alpha: 0.3)
                  : AppTheme.divider),
        ),
        child: Column(
          children: [
            if (allAgree) ...[
              const Text('🎉', style: TextStyle(fontSize: 28)),
              const SizedBox(height: 4),
              Text(
                members.length <= 2 ? 'You both chose the same!' : 'Everyone chose the same!',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppTheme.primary,
                ),
              ),
            ] else if (!isSinglePlayer && choices.length > 1) ...[
              Text(
                'Different picks — interesting!',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ] else ...[
              Text(
                'Ask your partner what they\'d pick! 😄',
                style: theme.textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
            ],
            if (!isSinglePlayer && choices.length > 1) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: members.map((id) {
                  final choice = choices[id] as String?;
                  final isMe = id == myId;
                  final label = isMe 
                      ? 'You' 
                      : (members.length <= 2 ? 'Partner' : 'Friend ${id.length > 5 ? id.substring(0, 6).toUpperCase() : id}');
                  
                  return SizedBox(
                    width: (MediaQuery.of(context).size.width - 88) / 2,
                    child: _ChoiceChip(label: label, choice: _label(choice)),
                  );
                }).toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ChoiceChip extends StatelessWidget {
  final String label;
  final String choice;
  const _ChoiceChip({required this.label, required this.choice});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Column(
        children: [
          Text(label, style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: 4),
          Text(
            choice,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(fontWeight: FontWeight.w700),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

// ─── WYR Option ───────────────────────────────────────────────────────────────

class _WyrOption extends StatelessWidget {
  final String text;
  final String label;
  final bool selected;
  final bool dimmed;
  final bool partnerChose;
  final Color color;
  final VoidCallback? onTap;

  const _WyrOption({
    required this.text,
    required this.label,
    required this.selected,
    required this.dimmed,
    required this.partnerChose,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 300),
      opacity: dimmed ? 0.35 : 1.0,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: selected
                ? color.withValues(alpha: 0.1)
                : partnerChose
                    ? color.withValues(alpha: 0.05)
                    : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected
                  ? color
                  : partnerChose
                      ? color.withValues(alpha: 0.5)
                      : AppTheme.divider,
              width: selected ? 2 : 1.5,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    label,
                    style: TextStyle(color: color, fontWeight: FontWeight.w800),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  text,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight:
                        selected ? FontWeight.w700 : FontWeight.normal,
                  ),
                ),
              ),
              if (selected) Icon(Icons.check_circle, color: color, size: 20),
              if (partnerChose && !selected)
                Icon(Icons.person,
                    color: color.withValues(alpha: 0.6), size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

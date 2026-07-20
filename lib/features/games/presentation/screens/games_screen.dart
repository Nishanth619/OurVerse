import 'package:closer/core/utils/app_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/providers/app_providers.dart';

class GamesScreen extends ConsumerWidget {
  const GamesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spaceAsync = ref.watch(spaceStreamProvider);
    final deviceIdAsync = ref.watch(deviceIdProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const FittedBox(fit: BoxFit.scaleDown, child: Text('Games'))),
      body: SafeArea(
        child: spaceAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text(AppUtils.getFriendlyErrorMessage(e), textAlign: TextAlign.center,)),
          data: (space) {
            if (space == null) {
              return const Center(child: Text('No space found.'));
            }
            return deviceIdAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text(AppUtils.getFriendlyErrorMessage(e), textAlign: TextAlign.center,)),
              data: (deviceId) {
                return CustomScrollView(
                  slivers: [
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
                      sliver: SliverToBoxAdapter(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Mini Games',
                              style: theme.textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Play together and learn more about each other.',
                              style: theme.textTheme.bodyMedium,
                            ),
                          ],
                        ),
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      sliver: SliverGrid(
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 16,
                          mainAxisSpacing: 16,
                          childAspectRatio: 0.80,
                        ),
                        delegate: SliverChildListDelegate([
                          // —— Game Card 1: Let's Understand Each Other ——
                          _GameCard(
                            title: "Would You Rather",
                            subtitle: "10 daily questions",
                            emoji: '🤔',
                            color: AppTheme.accent,
                            onTap: () {
                              context.push('/games/wyr');
                            },
                          ),
                          // —— Game Card 2: Doodle with Me ——
                          _GameCard(
                            title: "Doodle with Me",
                            subtitle: "Draw together",
                            emoji: '🎨',
                            color: const Color(0xFF5B8AF5),
                            onTap: () {
                              context.push('/games/doodle');
                            },
                          ),
                          // —— Game Card 3: Flash ——
                          _GameCard(
                            title: 'Flash ⚡',
                            subtitle: 'Daily photo streak',
                            emoji: '📸',
                            color: const Color(0xFFFF7043),
                            onTap: () {
                              context.push('/games/flash');
                            },
                          ),
                          // —— Game Card 4: Arcade Games ——
                          _GameCard(
                            title: 'Arcade Games',
                            subtitle: 'Multiplayer games',
                            emoji: '🕹️',
                            color: const Color(0xFF9C27B0), // Purple color
                            onTap: () {
                              context.push('/games/arcade');
                            },
                          ),
                          // —— Game Card 5: Watch Together (YouTube) ——
                          _GameCard(
                            title: 'Watch Together',
                            subtitle: 'Sync YouTube videos',
                            emoji: '🍿',
                            color: const Color(0xFFF44336), // YouTube Red
                            onTap: () => context.push('/youtube-sync'),
                          ),
                          // —— Game Card 6: Vibe Together ——
                          _GameCard(
                            title: 'Vibe Together',
                            subtitle: 'Listen to music in sync',
                            emoji: '🎧',
                            color: const Color(0xFFB388FF),
                            onTap: () => context.push('/vibe'),
                          ),
                        ]),
                      ),
                    ),
                    const SliverPadding(padding: EdgeInsets.only(bottom: 32)),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }

}

class _GameCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final String emoji;
  final Color color;
  final VoidCallback onTap;

  const _GameCard({
    required this.title,
    required this.subtitle,
    required this.emoji,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppTheme.divider),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(emoji, style: const TextStyle(fontSize: 24)),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppTheme.onSurfaceMuted,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

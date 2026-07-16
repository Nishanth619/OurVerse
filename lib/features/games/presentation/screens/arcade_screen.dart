import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../shared/providers/app_providers.dart';
import '../../../vibe/presentation/widgets/sync_status_chip.dart';

class ArcadeScreen extends ConsumerStatefulWidget {
  final String spaceId;
  final List<String> memberIds;
  final String deviceId;

  const ArcadeScreen({
    super.key,
    required this.spaceId,
    required this.memberIds,
    required this.deviceId,
  });

  @override
  ConsumerState<ArcadeScreen> createState() => _ArcadeScreenState();
}

class _ArcadeScreenState extends ConsumerState<ArcadeScreen> {
  late final PresenceRepository _presenceRepo;

  @override
  void initState() {
    super.initState();
        _presenceRepo = ref.read(presenceRepositoryProvider);
    _presenceRepo.setPresent(widget.spaceId, 'arcade', widget.deviceId);
  }

  @override
  void dispose() {
    _presenceRepo.setAbsent(widget.spaceId, 'arcade', widget.deviceId);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final partnerId = widget.memberIds.firstWhere((id) => id != widget.deviceId, orElse: () => '');
    final partnerPresentAsync = partnerId.isEmpty
        ? const AsyncData(false)
        : ref.watch(featurePresenceProvider(
            (spaceId: widget.spaceId, featureId: 'arcade', partnerId: partnerId)));
    final partnerPresent = partnerPresentAsync.valueOrNull ?? false;

    return Scaffold(
      appBar: AppBar(
        title: const FittedBox(fit: BoxFit.scaleDown, child: Text('Arcade Games')),
        actions: [
          Center(
            child: SyncStatusChip(
              state: partnerPresent ? SyncState.inSync : SyncState.partnerLeft,
            ),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Multiplayer Arcade',
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Interactive, fast-paced games to play together.',
                      style: theme.textTheme.bodyLarge,
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
                  childAspectRatio: 0.85,
                ),
                delegate: SliverChildListDelegate([
                  // —— Word Hunt Card ——
                  _ArcadeGameCard(
                    title: 'Word Hunt Race',
                    subtitle: 'Find the most words in 2 mins!',
                    emoji: '🔎',
                    color: const Color(0xFF673AB7),
                    onTap: () => context.push('/games/wordhunt'),
                  ),
                  // —— Ludo Card ——
                  _ArcadeGameCard(
                    title: 'Ludo',
                    subtitle: 'Classic 4-token multiplayer Ludo!',
                    emoji: '🎲',
                    color: const Color(0xFF1E88E5),
                    onTap: () => context.push('/games/ludo'),
                  ),
                  // 🐍 Snakes & Ladders Card 🪜
                  _ArcadeGameCard(
                    title: 'Snakes & Ladders',
                    subtitle: 'Race to 100! Avoid snakes, climb ladders.',
                    emoji: '🐍',
                    color: const Color(0xFF43A047),
                    onTap: () => context.push('/games/snakesladders'),
                  ),
                  // 🎱 Bingo Card
                  _ArcadeGameCard(
                    title: 'Bingo',
                    subtitle: 'First to 5 lines wins! 🏆',
                    emoji: '🎱',
                    gradient: const LinearGradient(
                      colors: [Color(0xFF1A1A2E), Color(0xFFE94560)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    onTap: () => context.push('/games/bingo'),
                  ),
                  // 🃏 UNO Card
                  _ArcadeGameCard(
                    title: 'UNO',
                    subtitle: 'Classic card game — empty hand wins!',
                    emoji: '🃏',
                    gradient: const LinearGradient(
                      colors: [Color(0xFFD32F2F), Color(0xFFFF6B35)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    onTap: () => context.push('/games/uno'),
                  ),
                ]),
              ),
            ),
            const SliverPadding(padding: EdgeInsets.only(bottom: 32)),
          ],
        ),
      ),
    );
  }
}

class _ArcadeGameCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final String emoji;
  final Color? color;
  final Gradient? gradient;
  final VoidCallback onTap;

  const _ArcadeGameCard({
    required this.title,
    required this.subtitle,
    required this.emoji,
    this.color,
    this.gradient,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final baseColor = color ?? (gradient?.colors.first ?? Colors.black);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color,
          gradient: gradient,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: baseColor.withValues(alpha: 0.35),
              blurRadius: 16,
              offset: const Offset(0, 8),
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
                color: Colors.white.withValues(alpha: 0.2),
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
                fontWeight: FontWeight.bold,
                color: Colors.white,
                letterSpacing: title == 'UNO' ? 2 : null,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: Colors.white.withValues(alpha: 0.85),
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

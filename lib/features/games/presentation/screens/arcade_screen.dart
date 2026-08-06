import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/ads/ad_service.dart';
import '../../../../core/services/daily_limits_service.dart';
import '../../../../data/models/models.dart';
import '../../../../shared/providers/app_providers.dart';
import '../../../vibe/presentation/widgets/sync_status_chip.dart';
import '../widgets/challenger_picker_bottom_sheet.dart';

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

  // Per-game play counts
  final Map<String, int> _plays = {};

  @override
  void initState() {
    super.initState();
    _presenceRepo = ref.read(presenceRepositoryProvider);
    _presenceRepo.setPresent(widget.spaceId, 'arcade', widget.deviceId);
    _loadAllPlays();
  }

  Future<void> _loadAllPlays() async {
    final games = ['wordhunt', 'ludo', 'snakesladders', 'bingo', 'uno'];
    final Map<String, int> updated = {};
    for (final g in games) {
      updated[g] = await DailyLimitsService.getGamePlaysLeft(g);
    }
    if (mounted) setState(() => _plays.addAll(updated));
  }

  @override
  void dispose() {
    _presenceRepo.setAbsent(widget.spaceId, 'arcade', widget.deviceId);
    super.dispose();
  }

  Future<void> _navigateTo(String gameId, String route, String gameTitle) async {
    final hasPlays = await DailyLimitsService.consumeGamePlay(gameId);
    if (!hasPlays && mounted) {
      _showAdWallDialog(gameId, gameTitle);
      return;
    }
    await context.push(route);
    if (mounted) _loadAllPlays();
  }

  /// For 2-player arcade games: if this is a Friends Space with 3+ members,
  /// show the challenger picker first. Then navigate with a filtered memberIds.
  Future<void> _navigateToTwoPlayerGame({
    required String gameId,
    required String route,
    required String gameTitle,
    required String gameEmoji,
    required SpaceModel space,
  }) async {
    // 1. Consume play or show AdWall
    final hasPlays = await DailyLimitsService.consumeGamePlay(gameId);
    if (!hasPlays && mounted) {
      _showAdWallDialog(gameId, gameTitle);
      return;
    }

    final members = space.memberDeviceIds;

    // Couple space or already exactly 2 members → go directly
    if (space.type == 'couple' || members.length <= 2) {
      if (mounted) await context.push(route);
      if (mounted) _loadAllPlays();
      return;
    }

    // Friends space with 3+ members → show challenger picker
    if (!mounted) return;
    final selectedOpponent = await showChallengerPicker(
      context: context,
      memberIds: members,
      myDeviceId: widget.deviceId,
      gameTitle: gameTitle,
      gameEmoji: gameEmoji,
    );

    if (selectedOpponent == null || !mounted) return;

    // Navigate with filtered memberIds so the game engine only sees 2 players
    await context.push(
      route,
      extra: [widget.deviceId, selectedOpponent],
    );
    if (mounted) _loadAllPlays();
  }

  void _showAdWallDialog(String gameId, String gameTitle) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2C),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text('Out of Plays! 😢',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text(
            'You have used up all your free plays for $gameTitle today. Watch a short ad to get 5 more plays!',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.85))),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF1E88E5)),
            onPressed: () {
              Navigator.pop(ctx);
              AdService.instance.showRewardedAd(
                onReward: () async {
                  await DailyLimitsService.addGamePlaysFromAd(gameId);
                  if (mounted) {
                    _loadAllPlays();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('🎉 5 plays added!'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                },
                onNotReady: (_) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Ad not ready yet, try again shortly.')),
                    );
                  }
                },
              );
            },
            icon: const Icon(Icons.play_circle_outline, size: 18),
            label: const Text('Watch Ad (+5 Plays)'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final spaceAsync = ref.watch(spaceStreamProvider);
    final space = spaceAsync.valueOrNull;
    final partnerId = widget.memberIds
        .firstWhere((id) => id != widget.deviceId, orElse: () => '');
    final partnerPresentAsync = partnerId.isEmpty
        ? const AsyncData(false)
        : ref.watch(featurePresenceProvider(
            (spaceId: widget.spaceId, featureId: 'arcade', partnerId: partnerId)));
    final partnerPresent = partnerPresentAsync.valueOrNull ?? false;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Arcade Games'),
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
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
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
                    const SizedBox(height: 8),
                    Text(
                      'Each game gives you 5 free plays per day.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.amber[700],
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
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
                  childAspectRatio: 0.78,
                ),
                delegate: SliverChildListDelegate([
                  // —— Word Hunt Card ——
                  _ArcadeGameCard(
                    title: 'Word Hunt Race',
                    subtitle: 'Find the most words in 2 mins!',
                    emoji: '🔎',
                    color: const Color(0xFF673AB7),
                    playsLeft: _plays['wordhunt'],
                    onTap: () {
                      _navigateTo('wordhunt', '/games/wordhunt', 'Word Hunt Race');
                    },
                  ),
                  // —— Ludo Card ——
                  _ArcadeGameCard(
                    title: 'Ludo',
                    subtitle: 'Classic 4-token multiplayer Ludo!',
                    emoji: '🎲',
                    color: const Color(0xFF1E88E5),
                    playsLeft: _plays['ludo'],
                    onTap: () {
                      if (space == null) return;
                      _navigateToTwoPlayerGame(
                        gameId: 'ludo',
                        route: '/games/ludo',
                        gameTitle: 'Ludo',
                        gameEmoji: '🎲',
                        space: space,
                      );
                    },
                  ),
                  // 🐍 Snakes & Ladders Card 🪜
                  _ArcadeGameCard(
                    title: 'Snakes & Ladders',
                    subtitle: 'Race to 100! Avoid snakes, climb ladders.',
                    emoji: '🐍',
                    color: const Color(0xFF43A047),
                    playsLeft: _plays['snakesladders'],
                    onTap: () {
                      if (space == null) return;
                      _navigateToTwoPlayerGame(
                        gameId: 'snakesladders',
                        route: '/games/snakesladders',
                        gameTitle: 'Snakes & Ladders',
                        gameEmoji: '🐍',
                        space: space,
                      );
                    },
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
                    playsLeft: _plays['bingo'],
                    onTap: () {
                      if (space == null) return;
                      _navigateToTwoPlayerGame(
                        gameId: 'bingo',
                        route: '/games/bingo',
                        gameTitle: 'Bingo',
                        gameEmoji: '🎱',
                        space: space,
                      );
                    },
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
                    playsLeft: _plays['uno'],
                    onTap: () {
                      if (space == null) return;
                      _navigateToTwoPlayerGame(
                        gameId: 'uno',
                        route: '/games/uno',
                        gameTitle: 'UNO',
                        gameEmoji: '🃏',
                        space: space,
                      );
                    },
                  ),
                ]),
              ),
            ),
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(child: AdBannerWidget()),
              ),
            ),
            const SliverPadding(padding: EdgeInsets.only(bottom: 24)),
          ],
        ),
      ),
    );
  }
}

// ─── Game Card ────────────────────────────────────────────────────────────────

class _ArcadeGameCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final String emoji;
  final Color? color;
  final Gradient? gradient;
  final int? playsLeft;
  final VoidCallback onTap;

  const _ArcadeGameCard({
    required this.title,
    required this.subtitle,
    required this.emoji,
    this.color,
    this.gradient,
    this.playsLeft,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final baseColor = color ?? (gradient?.colors.first ?? Colors.black);
    final plays = playsLeft ?? 5;
    final isEmpty = plays <= 0;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Stack(
        children: [
          Container(
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
                const Spacer(),
                // ── Per-game play badge ──
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: isEmpty
                        ? Colors.red.withValues(alpha: 0.85)
                        : Colors.white.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    isEmpty ? '❌ No plays left' : '🎟️ $plays plays left',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

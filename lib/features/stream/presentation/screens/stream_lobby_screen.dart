import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/providers/app_providers.dart';
import '../../providers/stream_providers.dart';
import 'stream_screen.dart';

/// Lobby shown before starting or joining a stream.
/// Watches Firebase RTDB — if partner is already live, shows "Join" option.
class StreamLobbyScreen extends ConsumerWidget {
  const StreamLobbyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spaceAsync = ref.watch(spaceStreamProvider);
    final deviceIdAsync = ref.watch(deviceIdProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF0D0D1A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          'Stream',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
      ),
      body: spaceAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Text('Error: $e', style: const TextStyle(color: Colors.white70)),
        ),
        data: (space) {
          if (space == null) {
            return const Center(
              child: Text('No space found', style: TextStyle(color: Colors.white70)),
            );
          }
          return deviceIdAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('$e')),
            data: (deviceId) {
              final partnerId = space.memberDeviceIds
                  .firstWhere((id) => id != deviceId, orElse: () => '');
              return _LobbyBody(
                spaceId: space.id,
                deviceId: deviceId,
                partnerId: partnerId,
              );
            },
          );
        },
      ),
    );
  }
}

class _LobbyBody extends ConsumerWidget {
  final String spaceId;
  final String deviceId;
  final String partnerId;

  const _LobbyBody({
    required this.spaceId,
    required this.deviceId,
    required this.partnerId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionAsync = ref.watch(streamSessionProvider(spaceId));

    return sessionAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => _buildStartOptions(context, null),
      data: (session) => _buildStartOptions(context, session),
    );
  }

  Widget _buildStartOptions(BuildContext context, session) {
    final partnerIsLive = session != null &&
        session.isLive &&
        session.hostId != deviceId;
    final iAmLive = session != null &&
        session.isLive &&
        session.hostId == deviceId;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header illustration
          Center(
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [
                    AppTheme.primary.withValues(alpha: 0.8),
                    AppTheme.accent.withValues(alpha: 0.8),
                  ],
                ),
              ),
              child: const Icon(Icons.live_tv, color: Colors.white, size: 56),
            ),
          ),
          const SizedBox(height: 24),
          const Center(
            child: Text(
              'Stream Together',
              style: TextStyle(
                color: Colors.white,
                fontSize: 26,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              'Share your camera live with your partner.\nLow latency · Private · Free',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.55),
                fontSize: 14,
                height: 1.6,
              ),
            ),
          ),
          const SizedBox(height: 40),

          // Partner is live banner
          if (partnerIsLive) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.accent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.accent.withValues(alpha: 0.4)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: const BoxDecoration(
                      color: Colors.redAccent,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Your partner is streaming live right now!',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _ActionCard(
              icon: Icons.play_circle_fill,
              title: 'Watch Live',
              subtitle: 'Join your partner\'s stream',
              color: AppTheme.accent,
              onTap: () => _navigateToStream(
                context,
                isHost: false,
                type: session?.streamType ?? 'screen',
              ),
            ),
            const SizedBox(height: 32),
            const Divider(color: Colors.white12),
            const SizedBox(height: 24),
          ],

          // Already streaming
          if (iAmLive) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.primary.withValues(alpha: 0.4)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: const BoxDecoration(
                      color: Colors.greenAccent,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'You are currently live!',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _ActionCard(
              icon: Icons.live_tv,
              title: 'Rejoin My Stream',
              subtitle: 'Go back to your live broadcast',
              color: AppTheme.primary,
              onTap: () => _navigateToStream(context, isHost: true),
            ),
            const SizedBox(height: 32),
          ],

          // Start streaming options (only if not already live)
          if (!iAmLive) ...[
            Text(
              'Start Streaming',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 13,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 12),
            _ActionCard(
              icon: Icons.screen_share,
              title: 'Share Screen',
              subtitle: 'Stream your entire phone screen live',
              color: AppTheme.accent,
              onTap: () => _navigateToStream(context, isHost: true, type: 'screen'),
            ),
          ],

          const SizedBox(height: 40),

          // Info chips
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _InfoChip(icon: Icons.lock, label: 'Private — only you two'),
              _InfoChip(icon: Icons.bolt, label: 'Ultra-low latency'),
              _InfoChip(icon: Icons.free_breakfast, label: 'Free to use'),
            ],
          ),
        ],
      ),
    );
  }

  void _navigateToStream(
    BuildContext context, {
    required bool isHost,
    String type = 'camera',
  }) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => StreamScreen(
        spaceId: spaceId,
        deviceId: deviceId,
        partnerId: partnerId,
        isHost: isHost,
        streamType: type,
      ),
      fullscreenDialog: true,
    ));
  }
}

// ─── Action Card ──────────────────────────────────────────────────────────────

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _ActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: color, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.5),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: color, size: 24),
          ],
        ),
      ),
    );
  }
}

// ─── Info Chip ────────────────────────────────────────────────────────────────

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _InfoChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white54, size: 14),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';

/// Shows a bottom sheet to pick ONE challenger from all space members.
/// Returns the [selectedPartnerId] or null if dismissed.
Future<String?> showChallengerPicker({
  required BuildContext context,
  required List<String> memberIds,
  required String myDeviceId,
  required String gameTitle,
  required String gameEmoji,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _ChallengerPickerSheet(
      memberIds: memberIds,
      myDeviceId: myDeviceId,
      gameTitle: gameTitle,
      gameEmoji: gameEmoji,
    ),
  );
}

class _ChallengerPickerSheet extends StatelessWidget {
  final List<String> memberIds;
  final String myDeviceId;
  final String gameTitle;
  final String gameEmoji;

  const _ChallengerPickerSheet({
    required this.memberIds,
    required this.myDeviceId,
    required this.gameTitle,
    required this.gameEmoji,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final opponents = memberIds.where((id) => id != myDeviceId).toList();

    return Container(
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppTheme.divider,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),

          // Title
          Text(
            '$gameEmoji  Choose your challenger',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Who do you want to play $gameTitle against?',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AppTheme.onSurfaceMuted,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),

          // Opponent list
          ...opponents.map((opponentId) => _OpponentTile(
                opponentId: opponentId,
                myDeviceId: myDeviceId,
                onTap: () => Navigator.pop(context, opponentId),
              )),

          const SizedBox(height: 8),

          // Cancel button
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () => Navigator.pop(context, null),
              child: const Text('Cancel'),
            ),
          ),
        ],
      ),
    );
  }
}

class _OpponentTile extends StatelessWidget {
  final String opponentId;
  final String myDeviceId;
  final VoidCallback onTap;

  const _OpponentTile({
    required this.opponentId,
    required this.myDeviceId,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // Show a truncated, readable ID as the display name
    final shortId = opponentId.length > 8
        ? opponentId.substring(0, 8).toUpperCase()
        : opponentId.toUpperCase();
    final displayName = 'Player $shortId';


    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.divider),
            color: AppTheme.surfaceAlt,
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: AppTheme.primary.withValues(alpha: 0.15),
                child: Text(
                  displayName.isNotEmpty ? displayName[0].toUpperCase() : '?',
                  style: TextStyle(
                    color: AppTheme.primary,
                    fontWeight: FontWeight.w700,
                    fontSize: 18,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    Text(
                      'Tap to challenge',
                      style: TextStyle(
                        color: AppTheme.onSurfaceMuted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.sports_esports_rounded,
                color: AppTheme.primary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

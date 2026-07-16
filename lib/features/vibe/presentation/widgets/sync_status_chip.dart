import 'package:flutter/material.dart';

enum SyncState { inSync, buffering, partnerLeft }

/// A small pill indicator showing sync / buffering / partner-left status.
class SyncStatusChip extends StatelessWidget {
  final SyncState state;

  const SyncStatusChip({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final (icon, label, color) = switch (state) {
      SyncState.inSync => (Icons.sync_rounded, 'Sync', const Color(0xFF69F0AE)),
      SyncState.buffering => (Icons.hourglass_top_rounded, 'Wait...', const Color(0xFFFFD740)),
      SyncState.partnerLeft => (Icons.person_outline, 'Away', const Color(0xFFFF6E6E)),
    };

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 14),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

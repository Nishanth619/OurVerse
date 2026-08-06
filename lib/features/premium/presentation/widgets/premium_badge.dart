import 'package:flutter/material.dart';

/// A small shimmering gold badge shown to premium users in the app header.
class PremiumBadge extends StatelessWidget {
  final bool compact;
  const PremiumBadge({super.key, this.compact = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 12,
        vertical: compact ? 3 : 5,
      ),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFFD700), Color(0xFFFFAA00)],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFFD700).withValues(alpha: 0.4),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '✨',
            style: TextStyle(fontSize: compact ? 10 : 12),
          ),
          const SizedBox(width: 4),
          Text(
            'Premium',
            style: TextStyle(
              color: Colors.black,
              fontWeight: FontWeight.w900,
              fontSize: compact ? 10 : 12,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}

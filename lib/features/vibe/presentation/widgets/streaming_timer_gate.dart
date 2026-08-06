import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/ads/ad_service.dart';
import '../../../../core/services/daily_limits_service.dart';

/// A widget that wraps streaming content (YouTube or Vibe Together) and enforces
/// the 30-minutes-per-day free limit. After the limit is reached, it covers
/// the child with a lock overlay and allows either partner to watch a rewarded
/// ad to add 30 more minutes.
class StreamingTimerGate extends StatefulWidget {
  final Widget child;
  final String label; // e.g. 'Watch Together' or 'Vibe Together'

  const StreamingTimerGate({
    super.key,
    required this.child,
    required this.label,
  });

  @override
  State<StreamingTimerGate> createState() => _StreamingTimerGateState();
}

class _StreamingTimerGateState extends State<StreamingTimerGate> {
  Timer? _minuteTimer;
  int _minutesLeft = 30;
  bool _locked = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _initTimer();
  }

  Future<void> _initTimer() async {
    final mins = await DailyLimitsService.getStreamingMinutesLeft();
    if (!mounted) return;
    setState(() {
      _minutesLeft = mins;
      _locked = mins <= 0;
      _loading = false;
    });
    if (!_locked) _startTimer();
  }

  void _startTimer() {
    _minuteTimer?.cancel();
    _minuteTimer = Timer.periodic(const Duration(minutes: 1), (_) async {
      final remaining = await DailyLimitsService.deductStreamingMinute();
      if (!mounted) return;
      setState(() {
        _minutesLeft = remaining;
        if (remaining <= 0) {
          _locked = true;
          _minuteTimer?.cancel();
        }
      });
    });
  }

  void _watchAdToExtend() {
    AdService.instance.showRewardedAd(
      onReward: () async {
        final updated = await DailyLimitsService.addStreamingMinutesFromAd();
        if (!mounted) return;
        setState(() {
          _minutesLeft = updated;
          _locked = false;
        });
        _startTimer();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('🎉 30 minutes added!'),
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
  }

  @override
  void dispose() {
    _minuteTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return widget.child;

    return Stack(
      children: [
        // The actual streaming content — always interactive (Leave button must always work)
        widget.child,

        // Timer badge in top-right (always visible while streaming)
        if (!_locked)
          Positioned(
            top: 80, // below the top bar
            right: 12,
            child: _TimerBadge(minutesLeft: _minutesLeft),
          ),

        // Lock overlay when limit is reached
        // The overlay covers the content visually but Leave button is rendered
        // INSIDE widget.child so it still receives taps through the Scaffold.
        if (_locked)
          Positioned.fill(
            child: _LockOverlay(
              label: widget.label,
              onWatchAd: _watchAdToExtend,
            ),
          ),
      ],
    );
  }
}

// ─── Timer Badge ─────────────────────────────────────────────────────────────

class _TimerBadge extends StatelessWidget {
  final int minutesLeft;
  const _TimerBadge({required this.minutesLeft});

  @override
  Widget build(BuildContext context) {
    final isLow = minutesLeft <= 5;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: (isLow ? Colors.red : Colors.black).withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isLow ? Colors.red : Colors.white24,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.timer, size: 14, color: isLow ? Colors.red[200] : Colors.white70),
          const SizedBox(width: 4),
          Text(
            '$minutesLeft min left',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isLow ? Colors.red[200] : Colors.white70,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Lock Overlay ─────────────────────────────────────────────────────────────

class _LockOverlay extends StatelessWidget {
  final String label;
  final VoidCallback onWatchAd;

  const _LockOverlay({required this.label, required this.onWatchAd});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.black.withValues(alpha: 0.92),
            const Color(0xFF0A0A1A).withValues(alpha: 0.97),
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: SafeArea(
        child: Stack(
          children: [
            // Exit button top-left
            Positioned(
              top: 8,
              left: 8,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 32),
                onPressed: () {
                  try {
                    context.pop();
                  } catch (_) {
                    Navigator.of(context).pop();
                  }
                },
              ),
            ),
            Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('⏰', style: TextStyle(fontSize: 56)),
                    const SizedBox(height: 16),
                    Text(
                      'Daily Free Limit Reached',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'You\'ve used your 30 minutes of free $label for today.\nEither partner can watch an ad to add 30 more minutes!',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white70, height: 1.5),
                    ),
                    const SizedBox(height: 28),
                    FilledButton.icon(
                      onPressed: onWatchAd,
                      icon: const Icon(Icons.play_circle_outline),
                      label: const Text('Watch Ad — Add 30 Minutes'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                        backgroundColor: const Color(0xFF7B2FBE),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextButton(
                      onPressed: () {
                        try {
                          context.pop();
                        } catch (_) {
                          Navigator.of(context).pop();
                        }
                      },
                      child: const Text('Leave', style: TextStyle(color: Colors.white70, fontSize: 16)),
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
}

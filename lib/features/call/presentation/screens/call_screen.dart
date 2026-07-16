import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:closer/features/call/providers/call_providers.dart';
import 'package:closer/features/call/call_manager.dart';

/// Full-screen active call UI — shown once both peers are connected.
class CallScreen extends ConsumerStatefulWidget {
  final String spaceId;
  final String myDeviceId;
  final String remoteDisplayName;

  const CallScreen({
    super.key,
    required this.spaceId,
    required this.myDeviceId,
    required this.remoteDisplayName,
  });

  @override
  ConsumerState<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends ConsumerState<CallScreen>
    with TickerProviderStateMixin {
  late final AnimationController _waveCtrl;

  @override
  void initState() {
    super.initState();
    _waveCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();

    // Watch for call ending from the other side
    ref.listenManual(callStateProvider, (_, next) {
      final state = next.valueOrNull;
      if (state == CallManagerState.ended ||
          state == CallManagerState.declined ||
          state == CallManagerState.failed ||
          state == CallManagerState.idle) {
        if (mounted) Navigator.of(context).pop();
      }
    });
  }

  @override
  void dispose() {
    _waveCtrl.dispose();
    super.dispose();
  }

  Future<void> _hangUp() async {
    HapticFeedback.heavyImpact();
    await ref.read(callManagerProvider).hangUp();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final manager = ref.read(callManagerProvider);
    final stateAsync = ref.watch(callStateProvider);
    final durationAsync = ref.watch(callDurationProvider);

    final callState = stateAsync.valueOrNull ?? CallManagerState.connecting;
    final duration = durationAsync.valueOrNull ?? Duration.zero;
    final isMuted = manager.isMuted;
    final isSpeaker = manager.isSpeaker;

    final statusLabel = switch (callState) {
      CallManagerState.connecting => 'Connecting...',
      CallManagerState.connected => _formatDuration(duration),
      CallManagerState.calling => 'Calling...',
      _ => 'Connecting...',
    };

    final isConnected = callState == CallManagerState.connected;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF0A0A1A),
              Color(0xFF1A0D30),
              Color(0xFF0A0A1A),
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 24),

              // Top label
              Text(
                'Voice Call',
                style: GoogleFonts.outfit(
                  color: Colors.white.withValues(alpha: 0.4),
                  fontSize: 13,
                  letterSpacing: 2,
                ),
              ),

              const Spacer(flex: 2),

              // Animated wave rings (only when connected)
              if (isConnected)
                _WaveRings(controller: _waveCtrl)
              else
                const _ConnectingSpinner(),

              const SizedBox(height: 40),

              // Remote name
              Text(
                widget.remoteDisplayName.isEmpty
                    ? 'Partner'
                    : widget.remoteDisplayName,
                style: GoogleFonts.outfit(
                  color: Colors.white,
                  fontSize: 30,
                  fontWeight: FontWeight.w700,
                ),
              ),

              const SizedBox(height: 10),

              // Status / timer
              Text(
                statusLabel,
                style: GoogleFonts.outfit(
                  color: isConnected
                      ? const Color(0xFF4CAF50)
                      : Colors.white.withValues(alpha: 0.5),
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),

              const Spacer(flex: 2),

              // Controls row
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    // Mute
                    _ControlButton(
                      icon: isMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
                      label: isMuted ? 'Unmute' : 'Mute',
                      active: isMuted,
                      activeColor: const Color(0xFFFF6B6B),
                      onTap: () {
                        manager.toggleMute();
                        setState(() {}); // refresh mute icon
                      },
                    ),

                    // Speaker
                    _ControlButton(
                      icon: isSpeaker
                          ? Icons.volume_up_rounded
                          : Icons.hearing_rounded,
                      label: isSpeaker ? 'Speaker' : 'Earpiece',
                      active: isSpeaker,
                      activeColor: const Color(0xFF7C4DFF),
                      onTap: () async {
                        await manager.toggleSpeaker();
                        setState(() {}); // refresh speaker icon
                      },
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 48),

              // End call button
              GestureDetector(
                onTap: _hangUp,
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFFFF4569),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFFF4569).withValues(alpha: 0.45),
                        blurRadius: 24,
                        spreadRadius: 6,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.call_end_rounded,
                    color: Colors.white,
                    size: 36,
                  ),
                ),
              ),

              const SizedBox(height: 60),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

// ── Animated wave rings (shown when connected) ────────────────────────────────

class _WaveRings extends StatelessWidget {
  final AnimationController controller;
  const _WaveRings({required this.controller});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 160,
      height: 160,
      child: AnimatedBuilder(
        animation: controller,
        builder: (_, __) {
          return Stack(
            alignment: Alignment.center,
            children: [
              ...List.generate(3, (i) {
                final t = (controller.value - i * 0.33).clamp(0.0, 1.0);
                return Transform.scale(
                  scale: 0.4 + t * 0.6,
                  child: Container(
                    width: 160,
                    height: 160,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: const Color(0xFF7C4DFF)
                            .withValues(alpha: (1 - t) * 0.4),
                        width: 2,
                      ),
                    ),
                  ),
                );
              }),
              // Center avatar
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const RadialGradient(
                    colors: [Color(0xFFB388FF), Color(0xFF7C4DFF)],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFB388FF).withValues(alpha: 0.4),
                      blurRadius: 24,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.favorite_rounded,
                  color: Colors.white,
                  size: 44,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ── Spinner shown while connecting ────────────────────────────────────────────

class _ConnectingSpinner extends StatelessWidget {
  const _ConnectingSpinner();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 120,
      height: 120,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const RadialGradient(
          colors: [Color(0xFFB388FF), Color(0xFF7C4DFF)],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFB388FF).withValues(alpha: 0.4),
            blurRadius: 24,
          ),
        ],
      ),
      child: const Padding(
        padding: EdgeInsets.all(16),
        child: CircularProgressIndicator(
          color: Colors.white,
          strokeWidth: 3,
        ),
      ),
    );
  }
}

// ── Control button (mute/speaker) ─────────────────────────────────────────────

class _ControlButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final Color activeColor;
  final VoidCallback onTap;

  const _ControlButton({
    required this.icon,
    required this.label,
    required this.active,
    required this.activeColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: active
                  ? activeColor.withValues(alpha: 0.2)
                  : Colors.white.withValues(alpha: 0.08),
              border: Border.all(
                color: active ? activeColor : Colors.white.withValues(alpha: 0.2),
                width: 1.5,
              ),
            ),
            child: Icon(
              icon,
              color: active ? activeColor : Colors.white70,
              size: 28,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: GoogleFonts.outfit(
              color: active ? activeColor : Colors.white54,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

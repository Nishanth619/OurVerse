import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:closer/features/call/providers/call_providers.dart';
import 'package:closer/features/call/data/call_signal.dart';
import 'call_screen.dart';

/// Full-screen incoming call UI — shown when your partner is calling.
/// Has its own route so it works over any screen (including lock screen).
class IncomingCallScreen extends ConsumerStatefulWidget {
  final String spaceId;
  final String myDeviceId;
  final CallSignal signal;

  const IncomingCallScreen({
    super.key,
    required this.spaceId,
    required this.myDeviceId,
    required this.signal,
  });

  @override
  ConsumerState<IncomingCallScreen> createState() => _IncomingCallScreenState();
}

class _IncomingCallScreenState extends ConsumerState<IncomingCallScreen>
    with TickerProviderStateMixin {
  late final AnimationController _pulseCtrl;
  late final AnimationController _ringCtrl;
  late final Animation<double> _pulseAnim;
  bool _accepting = false;

  @override
  void initState() {
    super.initState();
    HapticFeedback.vibrate();

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _ringCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);

    _pulseAnim = Tween<double>(begin: 0.85, end: 1.05).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );

    // Tell manager we are ringing so it has spaceId/deviceId context
    // This allows declineCall() to work even before _accept() is called.
    ref.read(callManagerProvider).receiveIncomingCall(
      spaceId: widget.spaceId,
      callerName: widget.signal.callerName,
      myDeviceId: widget.myDeviceId,
      callerDeviceId: widget.signal.callerId,
    );

    // Watch signal — if caller hangs up before we answer, pop this screen.
    ref.listenManual(
      incomingCallSignalProvider(widget.spaceId),
      (_, next) {
        final signal = next.valueOrNull;
        if (mounted && !_accepting) {
          if (signal == null || signal.state != CallState.ringing) {
            Navigator.of(context).pop();
          }
        }
      },
    );
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _ringCtrl.dispose();
    super.dispose();
  }

  Future<void> _accept() async {
    setState(() => _accepting = true);
    HapticFeedback.heavyImpact();

    final manager = ref.read(callManagerProvider);

    manager.acceptCall(widget.signal.offerSdp ?? '');

    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => CallScreen(
          spaceId: widget.spaceId,
          myDeviceId: widget.myDeviceId,
          remoteDisplayName: widget.signal.callerName,
        ),
      ),
    );
  }

  Future<void> _decline() async {
    HapticFeedback.mediumImpact();
    await ref.read(callManagerProvider).declineCall();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF0D0D1A),
              Color(0xFF1A0A2E),
              Color(0xFF0D0D1A),
            ],
          ),
        ),
        child: Stack(
          children: [
            // Animated background rings
            ..._buildBackgroundRings(size),

            // Content
            SafeArea(
              child: Column(
                children: [
                  const Spacer(flex: 2),

                  // Status label
                  Text(
                    'Incoming Call',
                    style: GoogleFonts.outfit(
                      color: Colors.white.withValues(alpha: 0.6),
                      fontSize: 16,
                      letterSpacing: 2,
                    ),
                  ),

                  const SizedBox(height: 40),

                  // Avatar — pulsing circle
                  AnimatedBuilder(
                    animation: _pulseAnim,
                    builder: (_, __) => Transform.scale(
                      scale: _pulseAnim.value,
                      child: Container(
                        width: 140,
                        height: 140,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: const RadialGradient(
                            colors: [
                              Color(0xFFB388FF),
                              Color(0xFF7C4DFF),
                            ],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFB388FF).withValues(alpha: 0.5),
                              blurRadius: 40,
                              spreadRadius: 10,
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.favorite_rounded,
                          color: Colors.white,
                          size: 64,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 36),

                  // Caller name
                  Text(
                    widget.signal.callerName,
                    style: GoogleFonts.outfit(
                      color: Colors.white,
                      fontSize: 32,
                      fontWeight: FontWeight.w700,
                    ),
                  ),

                  const SizedBox(height: 8),

                  // Animated "calling" indicator
                  AnimatedBuilder(
                    animation: _ringCtrl,
                    builder: (_, __) => Row(
                      mainAxisSize: MainAxisSize.min,
                      children: List.generate(3, (i) {
                        final delay = i / 3;
                        final t = (_ringCtrl.value - delay).clamp(0.0, 1.0);
                        return Container(
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withValues(alpha: 0.3 + t * 0.7),
                          ),
                        );
                      }),
                    ),
                  ),

                  const Spacer(flex: 3),

                  // Buttons row
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 48),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Decline
                        _CallButton(
                          icon: Icons.call_end_rounded,
                          color: const Color(0xFFFF4569),
                          label: 'Decline',
                          onTap: _accepting ? null : _decline,
                        ),

                        // Accept
                        _accepting
                            ? const SizedBox(
                                width: 72,
                                height: 72,
                                child: CircularProgressIndicator(
                                  color: Color(0xFF4CAF50),
                                  strokeWidth: 3,
                                ),
                              )
                            : _CallButton(
                                icon: Icons.call_rounded,
                                color: const Color(0xFF4CAF50),
                                label: 'Accept',
                                onTap: _accept,
                              ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 60),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildBackgroundRings(Size size) {
    return List.generate(4, (i) {
      return AnimatedBuilder(
        animation: _pulseCtrl,
        builder: (_, __) {
          final scale = 0.5 + i * 0.2 + _pulseCtrl.value * 0.06;
          return Positioned.fill(
            child: Align(
              alignment: const Alignment(0, -0.15),
              child: Transform.scale(
                scale: scale,
                child: Container(
                  width: 180,
                  height: 180,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: const Color(0xFFB388FF)
                          .withValues(alpha: math.max(0, 0.15 - i * 0.03)),
                      width: 1.5,
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      );
    });
  }
}

// ── Reusable call action button ───────────────────────────────────────────────

class _CallButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback? onTap;

  const _CallButton({
    required this.icon,
    required this.color,
    required this.label,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.45),
                  blurRadius: 20,
                  spreadRadius: 4,
                ),
              ],
            ),
            child: Icon(icon, color: Colors.white, size: 32),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          label,
          style: GoogleFonts.outfit(
            color: Colors.white.withValues(alpha: 0.7),
            fontSize: 14,
          ),
        ),
      ],
    );
  }
}

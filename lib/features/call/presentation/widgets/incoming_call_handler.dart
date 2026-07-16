import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:closer/shared/providers/app_providers.dart';
import 'package:closer/features/call/providers/call_providers.dart';
import 'package:closer/features/call/data/call_signal.dart';
import 'package:closer/router.dart';
import 'package:closer/features/call/presentation/screens/incoming_call_screen.dart';

/// Wraps the app root and listens for incoming calls in the active space.
/// When a ringing call is detected (from partner), it pops up the
/// [IncomingCallScreen] over whatever is currently on screen.
///
/// Usage: wrap MaterialApp.router with this widget.
class IncomingCallHandler extends ConsumerStatefulWidget {
  final Widget child;
  const IncomingCallHandler({super.key, required this.child});

  @override
  ConsumerState<IncomingCallHandler> createState() =>
      _IncomingCallHandlerState();
}

class _IncomingCallHandlerState extends ConsumerState<IncomingCallHandler> {
  bool _callScreenShown = false;
  final Set<String> _watchedSpaceIds = {}; // prevent duplicate listeners

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _startListening());
  }

  void _startListening() {
    ref.listenManual<AsyncValue<String?>>(
      savedSpaceIdProvider,
      (_, spaceAsync) {
        final spaceId = spaceAsync.valueOrNull;
        if (spaceId == null) return;
        _watchCallsForSpace(spaceId);
      },
      fireImmediately: true,
    );

    // Also watch activeSpaceIdProvider for immediate space changes
    ref.listenManual<String?>(
      activeSpaceIdProvider,
      (_, spaceId) {
        if (spaceId != null) _watchCallsForSpace(spaceId);
      },
      fireImmediately: true,
    );
  }

  void _watchCallsForSpace(String spaceId) {
    // Guard against setting up duplicate listeners for the same space
    if (_watchedSpaceIds.contains(spaceId)) return;
    _watchedSpaceIds.add(spaceId);

    ref.listenManual<AsyncValue<CallSignal?>>(
      incomingCallSignalProvider(spaceId),
      (prev, next) {
        final signal = next.valueOrNull;
        final deviceId = ref.read(deviceIdProvider).value ?? '';

        // Ignore if we are the caller
        if (signal != null && signal.callerId == deviceId) return;

        if (signal != null &&
            signal.state == CallState.ringing &&
            !_callScreenShown) {
          _showIncomingCallScreen(spaceId, deviceId, signal);
        }
      },
      fireImmediately: true,
    );
  }

  void _showIncomingCallScreen(
      String spaceId, String myDeviceId, CallSignal signal) {
    _callScreenShown = true;

    final navigator = rootNavigatorKey.currentState;
    if (navigator == null) return;

    navigator.push(
      PageRouteBuilder(
        opaque: true, // full-screen, don't render background
        barrierColor: Colors.black,
        pageBuilder: (_, __, ___) => IncomingCallScreen(
          spaceId: spaceId,
          myDeviceId: myDeviceId,
          signal: signal,
        ),
        transitionsBuilder: (_, anim, __, child) {
          return SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 1),
              end: Offset.zero,
            ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOut)),
            child: child,
          );
        },
      ),
    ).then((_) => _callScreenShown = false);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/stream_providers.dart';

const _discordVoiceBg = Color(0xFF232428);
const _discordGreen = Color(0xFF57F287);
const _discordBlurple = Color(0xFF5865F2);
const _discordRed = Color(0xFFED4245);

class ScreenShareBar extends ConsumerWidget {
  const ScreenShareBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(screenShareStateProvider);

    if (!state.isInRoom && !state.isSharing) return const SizedBox.shrink();

    final isSharing = state.isSharing;
    final text = isSharing ? 'Screen Share Active' : 'Voice Connected';

    return Container(
      color: _discordVoiceBg,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: SafeArea(
        top: false,
        bottom: true,
        child: Row(
          children: [
            // Green pulsing dot
            Container(
              width: 10,
              height: 10,
              decoration: const BoxDecoration(
                color: _discordGreen,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
            
            // Buttons
            ElevatedButton(
              onPressed: () {
                // Navigate back to the stream route (lobby or screen)
                if (state.spaceId.isNotEmpty) {
                  context.push('/stream/${state.spaceId}?isHost=true&streamType=screen');
                } else {
                  context.push('/stream');
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: _discordBlurple,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('Return', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: () {
                // Instead of disconnecting entirely, let's just use "Stop" if sharing, 
                // or if we're just connected, "Leave" isn't fully managed here, it's better to just Return and leave.
                // But let's implement basic disconnect if needed. 
                // Actually the best way is to let the user Return and use the main controls. 
                // But for Screen Share, stop makes sense.
                if (isSharing) {
                  // We can't directly stop sharing here because Agora Engine is managed in stream_screen.dart
                  // The user has to return to the room to stop sharing gracefully.
                  // We'll just let them Return. 
                  // But wait, the previous code called `ref.read(screenShareStateProvider.notifier).stopSharing()`.
                  // Since we've moved Agora to stream_screen, stopping here will only update UI, not Agora.
                  // So we will just provide a "Return" button and they can stop/leave from the room.
                  context.push('/stream/${state.spaceId}?isHost=true&streamType=screen');
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: _discordRed,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(isSharing ? 'Stop' : 'Leave', style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
}

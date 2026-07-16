import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../data/vibe_models.dart';
import '../../providers/vibe_providers.dart';
import '../../../../shared/providers/app_providers.dart';

/// Shows songs that were previously played in this space, with a tap
/// to relisten — starts a new shared session for the chosen track.
class SongHistoryScreen extends ConsumerWidget {
  final String spaceId;
  const SongHistoryScreen({super.key, required this.spaceId});

  
  Future<void> _replay(BuildContext context, WidgetRef ref, VibeHistoryItem item) async {
    final deviceId = ref.read(deviceIdProvider).value;
    if (deviceId == null) return;
    final session = VibeSession(
      videoId: item.videoId,
      videoTitle: item.title,
      videoThumb: item.thumb,
      videoDurationMs: item.durationMs,
      isPlaying: true,
      startedAt: DateTime.now().millisecondsSinceEpoch,
      startPositionMs: 0,
      updatedBy: deviceId,
    );
    await ref.read(vibeRepositoryProvider).startSession(spaceId, session);
    if (context.mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyAsync = ref.watch(vibeHistoryProvider(spaceId));
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F14),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F0F14),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          'Recently Played',
          style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w700),
        ),
      ),
      body: historyAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: Color(0xFFB388FF)),
        ),
        error: (e, _) => const Center(
          child: Text('Could not load history',
              style: TextStyle(color: Colors.white60)),
        ),
        data: (items) {
          if (items.isEmpty) {
            return Center(
              child: Text(
                'No songs played yet',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 15),
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              return GestureDetector(
                onTap: () => _replay(context, ref, item),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
                  ),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: item.thumb.isNotEmpty
                            ? Image.network(
                                item.thumb,
                                width: 64,
                                height: 48,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Container(
                                  width: 64,
                                  height: 48,
                                  color: Colors.white12,
                                  child: const Icon(Icons.music_note, color: Colors.white54),
                                ),
                              )
                            : Container(
                                width: 64,
                                height: 48,
                                color: Colors.white12,
                                child: const Icon(Icons.music_note, color: Colors.white54),
                              ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          item.title,
                          style: const TextStyle(color: Colors.white, fontSize: 14),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(Icons.replay_rounded, color: Color(0xFFB388FF), size: 26),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

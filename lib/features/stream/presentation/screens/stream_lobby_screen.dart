import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../providers/stream_providers.dart';

const _bg = Color(0xFF1E1F22);
const _card = Color(0xFF2B2D31);
const _blurple = Color(0xFF5865F2);
const _green = Color(0xFF57F287);
const _textPrimary = Color(0xFFFFFFFF);
const _textSecondary = Color(0xFFB5BAC1);

class StreamLobbyScreen extends ConsumerWidget {
  final String spaceId;
  const StreamLobbyScreen({super.key, required this.spaceId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final membersAsync = ref.watch(roomMembersProvider(spaceId));

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: _textPrimary),
          onPressed: () => context.pop(),
        ),
        title: Text(
          'Voice Channel',
          style: GoogleFonts.inter(
            color: _textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  color: _card,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Column(
                  children: [
                    const Icon(
                      Icons.volume_up_rounded,
                      size: 64,
                      color: _blurple,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Private Room',
                      style: GoogleFonts.inter(
                        color: _textPrimary,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Your private space',
                      style: GoogleFonts.inter(
                        color: _textSecondary,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 32),
                    
                    // Members list
                    membersAsync.when(
                      data: (members) {
                        if (members.isEmpty) {
                          return Text(
                            'Room is empty',
                            style: GoogleFonts.inter(color: _textSecondary),
                          );
                        }
                        
                        return Column(
                          children: [
                            Wrap(
                              spacing: -12,
                              children: members.map((m) {
                                return Container(
                                  width: 48,
                                  height: 48,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(color: _green, width: 2),
                                    color: _bg,
                                  ),
                                  alignment: Alignment.center,
                                  child: Text(
                                    m.displayName.isNotEmpty ? m.displayName[0].toUpperCase() : '?',
                                    style: GoogleFonts.inter(
                                      color: _textPrimary,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 20,
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                            const SizedBox(height: 16),
                            if (members.length == 1)
                              Text(
                                '${members.first.displayName} is waiting...',
                                style: GoogleFonts.inter(color: _textSecondary, fontSize: 14),
                              ),
                            if (members.length > 1)
                              Text(
                                '${members.length} people in room',
                                style: GoogleFonts.inter(color: _textSecondary, fontSize: 14),
                              ),
                            if (members.any((m) => m.isScreenSharing))
                              Padding(
                                padding: const EdgeInsets.only(top: 8.0),
                                child: Text(
                                  '🖥 Someone is sharing their screen',
                                  style: GoogleFonts.inter(color: _green, fontSize: 14, fontWeight: FontWeight.bold),
                                ),
                              ),
                          ],
                        );
                      },
                      loading: () => const CircularProgressIndicator(color: _blurple),
                      error: (_, __) => Text('Room is empty', style: GoogleFonts.inter(color: _textSecondary)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 48),
              
              ElevatedButton(
                onPressed: () {
                  context.pushNamed(
                    'stream_screen',
                    pathParameters: {'spaceId': spaceId},
                    queryParameters: {
                      'isHost': 'true',
                      'streamType': 'screen',
                    },
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: _blurple,
                  foregroundColor: _textPrimary,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(28),
                  ),
                ),
                child: Text(
                  'Join Room',
                  style: GoogleFonts.inter(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

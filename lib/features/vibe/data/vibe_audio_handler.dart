import 'dart:async';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:just_audio/just_audio.dart';
import 'package:audio_service/audio_service.dart' show MediaItem;

// ── VibeAudioHandler ───────────────────────────────────────────────────────

/// Lightweight audio handler wrapping just_audio's AudioPlayer.
/// Supports two audio sources:
///   - Firebase Storage download URLs (sourceType == 'local_upload')
///   - Local device file paths     (sourceType == 'local_sync')
class VibeAudioHandler {
  final AudioPlayer _player = AudioPlayer();
  final _playbackErrorController = StreamController<String>.broadcast();

  VibeAudioHandler() {
    _player.playbackEventStream.listen(
      (_) {},
      onError: (Object e, StackTrace st) {
        debugPrint('[VibeAudioHandler] playback error: $e');
        _playbackErrorController.add(e.toString());
      },
    );
  }

  /// Fires when playback fails mid-stream (not just on initial load).
  Stream<String> get playbackErrorStream => _playbackErrorController.stream;

  /// Loads a local file OR an https:// URL (e.g. Firebase Storage download URL).
  /// Used for sourceType == 'local_upload' and 'local_sync'.
  Future<void> loadLocalOrUrl({
    required String source,
    required MediaItem item,
  }) async {
    AudioSource audioSource;
    if (source.startsWith('http://') || source.startsWith('https://')) {
      audioSource = AudioSource.uri(Uri.parse(source));
    } else {
      // Treat as a local file path
      audioSource = AudioSource.file(source);
    }
    await _player.setAudioSource(audioSource);
  }

  Future<void> play() => _player.play();
  Future<void> pause() => _player.pause();
  Future<void> stop() => _player.stop();
  Future<void> seek(Duration position) => _player.seek(position);
  Future<void> setSpeed(double speed) => _player.setSpeed(speed);

  Duration get position => _player.position;
  bool get isPlaying => _player.playing;
  Stream<Duration> get positionStream => _player.positionStream;
  Stream<bool> get playingStream =>
      _player.playerStateStream.map((s) => s.playing);
  Stream<void> get completionStream => _player.playerStateStream
      .where((s) => s.processingState == ProcessingState.completed)
      .map((_) => null);

  Future<void> dispose() {
    _playbackErrorController.close();
    return _player.dispose();
  }
}

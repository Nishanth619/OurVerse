import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../data/vibe_models.dart';
import '../../providers/vibe_providers.dart';

/// Shows a bottom sheet to pick a local audio file and either:
///  - Upload it to Firebase Storage so both partners stream it (local_upload), or
///  - Only sync playback controls, each plays their own local copy (local_sync).
Future<VibeSession?> showLocalSongPicker({
  required BuildContext context,
  required String spaceId,
  required String deviceId,
}) {
  return showModalBottomSheet<VibeSession?>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _LocalSongPickerSheet(
      spaceId: spaceId,
      deviceId: deviceId,
    ),
  );
}

// ─── Sheet ────────────────────────────────────────────────────────────────────

class _LocalSongPickerSheet extends ConsumerStatefulWidget {
  final String spaceId;
  final String deviceId;

  const _LocalSongPickerSheet({
    required this.spaceId,
    required this.deviceId,
  });

  @override
  ConsumerState<_LocalSongPickerSheet> createState() =>
      _LocalSongPickerSheetState();
}

class _LocalSongPickerSheetState
    extends ConsumerState<_LocalSongPickerSheet> {
  PlatformFile? _pickedFile;
  bool _uploadAndShare = true; // default: share with partner
  double _uploadProgress = 0;
  bool _isUploading = false;
  bool _isPicking = false;
  String? _error;

  Future<void> _pickFile() async {
    setState(() { _isPicking = true; _error = null; });
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['mp3', 'm4a', 'flac', 'aac', 'ogg', 'wav'],
        allowMultiple: false,
      );
      if (result != null && result.files.isNotEmpty) {
        setState(() => _pickedFile = result.files.first);
      }
    } catch (e) {
      setState(() => _error = 'Could not access files: $e');
    } finally {
      setState(() => _isPicking = false);
    }
  }

  Future<void> _startPlaying() async {
    final file = _pickedFile;
    if (file == null || file.path == null) return;

    setState(() { _isUploading = true; _error = null; _uploadProgress = 0; });

    final repo = ref.read(vibeRepositoryProvider);
    final fileName = file.name;
    final filePath = file.path!;
    final songId = 'local_${DateTime.now().millisecondsSinceEpoch}';
    final durationMs = await _getLocalDuration(filePath);

    try {
      if (_uploadAndShare) {
        // ── Upload to Firebase Storage ──────────────────────────────────
        final uploadStream = repo.uploadLocalSong(
            widget.spaceId, File(filePath), fileName);
        String? downloadUrl;

        await for (final snap in uploadStream) {
          final total = snap.totalBytes;
          if (total > 0) {
            setState(() => _uploadProgress = snap.bytesTransferred / total);
          }
          if (snap.state == TaskState.success) {
            downloadUrl = await snap.ref.getDownloadURL();
          }
        }

        if (downloadUrl == null) {
          setState(() {
            _error = 'Upload failed — please try again.';
            _isUploading = false;
          });
          return;
        }

        // Build session: partner streams from Firebase Storage URL
        final session = VibeSession(
          videoId: songId,
          videoTitle: _cleanName(fileName),
          videoThumb: '',
          videoDurationMs: durationMs,
          isPlaying: true,
          sourceType: 'local_upload',
          localStorageUrl: downloadUrl,
          startedAt: DateTime.now().millisecondsSinceEpoch,
          startPositionMs: 0,
          updatedBy: widget.deviceId,
        );
        if (mounted) Navigator.of(context).pop(session);
      } else {
        // ── Sync-only: play from local path, partner syncs controls ────
        final session = VibeSession(
          videoId: songId,
          videoTitle: _cleanName(fileName),
          videoThumb: '',
          videoDurationMs: durationMs,
          isPlaying: true,
          sourceType: 'local_sync',
          localStorageUrl: filePath, // local path stored only for current device
          startedAt: DateTime.now().millisecondsSinceEpoch,
          startPositionMs: 0,
          updatedBy: widget.deviceId,
        );
        if (mounted) Navigator.of(context).pop(session);
      }
    } catch (e) {
      setState(() {
        _error = 'Error: $e';
        _isUploading = false;
      });
    }
  }

  Future<int> _getLocalDuration(String path) async {
    // just_audio can read duration when the file is loaded during playback.
    // Return 0 here — it gets updated by the player once loaded.
    return 0;
  }

  String _cleanName(String fileName) {
    // Remove extension
    return fileName.replaceAll(RegExp(r'\.[^.]+$'), '');
  }

  String _fmtSize(int bytes) {
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      margin: EdgeInsets.only(bottom: bottom),
      decoration: const BoxDecoration(
        color: Color(0xFF1A1A2E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Title
              Text(
                '📂 Play a local song',
                style: GoogleFonts.outfit(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Pick an offline song from your device',
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5), fontSize: 13),
              ),
              const SizedBox(height: 24),

              // Pick button or file info
              if (_pickedFile == null)
                _PickButton(onTap: _pickFile, isLoading: _isPicking)
              else
                _FileCard(
                  name: _cleanName(_pickedFile!.name),
                  ext: _pickedFile!.extension?.toUpperCase() ?? '',
                  size: _fmtSize(_pickedFile!.size),
                  onClear: _isUploading
                      ? null
                      : () => setState(() => _pickedFile = null),
                ),

              const SizedBox(height: 20),

              // Upload toggle
              if (_pickedFile != null && !_isUploading)
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                        color: Colors.white.withValues(alpha: 0.1)),
                  ),
                  child: SwitchListTile(
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    title: const Text('Upload & share with partner',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w600)),
                    subtitle: Text(
                      _uploadAndShare
                          ? 'Partner will stream your file automatically'
                          : 'Sync controls only — partner needs the same song',
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.5),
                          fontSize: 12),
                    ),
                    value: _uploadAndShare,
                    onChanged: (v) => setState(() => _uploadAndShare = v),
                    activeThumbColor: const Color(0xFFB388FF),
                  ),
                ),

              // Upload progress
              if (_isUploading && _uploadAndShare) ...[
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Icon(Icons.cloud_upload_outlined,
                        color: Color(0xFFB388FF), size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: _uploadProgress,
                          backgroundColor: Colors.white12,
                          valueColor: const AlwaysStoppedAnimation<Color>(
                              Color(0xFFB388FF)),
                          minHeight: 6,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${(_uploadProgress * 100).toStringAsFixed(0)}%',
                      style: const TextStyle(
                          color: Color(0xFFB388FF),
                          fontSize: 12,
                          fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ],

              // Error
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!,
                    style: const TextStyle(
                        color: Color(0xFFFF6E6E), fontSize: 13)),
              ],

              const SizedBox(height: 24),

              // Action button
              ElevatedButton.icon(
                onPressed: (_pickedFile != null && !_isUploading)
                    ? _startPlaying
                    : null,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: const Color(0xFFB388FF),
                  disabledBackgroundColor: Colors.white12,
                  foregroundColor: Colors.white,
                  disabledForegroundColor: Colors.white38,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  elevation: 0,
                ),
                icon: _isUploading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                    : Icon(
                        _uploadAndShare
                            ? Icons.cloud_upload_rounded
                            : Icons.sync_rounded,
                        color: _pickedFile == null ? Colors.white54 : Colors.white,
                      ),
                label: Text(
                  _isUploading
                      ? (_uploadAndShare ? 'Uploading...' : 'Starting...')
                      : (_uploadAndShare
                          ? 'Upload & Play Together'
                          : 'Play & Sync Controls'),
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: _pickedFile == null ? Colors.white54 : Colors.white),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Pick Button ──────────────────────────────────────────────────────────────

class _PickButton extends StatelessWidget {
  final VoidCallback onTap;
  final bool isLoading;
  const _PickButton({required this.onTap, required this.isLoading});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isLoading ? null : onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: const Color(0xFFB388FF).withValues(alpha: 0.4),
            width: 1.5,
          ),
        ),
        child: Column(
          children: [
            isLoading
                ? const SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(
                        color: Color(0xFFB388FF), strokeWidth: 2.5))
                : const Icon(Icons.audio_file_rounded,
                    color: Color(0xFFB388FF), size: 36),
            const SizedBox(height: 10),
            Text(
              isLoading ? 'Opening file picker...' : 'Tap to browse songs',
              style: const TextStyle(
                  color: Color(0xFFB388FF),
                  fontWeight: FontWeight.w600,
                  fontSize: 14),
            ),
            const SizedBox(height: 4),
            Text(
              'MP3 · M4A · FLAC · AAC · WAV',
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.35), fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── File Card ────────────────────────────────────────────────────────────────

class _FileCard extends StatelessWidget {
  final String name;
  final String ext;
  final String size;
  final VoidCallback? onClear;

  const _FileCard(
      {required this.name,
      required this.ext,
      required this.size,
      required this.onClear});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFB388FF).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: const Color(0xFFB388FF).withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFFB388FF).withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(
              child: Text(
                  ext.isEmpty ? '🎵' : ext,
                  style: TextStyle(
                      fontSize: ext.isEmpty ? 22.0 : 12.0,
                      color: const Color(0xFFB388FF),
                      fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 14),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(size,
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.45),
                        fontSize: 12)),
              ],
            ),
          ),
          if (onClear != null)
            IconButton(
              onPressed: onClear,
              icon: const Icon(Icons.close_rounded,
                  color: Colors.white38, size: 20),
              tooltip: 'Remove',
            ),
        ],
      ),
    );
  }
}

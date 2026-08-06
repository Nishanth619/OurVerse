import 'package:closer/core/utils/app_utils.dart';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/theme/app_theme.dart';
import '../../data/flash_repository.dart';
import '../../../../data/services/notification_service.dart';
import '../../../../shared/providers/app_providers.dart';
import '../../../vibe/presentation/widgets/sync_status_chip.dart';
import '../../../../core/ads/ad_service.dart';

// ——─ Providers ————————————————————————————————————————————————————————————————


// ——─ Screen ——————————————————————————————————————————————————————————————————─

class FlashScreen extends ConsumerStatefulWidget {
  final String spaceId;
  final List<String> memberIds;
  final String deviceId;

  const FlashScreen({
    super.key,
    required this.spaceId,
    required this.memberIds,
    required this.deviceId,
  });

  @override
  ConsumerState<FlashScreen> createState() => _FlashScreenState();
}

class _FlashScreenState extends ConsumerState<FlashScreen>
    with SingleTickerProviderStateMixin {
  final _picker = ImagePicker();
  bool _uploading = false;
  late AnimationController _celebController;
  late Animation<double> _celebAnim;

  // Partner ID
  String get _partnerId => widget.memberIds
      .firstWhere((id) => id != widget.deviceId, orElse: () => '');

  late final PresenceRepository _presenceRepo;

  @override
  void initState() {
    super.initState();
    _celebController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _celebAnim = CurvedAnimation(
      parent: _celebController,
      curve: Curves.elasticOut,
    );
    // Check if streak should be reset (missed a day)
    // Use provider instead of direct instantiation
    ref.read(flashRepositoryProvider).checkAndResetStreakIfNeeded(widget.spaceId);
        _presenceRepo = ref.read(presenceRepositoryProvider);
    _presenceRepo.setPresent(widget.spaceId, 'flash', widget.deviceId);
  }

  @override
  void dispose() {
    _celebController.dispose();
    _presenceRepo.setAbsent(widget.spaceId, 'flash', widget.deviceId);
    super.dispose();
  }

  Future<void> _pickAndFlash(ImageSource source) async {
    final picked = await _picker.pickImage(
      source: source,
      imageQuality: 60,
      maxWidth: 1080,
    );
    if (picked == null) return;

    setState(() => _uploading = true);
    try {
      final repo = ref.read(flashRepositoryProvider);
      final base64Url = await repo.processPhotoToBase64(File(picked.path));
      
      await repo.submitFlash(
        spaceId: widget.spaceId,
        deviceId: widget.deviceId,
        photoUrl: base64Url,
        allMemberIds: widget.memberIds,
      );

      final partnerId = widget.memberIds.firstWhere(
        (id) => id != widget.deviceId,
        orElse: () => '',
      );
      if (partnerId.isNotEmpty) {
        await NotificationService.pingPartnerFlashViaVercel(partnerId);
      }

      // Show ad on success transition
      AdService.instance.showInterstitialIfReady();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Upload failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  void _showSourcePicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Flash your moment',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: Color(0xFF2A1020),
              ),
            ),
            const SizedBox(height: 20),
            _SourceButton(
              icon: Icons.camera_alt_rounded,
              label: 'Take a photo',
              color: AppTheme.primary,
              onTap: () {
                Navigator.pop(ctx);
                _pickAndFlash(ImageSource.camera);
              },
            ),
            const SizedBox(height: 12),
            _SourceButton(
              icon: Icons.photo_library_rounded,
              label: 'Choose from gallery',
              color: const Color(0xFF5B8AF5),
              onTap: () {
                Navigator.pop(ctx);
                _pickAndFlash(ImageSource.gallery);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final flashAsync = ref.watch(flashTodayProvider(widget.spaceId));
    final partnerPresentAsync = _partnerId.isEmpty
        ? const AsyncData(false)
        : ref.watch(featurePresenceProvider(
            (spaceId: widget.spaceId, featureId: 'flash', partnerId: _partnerId)));
    final partnerPresent = partnerPresentAsync.valueOrNull ?? false;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFFFF0F3), Color(0xFFFFF8E7)],
          ),
        ),
        child: SafeArea(
          child: flashAsync.when(
            loading: () => const Center(
              child: CircularProgressIndicator(color: AppTheme.primary),
            ),
            error: (e, _) => Center(child: Text(AppUtils.getFriendlyErrorMessage(e), textAlign: TextAlign.center,)),
            data: (flashDay) {
              final iHaveFlashed = flashDay.hasFlashed(widget.deviceId);
              final partnerHasFlashed = _partnerId.isNotEmpty &&
                  flashDay.hasFlashed(_partnerId);
              final bothFlashed = flashDay.bothFlashed;

              // Trigger celebration animation when both flash
              if (bothFlashed && !_celebController.isCompleted) {
                _celebController.forward();
              }

              return CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: _FlashAppBar(
                      streak: flashDay.streak,
                      partnerPresent: partnerPresent,
                    ),
                  ),
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 16),
                      child: Column(
                        children: [
                          // —— Both flashed celebration ————————————————————─
                          if (bothFlashed)
                            ScaleTransition(
                              scale: _celebAnim,
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(16),
                                margin: const EdgeInsets.only(bottom: 16),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      AppTheme.primary
                                          .withValues(alpha: 0.15),
                                      AppTheme.accent
                                          .withValues(alpha: 0.15),
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: AppTheme.primary
                                        .withValues(alpha: 0.3),
                                  ),
                                ),
                                child: Column(
                                  children: [
                                    const Text('🔥',
                                        style: TextStyle(fontSize: 32)),
                                    const SizedBox(height: 4),
                                    Text(
                                      'You both Flashed today!',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w800,
                                        color: AppTheme.primary,
                                      ),
                                    ),
                                    Text(
                                      '+1 streak earned',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: AppTheme.onSurfaceMuted,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),

                          // —— Photo cards row ——————————————————————————————
                          Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            children: widget.memberIds.map((id) {
                              final isMe = id == widget.deviceId;
                              final label = isMe
                                  ? 'You ⚡'
                                  : (widget.memberIds.length <= 2 ? 'Partner 💕' : 'Friend ${id.length > 5 ? id.substring(0, 6).toUpperCase() : id}');
                              return SizedBox(
                                width: (MediaQuery.of(context).size.width - 40 - 12) / 2,
                                child: _PhotoCard(
                                  label: label,
                                  entry: flashDay.entryFor(id),
                                  isMe: isMe,
                                  partnerHasFlashed: flashDay.hasFlashed(id),
                                ),
                              );
                            }).toList(),
                          ),

                          const SizedBox(height: 24),

                          // —— Flash button ————————————————————————————————─
                          if (!iHaveFlashed)
                            _FlashButton(
                              uploading: _uploading,
                              onTap: _showSourcePicker,
                            )
                          else if (!bothFlashed)
                            _WaitingChip(
                              partnerFlashed: partnerHasFlashed,
                            ),

                          const Spacer(),

                          // —— Helper text ——————————————————————————————————
                          Text(
                            'Flash resets every day at midnight 🌙',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppTheme.onSurfaceMuted,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 8),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

// ——─ App Bar with Streak ——————————————————————————————————————————————————————

class _FlashAppBar extends StatelessWidget {
  final int streak;
  final bool partnerPresent;
  const _FlashAppBar({required this.streak, required this.partnerPresent});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded,
                color: Color(0xFF2A1020), size: 20),
            onPressed: () => Navigator.pop(context),
          ),
          Expanded(
            child: Column(
              children: [
                const Text(
                  'Flash ⚡',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF2A1020),
                  ),
                ),
                Text(
                  'Share a moment of your day',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppTheme.onSurfaceMuted,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          // Streak badge
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: streak > 0
                  ? AppTheme.accent.withValues(alpha: 0.15)
                  : AppTheme.surfaceAlt,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: streak > 0
                    ? AppTheme.accent.withValues(alpha: 0.4)
                    : AppTheme.divider,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  streak > 0 ? '🔥' : '💤',
                  style: const TextStyle(fontSize: 14),
                ),
                const SizedBox(width: 4),
                Text(
                  '$streak',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: streak > 0
                        ? AppTheme.accent
                        : AppTheme.onSurfaceMuted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          SyncStatusChip(
            state: partnerPresent ? SyncState.inSync : SyncState.partnerLeft,
          ),
        ],
      ),
    );
  }
}

// ——─ Photo Card ——————————————————————————————————————————————————————————————─

class _PhotoCard extends StatelessWidget {
  final String label;
  final FlashEntry? entry;
  final bool isMe;
  final bool partnerHasFlashed;

  const _PhotoCard({
    required this.label,
    required this.entry,
    required this.isMe,
    this.partnerHasFlashed = false,
  });

  @override
  Widget build(BuildContext context) {
    final hasPhoto = entry != null && entry!.photoUrl.isNotEmpty;
    final color = isMe ? AppTheme.primary : const Color(0xFF5B8AF5);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ),
        AspectRatio(
          aspectRatio: 3 / 4,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            decoration: BoxDecoration(
              color: hasPhoto ? Colors.transparent : color.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: hasPhoto
                    ? color.withValues(alpha: 0.4)
                    : color.withValues(alpha: 0.2),
                width: hasPhoto ? 2 : 1.5,
              ),
              boxShadow: hasPhoto
                  ? [
                      BoxShadow(
                        color: color.withValues(alpha: 0.2),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      )
                    ]
                  : [],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: hasPhoto
                  ? Image.memory(
                      base64Decode(entry!.photoUrl),
                      fit: BoxFit.cover,
                    )
                  : Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            isMe
                                ? Icons.add_a_photo_outlined
                                : (partnerHasFlashed
                                    ? Icons.hourglass_top_rounded
                                    : Icons.person_outline_rounded),
                            size: 36,
                            color: color.withValues(alpha: 0.5),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            isMe
                                ? 'Your flash'
                                : (partnerHasFlashed
                                    ? 'Loading...'
                                    : 'Waiting...'),
                            style: TextStyle(
                              fontSize: 12,
                              color: color.withValues(alpha: 0.6),
                              fontWeight: FontWeight.w600,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
            ),
          ),
        ),
      ],
    );
  }
}

// ——─ Flash Button ————————————————————————————————————————————————————————————─

class _FlashButton extends StatelessWidget {
  final bool uploading;
  final VoidCallback onTap;
  const _FlashButton({required this.uploading, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: uploading ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: double.infinity,
        height: 58,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: uploading
                ? [AppTheme.primary.withValues(alpha: 0.5), AppTheme.primary.withValues(alpha: 0.4)]
                : [AppTheme.primary, const Color(0xFFD44F6A)],
          ),
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: AppTheme.primary.withValues(alpha: 0.35),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Center(
          child: uploading
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2.5,
                  ),
                )
              : const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('⚡', style: TextStyle(fontSize: 20)),
                    SizedBox(width: 8),
                    Text(
                      'Flash your day',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

// ——─ Waiting Chip ————————————————————————————————————————————————————————————─

class _WaitingChip extends StatelessWidget {
  final bool partnerFlashed;
  const _WaitingChip({required this.partnerFlashed});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surfaceAlt,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            partnerFlashed ? '🎉' : '⏳',
            style: const TextStyle(fontSize: 20),
          ),
          const SizedBox(width: 10),
          Text(
            partnerFlashed
                ? 'Partner has also flashed! 🔥'
                : 'Waiting for partner to Flash...',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppTheme.onSurfaceMuted,
            ),
          ),
        ],
      ),
    );
  }
}

// ——─ Source Picker Button ————————————————————————————————————————————————————─

class _SourceButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _SourceButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 14),
            Text(
              label,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
// TEST LINE

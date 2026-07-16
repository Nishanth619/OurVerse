import 'package:closer/core/utils/app_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import '../../../../shared/providers/app_providers.dart';
import '../../../../core/theme/app_theme.dart';

class CreateSpaceScreen extends ConsumerStatefulWidget {
  const CreateSpaceScreen({super.key});

  @override
  ConsumerState<CreateSpaceScreen> createState() => _CreateSpaceScreenState();
}

class _CreateSpaceScreenState extends ConsumerState<CreateSpaceScreen> {
  String _selectedType = 'couple';
  final _nameController = TextEditingController();
  bool _loading = false;
  String? _generatedCode;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _createSpace() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter your name first')),
      );
      return;
    }

    setState(() => _loading = true);
    try {
      // Use DI provider instead of direct instantiation (Fix 12)
      final authService = ref.read(authServiceProvider);
      await authService.setDeviceName(name);

      final repo = ref.read(spaceRepositoryProvider);
      final space = await repo.createSpace(type: _selectedType);

      ref.read(activeSpaceIdProvider.notifier).state = space.id;

      setState(() => _generatedCode = space.inviteCode);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppUtils.getFriendlyErrorMessage(e),
              textAlign: TextAlign.center,
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _copyCode() {
    if (_generatedCode == null) return;
    Clipboard.setData(ClipboardData(text: _generatedCode!));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Invite code copied!')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_generatedCode != null) {
      return _buildCodeReveal(theme);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Create a Space')),
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverFillRemaining(
              hasScrollBody: false,
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('What should we call you?',
                        style: theme.textTheme.titleLarge),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _nameController,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(hintText: 'Your name'),
                    ),
                    const SizedBox(height: 28),
                    Text('This space is for...', style: theme.textTheme.titleLarge),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _TypeTile(
                            emoji: '💑',
                            label: 'Couple',
                            selected: _selectedType == 'couple',
                            onTap: () => setState(() => _selectedType = 'couple'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _TypeTile(
                            emoji: '👯',
                            label: 'Friends',
                            selected: _selectedType == 'friends',
                            onTap: () => setState(() => _selectedType = 'friends'),
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    ElevatedButton(
                      onPressed: _loading ? null : _createSpace,
                      child: _loading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('Create Space'),
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

  Widget _buildCodeReveal(ThemeData theme) {
    return Scaffold(
      appBar: AppBar(title: const Text('Your Space is Ready!')),
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverFillRemaining(
              hasScrollBody: false,
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    const Spacer(),
                    const Text('🎉', style: TextStyle(fontSize: 64)),
                    const SizedBox(height: 24),
                    Text(
                      'Share this code with your\n${_selectedType == 'couple' ? 'partner' : 'friends'}',
                      style: theme.textTheme.headlineMedium,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 32),
                    GestureDetector(
                      onTap: _copyCode,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 32,
                          vertical: 20,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.surfaceAlt,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: AppTheme.primary,
                            width: 2,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                _generatedCode!,
                                style: theme.textTheme.displayLarge?.copyWith(
                                  letterSpacing: 8,
                                  color: AppTheme.primary,
                                  fontSize: 32,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            const Icon(Icons.copy, color: AppTheme.primary),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Tap to copy',
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: () {
                        final link =
                            'https://closer.app/invite?code=${_generatedCode!}';
                        Share.share(
                          'Join my OurVerse space! Use code ${_generatedCode!} or tap: $link',
                          subject: 'Join me on OurVerse',
                        );
                      },
                      icon: const Icon(Icons.share),
                      label: const Text('Share invite link'),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '⚠️ Save this code somewhere — you\'ll need it\nto rejoin if you reinstall the app.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: AppTheme.accent.withValues(alpha: 0.9),
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const Spacer(),
                    ElevatedButton(
                      onPressed: () => context.go('/home'),
                      child: const Text('Start ✨'),
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

class _TypeTile extends StatelessWidget {
  final String emoji;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _TypeTile({
    required this.emoji,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
          color:
              selected ? AppTheme.primary.withValues(alpha: 0.1) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? AppTheme.primary : AppTheme.divider,
            width: selected ? 2 : 1.5,
          ),
        ),
        child: Column(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 32)),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: selected ? AppTheme.primary : AppTheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

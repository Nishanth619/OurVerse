import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/utils/app_utils.dart';
import '../../../../shared/providers/app_providers.dart';

class JoinSpaceScreen extends ConsumerStatefulWidget {
  final String? prefillCode;

  const JoinSpaceScreen({super.key, this.prefillCode});

  @override
  ConsumerState<JoinSpaceScreen> createState() => _JoinSpaceScreenState();
}

class _JoinSpaceScreenState extends ConsumerState<JoinSpaceScreen> {
  late final TextEditingController _codeController;
  final _nameController = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _codeController = TextEditingController(
      text: widget.prefillCode?.toUpperCase().trim() ?? '',
    );
  }

  @override
  void dispose() {
    _codeController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _joinSpace() async {
    final name = _nameController.text.trim();
    final code = _codeController.text.trim().toUpperCase();

    if (name.isEmpty) {
      setState(() => _error = 'Enter your name');
      return;
    }
    if (code.length != 6) {
      setState(() => _error = 'Enter a valid 6-character code');
      return;
    }

    // Dismiss keyboard
    FocusScope.of(context).unfocus();

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // Use DI provider instead of direct instantiation (Fix 12)
      final auth = ref.read(authServiceProvider);
      await auth.setDeviceName(name);

      final repo = ref.read(spaceRepositoryProvider);
      final space = await repo.joinSpace(inviteCode: code);

      if (space == null) {
        setState(() => _error = 'Code not found. Check and try again.');
        return;
      }

      ref.read(activeSpaceIdProvider.notifier).state = space.id;
      if (mounted) context.go('/home');
    } catch (e, st) {
      debugPrint('JoinSpace error: $e\n$st');
      setState(() => _error = AppUtils.getFriendlyErrorMessage(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Join a Space')),
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
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(hintText: 'Your name'),
                    ),
                    const SizedBox(height: 24),
                    Text('Enter the invite code', style: theme.textTheme.titleLarge),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _codeController,
                      textCapitalization: TextCapitalization.characters,
                      maxLength: 6,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _joinSpace(),
                      onChanged: (v) {
                        // Auto-uppercase as user types
                        final upper = v.toUpperCase();
                        if (v != upper) {
                          _codeController.value = TextEditingValue(
                            text: upper,
                            selection: TextSelection.collapsed(offset: upper.length),
                          );
                        }
                      },
                      style: const TextStyle(
                        letterSpacing: 6,
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                      ),
                      decoration: InputDecoration(
                        hintText: 'XXXXXX',
                        hintStyle: TextStyle(
                          letterSpacing: 4,
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
                        ),
                        counterText: '',
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        _error!,
                        style: TextStyle(
                          color: theme.colorScheme.error,
                          fontSize: 13,
                        ),
                      ),
                    ],
                    const Spacer(),
                    ElevatedButton(
                      onPressed: _loading ? null : _joinSpace,
                      child: _loading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('Join Space'),
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


import 'package:closer/core/utils/app_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../data/services/auth_service.dart';
import '../../../../data/services/notification_service.dart';
import '../../../../data/services/home_widget_service.dart';
import '../../../../shared/providers/app_providers.dart';
import '../../../../shared/providers/subscription_providers.dart';
import '../../../../features/premium/presentation/widgets/premium_badge.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _notificationsEnabled = true;
  bool _moodPingsEnabled = true;
  String _widgetMode = 'question';
  bool _settingsLoaded = false;

  final _nicknameController = TextEditingController();
  final _myNameController = TextEditingController();
  bool _savingNickname = false;
  bool _savingMyName = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _loadMyName();
  }

  @override
  void dispose() {
    _nicknameController.dispose();
    _myNameController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final notifEnabled = await NotificationService.isEnabled();
    final moodPingsEnabled = await NotificationService.isMoodPingsEnabled();
    final widgetMode = await HomeWidgetService.getWidgetMode();
    if (mounted) {
      setState(() {
        _notificationsEnabled = notifEnabled;
        _moodPingsEnabled = moodPingsEnabled;
        _widgetMode = widgetMode;
        _settingsLoaded = true;
      });
    }
  }

  Future<void> _loadMyName() async {
    final auth = ref.read(authServiceProvider);
    final name = await auth.getDeviceName();
    if (mounted) {
      _myNameController.text = name == 'Someone' ? '' : name;
    }
  }

  Future<void> _saveSpaceNickname(String spaceId) async {
    final name = _nicknameController.text.trim();
    if (name.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() => _savingNickname = true);
    try {
      await ref.read(spaceRepositoryProvider).updateSpaceName(spaceId, name);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Space name updated!')),
        );
      }
    } finally {
      if (mounted) setState(() => _savingNickname = false);
    }
  }

  Future<void> _saveMyName() async {
    final name = _myNameController.text.trim();
    if (name.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() => _savingMyName = true);
    try {
      final auth = ref.read(authServiceProvider);
      await auth.setDeviceName(name);
      // Invalidate the deviceNameProvider so any listeners update
      ref.invalidate(deviceNameProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Your name updated!')),
        );
      }
    } finally {
      if (mounted) setState(() => _savingMyName = false);
    }
  }

  Future<void> _toggleNotifications(bool value) async {
    setState(() => _notificationsEnabled = value);
    await NotificationService.setEnabled(value);
  }

  Future<void> _toggleMoodPings(bool value) async {
    setState(() => _moodPingsEnabled = value);
    await NotificationService.setMoodPingsEnabled(value);
  }

  Future<void> _setWidgetMode(String mode) async {
    setState(() => _widgetMode = mode);
    await HomeWidgetService.setWidgetMode(mode);
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void _leaveSpace() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Leave this space?'),
        content: const Text(
          "You'll need the invite code to rejoin. Make sure you've saved it somewhere.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              final auth = AuthService();
              await auth.clearSpaceId();
              ref.read(activeSpaceIdProvider.notifier).state = null;
              if (mounted) {
                Navigator.pop(context);
                context.go('/');
              }
            },
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Leave'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final spaceAsync = ref.watch(spaceStreamProvider);

    // Pre-fill space nickname from stream without a Builder widget
    spaceAsync.whenData((space) {
      if (space != null &&
          _nicknameController.text.isEmpty &&
          space.spaceName.isNotEmpty) {
        _nicknameController.text = space.spaceName;
      }
    });

    if (!_settingsLoaded) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: SafeArea(
        child: spaceAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text(AppUtils.getFriendlyErrorMessage(e), textAlign: TextAlign.center,)),
          data: (space) {
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // ── My Name ────────────────────────────────────────────────
                const _SectionHeader(title: 'MY PROFILE'),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('MY NAME', style: theme.textTheme.labelSmall),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _myNameController,
                                textCapitalization: TextCapitalization.words,
                                decoration: const InputDecoration(
                                  hintText: 'Your name',
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            ElevatedButton(
                              onPressed: _savingMyName ? null : _saveMyName,
                              style: ElevatedButton.styleFrom(
                                  minimumSize: const Size(60, 48)),
                              child: _savingMyName
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white))
                                  : const Text('Save'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Shown in answer reveal cards',
                          style: theme.textTheme.bodyMedium?.copyWith(
                              fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // ── Space Info ─────────────────────────────────────────────
                const _SectionHeader(title: 'YOUR SPACE'),
                if (space != null) ...[
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                space.type == 'couple' ? '💑' : '👯',
                                style: const TextStyle(fontSize: 24),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                space.type == 'couple'
                                    ? 'Couple Space'
                                    : 'Friends Space',
                                style: theme.textTheme.titleLarge,
                              ),
                              const Spacer(),
                              // Streak badge
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: AppTheme.accent.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Text('🔥',
                                        style: TextStyle(fontSize: 14)),
                                    const SizedBox(width: 4),
                                    Text(
                                      '${space.currentStreak}',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          color: AppTheme.accent,
                                          fontSize: 14),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${space.memberDeviceIds.length} member(s)',
                            style: theme.textTheme.bodyMedium,
                          ),
                          const Divider(height: 24),

                          // Space nickname
                          Text('SPACE NICKNAME',
                              style: theme.textTheme.labelSmall),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _nicknameController,
                                  textCapitalization:
                                      TextCapitalization.sentences,
                                  decoration: const InputDecoration(
                                    hintText: 'e.g. Us 💞',
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              ElevatedButton(
                                onPressed: _savingNickname
                                    ? null
                                    : () => _saveSpaceNickname(space.id),
                                style: ElevatedButton.styleFrom(
                                    minimumSize: const Size(60, 48)),
                                child: _savingNickname
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white))
                                    : const Text('Save'),
                              ),
                            ],
                          ),
                          const Divider(height: 24),

                          // Invite code
                          Text('INVITE CODE',
                              style: theme.textTheme.labelSmall),
                          const SizedBox(height: 6),
                          GestureDetector(
                            onTap: () {
                              Clipboard.setData(
                                  ClipboardData(text: space.inviteCode));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Code copied!')),
                              );
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 10),
                              decoration: BoxDecoration(
                                color: AppTheme.surfaceAlt,
                                borderRadius: BorderRadius.circular(12),
                                border:
                                    Border.all(color: AppTheme.divider),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    space.inviteCode,
                                    style: theme.textTheme.headlineMedium
                                        ?.copyWith(
                                      letterSpacing: 4,
                                      color: AppTheme.primary,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  const Icon(Icons.copy,
                                      size: 16, color: AppTheme.primary),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Tap to copy and share with your ${space.type == 'couple' ? 'partner' : 'friends'}',
                            style: theme.textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 16),

                // ── Notifications ──────────────────────────────────────────
                const _SectionHeader(title: 'NOTIFICATIONS'),
                Card(
                  child: Column(
                    children: [
                      SwitchListTile(
                        title: const Text('Partner mood updates'),
                        subtitle: const Text("Get notified when they change their emoji"),
                        value: _moodPingsEnabled,
                        onChanged: _toggleMoodPings,
                        activeThumbColor: AppTheme.primary,
                      ),
                      const Divider(height: 1, indent: 16, endIndent: 16),
                      SwitchListTile(
                        title: const Text('Daily reminder'),
                        subtitle: const Text(
                            "Get nudged at 8 PM if you haven't checked in"),
                        value: _notificationsEnabled,
                        onChanged: _toggleNotifications,
                        activeThumbColor: AppTheme.primary,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // ── Widget ─────────────────────────────────────────────────
                const _SectionHeader(title: 'HOME SCREEN WIDGET'),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Show on widget',
                          style: theme.textTheme.bodyLarge
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: _WidgetModeOption(
                                label: "Today's\nQuestion",
                                emoji: '❓',
                                selected: _widgetMode == 'question',
                                onTap: () => _setWidgetMode('question'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _WidgetModeOption(
                                label: "Partner's\nMood",
                                emoji: '😊',
                                selected: _widgetMode == 'mood',
                                onTap: () => _setWidgetMode('mood'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _WidgetModeOption(
                                label: "Partner's\nFlash",
                                emoji: '📸',
                                selected: _widgetMode == 'flash',
                                onTap: () => _setWidgetMode('flash'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // ── Premium ──────────────────────────────────────────────────────
                const _SectionHeader(title: 'SUBSCRIPTION'),
                Builder(builder: (context) {
                  final isPremium = ref.watch(isPremiumProvider).valueOrNull ?? false;
                  return Card(
                    child: ListTile(
                      leading: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFFFFD700), Color(0xFFFFAA00)],
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.star_rounded, color: Colors.black, size: 22),
                      ),
                      title: Text(
                        isPremium ? 'Ourverse Premium' : 'Upgrade to Premium',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(
                        isPremium
                            ? 'You have unlimited plays, streaming & no ads!'
                            : 'Remove ads • Unlimited plays • Unlimited streaming',
                      ),
                      trailing: isPremium
                          ? const PremiumBadge(compact: true)
                          : const Icon(Icons.arrow_forward_ios, size: 16),
                      onTap: () => context.push('/premium'),
                    ),
                  );
                }),

                const SizedBox(height: 16),

                // ── About & Legal ──────────────────────────────────────────
                const _SectionHeader(title: 'ABOUT & LEGAL'),
                Card(
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.privacy_tip_outlined),
                        title: const Text('Privacy Policy'),
                        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                        onTap: () => _openUrl('https://www.nexaaradhya.site/privacy/ourverse'),
                      ),
                      const Divider(height: 1, indent: 16, endIndent: 16),
                      ListTile(
                        leading: const Icon(Icons.description_outlined),
                        title: const Text('Terms and Conditions'),
                        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                        onTap: () => _openUrl('https://www.nexaaradhya.site/terms/ourverse'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // ── Danger Zone ────────────────────────────────────────────
                const _SectionHeader(title: 'ACCOUNT & SPACE'),
                Card(
                  child: Column(
                    children: [
                      ListTile(
                        leading:
                            const Icon(Icons.exit_to_app, color: Colors.redAccent),
                        title: const Text('Leave space'),
                        subtitle: const Text(
                            "You'll need the invite code to rejoin"),
                        textColor: Colors.redAccent,
                        onTap: _leaveSpace,
                      ),
                      const Divider(height: 1, indent: 16, endIndent: 16),
                      ListTile(
                        leading: const Icon(Icons.delete_forever, color: Colors.redAccent),
                        title: const Text('Delete Account'),
                        subtitle: const Text("Permanently erase your data"),
                        textColor: Colors.redAccent,
                        onTap: () => _openUrl('https://www.nexaaradhya.site/delete-account/ourverse'),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 32),
                Center(
                  child: Text(
                    'OurVerse v1.0.0 · Made with 💞',
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                const SizedBox(height: 24),
              ],
            );
          },
        ),
      ),
    );
  }
}

// ─── Section Header ───────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8, top: 4),
      child: Text(
        title,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              letterSpacing: 1.2,
            ),
      ),
    );
  }
}

// ─── Widget Mode Option ───────────────────────────────────────────────────────

class _WidgetModeOption extends StatelessWidget {
  final String label;
  final String emoji;
  final bool selected;
  final VoidCallback onTap;

  const _WidgetModeOption({
    required this.label,
    required this.emoji,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: selected
              ? AppTheme.primary.withValues(alpha: 0.1)
              : AppTheme.surfaceAlt,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? AppTheme.primary : AppTheme.divider,
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 22)),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: selected ? AppTheme.primary : AppTheme.onSurfaceMuted,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../stream/presentation/widgets/screen_share_bar.dart';
import '../../../stream/providers/stream_providers.dart';

class MainShellScreen extends ConsumerWidget {
  final StatefulNavigationShell shell;
  const MainShellScreen({super.key, required this.shell});

  void _onTap(int index) {
    shell.goBranch(
      index,
      initialLocation: index == shell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopScope(
      canPop: shell.currentIndex == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        // If we didn't pop (meaning we're not on the home tab),
        // intercept the back button to go back to Home.
        if (shell.currentIndex != 0) {
          shell.goBranch(0);
        }
      },
      child: Scaffold(
        body: Column(
          children: [
            Expanded(child: shell),
            Consumer(builder: (ctx, ref, _) {
              final state = ref.watch(screenShareStateProvider);
              if (!state.isInRoom && !state.isSharing) return const SizedBox.shrink();
              return const ScreenShareBar();
            }),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: shell.currentIndex,
          onDestinationSelected: _onTap,
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home),
              label: 'Home',
            ),
            NavigationDestination(
              icon: Icon(Icons.games_outlined),
              selectedIcon: Icon(Icons.games),
              label: 'Games',
            ),
            NavigationDestination(
              icon: Icon(Icons.chat_bubble_outline_rounded),
              selectedIcon: Icon(Icons.chat_bubble_rounded),
              label: 'Only Us',
            ),
            NavigationDestination(
              icon: Icon(Icons.settings_outlined),
              selectedIcon: Icon(Icons.settings),
              label: 'Settings',
            ),
          ],
        ),
      ),
    );
  }
}

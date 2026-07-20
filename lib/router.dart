import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'shared/providers/app_providers.dart';
import 'features/onboarding/presentation/screens/splash_screen.dart';
import 'features/onboarding/presentation/screens/onboarding_screen.dart';
import 'features/onboarding/presentation/screens/welcome_screen.dart';
import 'features/onboarding/presentation/screens/create_space_screen.dart';
import 'features/onboarding/presentation/screens/join_space_screen.dart';
import 'features/home/presentation/screens/home_screen.dart';
import 'features/home/presentation/screens/main_shell_screen.dart';
import 'features/games/presentation/screens/games_screen.dart';
import 'features/games/presentation/screens/wyr_game_screen.dart';
import 'features/games/presentation/screens/flash_screen.dart';
import 'features/games/presentation/screens/arcade_screen.dart';
import 'features/games/presentation/screens/doodle_screen.dart';
import 'features/games/presentation/screens/word_hunt_screen.dart';
import 'features/games/presentation/screens/ludo_screen.dart';
import 'features/games/presentation/screens/snakes_ladders_screen.dart';
import 'features/games/presentation/screens/bingo_screen.dart';
import 'features/games/presentation/screens/uno_screen.dart';

import 'features/settings/presentation/screens/settings_screen.dart';
import 'features/question/presentation/screens/question_detail_screen.dart';
import 'features/chat/presentation/screens/chat_screen.dart';
import 'features/vibe/presentation/screens/vibe_screen.dart';
import 'features/vibe/presentation/screens/youtube_sync_screen.dart';
import 'features/stream/presentation/screens/stream_lobby_screen.dart';

/// Bridges Riverpod [StateProvider] to a [Listenable] so GoRouter
/// re-evaluates redirect() whenever the active space ID changes.
class _SpaceIdListenable extends ChangeNotifier {
  _SpaceIdListenable(Ref ref) {
    ref.listen<String?>(activeSpaceIdProvider, (_, __) => notifyListeners());
  }
}

final rootNavigatorKey = GlobalKey<NavigatorState>();

final routerProvider = Provider<GoRouter>((ref) {
  final listenable = _SpaceIdListenable(ref);

  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: '/splash',
    refreshListenable: listenable,
    redirect: (context, state) {
      final spaceId = ref.read(activeSpaceIdProvider);
      final loc = state.matchedLocation;

      if (loc == '/splash') return null;
      if (loc == '/onboarding') return null; // always allow onboarding

      // Has space → skip onboarding
      if (spaceId != null &&
          (loc == '/' || loc == '/create' || loc == '/join')) {
        return '/home';
      }

      // No space → can't access app screens
      if (spaceId == null &&
          (loc == '/home' ||
              loc == '/games' ||
              loc == '/chat' ||
              loc == '/settings' ||
              loc == '/question' ||
              loc == '/vibe' ||
              loc == '/youtube-sync')) {
        return '/';
      }

      return null;
    },
    routes: [
      GoRoute(
        path: '/splash',
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: '/onboarding',
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(
        path: '/',
        builder: (context, state) => const WelcomeScreen(),
      ),
      GoRoute(
        path: '/create',
        builder: (context, state) => const CreateSpaceScreen(),
      ),
      GoRoute(
        path: '/join',
        builder: (context, state) {
          final code = state.uri.queryParameters['code'];
          return JoinSpaceScreen(prefillCode: code);
        },
      ),
      GoRoute(
        path: '/invite',
        builder: (context, state) {
          final code = state.uri.queryParameters['code'];
          return JoinSpaceScreen(prefillCode: code);
        },
      ),
      GoRoute(
        path: '/question',
        builder: (context, state) => const QuestionDetailScreen(),
      ),
      GoRoute(
        path: '/vibe',
        builder: (context, state) {
          final spaceAsync = ref.read(spaceStreamProvider);
          final deviceId = ref.read(deviceIdProvider).value ?? '';
          final space = spaceAsync.value;
          final memberIds = space?.memberDeviceIds ?? [];
          final partnerId =
              memberIds.firstWhere((id) => id != deviceId, orElse: () => '');
          return VibeScreen(
            spaceId: space?.id ?? '',
            deviceId: deviceId,
            partnerId: partnerId,
          );
        },
      ),
      GoRoute(
        path: '/youtube-sync',
        builder: (context, state) {
          final spaceAsync = ref.read(spaceStreamProvider);
          final deviceId = ref.read(deviceIdProvider).value ?? '';
          final space = spaceAsync.value;
          final memberIds = space?.memberDeviceIds ?? [];
          final partnerId =
              memberIds.firstWhere((id) => id != deviceId, orElse: () => '');
          return YoutubeSyncScreen(
            spaceId: space?.id ?? '',
            deviceId: deviceId,
            partnerId: partnerId,
          );
        },
      ),
      GoRoute(
        path: '/stream',
        builder: (context, state) => const StreamLobbyScreen(),
      ),
      GoRoute(
        path: '/games/wyr',
        builder: (context, state) {
          final space = ref.read(spaceStreamProvider).value;
          final deviceId = ref.read(deviceIdProvider).value ?? '';
          return WyrGameScreen(
            spaceId: space?.id ?? '',
            memberIds: space?.memberDeviceIds ?? [],
            deviceId: deviceId,
          );
        },
      ),
      GoRoute(
        path: '/games/flash',
        builder: (context, state) {
          final space = ref.read(spaceStreamProvider).value;
          final deviceId = ref.read(deviceIdProvider).value ?? '';
          return FlashScreen(
            spaceId: space?.id ?? '',
            memberIds: space?.memberDeviceIds ?? [],
            deviceId: deviceId,
          );
        },
      ),
      GoRoute(
        path: '/games/arcade',
        builder: (context, state) {
          final space = ref.read(spaceStreamProvider).value;
          final deviceId = ref.read(deviceIdProvider).value ?? '';
          return ArcadeScreen(
            spaceId: space?.id ?? '',
            memberIds: space?.memberDeviceIds ?? [],
            deviceId: deviceId,
          );
        },
      ),
      GoRoute(
        path: '/games/doodle',
        builder: (context, state) {
          final space = ref.read(spaceStreamProvider).value;
          final deviceId = ref.read(deviceIdProvider).value ?? '';
          return DoodleScreen(
            spaceId: space?.id ?? '',
            memberIds: space?.memberDeviceIds ?? [],
            deviceId: deviceId,
          );
        },
      ),
      GoRoute(
        path: '/games/wordhunt',
        builder: (context, state) {
          final space = ref.read(spaceStreamProvider).value;
          final deviceId = ref.read(deviceIdProvider).value ?? '';
          return WordHuntScreen(
            spaceId: space?.id ?? '',
            memberIds: space?.memberDeviceIds ?? [],
            deviceId: deviceId,
          );
        },
      ),
      GoRoute(
        path: '/games/ludo',
        builder: (context, state) {
          final space = ref.read(spaceStreamProvider).value;
          final deviceId = ref.read(deviceIdProvider).value ?? '';
          return LudoScreen(
            spaceId: space?.id ?? '',
            memberIds: space?.memberDeviceIds ?? [],
            deviceId: deviceId,
          );
        },
      ),
      GoRoute(
        path: '/games/snakesladders',
        builder: (context, state) {
          final space = ref.read(spaceStreamProvider).value;
          final deviceId = ref.read(deviceIdProvider).value ?? '';
          return SnakesLaddersScreen(
            spaceId: space?.id ?? '',
            memberIds: space?.memberDeviceIds ?? [],
            deviceId: deviceId,
          );
        },
      ),
      GoRoute(
        path: '/games/bingo',
        builder: (context, state) {
          final space = ref.read(spaceStreamProvider).value;
          final deviceId = ref.read(deviceIdProvider).value ?? '';
          return BingoScreen(
            spaceId: space?.id ?? '',
            memberIds: space?.memberDeviceIds ?? [],
            deviceId: deviceId,
          );
        },
      ),
      GoRoute(
        path: '/games/uno',
        builder: (context, state) {
          final space = ref.read(spaceStreamProvider).value;
          final deviceId = ref.read(deviceIdProvider).value ?? '';
          return UnoScreen(
            spaceId: space?.id ?? '',
            memberIds: space?.memberDeviceIds ?? [],
            deviceId: deviceId,
          );
        },
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => MainShellScreen(shell: shell),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/home',
              builder: (context, state) => const HomeScreen(),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/games',
              builder: (context, state) => const GamesScreen(),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/chat',
              builder: (context, state) {
                final spaceAsync = ref.read(spaceStreamProvider);
                final deviceId = ref.read(deviceIdProvider).value ?? '';
                final deviceName = ref.read(deviceNameProvider).value ?? 'Me';
                final space = spaceAsync.value;
                return ChatScreen(
                  spaceId: space?.id ?? '',
                  memberIds: space?.memberDeviceIds ?? [],
                  deviceId: deviceId,
                  deviceName: deviceName,
                );
              },
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/settings',
              builder: (context, state) => const SettingsScreen(),
            ),
          ]),
        ],
      ),
    ],
    errorBuilder: (context, state) => const WelcomeScreen(),
  );
});

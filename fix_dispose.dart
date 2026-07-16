import 'dart:io';

void main() {
  final files = [
    'lib/features/games/presentation/screens/arcade_screen.dart',
    'lib/features/games/presentation/screens/doodle_screen.dart',
    'lib/features/games/presentation/screens/flash_screen.dart',
    'lib/features/games/presentation/screens/ludo_screen.dart',
    'lib/features/games/presentation/screens/snakes_ladders_screen.dart',
    'lib/features/games/presentation/screens/word_hunt_screen.dart',
    'lib/features/games/presentation/screens/wyr_game_screen.dart',
  ];

  for (final path in files) {
    final file = File(path);
    if (!file.existsSync()) continue;
    String content = file.readAsStringSync();

    // Insert late final PresenceRepository _presenceRepo; after the state class opening or before initState
    if (!content.contains('late final PresenceRepository _presenceRepo;')) {
      content = content.replaceFirst('void initState() {', 'late final PresenceRepository _presenceRepo;\n\n  @override\n  void initState() {');
    }

    // Insert initialization in initState
    content = content.replaceFirst(
      'ref.read(presenceRepositoryProvider).setPresent',
      '_presenceRepo = ref.read(presenceRepositoryProvider);\n      _presenceRepo.setPresent'
    );
    // There might be another ref.read in initState, if there was already one replaced, it might not work.
    // So let's use regex.
    content = content.replaceAll('ref.read(presenceRepositoryProvider).setPresent', '_presenceRepo.setPresent');
    content = content.replaceAll('ref.read(presenceRepositoryProvider).setAbsent', '_presenceRepo.setAbsent');

    file.writeAsStringSync(content);
    print('Updated $path');
  }
}

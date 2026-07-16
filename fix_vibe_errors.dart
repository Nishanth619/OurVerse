import 'dart:io';

void main() {
  final file = File('lib/features/vibe/presentation/screens/vibe_screen.dart');
  String content = file.readAsStringSync();
  bool changed = false;

  final regex = RegExp(r"setState\(\(\) => _loadError = '[^']*\$(e|err)'\);");
  if (regex.hasMatch(content)) {
    content = content.replaceAllMapped(regex, (match) {
      final errVar = match.group(1);
      return "setState(() => _loadError = AppUtils.getFriendlyErrorMessage($errVar));";
    });
    changed = true;
  }

  // Also replace basic assignment
  final regex2 = RegExp(r"_loadError = '[^']*\$e';");
  if (regex2.hasMatch(content)) {
    content = content.replaceAllMapped(regex2, (match) {
      return "_loadError = AppUtils.getFriendlyErrorMessage(e);";
    });
    changed = true;
  }

  if (changed) {
    if (!content.contains('app_utils.dart')) {
      content = "import 'package:closer/core/utils/app_utils.dart';\n" + content;
    }
    file.writeAsStringSync(content);
    print('Updated vibe_screen.dart');
  }
}

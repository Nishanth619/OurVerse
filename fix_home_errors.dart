import 'dart:io';

void main() {
  final file = File('lib/features/home/presentation/screens/home_screen.dart');
  String content = file.readAsStringSync();
  bool changed = false;

  if (content.contains("'Error loading space: \$e'")) {
    content = content.replaceAll(
      "'Error loading space: \$e'",
      "AppUtils.getFriendlyErrorMessage(e)"
    );
    changed = true;
  }
  
  if (content.contains("'Error: \$e'")) {
    content = content.replaceAll(
      "'Error: \$e'",
      "AppUtils.getFriendlyErrorMessage(e)"
    );
    changed = true;
  }

  if (changed) {
    if (!content.contains('app_utils.dart')) {
      content = "import 'package:closer/core/utils/app_utils.dart';\n" + content;
    }
    file.writeAsStringSync(content);
    print('Updated home_screen.dart');
  }
}

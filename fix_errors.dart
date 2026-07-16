import 'dart:io';

void main() {
  final dir = Directory('lib');
  final files = dir.listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'));

  for (final file in files) {
    String content = file.readAsStringSync();
    bool changed = false;

    if (content.contains("Text('Error: \$e')") || content.contains('Text("Error: \$e")')) {
      content = content.replaceAll("Text('Error: \$e')", "Text(AppUtils.getFriendlyErrorMessage(e), textAlign: TextAlign.center,)");
      content = content.replaceAll('Text("Error: \$e")', "Text(AppUtils.getFriendlyErrorMessage(e), textAlign: TextAlign.center,)");
      changed = true;
    }

    if (changed) {
      // add import if missing
      if (!content.contains('app_utils.dart')) {
        // Calculate relative path to lib/core/utils/app_utils.dart
        // This is tricky, just use absolute package import
        content = "import 'package:closer/core/utils/app_utils.dart';\n" + content;
      }
      file.writeAsStringSync(content);
      print('Updated \${file.path}');
    }
  }
}

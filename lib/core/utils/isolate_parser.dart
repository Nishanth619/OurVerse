import 'dart:isolate';

/// Utility class to offload heavy JSON/Map parsing to a background isolate.
/// This prevents frame drops on the main UI thread, ensuring a buttery smooth
/// 90/120fps experience even when parsing large collections from Firestore.
class IsolateParser {
  /// Parses a list of Maps into a list of models on a background isolate.
  static Future<List<T>> parseList<T>(
    List<Map<String, dynamic>> rawData,
    T Function(Map<String, dynamic>) builder,
  ) async {
    return await Isolate.run(() {
      // Runs in a background thread
      return rawData.map((data) => builder(data)).toList();
    });
  }
}

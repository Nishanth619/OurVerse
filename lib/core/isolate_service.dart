import 'package:flutter/foundation.dart';

import '../features/games/data/uno_engine.dart';
import '../features/games/data/bingo_model.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Top-level callback functions
//
// compute() requires functions that are NOT closures — they must be top-level
// or static class methods so Dart can send them across isolate boundaries.
// ─────────────────────────────────────────────────────────────────────────────

List<String> _unoGenerateDeck(void _) => UnoEngine.generateDeck();

List<String> _unoSortHand(List<String> hand) => UnoEngine.sortHand(hand);

int _bingoCountLines(List<dynamic> args) => countCompletedLines(
      List<int>.from(args[0] as List),
      List<int>.from(args[1] as List),
    );

// ─── IsolateService ───────────────────────────────────────────────────────────

/// Central hub for CPU-heavy operations that run on background isolates via
/// Flutter's [compute()] helper.
///
/// Each call spawns a fresh Dart isolate, executes the function in parallel
/// with the UI thread, and returns the result — ensuring the UI stays at a
/// steady 60 fps even during heavy computations.
///
/// Usage:
/// ```dart
/// // Instead of (blocks UI thread):
/// final deck = UnoEngine.generateDeck();
///
/// // Use (background isolate):
/// final deck = await IsolateService.generateUnoDeck();
/// ```
class IsolateService {
  const IsolateService._(); // not instantiable

  // ── UNO ────────────────────────────────────────────────────────────────────

  /// Shuffles and returns a full 108-card UNO deck on a **background isolate**.
  static Future<List<String>> generateUnoDeck() =>
      compute(_unoGenerateDeck, null);

  /// Sorts a UNO hand (by color then value) on a **background isolate**.
  static Future<List<String>> sortUnoHand(List<String> hand) =>
      compute(_unoSortHand, hand);

  // ── Bingo ──────────────────────────────────────────────────────────────────

  /// Counts completed Bingo lines for a board on a **background isolate**.
  static Future<int> countBingoLines(List<int> board, List<int> called) =>
      compute(_bingoCountLines, [board, called]);

  // ── Parallel helpers ───────────────────────────────────────────────────────

  /// Counts Bingo lines for BOTH players simultaneously using two isolates
  /// running in parallel. Returns [p1Lines, p2Lines].
  static Future<List<int>> countBingoLinesForBoth(
    List<int> p1Board,
    List<int> p2Board,
    List<int> called,
  ) async {
    final results = await Future.wait([
      compute(_bingoCountLines, [p1Board, called]),
      compute(_bingoCountLines, [p2Board, called]),
    ]);
    return results;
  }
}

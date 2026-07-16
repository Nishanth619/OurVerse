import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'word_hunt_model.dart';

// ── Top-level compute callback ─────────────────────────────────────────────────
// Must be top-level (not a closure) so Dart can send it to a fresh isolate.
List<String> _generateGridIsolate(void _) =>
    WordHuntRepository._generateGridStatic();

// ── WordHuntRepository ────────────────────────────────────────────────────────

class WordHuntRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static const int gridSize = 8;

  // Common easy 3–6 letter words to seed the grid
  static const List<String> _seedWords = [
    'LOVE', 'CARE', 'KISS', 'HUG', 'BOND', 'HEART',
    'ROSE', 'DATE', 'GLOW', 'STAR', 'SOFT', 'WARM',
    'JOY', 'FUN', 'GIFT', 'SOUL', 'HOPE', 'BLISS',
    'CUTE', 'DEAR', 'SWEET', 'FIRE', 'SHINE', 'DANCE',
    'SONG', 'DREAM', 'SMILE', 'BRIGHT', 'PURE', 'MAGIC',
  ];

  // Vowel-heavy weighted letter pool for fill cells
  static const String _fillPool =
      'AAABCDEEEEFGHIIIIJKLMNOOOOPQRSTUUUVWXYZ'
      'AAEEIIOOUU'; // extra vowels for easy words

  Stream<WordHuntModel?> watchCurrentGame(String spaceId) {
    return _firestore
        .collection('spaces')
        .doc(spaceId)
        .collection('games')
        .doc('word_hunt_current')
        .snapshots()
        .map((doc) => doc.exists ? WordHuntModel.fromFirestore(doc) : null);
  }

  // ── Grid generation ──────────────────────────────────────────────────────────

  /// Generates an 8×8 grid asynchronously on a **background isolate**.
  ///
  /// The grid placement algorithm runs nested loops across all words, directions
  /// and random positions — offloading it keeps the UI thread at 60fps while
  /// the new game is being prepared.
  Future<List<String>> generateGrid() =>
      compute(_generateGridIsolate, null);

  /// Static variant of grid generation — called by the isolate top-level
  /// function [_generateGridIsolate]. Must be static so it is accessible
  /// without a class instance inside the spawned isolate.
  static List<String> _generateGridStatic() {
    final rand = Random();
    final grid = List<String>.filled(gridSize * gridSize, '');

    // Shuffle seed words and try to place as many as possible
    final words = List<String>.from(_seedWords)..shuffle(rand);

    for (final word in words) {
      _tryPlaceWord(grid, word, rand);
    }

    // Fill remaining empty cells with vowel-heavy random letters
    for (int i = 0; i < grid.length; i++) {
      if (grid[i].isEmpty) {
        grid[i] = _fillPool[rand.nextInt(_fillPool.length)];
      }
    }

    return grid;
  }

  static bool _tryPlaceWord(List<String> grid, String word, Random rand) {
    // Directions: right, down, diagonal DR, diagonal DL
    final directions = [
      [0, 1], [1, 0], [1, 1], [1, -1],
    ];

    final dirs = List.from(directions)..shuffle(rand);

    for (final dir in dirs) {
      final dr = dir[0] as int;
      final dc = dir[1] as int;

      // Try up to 20 random starting positions
      for (int attempt = 0; attempt < 20; attempt++) {
        final startRow = rand.nextInt(gridSize);
        final startCol = rand.nextInt(gridSize);

        if (_canPlaceWord(grid, word, startRow, startCol, dr, dc)) {
          _placeWord(grid, word, startRow, startCol, dr, dc);
          return true;
        }
      }
    }
    return false;
  }

  static bool _canPlaceWord(
      List<String> grid, String word, int row, int col, int dr, int dc) {
    for (int i = 0; i < word.length; i++) {
      final r = row + i * dr;
      final c = col + i * dc;
      if (r < 0 || r >= gridSize || c < 0 || c >= gridSize) return false;
      final existing = grid[r * gridSize + c];
      if (existing.isNotEmpty && existing != word[i]) return false;
    }
    return true;
  }

  static void _placeWord(
      List<String> grid, String word, int row, int col, int dr, int dc) {
    for (int i = 0; i < word.length; i++) {
      grid[(row + i * dr) * gridSize + (col + i * dc)] = word[i];
    }
  }

  // ── Firestore operations ─────────────────────────────────────────────────────

  Future<void> startNewGame(String spaceId) async {
    // ── Grid generation on a background isolate ───────────────────────────────
    // The word-placement algorithm loops over 30 words × 4 directions ×
    // 20 attempts = 2 400 iterations. Running it on an isolate ensures zero
    // UI-thread blocking while the new game grid is computed.
    final grid = await generateGrid();

    final newGame = WordHuntModel(
      id: 'word_hunt_current',
      grid: grid,
      startedAt: {},
      finishedAt: {},
      wordsFound: {},
      score: {},
      createdAt: Timestamp.now(),
    );

    await _firestore
        .collection('spaces')
        .doc(spaceId)
        .collection('games')
        .doc('word_hunt_current')
        .set(newGame.toMap());
  }

  Future<void> startGameForUser(String spaceId, String deviceId) async {
    await _firestore
        .collection('spaces')
        .doc(spaceId)
        .collection('games')
        .doc('word_hunt_current')
        .set({
          'startedAt': {
            deviceId: FieldValue.serverTimestamp(),
          }
        }, SetOptions(merge: true));
  }

  Future<void> submitRound(
      String spaceId, String deviceId, List<String> words, int score) async {
    await _firestore
        .collection('spaces')
        .doc(spaceId)
        .collection('games')
        .doc('word_hunt_current')
        .set({
          'finishedAt': {
            deviceId: FieldValue.serverTimestamp(),
          },
          'wordsFound': {
            deviceId: words,
          },
          'score': {
            deviceId: score,
          }
        }, SetOptions(merge: true));
  }
}

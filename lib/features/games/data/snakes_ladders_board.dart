import 'dart:math';

/// Snakes and Ladders board geometry helpers.

/// Converts a 1-100 board position to a [row, col] on a 10x10 grid.
/// row=0 is TOP (cells 91-100), row=9 is BOTTOM (cells 1-10).
/// Canvas Y = row * cellSize,  Canvas X = col * cellSize.
List<int> positionToCell(int pos) {
  if (pos < 1 || pos > 100) return [-1, -1];
  final p = pos - 1;
  final r = 9 - (p ~/ 10);
  int c = p % 10;
  if ((p ~/ 10) % 2 != 0) c = 9 - c;
  return [r, c];
}

/// Returns the cell number at visual [col] (0=left…9=right)
/// and [rowFromBottom] (0=bottom row 1–10, 9=top row 91–100).
int _cellAt(int col, int rowFromBottom) {
  return rowFromBottom % 2 == 0
      ? rowFromBottom * 10 + col + 1
      : rowFromBottom * 10 + (9 - col) + 1;
}

/// Returns all cell numbers inside a rectangular visual zone.
List<int> _cellsInZone(
    int colMin, int colMax, int rowMin, int rowMax) {
  final cells = <int>[];
  for (int r = rowMin; r <= rowMax; r++) {
    for (int c = colMin; c <= colMax; c++) {
      cells.add(_cellAt(c, r));
    }
  }
  return cells;
}

/// Picks a random unoccupied cell from [candidates]. Returns null if all taken.
int? _pickFrom(List<int> candidates, Set<int> occupied, Random rng) {
  final free = candidates.where((c) => !occupied.contains(c)).toList();
  if (free.isEmpty) return null;
  free.shuffle(rng);
  return free.first;
}

List<int> _range(int lo, int hi) =>
    lo > hi ? [] : List.generate(hi - lo + 1, (i) => lo + i);

/// Generates a visually balanced, fully random Snakes & Ladders board.
Map<String, Map<int, int>> generateRandomBoard() {
  final rng = Random();
  final Map<int, int> snakes = {};
  final Map<int, int> ladders = {};
  final Set<int> occupied = {1, 100};

  // 1. We want fewer elements so it doesn't look like a messy hairball.
  // Let's do 6 snakes and 6 ladders.
  final numElements = 6;

  // We will divide the board into 6 zones (3 rows × 2 cols) to ensure spread.
  // Zones: Bottom (rows 0-2), Middle (rows 3-6), Top (rows 7-9)
  final zones = [
    [0, 4, 1, 3], // Bottom-Left
    [5, 9, 1, 3], // Bottom-Right
    [0, 4, 4, 6], // Mid-Left
    [5, 9, 4, 6], // Mid-Right
    [0, 4, 7, 9], // Top-Left
    [5, 9, 7, 9], // Top-Right
  ];

  final snakeZones = List.of(zones)..shuffle(rng);
  final ladderZones = List.of(zones)..shuffle(rng);

  for (int i = 0; i < numElements; i++) {
    // ---- LADDERS ----
    final lZ = ladderZones[i];
    final lCandidates = _cellsInZone(lZ[0], lZ[1], lZ[2], lZ[3])
        .where((c) => c >= 2 && c <= 85)
        .toList();
    final lStart = _pickFrom(lCandidates, occupied, rng);
    
    if (lStart != null) {
      occupied.add(lStart);
      // Limit ladder length to prevent crossing the whole board (span 11 to 30)
      final lEndMin = lStart + 11;
      final lEndMax = min(lStart + 35, 99);
      final lEnd = _pickFrom(_range(lEndMin, lEndMax), occupied, rng);
      if (lEnd != null) {
        occupied.add(lEnd);
        ladders[lStart] = lEnd;
      } else {
        occupied.remove(lStart);
      }
    }

    // ---- SNAKES ----
    final sZ = snakeZones[i];
    final sCandidates = _cellsInZone(sZ[0], sZ[1], sZ[2], sZ[3])
        .where((c) => c >= 15 && c <= 99)
        .toList();
    final sStart = _pickFrom(sCandidates, occupied, rng);

    if (sStart != null) {
      occupied.add(sStart);
      // Limit snake length to prevent crossing the whole board (span 11 to 35)
      final sEndMax = sStart - 11;
      final sEndMin = max(sStart - 35, 2);
      final sEnd = _pickFrom(_range(sEndMin, sEndMax), occupied, rng);
      if (sEnd != null) {
        occupied.add(sEnd);
        snakes[sStart] = sEnd;
      } else {
        occupied.remove(sStart);
      }
    }
  }

  // Optionally add 1 "Long" snake and 1 "Long" ladder for excitement, 
  // picking carefully to avoid existing ones.
  final longLadderStart = _pickFrom(_range(2, 20), occupied, rng);
  if (longLadderStart != null) {
    occupied.add(longLadderStart);
    final longLadderEnd = _pickFrom(_range(70, 95), occupied, rng);
    if (longLadderEnd != null) {
      occupied.add(longLadderEnd);
      ladders[longLadderStart] = longLadderEnd;
    } else {
      occupied.remove(longLadderStart);
    }
  }

  final longSnakeStart = _pickFrom(_range(80, 99), occupied, rng);
  if (longSnakeStart != null) {
    occupied.add(longSnakeStart);
    final longSnakeEnd = _pickFrom(_range(5, 30), occupied, rng);
    if (longSnakeEnd != null) {
      occupied.add(longSnakeEnd);
      snakes[longSnakeStart] = longSnakeEnd;
    } else {
      occupied.remove(longSnakeStart);
    }
  }

  return {'snakes': snakes, 'ladders': ladders};
}

/// Ludo board constants: path coordinates, home columns, safe squares.
/// The board is a standard 15×15 grid (rows & cols are 0-indexed).

// ─── 52-step main path (row, col) ─────────────────────────────────────────
// Index 0  = Red's entry square
// Index 26 = Blue's entry square (opposite side)
const List<List<int>> kMainPath = [
  [6,1],[6,2],[6,3],[6,4],[6,5],           // 0-4  : Red entry row (right)
  [5,6],[4,6],[3,6],[2,6],[1,6],[0,6],     // 5-10 : up col 6
  [0,7],                                    // 11
  [0,8],[1,8],[2,8],[3,8],[4,8],[5,8],     // 12-17: down col 8 (top side)
  [6,9],[6,10],[6,11],[6,12],[6,13],[6,14],// 18-23: right on row 6
  [7,14],                                   // 24
  [8,14],[8,13],[8,12],[8,11],[8,10],[8,9],// 25-30: left on row 8 (Blue entry at 26)
  [9,8],[10,8],[11,8],[12,8],[13,8],[14,8],// 31-36: down col 8 (right side)
  [14,7],                                   // 37
  [14,6],[13,6],[12,6],[11,6],[10,6],[9,6],// 38-43: up col 6 (bottom side)
  [8,5],[8,4],[8,3],[8,2],[8,1],[8,0],     // 44-49: left on row 8
  [7,0],                                    // 50
  [6,0],                                    // 51
];

// ─── Home columns ──────────────────────────────────────────────────────────
// pos 52 = first home step, pos 57 = last home step (enters center next)
const List<List<int>> kRedHomeCol  = [[7,1],[7,2],[7,3],[7,4],[7,5],[7,6]];
const List<List<int>> kBlueHomeCol = [[7,13],[7,12],[7,11],[7,10],[7,9],[7,8]];

// The very center of the board (finished)
const List<int> kCenter = [7, 7];
const int kFinished = 58;

// ─── Safe squares (cannot capture here) ──────────────────────────────────
// Includes both player starts and the 4 star/safe squares
const Set<String> kSafeCells = {
  '6,1',  // Red start
  '8,13', // Blue start
  '2,6',  // Star (index 8)
  '6,12', // Star (index 21)
  '12,8', // Star (index 33)
  '8,2',  // Star (index 47)
};

bool isSafeCell(int r, int c) => kSafeCells.contains('$r,$c');

// ─── Position converters ───────────────────────────────────────────────────
// pos: -1 = base, 0-51 = main path, 52-57 = home column, 58 = finished

List<int> redPosToCell(int pos) {
  if (pos < 0) return [-1, -1];
  if (pos <= 51) return kMainPath[pos];
  if (pos <= 57) return kRedHomeCol[pos - 52];
  return kCenter;
}

List<int> bluePosToCell(int pos) {
  if (pos < 0) return [-1, -1];
  if (pos <= 51) return kMainPath[(pos + 26) % 52];
  if (pos <= 57) return kBlueHomeCol[pos - 52];
  return kCenter;
}

// Visual base slot positions within each corner home zone
// Expressed as (row, col) in board grid units (can be fractional)
const List<List<double>> kRedBaseSlots = [
  [2.15, 2.15], [2.15, 3.85], [3.85, 2.15], [3.85, 3.85],
];

const List<List<double>> kBlueBaseSlots = [
  [11.15, 11.15], [11.15, 12.85], [12.85, 11.15], [12.85, 12.85],
];

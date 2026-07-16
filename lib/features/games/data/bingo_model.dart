import 'package:cloud_firestore/cloud_firestore.dart';

// ─── Model ────────────────────────────────────────────────────────────────────

class BingoSession {
  final String id;
  final String status; // 'waiting' | 'playing' | 'p1_won' | 'p2_won'
  final String player1Id;
  final String player2Id;
  final String turn; // deviceId of who picks next
  final List<int> player1Board; // 25 numbers (1-25), shuffled
  final List<int> player2Board; // 25 numbers (1-25), shuffled
  final List<int> calledNumbers; // all numbers picked so far
  final int player1Lines; // completed line count
  final int player2Lines;
  final Timestamp createdAt;

  const BingoSession({
    required this.id,
    required this.status,
    required this.player1Id,
    required this.player2Id,
    required this.turn,
    required this.player1Board,
    required this.player2Board,
    required this.calledNumbers,
    required this.player1Lines,
    required this.player2Lines,
    required this.createdAt,
  });

  factory BingoSession.fromFirestore(DocumentSnapshot snap) {
    final d = snap.data() as Map<String, dynamic>;
    return BingoSession(
      id: snap.id,
      status: d['status'] ?? 'waiting',
      player1Id: d['player1Id'] ?? '',
      player2Id: d['player2Id'] ?? '',
      turn: d['turn'] ?? '',
      player1Board: List<int>.from(d['player1Board'] ?? []),
      player2Board: List<int>.from(d['player2Board'] ?? []),
      calledNumbers: List<int>.from(d['calledNumbers'] ?? []),
      player1Lines: d['player1Lines'] ?? 0,
      player2Lines: d['player2Lines'] ?? 0,
      createdAt: d['createdAt'] ?? Timestamp.now(),
    );
  }

  Map<String, dynamic> toMap() => {
        'status': status,
        'player1Id': player1Id,
        'player2Id': player2Id,
        'turn': turn,
        'player1Board': player1Board,
        'player2Board': player2Board,
        'calledNumbers': calledNumbers,
        'player1Lines': player1Lines,
        'player2Lines': player2Lines,
        'createdAt': createdAt,
      };
}

// ─── Win-check helper ─────────────────────────────────────────────────────────

/// Returns how many completed lines (rows + cols + 2 diags) a board has.
int countCompletedLines(List<int> board, List<int> called) {
  final calledSet = called.toSet();
  int lines = 0;

  // Rows
  for (int r = 0; r < 5; r++) {
    if (List.generate(5, (c) => board[r * 5 + c]).every(calledSet.contains)) {
      lines++;
    }
  }
  // Cols
  for (int c = 0; c < 5; c++) {
    if (List.generate(5, (r) => board[r * 5 + c]).every(calledSet.contains)) {
      lines++;
    }
  }
  // Main diagonal
  if (List.generate(5, (i) => board[i * 5 + i]).every(calledSet.contains)) {
    lines++;
  }
  // Anti diagonal
  if (List.generate(5, (i) => board[i * 5 + (4 - i)]).every(calledSet.contains)) {
    lines++;
  }

  return lines;
}

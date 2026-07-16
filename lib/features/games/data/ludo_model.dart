import 'package:cloud_firestore/cloud_firestore.dart';

/// Immutable snapshot of a Ludo game stored in Firestore.
///
/// Position encoding per token (see ludo_board.dart):
///   -1      = in base
///   0–51    = main path (color-relative, converted via red/bluePosToCell)
///   52–57   = home column
///   58      = finished (kFinished)
class LudoSession {
  final String id;
  final String redPlayerId;
  final String bluePlayerId;
  final String turn; // deviceId whose turn it is
  final int diceValue; // 0 = not rolled yet this turn
  final bool hasRolled; // has the current player rolled this turn?
  final int sixStreak; // consecutive 6s rolled by current player this turn-chain
  final List<int> redPositions; // 4 values
  final List<int> bluePositions; // 4 values
  final String status; // 'waiting' | 'playing' | 'red_won' | 'blue_won'
  final Timestamp createdAt;

  const LudoSession({
    required this.id,
    required this.redPlayerId,
    required this.bluePlayerId,
    required this.turn,
    required this.diceValue,
    required this.hasRolled,
    required this.sixStreak,
    required this.redPositions,
    required this.bluePositions,
    required this.status,
    required this.createdAt,
  });

  factory LudoSession.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>? ?? {};
    return LudoSession(
      id: doc.id,
      redPlayerId: d['redPlayerId'] as String? ?? '',
      bluePlayerId: d['bluePlayerId'] as String? ?? '',
      turn: d['turn'] as String? ?? '',
      diceValue: d['diceValue'] as int? ?? 0,
      hasRolled: d['hasRolled'] as bool? ?? false,
      sixStreak: d['sixStreak'] as int? ?? 0,
      redPositions: List<int>.from(d['redPositions'] ?? const [-1, -1, -1, -1]),
      bluePositions: List<int>.from(d['bluePositions'] ?? const [-1, -1, -1, -1]),
      status: d['status'] as String? ?? 'waiting',
      createdAt: d['createdAt'] as Timestamp? ?? Timestamp.now(),
    );
  }

  Map<String, dynamic> toMap() => {
        'redPlayerId': redPlayerId,
        'bluePlayerId': bluePlayerId,
        'turn': turn,
        'diceValue': diceValue,
        'hasRolled': hasRolled,
        'sixStreak': sixStreak,
        'redPositions': redPositions,
        'bluePositions': bluePositions,
        'status': status,
        'createdAt': createdAt,
      };

  /// Plain, unambiguous copyWith — every field maps to exactly one named
  /// parameter, no hidden side-effects between parameters.
  LudoSession copyWith({
    String? turn,
    int? diceValue,
    bool? hasRolled,
    int? sixStreak,
    List<int>? redPositions,
    List<int>? bluePositions,
    String? status,
  }) =>
      LudoSession(
        id: id,
        redPlayerId: redPlayerId,
        bluePlayerId: bluePlayerId,
        turn: turn ?? this.turn,
        diceValue: diceValue ?? this.diceValue,
        hasRolled: hasRolled ?? this.hasRolled,
        sixStreak: sixStreak ?? this.sixStreak,
        redPositions: redPositions ?? this.redPositions,
        bluePositions: bluePositions ?? this.bluePositions,
        status: status ?? this.status,
        createdAt: createdAt,
      );

  bool get isRedWon => status == 'red_won';
  bool get isBlueWon => status == 'blue_won';

  /// Convenience: positions list for a given color.
  List<int> positionsFor(String color) =>
      color == 'red' ? redPositions : bluePositions;
}

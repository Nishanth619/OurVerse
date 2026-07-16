import 'package:cloud_firestore/cloud_firestore.dart';

// ─── Card Encoding ─────────────────────────────────────────────────────────────
// Colors: R=Red, G=Green, B=Blue, Y=Yellow, W=Wild
// Values: 0-9, S=Skip, R=Reverse, D2=Draw Two
// Wild cards: 'W' (Wild), 'WD4' (Wild Draw Four)
// Examples: 'R5', 'BS', 'GR', 'YD2', 'W', 'WD4'

class UnoSession {
  final String id;
  final String player1Id;
  final String player2Id;
  final List<String> player1Hand;
  final List<String> player2Hand;
  final List<String> drawPile;
  final List<String> discardPile;
  final String currentTurn;
  final String currentColor; // 'R', 'G', 'B', 'Y'
  final String status; // 'waiting' | 'playing' | 'p1_won' | 'p2_won'
  final String? unoPlayerId; // non-null when a player just hit 1 card
  final Timestamp createdAt;

  const UnoSession({
    required this.id,
    required this.player1Id,
    required this.player2Id,
    required this.player1Hand,
    required this.player2Hand,
    required this.drawPile,
    required this.discardPile,
    required this.currentTurn,
    required this.currentColor,
    required this.status,
    this.unoPlayerId,
    required this.createdAt,
  });

  // ── Getters ───────────────────────────────────────────────────────────────────

  bool get isPlaying => status == 'playing';
  bool get isFinished => status == 'p1_won' || status == 'p2_won';

  String? get winnerId {
    if (status == 'p1_won') return player1Id;
    if (status == 'p2_won') return player2Id;
    return null;
  }

  List<String> handOf(String playerId) =>
      playerId == player1Id ? player1Hand : player2Hand;

  String opponentOf(String playerId) =>
      playerId == player1Id ? player2Id : player1Id;

  bool isPlayer1(String playerId) => playerId == player1Id;

  // ── Serialization ─────────────────────────────────────────────────────────────

  Map<String, dynamic> toMap() => {
        'player1Id': player1Id,
        'player2Id': player2Id,
        'player1Hand': player1Hand,
        'player2Hand': player2Hand,
        'drawPile': drawPile,
        'discardPile': discardPile,
        'currentTurn': currentTurn,
        'currentColor': currentColor,
        'status': status,
        'unoPlayerId': unoPlayerId,
        'createdAt': createdAt,
      };

  factory UnoSession.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return UnoSession(
      id: doc.id,
      player1Id: d['player1Id'] as String? ?? '',
      player2Id: d['player2Id'] as String? ?? '',
      player1Hand: List<String>.from(d['player1Hand'] as List? ?? []),
      player2Hand: List<String>.from(d['player2Hand'] as List? ?? []),
      drawPile: List<String>.from(d['drawPile'] as List? ?? []),
      discardPile: List<String>.from(d['discardPile'] as List? ?? []),
      currentTurn: d['currentTurn'] as String? ?? '',
      currentColor: d['currentColor'] as String? ?? 'R',
      status: d['status'] as String? ?? 'waiting',
      unoPlayerId: d['unoPlayerId'] as String?,
      createdAt: d['createdAt'] as Timestamp? ?? Timestamp.now(),
    );
  }

  UnoSession copyWith({
    List<String>? player1Hand,
    List<String>? player2Hand,
    List<String>? drawPile,
    List<String>? discardPile,
    String? currentTurn,
    String? currentColor,
    String? status,
    Object? unoPlayerId = _sentinel, // use sentinel to allow explicit null
  }) {
    return UnoSession(
      id: id,
      player1Id: player1Id,
      player2Id: player2Id,
      player1Hand: player1Hand ?? this.player1Hand,
      player2Hand: player2Hand ?? this.player2Hand,
      drawPile: drawPile ?? this.drawPile,
      discardPile: discardPile ?? this.discardPile,
      currentTurn: currentTurn ?? this.currentTurn,
      currentColor: currentColor ?? this.currentColor,
      status: status ?? this.status,
      unoPlayerId: identical(unoPlayerId, _sentinel)
          ? this.unoPlayerId
          : unoPlayerId as String?,
      createdAt: createdAt,
    );
  }

  static const Object _sentinel = Object();

  /// Returns new session with the given player's hand updated
  UnoSession withHand(String playerId, List<String> newHand) {
    if (playerId == player1Id) {
      return copyWith(player1Hand: newHand);
    } else {
      return copyWith(player2Hand: newHand);
    }
  }

  /// Returns new session with opponent's hand updated
  UnoSession withOpponentHand(String playerId, List<String> newHand) {
    final opId = opponentOf(playerId);
    return withHand(opId, newHand);
  }
}

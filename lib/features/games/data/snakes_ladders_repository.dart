import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'snakes_ladders_model.dart';
import 'snakes_ladders_board.dart';

final snakesLaddersRepositoryProvider = Provider((ref) => SnakesLaddersRepository());

final snakesLaddersStreamProvider = StreamProvider.family<SnakesLaddersSession?, String>((ref, spaceId) {
  return ref.watch(snakesLaddersRepositoryProvider).watchGame(spaceId);
});

class SnakesLaddersRepository {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  DocumentReference _doc(String spaceId) => _db
      .collection('spaces')
      .doc(spaceId)
      .collection('games')
      .doc('snakes_ladders_current');

  Stream<SnakesLaddersSession?> watchGame(String spaceId) =>
      _doc(spaceId).snapshots().map((s) => s.exists ? SnakesLaddersSession.fromFirestore(s) : null);

  Future<void> startNewGame(String spaceId, String redId, String blueId, {bool force = false}) async {
    final ref = _doc(spaceId);
    await _db.runTransaction((txn) async {
      final snap = await txn.get(ref);
      if (snap.exists && !force) {
        final data = snap.data() as Map<String, dynamic>?;
        if (data != null && data['status'] == 'playing') return;
      }
      
      final board = generateRandomBoard();
      
      final session = SnakesLaddersSession(
        id: 'snakes_ladders_current',
        redPlayerId: redId,
        bluePlayerId: blueId,
        turn: redId, // Red goes first
        diceValue: 0,
        hasRolled: false,
        redPosition: 0,  // 0 = off-board; token appears after first roll
        bluePosition: 0,
        status: 'playing',
        createdAt: Timestamp.now(),
        snakes: board['snakes'] ?? {},
        ladders: board['ladders'] ?? {},
      );
      txn.set(ref, session.toMap());
    });
  }

  Future<void> saveSession(String spaceId, SnakesLaddersSession session) async {
    await _doc(spaceId).set(session.toMap());
  }

  /// Calculates the new position after a dice roll.
  /// Handles exact-100 logic and automatic snake/ladder teleportation.
  static int calculateNewPosition(int currentPos, int diceRoll, Map<int, int> snakes, Map<int, int> ladders) {
    int newPos = currentPos + diceRoll;
    
    // Must land exactly on 100 to win.
    // If roll exceeds 100, player bounces back.
    if (newPos > 100) {
      final excess = newPos - 100;
      newPos = 100 - excess;
    }
    
    // Check for ladders
    if (ladders.containsKey(newPos)) {
      newPos = ladders[newPos]!;
    }
    // Check for snakes
    else if (snakes.containsKey(newPos)) {
      newPos = snakes[newPos]!;
    }
    
    return newPos;
  }
}

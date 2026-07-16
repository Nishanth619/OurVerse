import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'ludo_model.dart';
import 'ludo_board.dart';

final ludoRepositoryProvider = Provider<LudoRepository>((_) => LudoRepository());

final ludoStreamProvider =
    StreamProvider.family<LudoSession?, String>((ref, spaceId) {
  return ref.watch(ludoRepositoryProvider).watchGame(spaceId);
});

class LudoRepository {
  final _db = FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> _doc(String spaceId) => _db
      .collection('spaces')
      .doc(spaceId)
      .collection('games')
      .doc('ludo_current');

  Stream<LudoSession?> watchGame(String spaceId) =>
      _doc(spaceId).snapshots().map((s) => s.exists ? LudoSession.fromFirestore(s) : null);

  /// Starts a new game. Uses a transaction so two simultaneous "Start" taps
  /// from both players can't race each other into inconsistent state.
  Future<void> startNewGame(String spaceId, String redId, String blueId, {bool force = false}) async {
    final ref = _doc(spaceId);
    await _db.runTransaction((txn) async {
      final snap = await txn.get(ref);
      // If a game is already in progress, don't clobber it unless forced.
      if (snap.exists && !force) {
        final data = snap.data();
        if (data != null && data['status'] == 'playing') return;
      }
      final session = LudoSession(
        id: 'ludo_current',
        redPlayerId: redId,
        bluePlayerId: blueId,
        turn: redId, // Red always goes first
        diceValue: 0,
        hasRolled: false,
        sixStreak: 0,
        redPositions: const [-1, -1, -1, -1],
        bluePositions: const [-1, -1, -1, -1],
        status: 'playing',
        createdAt: Timestamp.now(),
      );
      txn.set(ref, session.toMap());
    });
  }

  /// Save a full updated session to Firestore (used after computing move locally).
  Future<void> saveSession(String spaceId, LudoSession session) async {
    await _doc(spaceId).set({
      'turn': session.turn,
      'diceValue': session.diceValue,
      'hasRolled': session.hasRolled,
      'sixStreak': session.sixStreak,
      'redPositions': session.redPositions,
      'bluePositions': session.bluePositions,
      'status': session.status,
    }, SetOptions(merge: true));
  }
}

// ─── Pure Game Logic (no Firebase, fully unit-testable) ───────────────────

class LudoGameLogic {
  /// Standard Ludo rule: 3 sixes in a row forfeits the turn (no move applied
  /// on the 3rd six, turn passes immediately). Caps the otherwise-infinite
  /// bonus-turn loop.
  static const int maxSixStreak = 3;

  /// Whether a token at [pos] can move with the given [dice].
  static bool canMove(int pos, int dice, bool isBase) {
    if (pos == kFinished) return false;
    if (pos == -1) return dice == 6; // must roll a 6 to leave base
    final next = pos + dice;
    if (next > 57) return false; // overshoots finish — invalid
    return true;
  }

  /// Returns the new position after moving [pos] by [dice].
  /// Returns [pos] unchanged if the move is invalid.
  static int applyMove(int pos, int dice) {
    if (pos == -1) return dice == 6 ? 0 : pos;
    final next = pos + dice;
    if (next > 57) return pos; // overshoot — invalid, no-op
    if (next == 57) return kFinished;
    return next;
  }

  /// Next turn after a move:
  /// - Hit the 3-six cap → forced pass, regardless of capture.
  /// - Rolled a 6 (within cap) or captured a token → same player goes again.
  /// - Otherwise → pass to the other player.
  static String nextTurn(
    LudoSession session,
    String movedBy,
    int dice,
    bool captured,
    int sixStreak,
  ) {
    if (dice == 6 && sixStreak >= maxSixStreak) {
      return movedBy == session.redPlayerId ? session.bluePlayerId : session.redPlayerId;
    }
    if (dice == 6 || captured) return movedBy; // bonus turn
    return movedBy == session.redPlayerId ? session.bluePlayerId : session.redPlayerId;
  }

  /// Check if the token at [cell] captures any opponent token.
  /// Returns the index of the captured token, or -1 if no capture.
  /// Safe cells never allow a capture.
  static int captureCheck({
    required List<int> cell,
    required List<int> opponentPositions,
    required List<int> Function(int) opponentPosToCell,
  }) {
    if (isSafeCell(cell[0], cell[1])) return -1;
    for (int i = 0; i < opponentPositions.length; i++) {
      final oCell = opponentPosToCell(opponentPositions[i]);
      if (oCell[0] == cell[0] && oCell[1] == cell[1]) return i;
    }
    return -1;
  }

  /// Are all 4 tokens of a color finished?
  static bool allFinished(List<int> positions) =>
      positions.every((p) => p == kFinished);

  /// Does any token in [positions] have a valid move with [dice]?
  static bool anyCanMove(List<int> positions, int dice) =>
      positions.any((pos) => canMove(pos, dice, pos == -1));
}

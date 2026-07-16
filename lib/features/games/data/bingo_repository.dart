import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/isolate_service.dart';
import 'bingo_model.dart';

// ─── Providers ────────────────────────────────────────────────────────────────

final bingoRepositoryProvider = Provider((ref) => BingoRepository());

final bingoStreamProvider =
    StreamProvider.family<BingoSession?, String>((ref, spaceId) {
  return ref.watch(bingoRepositoryProvider).watchGame(spaceId);
});

// ─── Repository ───────────────────────────────────────────────────────────────

class BingoRepository {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  DocumentReference _doc(String spaceId) => _db
      .collection('spaces')
      .doc(spaceId)
      .collection('games')
      .doc('bingo_current');

  Stream<BingoSession?> watchGame(String spaceId) =>
      _doc(spaceId).snapshots().map((s) =>
          s.exists ? BingoSession.fromFirestore(s) : null);

  // ── Start new game ─────────────────────────────────────────────────────────
  Future<void> startNewGame(
    String spaceId,
    String player1Id,
    String player2Id, {
    bool force = false,
  }) async {
    final ref = _doc(spaceId);
    await _db.runTransaction((txn) async {
      final snap = await txn.get(ref);
      if (snap.exists && !force) {
        final data = snap.data() as Map<String, dynamic>?;
        if (data != null && data['status'] == 'playing') return;
      }

      final rng = Random();
      // Generate two independent shuffled boards of numbers 1-25
      final nums1 = List.generate(25, (i) => i + 1)..shuffle(rng);
      final nums2 = List.generate(25, (i) => i + 1)..shuffle(rng);

      final session = BingoSession(
        id: 'bingo_current',
        status: 'playing',
        player1Id: player1Id,
        player2Id: player2Id,
        turn: player1Id, // Player 1 picks first
        player1Board: nums1,
        player2Board: nums2,
        calledNumbers: [],
        player1Lines: 0,
        player2Lines: 0,
        createdAt: Timestamp.now(),
      );
      txn.set(ref, session.toMap());
    });
  }

  // ── Call a number ──────────────────────────────────────────────────────────
  Future<void> callNumber(
    String spaceId,
    BingoSession session,
    int number,
    String myDeviceId,
  ) async {
    if (session.turn != myDeviceId) return;
    if (session.calledNumbers.contains(number)) return;
    if (session.status != 'playing') return;

    final newCalled = [...session.calledNumbers, number];

    // ── Line counting on two parallel background isolates ──────────────────────
    // Both boards are scanned simultaneously in separate Dart isolates.
    // Future.wait() launches them in parallel and waits for both to finish.
    final lineResults = await IsolateService.countBingoLinesForBoth(
      session.player1Board,
      session.player2Board,
      newCalled,
    );
    final p1Lines = lineResults[0];
    final p2Lines = lineResults[1];

    // Win condition: 5 completed lines
    String newStatus = 'playing';
    if (p1Lines >= 5 && p2Lines >= 5) {
      newStatus = 'draw';
    } else if (p1Lines >= 5) {
      newStatus = 'p1_won';
    } else if (p2Lines >= 5) {
      newStatus = 'p2_won';
    }

    // Switch turns
    final nextTurn = myDeviceId == session.player1Id
        ? session.player2Id
        : session.player1Id;

    await _doc(spaceId).update({
      'calledNumbers': newCalled,
      'player1Lines': p1Lines,
      'player2Lines': p2Lines,
      'status': newStatus,
      'turn': newStatus == 'playing' ? nextTurn : myDeviceId,
    });
  }
}

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/isolate_service.dart';
import 'uno_model.dart';
import 'uno_engine.dart';

// ─── Providers ────────────────────────────────────────────────────────────────

final unoRepositoryProvider = Provider((ref) => UnoRepository());

final unoSessionProvider =
    StreamProvider.family<UnoSession?, String>((ref, spaceId) {
  return ref.watch(unoRepositoryProvider).watchGame(spaceId);
});

// ─── Repository ───────────────────────────────────────────────────────────────

class UnoRepository {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  static const String _docId = 'uno_current';

  DocumentReference _doc(String spaceId) => _db
      .collection('spaces')
      .doc(spaceId)
      .collection('games')
      .doc(_docId);

  /// Real-time stream of the UNO session (null if no game exists yet).
  Stream<UnoSession?> watchGame(String spaceId) {
    return _doc(spaceId)
        .snapshots()
        .map((s) => s.exists ? UnoSession.fromFirestore(s) : null);
  }

  /// Starts a new game. Uses a transaction so only one player "wins" the race.
  /// [force] can restart even if a game is in progress (used for Rematch).
  Future<void> startNewGame(
    String spaceId,
    String player1Id,
    String player2Id, {
    bool force = false,
  }) async {
    final ref = _doc(spaceId);

    // ── Deck generation on a background isolate ───────────────────────────────
    // Shuffling 108 cards runs in a separate Dart isolate so the UI thread
    // is never blocked. The resulting List<String> is sent back to the main
    // thread before we open the Firestore transaction.
    final deck = await IsolateService.generateUnoDeck();

    await _db.runTransaction((txn) async {
      final snap = await txn.get(ref);

      // Don't restart an active game unless forced
      if (snap.exists && !force) {
        final data = snap.data() as Map<String, dynamic>?;
        if (data != null && data['status'] == 'playing') return;
      }

      // Build session from the isolate-generated deck (Timestamp.now() stays
      // on the main thread where Firestore native code can access the clock).
      final session = UnoEngine.newGameWithDeck(deck, _docId, player1Id, player2Id);
      txn.set(ref, session.toMap());
    });
  }

  /// Persists an updated session state (after a card play or draw).
  Future<void> saveSession(String spaceId, UnoSession session) async {
    await _doc(spaceId).set(session.toMap());
  }
}

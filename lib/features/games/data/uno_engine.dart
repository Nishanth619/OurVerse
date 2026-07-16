import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'uno_model.dart';

// ─── UNO Game Engine ──────────────────────────────────────────────────────────
// Pure Dart game logic. No UI, no Firestore I/O.

class UnoEngine {
  static const List<String> colors = ['R', 'G', 'B', 'Y'];
  static const List<String> numbers = [
    '0', '1', '2', '3', '4', '5', '6', '7', '8', '9'
  ];
  static const List<String> actions = ['S', 'R', 'D2'];

  // ── Deck ─────────────────────────────────────────────────────────────────────

  /// Generates a full shuffled 108-card UNO deck.
  static List<String> generateDeck() {
    final deck = <String>[];

    for (final c in colors) {
      // One zero per color
      deck.add('${c}0');
      // Two each of 1-9
      for (final n in numbers.skip(1)) {
        deck.add('$c$n');
        deck.add('$c$n');
      }
      // Two each of Skip, Reverse, Draw Two
      for (final a in actions) {
        deck.add('$c$a');
        deck.add('$c$a');
      }
    }

    // 4 Wild + 4 Wild Draw Four
    for (var i = 0; i < 4; i++) {
      deck.add('W');
      deck.add('WD4');
    }

    deck.shuffle(Random());
    return deck;
  }

  // ── New Game ──────────────────────────────────────────────────────────────────

  /// Creates a fresh game from a **pre-shuffled** [deck].
  ///
  /// Use this variant when you want to run [generateDeck] on a background
  /// isolate (via [IsolateService.generateUnoDeck]) and then build the session
  /// on the main thread (needed because [Timestamp.now()] is not isolate-safe).
  static UnoSession newGameWithDeck(
    List<String> deck,
    String docId,
    String p1Id,
    String p2Id,
  ) {
    final p1Hand = List<String>.from(deck.sublist(0, 7));
    final p2Hand = List<String>.from(deck.sublist(7, 14));
    var remaining = List<String>.from(deck.sublist(14));

    // First discard card must not be Wild Draw Four (UNO official rule)
    String firstCard = remaining.firstWhere(
      (c) => c != 'WD4' && !c.startsWith('W'),
      orElse: () => remaining.first,
    );
    remaining.remove(firstCard);

    final startColor = firstCard[0];

    return UnoSession(
      id: docId,
      player1Id: p1Id,
      player2Id: p2Id,
      player1Hand: sortHand(p1Hand),
      player2Hand: sortHand(p2Hand),
      drawPile: remaining,
      discardPile: [firstCard],
      currentTurn: p1Id,
      currentColor: startColor,
      status: 'playing',
      unoPlayerId: null,
      createdAt: Timestamp.now(),
    );
  }

  /// Creates a fresh game session with dealt hands and a starting discard card.
  /// Deck generation happens synchronously on the calling thread.
  /// Prefer [newGameWithDeck] with [IsolateService.generateUnoDeck] for
  /// better performance.
  static UnoSession newGame(String docId, String p1Id, String p2Id) {
    final deck = generateDeck();

    final p1Hand = List<String>.from(deck.sublist(0, 7));
    final p2Hand = List<String>.from(deck.sublist(7, 14));
    var remaining = List<String>.from(deck.sublist(14));

    // First discard card must not be Wild Draw Four (UNO official rule)
    // Also avoid starting with a Wild (simplification)
    String firstCard = remaining.firstWhere(
      (c) => c != 'WD4' && !c.startsWith('W'),
      orElse: () => remaining.first,
    );
    remaining.remove(firstCard);

    final startColor = firstCard[0]; // Safe: first card is never Wild here

    return UnoSession(
      id: docId,
      player1Id: p1Id,
      player2Id: p2Id,
      player1Hand: sortHand(p1Hand),
      player2Hand: sortHand(p2Hand),
      drawPile: remaining,
      discardPile: [firstCard],
      currentTurn: p1Id,
      currentColor: startColor,
      status: 'playing',
      unoPlayerId: null,
      createdAt: Timestamp.now(),
    );
  }

  // ── Card Validation ──────────────────────────────────────────────────────────

  /// Returns true if [card] can be legally played on [topCard] with [currentColor].
  static bool canPlay(String card, String topCard, String currentColor) {
    // Wild cards can always be played
    if (card == 'W' || card == 'WD4') return true;

    final cardColor = card[0];
    final cardValue = card.substring(1);

    // Match by color
    if (cardColor == currentColor) return true;

    // Match by value/type (can't match against a Wild's value)
    if (!topCard.startsWith('W')) {
      final topValue = topCard.substring(1);
      if (cardValue == topValue) return true;
    }

    return false;
  }

  /// Returns true if the player has at least one playable card.
  static bool hasPlayableCard(
      List<String> hand, String topCard, String currentColor) {
    return hand.any((c) => canPlay(c, topCard, currentColor));
  }

  // ── Sort Hand ────────────────────────────────────────────────────────────────

  /// Sorts hand: Red → Green → Blue → Yellow → Wilds; within each color by value.
  static List<String> sortHand(List<String> hand) {
    const colorOrder = {'R': 0, 'G': 1, 'B': 2, 'Y': 3};
    return [...hand]..sort((a, b) {
        final ca = a.startsWith('W') ? 4 : (colorOrder[a[0]] ?? 5);
        final cb = b.startsWith('W') ? 4 : (colorOrder[b[0]] ?? 5);
        if (ca != cb) return ca.compareTo(cb);
        // Within same color: numbers before actions
        final va = a.startsWith('W') ? a : a.substring(1);
        final vb = b.startsWith('W') ? b : b.substring(1);
        return va.compareTo(vb);
      });
  }

  // ── Apply Play ───────────────────────────────────────────────────────────────

  /// Applies [card] play by [playerId]. Returns the updated session.
  /// [chosenColor] is required when playing 'W' or 'WD4'.
  static UnoSession applyPlay(
    UnoSession session,
    String playerId,
    String card,
    String? chosenColor,
  ) {
    final isP1 = session.isPlayer1(playerId);
    final opponentId = session.opponentOf(playerId);

    // Remove card from player hand
    var myHand = List<String>.from(session.handOf(playerId));
    myHand.remove(card);
    myHand = sortHand(myHand);

    // Add card to discard pile
    var discardPile = [...session.discardPile, card];

    // Determine new active color
    final nextColor = (card == 'W' || card == 'WD4')
        ? (chosenColor ?? 'R')
        : card[0];

    // Check win condition — empty hand = win
    if (myHand.isEmpty) {
      final winStatus = isP1 ? 'p1_won' : 'p2_won';
      return _rebuild(
        session: session,
        isP1: isP1,
        myHand: myHand,
        opHand: List<String>.from(session.handOf(opponentId)),
        drawPile: List<String>.from(session.drawPile),
        discardPile: discardPile,
        color: nextColor,
        status: winStatus,
        turn: playerId,
        unoPlayerId: null,
      );
    }

    // Apply special card effects
    var drawPile = List<String>.from(session.drawPile);
    var opponentHand = List<String>.from(session.handOf(opponentId));
    String nextTurn = opponentId; // default: pass to opponent

    // Helper: reshuffle discard into draw if needed
    void reshuffleIfNeeded(int needed) {
      if (drawPile.length < needed && discardPile.length > 1) {
        final top = discardPile.last;
        final rest = discardPile.sublist(0, discardPile.length - 1)
          ..shuffle(Random());
        drawPile = [...drawPile, ...rest];
        discardPile = [top];
      }
    }

    final cardValue = card.startsWith('W') ? card : card.substring(1);

    switch (cardValue) {
      case 'S': // Skip — in 2-player: opponent loses turn
      case 'R': // Reverse — in 2-player: acts like Skip
        nextTurn = playerId; // stay on current player
        break;

      case 'D2': // Draw Two
        reshuffleIfNeeded(2);
        if (drawPile.isNotEmpty) {
          final n = drawPile.length < 2 ? drawPile.length : 2;
          opponentHand.addAll(drawPile.take(n));
          drawPile = drawPile.skip(n).toList();
        }
        nextTurn = playerId; // opponent loses turn
        break;

      case 'WD4': // Wild Draw Four
        reshuffleIfNeeded(4);
        if (drawPile.isNotEmpty) {
          final n = drawPile.length < 4 ? drawPile.length : 4;
          opponentHand.addAll(drawPile.take(n));
          drawPile = drawPile.skip(n).toList();
        }
        nextTurn = playerId; // opponent loses turn
        break;
    }

    // Detect UNO (1 card left in hand)
    final unoPlayerId = myHand.length == 1 ? playerId : null;

    return _rebuild(
      session: session,
      isP1: isP1,
      myHand: myHand,
      opHand: sortHand(opponentHand),
      drawPile: drawPile,
      discardPile: discardPile,
      color: nextColor,
      status: 'playing',
      turn: nextTurn,
      unoPlayerId: unoPlayerId,
    );
  }

  // ── Draw Card ────────────────────────────────────────────────────────────────

  /// Draws one card for [playerId] and ends their turn.
  static UnoSession drawCard(UnoSession session, String playerId) {
    var drawPile = List<String>.from(session.drawPile);
    var discardPile = List<String>.from(session.discardPile);

    // Reshuffle discard into draw if draw pile is empty
    if (drawPile.isEmpty && discardPile.length > 1) {
      final top = discardPile.last;
      final rest = discardPile.sublist(0, discardPile.length - 1)
        ..shuffle(Random());
      drawPile = rest;
      discardPile = [top];
    }

    if (drawPile.isEmpty) return session; // No cards to draw

    final drawn = drawPile.removeAt(0);
    var myHand = List<String>.from(session.handOf(playerId))..add(drawn);
    myHand = sortHand(myHand);

    final isP1 = session.isPlayer1(playerId);
    final opponentHand = List<String>.from(session.handOf(session.opponentOf(playerId)));

    return _rebuild(
      session: session,
      isP1: isP1,
      myHand: myHand,
      opHand: opponentHand,
      drawPile: drawPile,
      discardPile: discardPile,
      color: session.currentColor,
      status: 'playing',
      turn: session.opponentOf(playerId), // drawing ends your turn
      unoPlayerId: session.unoPlayerId,
    );
  }

  // ── Internal Builder ──────────────────────────────────────────────────────────

  static UnoSession _rebuild({
    required UnoSession session,
    required bool isP1,
    required List<String> myHand,
    required List<String> opHand,
    required List<String> drawPile,
    required List<String> discardPile,
    required String color,
    required String status,
    required String turn,
    required String? unoPlayerId,
  }) {
    return UnoSession(
      id: session.id,
      player1Id: session.player1Id,
      player2Id: session.player2Id,
      player1Hand: isP1 ? myHand : opHand,
      player2Hand: isP1 ? opHand : myHand,
      drawPile: drawPile,
      discardPile: discardPile,
      currentTurn: turn,
      currentColor: color,
      status: status,
      unoPlayerId: unoPlayerId,
      createdAt: session.createdAt,
    );
  }
}

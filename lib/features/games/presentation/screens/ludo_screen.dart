import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/responsive.dart';
import '../../data/ludo_board.dart';
import '../../data/ludo_model.dart';
import '../../data/ludo_repository.dart';
import '../widgets/ludo_board_painter.dart';
import '../../../../shared/providers/app_providers.dart';
import '../../../vibe/presentation/widgets/sync_status_chip.dart';
import '../../../../core/ads/ad_service.dart';

// ─── Dice animation values ────────────────────────────────────────────────
const List<String> _diceFaces = ['⚀', '⚁', '⚂', '⚃', '⚄', '⚅'];

class LudoScreen extends ConsumerStatefulWidget {
  final String spaceId;
  final List<String> memberIds;
  final String deviceId;

  const LudoScreen({
    super.key,
    required this.spaceId,
    required this.memberIds,
    required this.deviceId,
  });

  @override
  ConsumerState<LudoScreen> createState() => _LudoScreenState();
}

class _LudoScreenState extends ConsumerState<LudoScreen> {
  Timer? _diceTimer;
  int _animDice = 1;
  bool _rolling = false;

  String get _partnerId =>
      widget.memberIds.firstWhere((id) => id != widget.deviceId, orElse: () => '');

  late final PresenceRepository _presenceRepo;

  @override
  void initState() {
    super.initState();
        _presenceRepo = ref.read(presenceRepositoryProvider);
    _presenceRepo.setPresent(widget.spaceId, 'ludo', widget.deviceId);
  }

  @override
  void dispose() {
    _diceTimer?.cancel();
    _presenceRepo.setAbsent(widget.spaceId, 'ludo', widget.deviceId);
    AdService.instance.showInterstitialIfReady();
    super.dispose();
  }

  bool _isMyTurn(LudoSession session) => session.turn == widget.deviceId;

  String _myColor(LudoSession s) => s.redPlayerId == widget.deviceId ? 'red' : 'blue';

  // ── Dice roll ────────────────────────────────────────────────────────────
  void _rollDice(LudoSession session) {
    if (!_isMyTurn(session) || session.hasRolled || _rolling) return;
    HapticFeedback.mediumImpact();

    setState(() => _rolling = true);
    int count = 0;
    _diceTimer = Timer.periodic(const Duration(milliseconds: 80), (t) {
      setState(() => _animDice = Random().nextInt(6) + 1);
      count++;
      if (count >= 10) {
        t.cancel();
        final finalVal = Random().nextInt(6) + 1;
        setState(() {
          _animDice = finalVal;
          _rolling = false;
        });
        _applyRoll(session, finalVal);
      }
    });
  }

  Future<void> _applyRoll(LudoSession session, int dice) async {
    final color = _myColor(session);
    final positions = List<int>.from(session.positionsFor(color));

    // Track consecutive sixes. Reset to 0 on any non-six roll.
    final nextStreak = dice == 6 ? session.sixStreak + 1 : 0;
    final repo = ref.read(ludoRepositoryProvider);

    // Three sixes in a row: forfeit immediately, no move, pass turn.
    if (dice == 6 && nextStreak >= LudoGameLogic.maxSixStreak) {
      final nextTurn =
          widget.deviceId == session.redPlayerId ? session.bluePlayerId : session.redPlayerId;
      await repo.saveSession(
        widget.spaceId,
        session.copyWith(
          diceValue: dice,
          hasRolled: false,
          sixStreak: 0,
          turn: nextTurn,
        ),
      );
      return;
    }

    final canAnyMove = LudoGameLogic.anyCanMove(positions, dice);

    if (!canAnyMove) {
      // No valid move → show the roll briefly, then pass turn (unless it
      // was a 6, in which case the player keeps their turn but must re-roll
      // since nothing could move).
      await Future.delayed(const Duration(milliseconds: 800));
      if (!mounted) return;
      final nextTurn = dice == 6
          ? widget.deviceId
          : (session.redPlayerId == widget.deviceId ? session.bluePlayerId : session.redPlayerId);
      await repo.saveSession(
        widget.spaceId,
        session.copyWith(
          diceValue: dice,
          hasRolled: false,
          sixStreak: nextStreak,
          turn: nextTurn,
        ),
      );
      return;
    }

    // Valid move available — let the player tap a token.
    await repo.saveSession(
      widget.spaceId,
      session.copyWith(diceValue: dice, hasRolled: true, sixStreak: nextStreak),
    );
  }

  // ── Token tap → move ────────────────────────────────────────────────────
  Future<void> _tapToken(LudoSession session, String color, int tokenIdx) async {
    if (!_isMyTurn(session) || !session.hasRolled) return;
    if (_myColor(session) != color) return; // can't tap opponent's tokens

    final dice = session.diceValue;
    final positions = List<int>.from(session.positionsFor(color));

    final oldPos = positions[tokenIdx];
    if (!LudoGameLogic.canMove(oldPos, dice, oldPos == -1)) return;

    final newPos = LudoGameLogic.applyMove(oldPos, dice);
    if (newPos == oldPos) return; // invalid, no-op
    HapticFeedback.selectionClick();

    positions[tokenIdx] = newPos;

    final opponentColor = color == 'red' ? 'blue' : 'red';
    final opponentPositions = List<int>.from(session.positionsFor(opponentColor));
    final opponentPosToCell = color == 'red' ? bluePosToCell : redPosToCell;

    bool captured = false;
    if (newPos < 52) {
      // Captures only happen on the shared main path, never in a home column.
      final myCell = color == 'red' ? redPosToCell(newPos) : bluePosToCell(newPos);
      final capturedIdx = LudoGameLogic.captureCheck(
        cell: myCell,
        opponentPositions: opponentPositions,
        opponentPosToCell: opponentPosToCell,
      );
      if (capturedIdx >= 0) {
        opponentPositions[capturedIdx] = -1; // send back to base
        captured = true;
        HapticFeedback.heavyImpact();
      }
    }

    final isWon = LudoGameLogic.allFinished(positions);
    final nextStatus = isWon ? (color == 'red' ? 'red_won' : 'blue_won') : 'playing';
    final nextTurn = isWon
        ? session.turn
        : LudoGameLogic.nextTurn(session, widget.deviceId, dice, captured, session.sixStreak);

    final updatedSession = session.copyWith(
      diceValue: 0,
      hasRolled: false,
      sixStreak: dice == 6 ? session.sixStreak : 0,
      turn: nextTurn,
      status: nextStatus,
      redPositions: color == 'red' ? positions : opponentPositions,
      bluePositions: color == 'blue' ? positions : opponentPositions,
    );

    await ref.read(ludoRepositoryProvider).saveSession(widget.spaceId, updatedSession);
  }

  @override
  Widget build(BuildContext context) {
    final sessionAsync = ref.watch(ludoStreamProvider(widget.spaceId));
    final partnerPresentAsync = _partnerId.isEmpty
        ? const AsyncData(false)
        : ref.watch(featurePresenceProvider(
            (spaceId: widget.spaceId, featureId: 'ludo', partnerId: _partnerId)));
    final partnerPresent = partnerPresentAsync.valueOrNull ?? false;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const FittedBox(fit: BoxFit.scaleDown, child: Text('Ludo 🎲', style: TextStyle(color: Colors.white))),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          Center(
            child: SyncStatusChip(
              state: partnerPresent ? SyncState.inSync : SyncState.partnerLeft,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Start New Game',
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Restart Game?'),
                  content: const Text('Are you sure you want to abandon the current game and start a new one?'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancel'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Restart', style: TextStyle(color: Colors.red)),
                    ),
                  ],
                ),
              );
              if (confirm == true) {
                await ref.read(ludoRepositoryProvider).startNewGame(widget.spaceId, widget.deviceId, _partnerId, force: true);
              }
            },
          ),
        ],
      ),
      body: SafeArea(
        child: sessionAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(
            child: Text('Error: $e', style: const TextStyle(color: Colors.white70)),
          ),
          data: (session) {
            if (session == null || session.status == 'waiting') {
              return _buildLobby(session);
            }
            if (session.status == 'red_won' || session.status == 'blue_won') {
              return _buildResult(session);
            }
            return _buildGame(session);
          },
        ),
      ),
    );
  }

  // ── Lobby ───────────────────────────────────────────────────────────────
  Widget _buildLobby(LudoSession? session) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('🎲',
                      style: TextStyle(fontSize: context.sp(76)),
                      textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  Text(
                    'Ludo',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: context.sp(28),
                      fontWeight: FontWeight.w900,
                      color: const Color(0xFF991B1B),
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('📜 Rules',
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: context.sp(14))),
                        const SizedBox(height: 8),
                        Text('• Classic 4-token Ludo rules',
                            style: TextStyle(fontSize: context.sp(13))),
                        Text('• Roll a 6 to enter the board',
                            style: TextStyle(fontSize: context.sp(13))),
                        Text('• Capture tokens to send them back',
                            style: TextStyle(fontSize: context.sp(13))),
                        Text('• Race all 4 tokens to the center to win!',
                            style: TextStyle(fontSize: context.sp(13))),
                      ],
                    ),
                  ),
                  const SizedBox(height: 28),
                  ElevatedButton.icon(
                    onPressed: () async {
                      await ref
                          .read(ludoRepositoryProvider)
                          .startNewGame(widget.spaceId, widget.deviceId, _partnerId);
                    },
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      backgroundColor: const Color(0xFF991B1B),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                      elevation: 0,
                    ),
                    icon: const Icon(Icons.play_arrow_rounded, size: 28),
                    label: Text('Start New Game',
                        style: TextStyle(
                            fontSize: context.sp(17),
                            fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ── Result ──────────────────────────────────────────────────────────────
  Widget _buildResult(LudoSession session) {
    final myColor = _myColor(session);
    final iWon = (myColor == 'red' && session.status == 'red_won') ||
        (myColor == 'blue' && session.status == 'blue_won');

    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(iWon ? '🏆' : '😢',
                      style: TextStyle(fontSize: context.sp(76)),
                      textAlign: TextAlign.center),
                  const SizedBox(height: 20),
                  Text(
                    iWon ? 'You Won!' : 'Partner Won!',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: context.sp(32),
                        fontWeight: FontWeight.w900,
                        color: Colors.white),
                  ),
                  const SizedBox(height: 40),
                  ElevatedButton(
                    onPressed: () async {
                      await ref
                          .read(ludoRepositoryProvider)
                          .startNewGame(
                              widget.spaceId, widget.deviceId, _partnerId);
                    },
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      backgroundColor: AppTheme.accent,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                    ),
                    child: Text('Play Again',
                        style: TextStyle(
                            fontSize: context.sp(17),
                            fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ── Main game view ──────────────────────────────────────────────────────
  Widget _buildGame(LudoSession session) {
    final myColor = _myColor(session);
    final myTurn = session.turn == widget.deviceId;

    return Column(
      children: [
        // ── Turn banner ──
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 20),
          color: myTurn
              ? (myColor == 'red' ? AppTheme.red : AppTheme.blue)
              : Colors.white12,
          child: Text(
            myTurn
                ? '🎲  Your turn! ${session.hasRolled ? "Tap a token to move" : "Roll the dice"}'
                : "⏳  Partner's turn...",
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
          ),
        ),

        // ── Board + tokens ──
        Expanded(
          child: LayoutBuilder(
            builder: (ctx, constraints) {
              final boardSize = constraints.maxWidth < constraints.maxHeight
                  ? constraints.maxWidth
                  : constraints.maxHeight;
              final cs = boardSize / 15; // cell size

              return Center(
                child: SizedBox(
                  width: boardSize,
                  height: boardSize,
                  child: Stack(
                    children: [
                      // Board drawing
                      CustomPaint(
                        size: Size(boardSize, boardSize),
                        painter: const LudoBoardPainter(),
                      ),

                      // Red tokens
                      ...List.generate(4, (i) {
                        return _buildToken(
                          session: session,
                          color: 'red',
                          tokenIdx: i,
                          pos: session.redPositions[i],
                          cs: cs,
                          myColor: myColor,
                        );
                      }),

                      // Blue tokens
                      ...List.generate(4, (i) {
                        return _buildToken(
                          session: session,
                          color: 'blue',
                          tokenIdx: i,
                          pos: session.bluePositions[i],
                          cs: cs,
                          myColor: myColor,
                        );
                      }),
                    ],
                  ),
                ),
              );
            },
          ),
        ),

        // ── Dice & controls ──
        Container(
          decoration: const BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              // Dice face
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.black12),
                ),
                child: Center(
                  child: Text(
                    session.diceValue > 0 && !_rolling
                        ? _diceFaces[session.diceValue - 1]
                        : _diceFaces[_animDice - 1],
                    style: const TextStyle(fontSize: 40, color: Colors.black87),
                  ),
                ),
              ),

              // Roll button
              GestureDetector(
                onTap: () => _rollDice(session),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                  decoration: BoxDecoration(
                    color: (myTurn && !session.hasRolled && !_rolling)
                        ? (myColor == 'red' ? AppTheme.red : AppTheme.blue)
                        : Colors.black12,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    session.hasRolled ? 'Tap token' : 'Roll',
                    style: TextStyle(
                      fontSize: 20, 
                      fontWeight: FontWeight.w900, 
                      color: (myTurn && !session.hasRolled && !_rolling) ? Colors.white : Colors.black45,
                    ),
                  ),
                ),
              ),

              // My color indicator
              Column(
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: myColor == 'red' ? AppTheme.red : AppTheme.blue,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.black12),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(myColor.toUpperCase(), style: const TextStyle(color: Colors.black54, fontSize: 11, fontWeight: FontWeight.bold)),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildToken({
    required LudoSession session,
    required String color,
    required int tokenIdx,
    required int pos,
    required double cs,
    required String myColor,
  }) {
    // Compute position on board.
    double cx, cy;
    if (pos == -1) {
      final slots = color == 'red' ? kRedBaseSlots : kBlueBaseSlots;
      cx = slots[tokenIdx][1] * cs;
      cy = slots[tokenIdx][0] * cs;
    } else {
      final cell = color == 'red' ? redPosToCell(pos) : bluePosToCell(pos);
      if (cell[0] == -1) return const SizedBox.shrink();
      // Offset slightly if multiple tokens of the same color share a cell.
      final allPos = color == 'red' ? session.redPositions : session.bluePositions;
      final sameCell = allPos.where((p) => p == pos).length;
      final offsetX = sameCell > 1 ? (tokenIdx % 2) * cs * 0.3 - cs * 0.15 : 0.0;
      final offsetY = sameCell > 1 ? (tokenIdx ~/ 2) * cs * 0.3 - cs * 0.15 : 0.0;
      cx = (cell[1] + 0.5) * cs + offsetX;
      cy = (cell[0] + 0.5) * cs + offsetY;
    }

    final tokenColor = color == 'red' ? AppTheme.red : AppTheme.blue;
    final canMove = _isMyTurn(session) &&
        session.hasRolled &&
        myColor == color &&
        LudoGameLogic.canMove(pos, session.diceValue, pos == -1);

    return AnimatedPositioned(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      left: cx - cs * 0.38,
      top: cy - cs * 0.38,
      child: GestureDetector(
        onTap: () => _tapToken(session, color, tokenIdx),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: cs * 0.76,
          height: cs * 0.76,
          decoration: BoxDecoration(
            color: pos == kFinished ? Colors.amber : tokenColor,
            shape: BoxShape.circle,
            border: Border.all(
              color: canMove ? Colors.white : Colors.black45,
              width: canMove ? 2.5 : 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: tokenColor.withValues(alpha: canMove ? 0.8 : 0.4),
                blurRadius: canMove ? 8 : 4,
                spreadRadius: canMove ? 2 : 0,
              ),
            ],
          ),
          child: Center(
            child: Text(
              '${tokenIdx + 1}',
              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.white),
            ),
          ),
        ),
      ),
    );
  }
}

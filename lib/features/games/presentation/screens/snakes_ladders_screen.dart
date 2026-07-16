import 'package:closer/core/utils/app_utils.dart';
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/utils/responsive.dart';
import '../../data/snakes_ladders_board.dart';
import '../../data/snakes_ladders_model.dart';
import '../../data/snakes_ladders_repository.dart';
import '../widgets/snakes_ladders_board_painter.dart';
import '../../../../shared/providers/app_providers.dart';
import '../../../vibe/presentation/widgets/sync_status_chip.dart';
import '../../../../core/ads/ad_service.dart';

const List<String> _diceFaces = ['⚀', '⚁', '⚂', '⚃', '⚄', '⚅'];

class SnakesLaddersScreen extends ConsumerStatefulWidget {
  final String spaceId;
  final List<String> memberIds;
  final String deviceId;

  const SnakesLaddersScreen({
    super.key,
    required this.spaceId,
    required this.memberIds,
    required this.deviceId,
  });

  @override
  ConsumerState<SnakesLaddersScreen> createState() => _SnakesLaddersScreenState();
}

class _SnakesLaddersScreenState extends ConsumerState<SnakesLaddersScreen>
    with SingleTickerProviderStateMixin {
  // ── Dice animation ──────────────────────────────────────────────────────
  Timer? _diceTimer;
  int _animDice = 1;
  bool _rolling = false;

  // ── Visual step animation ───────────────────────────────────────────────
  // While animating a move we show a "preview" position locally
  // (so the token slides step-by-step) before Firestore is updated.
  bool _animating = false;
  int _animRedPos = 0;
  int _animBluePos = 0;

  // Last snake/ladder event for the flash banner
  String? _eventBanner; // "🐍 Snake!" or "🪜 Ladder!"
  Timer? _bannerTimer;

  String get _partnerId =>
      widget.memberIds.firstWhere((id) => id != widget.deviceId, orElse: () => '');

  late final PresenceRepository _presenceRepo;

  @override
  void initState() {
    super.initState();
        _presenceRepo = ref.read(presenceRepositoryProvider);
    _presenceRepo.setPresent(widget.spaceId, 'snakes_ladders', widget.deviceId);
  }

  @override
  void dispose() {
    _diceTimer?.cancel();
    _bannerTimer?.cancel();
    _presenceRepo.setAbsent(widget.spaceId, 'snakes_ladders', widget.deviceId);
    AdService.instance.showInterstitialIfReady();
    super.dispose();
  }

  // ── Roll dice ───────────────────────────────────────────────────────────
  void _rollDice(SnakesLaddersSession session) {
    final myTurn = session.turn == widget.deviceId;
    if (!myTurn || session.hasRolled || _rolling || _animating) return;

    HapticFeedback.mediumImpact();
    setState(() => _rolling = true);
    int count = 0;
    _diceTimer = Timer.periodic(const Duration(milliseconds: 75), (t) {
      setState(() => _animDice = Random().nextInt(6) + 1);
      count++;
      if (count >= 12) {
        t.cancel();
        final finalVal = Random().nextInt(6) + 1;
        setState(() {
          _animDice = finalVal;
          _rolling = false;
        });
        _animateMove(session, finalVal);
      }
    });
  }

  // ── Step-by-step animation then persist ────────────────────────────────
  Future<void> _animateMove(SnakesLaddersSession session, int diceValue) async {
    final myColor = session.redPlayerId == widget.deviceId ? 'red' : 'blue';
    int currentPos = myColor == 'red' ? session.redPosition : session.bluePosition;

    // --- Production rule: must have rolled ≥1 to leave start (pos 0) ---
    // Start pos is 0 (not on board); any roll moves player to that square.
    int rawTarget = currentPos + diceValue;

    // Exact-100 rule: bounce back if overshooting
    if (rawTarget > 100) {
      rawTarget = 100 - (rawTarget - 100);
    }

    setState(() {
      _animating = true;
      _animRedPos = session.redPosition;
      _animBluePos = session.bluePosition;
    });

    // Slide token step by step
    for (int step = currentPos + 1; step <= rawTarget; step++) {
      await Future.delayed(const Duration(milliseconds: 200));
      if (!mounted) return;
      setState(() {
        if (myColor == 'red') {
          _animRedPos = step;
        } else {
          _animBluePos = step;
        }
      });
    }

    // Brief pause on landing square
    await Future.delayed(const Duration(milliseconds: 300));

    // Snake or Ladder teleport
    int finalPos = rawTarget;
    String? event;

    if (session.snakes.containsKey(rawTarget)) {
      finalPos = session.snakes[rawTarget]!;
      event = '🐍 Snake! Sliding down...';
      HapticFeedback.heavyImpact();
    } else if (session.ladders.containsKey(rawTarget)) {
      finalPos = session.ladders[rawTarget]!;
      event = '🪜 Ladder! Climbing up!';
      HapticFeedback.heavyImpact();
    }

    if (event != null) {
      await Future.delayed(const Duration(milliseconds: 250));
      if (!mounted) return;
      setState(() {
        if (myColor == 'red') _animRedPos = finalPos;
        else _animBluePos = finalPos;
        _eventBanner = event;
      });
      _bannerTimer?.cancel();
      _bannerTimer = Timer(const Duration(seconds: 2), () {
        if (mounted) setState(() => _eventBanner = null);
      });
      await Future.delayed(const Duration(milliseconds: 600));
    }

    // Win check
    if (finalPos == 100) {
      HapticFeedback.heavyImpact();
    }

    // Determine next turn
    // Rolling a 6 gives an extra turn. If partner is not in the space yet,
    // keep turn with current player to avoid passing to an empty ID.
    final nextTurn = (diceValue == 6 || _partnerId.isEmpty)
        ? widget.deviceId
        : _partnerId;
    final nextStatus = (finalPos == 100) ? '${myColor}_won' : session.status;
    final finalTurn = (finalPos == 100) ? session.turn : nextTurn;

    final newSession = session.copyWith(
      turn: finalTurn,
      diceValue: diceValue,
      hasRolled: false,
      redPosition: myColor == 'red' ? finalPos : session.redPosition,
      bluePosition: myColor == 'blue' ? finalPos : session.bluePosition,
      status: nextStatus,
    );

    await ref.read(snakesLaddersRepositoryProvider).saveSession(widget.spaceId, newSession);

    if (mounted) setState(() => _animating = false);
  }

  // ── Build ───────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final sessionAsync = ref.watch(snakesLaddersStreamProvider(widget.spaceId));
    final partnerPresentAsync = _partnerId.isEmpty
        ? const AsyncData(false)
        : ref.watch(featurePresenceProvider(
            (spaceId: widget.spaceId, featureId: 'snakes_ladders', partnerId: _partnerId)));
    final partnerPresent = partnerPresentAsync.valueOrNull ?? false;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            'Snakes & Ladders',
            style: TextStyle(
              color: Color(0xFF166534),
              fontWeight: FontWeight.w900,
              shadows: [Shadow(color: Colors.white, blurRadius: 4, offset: Offset(0, 2))],
            ),
          ),
        ),
        iconTheme: const IconThemeData(color: Color(0xFF166534)),
        actions: [
          Center(
            child: SyncStatusChip(
              state: partnerPresent ? SyncState.inSync : SyncState.partnerLeft,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'New Game',
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  title: const Text('Restart Game?'),
                  content: const Text('Abandon the current game and start fresh?'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Restart', style: TextStyle(color: Colors.red)),
                    ),
                  ],
                ),
              );
              if (confirm == true) {
                await ref
                    .read(snakesLaddersRepositoryProvider)
                    .startNewGame(widget.spaceId, widget.deviceId, _partnerId, force: true);
              }
            },
          ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFa8edea), Color(0xFFfed6e3)],
          ),
        ),
        child: SafeArea(
          child: sessionAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text(AppUtils.getFriendlyErrorMessage(e), textAlign: TextAlign.center,)),
            data: (session) {
              if (session == null || session.status == 'waiting') return _buildLobby();
              if (session.status == 'red_won' || session.status == 'blue_won') {
                return _buildResult(session);
              }
              return _buildGame(session);
            },
          ),
        ),
      ),
    );
  }

  // ── Lobby ───────────────────────────────────────────────────────────────
  Widget _buildLobby() {
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
                  Text('🐍🪜',
                      style: TextStyle(fontSize: context.sp(76)),
                      textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  Text(
                    'Snakes & Ladders',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: context.sp(28),
                      fontWeight: FontWeight.w900,
                      color: const Color(0xFF166534),
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
                        Text('• Race from 1 to 100 to win',
                            style: TextStyle(fontSize: context.sp(13))),
                        Text('• Roll a 6 to get an extra turn!',
                            style: TextStyle(fontSize: context.sp(13))),
                        Text('• 🪜 Ladders take you UP',
                            style: TextStyle(fontSize: context.sp(13))),
                        Text('• 🐍 Snakes pull you DOWN',
                            style: TextStyle(fontSize: context.sp(13))),
                        Text('• Must land exactly on 100 to win',
                            style: TextStyle(fontSize: context.sp(13))),
                      ],
                    ),
                  ),
                  const SizedBox(height: 28),
                  ElevatedButton.icon(
                    onPressed: () async {
                      await ref
                          .read(snakesLaddersRepositoryProvider)
                          .startNewGame(widget.spaceId, widget.deviceId, _partnerId);
                    },
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      backgroundColor: const Color(0xFF166534),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                      elevation: 4,
                    ),
                    icon: const Icon(Icons.play_arrow_rounded),
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
  Widget _buildResult(SnakesLaddersSession session) {
    final myColor = session.redPlayerId == widget.deviceId ? 'red' : 'blue';
    final iWon = (myColor == 'red' && session.status == 'red_won') ||
        (myColor == 'blue' && session.status == 'blue_won');

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
                  Text(iWon ? '🎉' : '😢',
                      style: TextStyle(fontSize: context.sp(76)),
                      textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  Text(
                    iWon ? 'You Win! 🏆' : 'Partner Won!',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: context.sp(30),
                      fontWeight: FontWeight.w900,
                      color: iWon ? const Color(0xFF166534) : Colors.black54,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    iWon
                        ? 'Congratulations! You reached 100!'
                        : 'Better luck next time!',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.black54, fontSize: context.sp(14)),
                  ),
                  const SizedBox(height: 40),
                  ElevatedButton.icon(
                    onPressed: () async {
                      await ref
                          .read(snakesLaddersRepositoryProvider)
                          .startNewGame(
                              widget.spaceId, widget.deviceId, _partnerId,
                              force: true);
                    },
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      backgroundColor: const Color(0xFF166534),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                      elevation: 4,
                    ),
                    icon: const Icon(Icons.replay_rounded),
                    label: Text('Play Again',
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

  // ── Game ────────────────────────────────────────────────────────────────
  Widget _buildGame(SnakesLaddersSession session) {
    final myColor = session.redPlayerId == widget.deviceId ? 'red' : 'blue';
    final myTurn = session.turn == widget.deviceId;
    final canRoll = myTurn && !session.hasRolled && !_rolling && !_animating;

    // Use animated positions when mid-animation, otherwise from Firestore
    final redPos = _animating ? _animRedPos : session.redPosition;
    final bluePos = _animating ? _animBluePos : session.bluePosition;

    return Column(
      children: [
        // ── Status bar ──────────────────────────────────────────────────
        AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
          decoration: BoxDecoration(
            color: _eventBanner != null
                ? const Color(0xFFFFF9C4)
                : myTurn
                    ? const Color(0xFFDCFCE7)
                    : Colors.white.withValues(alpha: 0.5),
            border: Border(
              bottom: BorderSide(
                color: _eventBanner != null
                    ? Colors.amber.shade300
                    : myTurn
                        ? const Color(0xFF86EFAC)
                        : Colors.transparent,
                width: 1.5,
              ),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_eventBanner != null)
                Text(
                  _eventBanner!,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: Color(0xFF92400E),
                  ),
                  textAlign: TextAlign.center,
                )
              else ...[
                Container(
                  width: 12,
                  height: 12,
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    color: myColor == 'red' ? Colors.red : Colors.blue,
                    shape: BoxShape.circle,
                  ),
                ),
                Text(
                  myTurn
                      ? (_rolling || _animating ? 'Rolling...' : '🎲 Your Turn — Roll the dice!')
                      : "⏳ Partner's turn...",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: myTurn ? const Color(0xFF166534) : Colors.black54,
                  ),
                ),
              ],
            ],
          ),
        ),

        // ── Board ───────────────────────────────────────────────────────
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final boardSize = min(constraints.maxWidth, constraints.maxHeight);
                const borderWidth = 3.5;
                final innerSize = boardSize - (borderWidth * 2);
                final cs = innerSize / 10;

                return Center(
                  child: Container(
                    width: boardSize,
                    height: boardSize,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: const Color(0xFF166534), width: borderWidth),
                      borderRadius: BorderRadius.circular(6),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.18),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: Stack(
                        children: [
                          // Board
                          CustomPaint(
                            size: Size(innerSize, innerSize),
                            painter: SnakesLaddersBoardPainter(
                              snakes: session.snakes,
                              ladders: session.ladders,
                            ),
                          ),
                          // Red token
                          if (redPos > 0)
                            _buildToken(
                              pos: redPos,
                              gradient: const [Color(0xFFef4444), Color(0xFF991b1b)],
                              cs: cs,
                              offset: (redPos == bluePos) ? Offset(-cs * 0.18, -cs * 0.18) : Offset.zero,
                              label: myColor == 'red' ? 'Y' : 'P',
                              isMe: myColor == 'red',
                            ),
                          // Blue token
                          if (bluePos > 0)
                            _buildToken(
                              pos: bluePos,
                              gradient: const [Color(0xFF60a5fa), Color(0xFF1e40af)],
                              cs: cs,
                              offset: (redPos == bluePos) ? Offset(cs * 0.18, cs * 0.18) : Offset.zero,
                              label: myColor == 'blue' ? 'Y' : 'P',
                              isMe: myColor == 'blue',
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),

        // ── Controls ─────────────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.85),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 12, offset: const Offset(0, -4))
            ],
          ),
          child: Row(
            children: [
              // Position info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Container(width: 10, height: 10,
                            decoration: BoxDecoration(color: myColor == 'red' ? const Color(0xFFef4444) : const Color(0xFF60a5fa), shape: BoxShape.circle)),
                        const SizedBox(width: 6),
                        Text('You: ${ myColor == 'red' ? redPos : bluePos}',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(width: 10, height: 10,
                            decoration: BoxDecoration(color: myColor == 'red' ? const Color(0xFF60a5fa) : const Color(0xFFef4444), shape: BoxShape.circle)),
                        const SizedBox(width: 6),
                        Text('Partner: ${myColor == 'red' ? bluePos : redPos}',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.black54)),
                      ],
                    ),
                  ],
                ),
              ),

              // Dice
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE5E7EB), width: 2),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.07), blurRadius: 8, offset: const Offset(0, 3))],
                ),
                child: Center(
                  child: Text(
                    session.diceValue > 0 && !_rolling
                        ? _diceFaces[session.diceValue - 1]
                        : _diceFaces[_animDice - 1],
                    style: const TextStyle(fontSize: 34),
                  ),
                ),
              ),

              const SizedBox(width: 14),

              // Roll button
              GestureDetector(
                onTap: () => _rollDice(session),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                  decoration: BoxDecoration(
                    color: canRoll ? const Color(0xFF166534) : Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: canRoll
                        ? [BoxShadow(color: const Color(0xFF166534).withValues(alpha: 0.35), blurRadius: 12, offset: const Offset(0, 5))]
                        : [],
                  ),
                  child: Text(
                    _rolling || _animating ? '...' : 'Roll',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1,
                      color: canRoll ? Colors.white : Colors.grey.shade500,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Token widget ─────────────────────────────────────────────────────────
  Widget _buildToken({
    required int pos,
    required List<Color> gradient,
    required double cs,
    required Offset offset,
    required String label,
    required bool isMe,
  }) {
    final cell = positionToCell(pos);
    if (cell[0] == -1) return const SizedBox.shrink();

    final cx = (cell[1] + 0.5) * cs;
    final cy = (cell[0] + 0.5) * cs;
    final tokenR = cs * 0.28;

    return AnimatedPositioned(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
      left: cx - tokenR + offset.dx,
      top: cy - tokenR + offset.dy,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        width: tokenR * 2,
        height: tokenR * 2,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [gradient[0].withValues(alpha: 0.9), gradient[1]],
            center: const Alignment(-0.4, -0.4),
            radius: 0.85,
          ),
          border: Border.all(
            color: isMe ? Colors.white : Colors.white70,
            width: isMe ? 2.5 : 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: gradient[0].withValues(alpha: 0.5),
              blurRadius: isMe ? 8 : 4,
              spreadRadius: isMe ? 1 : 0,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: tokenR * 0.9,
              shadows: const [Shadow(color: Colors.black38, blurRadius: 2)],
            ),
          ),
        ),
      ),
    );
  }
}

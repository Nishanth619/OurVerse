import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/utils/responsive.dart';
import '../../../../shared/providers/app_providers.dart';
import '../../../vibe/presentation/widgets/sync_status_chip.dart';
import '../../data/bingo_model.dart';
import '../../data/bingo_repository.dart';
import '../../../../core/ads/ad_service.dart';
import '../../../../core/services/daily_limits_service.dart';

// ─── Colours ─────────────────────────────────────────────────────────────────

const _bgFrom = Color(0xFF1A1A2E);
const _bgTo = Color(0xFF16213E);
const _accent = Color(0xFFE94560);
const _accentBlue = Color(0xFF0F3460);
const _gold = Color(0xFFFFD700);
const _cardBg = Color(0xFF0F3460);
const _calledCell = Color(0xFFE94560);
const _myCalledCell = Color(0xFFFF6B6B);

// ─── Screen ───────────────────────────────────────────────────────────────────

class BingoScreen extends ConsumerStatefulWidget {
  final String spaceId;
  final List<String> memberIds;
  final String deviceId;
  final String spaceType;

  const BingoScreen({
    super.key,
    required this.spaceId,
    required this.memberIds,
    required this.deviceId,
    this.spaceType = 'couple',
  });

  @override
  ConsumerState<BingoScreen> createState() => _BingoScreenState();
}

class _BingoScreenState extends ConsumerState<BingoScreen>
    with TickerProviderStateMixin {
  String get _label => widget.spaceType == 'friends' ? 'Bestie' : 'Partner';

  late final PresenceRepository _presenceRepo;
  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;
  int? _lastCalled;

  @override
  void initState() {
    super.initState();
    _presenceRepo = ref.read(presenceRepositoryProvider);
    _presenceRepo.setPresent(widget.spaceId, 'bingo', widget.deviceId);
    // Consume the play now — the user is actually IN the game.
    DailyLimitsService.consumeGamePlay('bingo');

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _pulseAnim = Tween<double>(begin: 1.0, end: 1.2).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.elasticOut),
    );
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _presenceRepo.setAbsent(widget.spaceId, 'bingo', widget.deviceId);
    AdService.instance.showInterstitialIfReady();
    super.dispose();
  }

  void _animateNumber(int number) {
    setState(() => _lastCalled = number);
    _pulseCtrl.forward(from: 0);
  }

  Future<void> _callNumber(BingoSession session, int number) async {
    _animateNumber(number);
    await ref
        .read(bingoRepositoryProvider)
        .callNumber(widget.spaceId, session, number, widget.deviceId);
  }

  @override
  Widget build(BuildContext context) {
    final sessionAsync =
        ref.watch(bingoStreamProvider(widget.spaceId));
    final partnerId = widget.memberIds
        .firstWhere((id) => id != widget.deviceId, orElse: () => '');
    final partnerPresentAsync = partnerId.isEmpty
        ? const AsyncData(false)
        : ref.watch(featurePresenceProvider(
            (spaceId: widget.spaceId, featureId: 'bingo', partnerId: partnerId)));
    final partnerPresent = partnerPresentAsync.valueOrNull ?? false;

    return Scaffold(
      backgroundColor: _bgFrom,
      appBar: AppBar(
        backgroundColor: _bgFrom,
        elevation: 0,
        title: const FittedBox(fit: BoxFit.scaleDown, child: Text(
          '🎱 Bingo',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            fontSize: 22,
          ),
        )),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          Center(
            child: SyncStatusChip(
              state: partnerPresent ? SyncState.inSync : SyncState.partnerLeft,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.white70),
            tooltip: 'New Game',
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  title: const Text('Restart Bingo?'),
                  content:
                      const Text('Abandon the current game and start fresh?'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Cancel')),
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Restart',
                          style: TextStyle(color: Colors.red)),
                    ),
                  ],
                ),
              );
              if (confirm == true && context.mounted) {
                await ref.read(bingoRepositoryProvider).startNewGame(
                      widget.spaceId,
                      widget.deviceId,
                      partnerId,
                      force: true,
                    );
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
            colors: [_bgFrom, _bgTo],
          ),
        ),
        child: sessionAsync.when(
          loading: () =>
              const Center(child: CircularProgressIndicator(color: _accent)),
          error: (e, _) => Center(
              child: Text(e.toString(),
                  style: const TextStyle(color: Colors.white70))),
          data: (session) {
            if (session == null || session.status == 'waiting') {
              return _buildLobby(partnerId);
            }
            if (session.status == 'p1_won' ||
                session.status == 'p2_won' ||
                session.status == 'draw') {
              return _buildResult(session, partnerId);
            }
            return _buildGame(session);
          },
        ),
      ),
    );
  }

  // ── Lobby ──────────────────────────────────────────────────────────────────

  Widget _buildLobby(String partnerId) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 24),
          Text('🎱',
              style: TextStyle(fontSize: context.sp(72)),
              textAlign: TextAlign.center),
          const SizedBox(height: 20),
          Text(
            'Bingo',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: context.sp(36),
              fontWeight: FontWeight.w900,
              color: Colors.white,
              letterSpacing: 4,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'First to 5 lines wins!',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white60, fontSize: context.sp(14)),
          ),
          const SizedBox(height: 28),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: _cardBg.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(16),
              border:
                  Border.all(color: _accent.withValues(alpha: 0.3), width: 1),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('📜 How to Play',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 15)),
                SizedBox(height: 12),
                _RuleRow(
                    icon: '🔢',
                    text: 'You each have a unique 5×5 grid of numbers 1–25'),
                _RuleRow(
                    icon: '👆',
                    text: 'On your turn, tap any uncalled number to mark it'),
                _RuleRow(
                    icon: '✨',
                    text:
                        'Marked numbers highlight on BOTH your boards instantly'),
                _RuleRow(
                    icon: '🏆',
                    text:
                        'Complete 5 lines (rows, columns, or diagonals) to win!'),
                _RuleRow(icon: '🔄', text: 'Turns alternate between players'),
              ],
            ),
          ),
          const SizedBox(height: 32),
          ElevatedButton.icon(
            onPressed: () async {
              await ref.read(bingoRepositoryProvider).startNewGame(
                    widget.spaceId,
                    widget.deviceId,
                    partnerId,
                  );
            },
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 18),
              backgroundColor: _accent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              elevation: 8,
              shadowColor: _accent.withValues(alpha: 0.5),
            ),
            icon: const Icon(Icons.play_arrow_rounded, size: 26),
            label: Text('Start New Game',
                style: TextStyle(fontSize: context.sp(17), fontWeight: FontWeight.bold)),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // ── Result ─────────────────────────────────────────────────────────────────

  Widget _buildResult(BingoSession session, String partnerId) {
    final iAmP1 = session.player1Id == widget.deviceId;
    final iWon = (iAmP1 && session.status == 'p1_won') ||
        (!iAmP1 && session.status == 'p2_won');
    final isDraw = session.status == 'draw';

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
                  Text(
                    isDraw ? '🤝' : (iWon ? '🎉' : '😢'),
                    style: TextStyle(fontSize: context.sp(80)),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    isDraw ? "It's a Draw!" : (iWon ? 'BINGO! You Win! 🎉' : '$_label Won!'),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: context.sp(28),
                      fontWeight: FontWeight.w900,
                      color: isDraw ? Colors.white60 : (iWon ? _gold : Colors.white60),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    isDraw
                        ? 'You both got 5 lines at the same time!'
                        : (iWon
                            ? 'You completed 5 lines first!'
                            : 'Better luck next time!'),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white54, fontSize: context.sp(14)),
                  ),
                  const SizedBox(height: 40),
                  ElevatedButton.icon(
                    onPressed: () async {
                      await ref.read(bingoRepositoryProvider).startNewGame(
                            widget.spaceId,
                            widget.deviceId,
                            partnerId,
                            force: true,
                          );
                    },
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      backgroundColor: _accent,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                      elevation: 8,
                      shadowColor: _accent.withValues(alpha: 0.5),
                    ),
                    icon: const Icon(Icons.replay_rounded),
                    label: Text('Play Again',
                        style: TextStyle(fontSize: context.sp(17), fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ── Game ───────────────────────────────────────────────────────────────────

  Widget _buildGame(BingoSession session) {
    final iAmP1 = session.player1Id == widget.deviceId;
    final myBoard = iAmP1 ? session.player1Board : session.player2Board;
    final myLines = iAmP1 ? session.player1Lines : session.player2Lines;
    final partnerLines = iAmP1 ? session.player2Lines : session.player1Lines;
    final isMyTurn = session.turn == widget.deviceId;

    return SafeArea(
      child: Column(
        children: [
          // ── Turn banner ─────────────────────────────────────────────────
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            width: double.infinity,
            padding:
                const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
            decoration: BoxDecoration(
              color: isMyTurn
                  ? _accent.withValues(alpha: 0.18)
                  : Colors.white.withValues(alpha: 0.05),
              border: Border(
                bottom: BorderSide(
                  color: isMyTurn
                      ? _accent.withValues(alpha: 0.5)
                      : Colors.transparent,
                  width: 1.5,
                ),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: Text(
                    isMyTurn
                        ? '👆 Your turn — tap a number!'
                        : '⏳ Waiting for $_label...',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: isMyTurn ? _accent : Colors.white60,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── BINGO progress bars ─────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Row(
              children: [
                Expanded(
                    child: _LineMeter(
                        label: 'You', lines: myLines, color: _accent)),
                const SizedBox(width: 12),
                Expanded(
                    child: _LineMeter(
                        label: _label,
                        lines: partnerLines,
                        color: const Color(0xFF4FC3F7))),
              ],
            ),
          ),

          // ── Last called number ──────────────────────────────────────────
          if (_lastCalled != null || session.calledNumbers.isNotEmpty)
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('Last called: ',
                      style:
                          TextStyle(color: Colors.white54, fontSize: 13)),
                  ScaleTransition(
                    scale: _pulseAnim,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 4),
                      decoration: BoxDecoration(
                        color: _accent,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '${session.calledNumbers.isNotEmpty ? session.calledNumbers.last : '—'}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // ── Board ───────────────────────────────────────────────────────
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: LayoutBuilder(
                builder: (ctx, constraints) {
                  final size = constraints.maxWidth;
                  return Column(
                    children: [
                      // BINGO header — letters strike through as lines complete
                      Row(
                        children: List.generate(5, (i) {
                          final letter = 'BINGO'[i];
                          final struck = myLines > i;
                          return Expanded(
                            child: Center(
                              child: AnimatedOpacity(
                                duration: const Duration(milliseconds: 400),
                                opacity: struck ? 0.35 : 1.0,
                                child: Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    Text(
                                      letter,
                                      style: TextStyle(
                                        fontSize: size / 7,
                                        fontWeight: FontWeight.w900,
                                        color: struck ? Colors.white38 : _gold,
                                        shadows: struck
                                            ? []
                                            : [
                                                Shadow(
                                                  color: _accent.withValues(alpha: 0.6),
                                                  blurRadius: 8,
                                                ),
                                              ],
                                      ),
                                    ),
                                    if (struck)
                                      Positioned(
                                        child: Container(
                                          height: 3,
                                          width: size / 7,
                                          decoration: BoxDecoration(
                                            color: _accent,
                                            borderRadius: BorderRadius.circular(2),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }),
                      ),
                      const SizedBox(height: 4),
                      // Grid with line overlay
                      Expanded(
                        child: LayoutBuilder(
                          builder: (ctx2, gridConstraints) {
                            final completedLines = getCompletedBingoLines(
                                myBoard, session.calledNumbers);
                            return Stack(
                              children: [
                                GridView.builder(
                                  physics: const NeverScrollableScrollPhysics(),
                                  gridDelegate:
                                      const SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: 5,
                                    mainAxisSpacing: 6,
                                    crossAxisSpacing: 6,
                                  ),
                                  itemCount: 25,
                                  itemBuilder: (ctx, idx) {
                                    final num = myBoard[idx];
                                    final isCalled =
                                        session.calledNumbers.contains(num);
                                    return _BingoCell(
                                      number: num,
                                      isCalled: isCalled,
                                      isMyTurn: isMyTurn,
                                      isLastCalled:
                                          session.calledNumbers.isNotEmpty &&
                                              session.calledNumbers.last == num,
                                      onTap: isMyTurn && !isCalled
                                          ? () => _callNumber(session, num)
                                          : null,
                                    );
                                  },
                                ),
                                // Line overlay drawn on top of grid
                                if (completedLines.isNotEmpty)
                                  IgnorePointer(
                                    child: CustomPaint(
                                      size: Size(gridConstraints.maxWidth,
                                          gridConstraints.maxHeight),
                                      painter: _BingoLinePainter(
                                        completedLines: completedLines,
                                        gridSize: gridConstraints.maxWidth,
                                      ),
                                    ),
                                  ),
                              ],
                            );
                          },
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),

          // ── Called numbers strip ─────────────────────────────────────────
          if (session.calledNumbers.isNotEmpty)
            Container(
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: session.calledNumbers.length,
                itemBuilder: (ctx, i) {
                  final n = session.calledNumbers[
                      session.calledNumbers.length - 1 - i];
                  final isFirst = i == 0;
                  return Container(
                    width: 36,
                    height: 36,
                    margin: const EdgeInsets.only(right: 6),
                    decoration: BoxDecoration(
                      color: isFirst
                          ? _accent
                          : _accent.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: _accent.withValues(alpha: isFirst ? 1.0 : 0.4),
                          width: isFirst ? 2 : 1),
                    ),
                    child: Center(
                      child: Text(
                        '$n',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: n >= 10 ? 12 : 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Completed-line detection ─────────────────────────────────────────────────

enum _BingoLineType { row, col, mainDiag, antiDiag }

class _BingoLineDesc {
  final _BingoLineType type;
  final int index; // 0-4 for row/col; 0 for diagonals
  const _BingoLineDesc(this.type, this.index);
}

List<_BingoLineDesc> getCompletedBingoLines(
    List<int> board, List<int> called) {
  final calledSet = called.toSet();
  final result = <_BingoLineDesc>[];
  for (int r = 0; r < 5; r++) {
    if (List.generate(5, (c) => board[r * 5 + c]).every(calledSet.contains)) {
      result.add(_BingoLineDesc(_BingoLineType.row, r));
    }
  }
  for (int c = 0; c < 5; c++) {
    if (List.generate(5, (r) => board[r * 5 + c]).every(calledSet.contains)) {
      result.add(_BingoLineDesc(_BingoLineType.col, c));
    }
  }
  if (List.generate(5, (i) => board[i * 5 + i]).every(calledSet.contains)) {
    result.add(_BingoLineDesc(_BingoLineType.mainDiag, 0));
  }
  if (List.generate(5, (i) => board[i * 5 + (4 - i)]).every(calledSet.contains)) {
    result.add(_BingoLineDesc(_BingoLineType.antiDiag, 0));
  }
  return result;
}

// ─── Line Painter ─────────────────────────────────────────────────────────────

class _BingoLinePainter extends CustomPainter {
  final List<_BingoLineDesc> completedLines;
  final double gridSize;

  const _BingoLinePainter(
      {required this.completedLines, required this.gridSize});

  @override
  void paint(Canvas canvas, Size size) {
    // Cell size accounting for 6px gaps between 5 cells
    final cellSize = (gridSize - 4 * 6) / 5;
    final gap = 6.0;
    final padding = 10.0; // line extends a bit beyond the cell centers

    // Helper: center of cell at (row, col)
    Offset cellCenter(int r, int c) {
      final x = c * (cellSize + gap) + cellSize / 2;
      final y = r * (cellSize + gap) + cellSize / 2;
      return Offset(x, y);
    }

    final paint = Paint()
      ..color = const Color(0xFFFFD700) // gold
      ..strokeWidth = 4.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);

    final glowPaint = Paint()
      ..color = const Color(0xFFFFD700).withValues(alpha: 0.35)
      ..strokeWidth = 12
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);

    for (final line in completedLines) {
      Offset start, end;
      switch (line.type) {
        case _BingoLineType.row:
          final r = line.index;
          start = cellCenter(r, 0) - Offset(padding, 0);
          end = cellCenter(r, 4) + Offset(padding, 0);
          break;
        case _BingoLineType.col:
          final c = line.index;
          start = cellCenter(0, c) - Offset(0, padding);
          end = cellCenter(4, c) + Offset(0, padding);
          break;
        case _BingoLineType.mainDiag:
          start = cellCenter(0, 0) - Offset(padding * 0.7, padding * 0.7);
          end = cellCenter(4, 4) + Offset(padding * 0.7, padding * 0.7);
          break;
        case _BingoLineType.antiDiag:
          start = cellCenter(0, 4) + Offset(padding * 0.7, -padding * 0.7);
          end = cellCenter(4, 0) - Offset(padding * 0.7, -padding * 0.7);
          break;
      }
      // Draw glow first, then crisp line on top
      canvas.drawLine(start, end, glowPaint);
      canvas.drawLine(start, end, paint);
    }
  }

  @override
  bool shouldRepaint(_BingoLinePainter old) =>
      old.completedLines.length != completedLines.length;
}

// ─── Cell Widget ──────────────────────────────────────────────────────────────

class _BingoCell extends StatefulWidget {
  final int number;
  final bool isCalled;
  final bool isMyTurn;
  final bool isLastCalled;
  final VoidCallback? onTap;

  const _BingoCell({
    required this.number,
    required this.isCalled,
    required this.isMyTurn,
    required this.isLastCalled,
    this.onTap,
  });

  @override
  State<_BingoCell> createState() => _BingoCellState();
}

class _BingoCellState extends State<_BingoCell>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 400));
    _scale = Tween<double>(begin: 0.7, end: 1.0).animate(
        CurvedAnimation(parent: _ctrl, curve: Curves.elasticOut));
    if (widget.isCalled) _ctrl.value = 1.0;
  }

  @override
  void didUpdateWidget(_BingoCell old) {
    super.didUpdateWidget(old);
    if (!old.isCalled && widget.isCalled) {
      _ctrl.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canTap = widget.onTap != null;

    return GestureDetector(
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          gradient: widget.isCalled
              ? RadialGradient(colors: [
                  widget.isLastCalled
                      ? _myCalledCell
                      : _calledCell.withValues(alpha: 0.85),
                  _accentBlue,
                ])
              : null,
          color: widget.isCalled
              ? null
              : canTap
                  ? _cardBg
                  : _cardBg.withValues(alpha: 0.5),
          border: Border.all(
            color: widget.isCalled
                ? _calledCell.withValues(alpha: 0.6)
                : canTap
                    ? Colors.white.withValues(alpha: 0.15)
                    : Colors.white.withValues(alpha: 0.07),
            width: widget.isLastCalled ? 2 : 1,
          ),
          boxShadow: widget.isCalled
              ? [
                  BoxShadow(
                    color: _accent.withValues(alpha: 0.4),
                    blurRadius: 8,
                    spreadRadius: 1,
                  )
                ]
              : null,
        ),
        child: widget.isCalled
            ? ScaleTransition(
                scale: _scale,
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('✓',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold)),
                      Text(
                        '${widget.number}',
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            : Center(
                child: Text(
                  '${widget.number}',
                  style: TextStyle(
                    color: canTap ? Colors.white : Colors.white38,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
      ),
    );
  }
}

// ─── Line Progress Meter ──────────────────────────────────────────────────────

class _LineMeter extends StatelessWidget {
  final String label;
  final int lines;
  final Color color;

  const _LineMeter(
      {required this.label, required this.lines, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
            Text('$lines/5',
                style: TextStyle(
                    color: color,
                    fontSize: 12,
                    fontWeight: FontWeight.w900)),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: lines / 5.0,
            backgroundColor: Colors.white12,
            valueColor: AlwaysStoppedAnimation<Color>(color),
            minHeight: 8,
          ),
        ),
      ],
    );
  }
}

// ─── Rule Row ─────────────────────────────────────────────────────────────────

class _RuleRow extends StatelessWidget {
  final String icon;
  final String text;
  const _RuleRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(icon, style: const TextStyle(fontSize: 16)),
          const SizedBox(width: 10),
          Expanded(
              child: Text(text,
                  style: const TextStyle(color: Colors.white70, fontSize: 13))),
        ],
      ),
    );
  }
}

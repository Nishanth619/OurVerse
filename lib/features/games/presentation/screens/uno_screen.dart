import 'dart:math' show pi;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/providers/app_providers.dart';
import '../../data/uno_engine.dart';
import '../../data/uno_model.dart';
import '../../data/uno_repository.dart';
import '../../../../core/ads/ad_service.dart';
import '../../../../core/services/daily_limits_service.dart';

// ─── Color Palette ────────────────────────────────────────────────────────────

const _kRed = Color(0xFFD32F2F);
const _kGreen = Color(0xFF388E3C);
const _kBlue = Color(0xFF1565C0);
const _kYellow = Color(0xFFF9A825);
const _kTableBg1 = Color(0xFF0D1B2A);
const _kTableBg2 = Color(0xFF1B2838);

Color _unoColor(String c) {
  switch (c) {
    case 'R': return _kRed;
    case 'G': return _kGreen;
    case 'B': return _kBlue;
    case 'Y': return _kYellow;
    default:  return Colors.grey;
  }
}

String _colorName(String c) {
  switch (c) {
    case 'R': return 'Red';
    case 'G': return 'Green';
    case 'B': return 'Blue';
    case 'Y': return 'Yellow';
    default:  return '';
  }
}

// ─── UNO Screen ───────────────────────────────────────────────────────────────

class UnoScreen extends ConsumerStatefulWidget {
  final String spaceId;
  final List<String> memberIds;
  final String deviceId;
  final String spaceType;

  const UnoScreen({
    super.key,
    required this.spaceId,
    required this.memberIds,
    required this.deviceId,
    this.spaceType = 'couple',
  });

  @override
  ConsumerState<UnoScreen> createState() => _UnoScreenState();
}

class _UnoScreenState extends ConsumerState<UnoScreen>
    with TickerProviderStateMixin {
  late final PresenceRepository _presenceRepo;
  late final AnimationController _discardAnim;
  late final AnimationController _unoBannerAnim;
  late final AnimationController _winAnim;

  bool _isSaving = false;

  String get _myId => widget.deviceId;
  String get _partnerId =>
      widget.memberIds.firstWhere((id) => id != _myId, orElse: () => '');

  String get _label => widget.spaceType == 'friends' ? 'Bestie' : 'Partner';

  @override
  void initState() {
    super.initState();
    _presenceRepo = ref.read(presenceRepositoryProvider);
    _presenceRepo.setPresent(widget.spaceId, 'uno', _myId);
    // Consume the play now — the user is actually IN the game.
    DailyLimitsService.consumeGamePlay('uno');

    _discardAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _unoBannerAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
    _winAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
  }

  @override
  void dispose() {
    _presenceRepo.setAbsent(widget.spaceId, 'uno', _myId);
    _discardAnim.dispose();
    _unoBannerAnim.dispose();
    _winAnim.dispose();
    AdService.instance.showInterstitialIfReady();
    super.dispose();
  }

  // ── Game Actions ──────────────────────────────────────────────────────────────

  Future<void> _startGame({bool rematch = false}) async {
    if (_isSaving) return;
    setState(() => _isSaving = true);
    try {
      final repo = ref.read(unoRepositoryProvider);
      // Player who taps Start is always player1 (first to tap)
      await repo.startNewGame(
        widget.spaceId,
        _myId,
        _partnerId.isNotEmpty ? _partnerId : _myId,
        force: rematch,
      );
      if (rematch) _winAnim.reverse();
    } catch (e) {
      if (mounted) _showError('Failed to start game. Check connection.');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _playCard(UnoSession session, String card) async {
    if (_isSaving) return;
    if (session.currentTurn != _myId) return;
    if (!UnoEngine.canPlay(card, session.discardPile.last, session.currentColor)) return;

    // Wild cards need color selection first
    String? chosenColor;
    if (card == 'W' || card == 'WD4') {
      chosenColor = await _showColorPicker();
      if (chosenColor == null || !mounted) return; // User cancelled
    }

    setState(() => _isSaving = true);
    try {
      final updated = UnoEngine.applyPlay(session, _myId, card, chosenColor);
      _discardAnim.forward(from: 0);
      if (updated.isFinished) _winAnim.forward();
      await ref.read(unoRepositoryProvider).saveSession(widget.spaceId, updated);
    } catch (e) {
      if (mounted) _showError('Failed to play card. Check connection.');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _drawCard(UnoSession session) async {
    if (_isSaving) return;
    if (session.currentTurn != _myId) return;

    setState(() => _isSaving = true);
    try {
      final updated = UnoEngine.drawCard(session, _myId);
      await ref.read(unoRepositoryProvider).saveSession(widget.spaceId, updated);
    } catch (e) {
      if (mounted) _showError('Failed to draw card. Check connection.');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: Colors.red.shade700,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.all(16),
    ));
  }

  // ── Color Picker ──────────────────────────────────────────────────────────────

  Future<String?> _showColorPicker() {
    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF1B2838),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Choose a Color',
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 28),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                for (final pair in [
                  ('R', 'Red', _kRed),
                  ('G', 'Green', _kGreen),
                  ('B', 'Blue', _kBlue),
                  ('Y', 'Yellow', _kYellow),
                ])
                  _ColorPickerButton(
                    code: pair.$1,
                    label: pair.$2,
                    color: pair.$3,
                    onTap: () => Navigator.of(ctx).pop(pair.$1),
                  ),
              ],
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final sessionAsync = ref.watch(unoSessionProvider(widget.spaceId));
    final partnerPresent = _partnerId.isEmpty
        ? false
        : (ref.watch(featurePresenceProvider((
                spaceId: widget.spaceId,
                featureId: 'uno',
                partnerId: _partnerId)))
            .valueOrNull ?? false);

    return Scaffold(
      backgroundColor: _kTableBg1,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const FittedBox(fit: BoxFit.scaleDown, child: Text(
          'UNO',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            fontSize: 24,
            letterSpacing: 2,
          ),
        )),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white70),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: _PresenceDot(online: partnerPresent),
            ),
          ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [_kTableBg1, _kTableBg2],
          ),
        ),
        child: sessionAsync.when(
          loading: () => const Center(
            child: CircularProgressIndicator(color: Colors.white54),
          ),
          error: (e, _) => Center(
            child: Text(
              'Error loading game',
              style: TextStyle(color: Colors.red.shade300),
            ),
          ),
          data: (session) {
            if (session == null || session.status == 'waiting') {
              return _buildLobby(partnerPresent);
            }
            return _buildGame(session);
          },
        ),
      ),
    );
  }

  // ── Lobby ─────────────────────────────────────────────────────────────────────

  Widget _buildLobby(bool partnerPresent) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Animated UNO logo
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [_kRed, Color(0xFFFF6B35)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: _kRed.withValues(alpha: 0.5),
                    blurRadius: 24,
                    spreadRadius: 4,
                  ),
                ],
              ),
              child: const Center(
                child: Text(
                  'UNO',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 36,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 32),
            const Text(
              'Ready to play?',
              style: TextStyle(
                color: Colors.white,
                fontSize: 26,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              partnerPresent
                  ? '🟢 Partner is here — let\'s go!'
                  : '⏳ Waiting for $_label to open UNO...',
              style: TextStyle(
                color: partnerPresent ? Colors.greenAccent : Colors.white54,
                fontSize: 15,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 40),
            SizedBox(
              width: double.infinity,
              height: 58,
              child: ElevatedButton(
                onPressed: _isSaving ? null : () => _startGame(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kRed,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                  elevation: 8,
                  shadowColor: _kRed.withValues(alpha: 0.5),
                ),
                child: _isSaving
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2.5,
                        ),
                      )
                    : const Text(
                        'Start Game 🃏',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'First to empty their hand wins!',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.4),
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Game Board ────────────────────────────────────────────────────────────────

  Widget _buildGame(UnoSession session) {
    final isMyTurn = session.currentTurn == _myId;
    final myHand = session.handOf(_myId);
    final partnerHand = session.handOf(_partnerId.isNotEmpty ? _partnerId : session.opponentOf(_myId));
    final topCard = session.discardPile.last;

    return Stack(
      children: [
        // ── Main game layout
        Column(
          children: [
            // ── Partner hand (top — face down)
            RepaintBoundary(child: _buildPartnerHand(partnerHand)),

            // ── Center table
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Turn indicator
                    _TurnIndicator(isMyTurn: isMyTurn, saving: _isSaving),
                    const SizedBox(height: 16),

                    // UNO banner
                    if (session.unoPlayerId != null)
                      RepaintBoundary(
                        child: _UnoBanner(
                          isMe: session.unoPlayerId == _myId,
                          animation: _unoBannerAnim,
                        ),
                      ),
                    if (session.unoPlayerId != null) const SizedBox(height: 12),

                    // Discard + Draw piles
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Draw pile
                        Column(
                          children: [
                            GestureDetector(
                              onTap: isMyTurn && !_isSaving
                                  ? () => _drawCard(session)
                                  : null,
                              child: _DrawPile(
                                count: session.drawPile.length,
                                enabled: isMyTurn && !_isSaving,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '${session.drawPile.length}',
                              style: const TextStyle(
                                color: Colors.white54,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(width: 28),

                        // Discard pile
                        Column(
                          children: [
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 350),
                              transitionBuilder: (child, anim) =>
                                  ScaleTransition(
                                scale: CurvedAnimation(
                                  parent: anim,
                                  curve: Curves.elasticOut,
                                ),
                                child: FadeTransition(
                                    opacity: anim, child: child),
                              ),
                              child: UnoCardWidget(
                                key: ValueKey(topCard),
                                card: topCard,
                                width: 95,
                                height: 140,
                                isPlayable: false,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Discard',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.4),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),

                    // Current color indicator
                    _ColorIndicator(color: session.currentColor),
                  ],
                ),
              ),
            ),

            // ── My hand (bottom — face up)
            RepaintBoundary(child: _buildMyHand(session, myHand, isMyTurn)),
          ],
        ),

        // ── Win/Lose overlay
        if (session.isFinished)
          _WinOverlay(
            iWon: session.winnerId == _myId,
            opponentHandCount: partnerHand.length,
            onRematch: () => _startGame(rematch: true),
            animation: _winAnim,
            label: _label,
          ),
      ],
    );
  }

  // ── Partner Hand ──────────────────────────────────────────────────────────────

  Widget _buildPartnerHand(List<String> hand) {
    return Container(
      height: 90,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.person, color: Colors.white54, size: 14),
              const SizedBox(width: 4),
              Text(
                'Partner · ${hand.length} cards',
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: List.generate(
                  hand.length,
                  (i) => Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: UnoCardWidget(
                      card: hand[i],
                      faceDown: true,
                      width: 38,
                      height: 55,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── My Hand ───────────────────────────────────────────────────────────────────

  Widget _buildMyHand(
    UnoSession session,
    List<String> hand,
    bool isMyTurn,
  ) {
    final topCard = session.discardPile.last;
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.35),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border(
          top: BorderSide(
            color: Colors.white.withValues(alpha: 0.08),
          ),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const SizedBox(width: 16),
              const Icon(Icons.person_outline, color: Colors.white70, size: 14),
              const SizedBox(width: 4),
              Text(
                'Your hand · ${hand.length} cards',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 115,
            child: hand.isEmpty
                ? const Center(
                    child: Text(
                      'No cards!',
                      style: TextStyle(color: Colors.white54),
                    ),
                  )
                : ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: hand.length,
                    itemBuilder: (ctx, i) {
                      final card = hand[i];
                      final playable = isMyTurn &&
                          !_isSaving &&
                          UnoEngine.canPlay(
                            card,
                            topCard,
                            session.currentColor,
                          );
                      return Padding(
                        padding: const EdgeInsets.only(right: 10),
                        child: UnoCardWidget(
                          card: card,
                          width: 65,
                          height: 97,
                          isPlayable: playable,
                          onTap: playable
                              ? () => _playCard(session, card)
                              : null,
                        ),
                      );
                    },
                  ),
          ),
          SizedBox(height: MediaQuery.of(context).padding.bottom + 12),
        ],
      ),
    );
  }
}

// ─── UNO Card Widget ──────────────────────────────────────────────────────────

class UnoCardWidget extends StatelessWidget {
  final String card;
  final bool faceDown;
  final bool isPlayable;
  final VoidCallback? onTap;
  final double width;
  final double height;

  const UnoCardWidget({
    super.key,
    required this.card,
    this.faceDown = false,
    this.isPlayable = true,
    this.onTap,
    this.width = 65,
    this.height = 97,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isPlayable ? onTap : null,
      child: AnimatedScale(
        scale: (isPlayable && onTap != null) ? 1.0 : 1.0,
        duration: const Duration(milliseconds: 150),
        child: AnimatedOpacity(
          opacity: (isPlayable || faceDown || onTap == null) ? 1.0 : 0.40,
          duration: const Duration(milliseconds: 200),
          child: Container(
            width: width,
            height: height,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(width * 0.13),
              boxShadow: [
                BoxShadow(
                  color: isPlayable && onTap != null
                      ? _unoColor(faceDown ? 'R' : (card.startsWith('W') ? 'R' : card[0]))
                          .withValues(alpha: 0.5)
                      : Colors.black.withValues(alpha: 0.3),
                  blurRadius: isPlayable && onTap != null ? 12 : 6,
                  spreadRadius: isPlayable && onTap != null ? 2 : 0,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(width * 0.13),
              child: faceDown ? _buildBack() : _buildFront(),
            ),
          ),
        ),
      ),
    );
  }

  // ── Card Front ────────────────────────────────────────────────────────────────

  Widget _buildFront() {
    final isWild = card == 'W' || card == 'WD4';
    if (isWild) return _buildWild();

    final color = _unoColor(card[0]);
    final value = card.substring(1);
    return _buildColored(color, value);
  }

  Widget _buildColored(Color color, String value) {
    final label = _cardLabel(value);
    final corner = _cornerLabel(value);
    final isNumber = int.tryParse(value) != null;

    return Stack(
      children: [
        // Background
        Container(color: color),

        // Inner border ring
        Positioned.fill(
          child: Container(
            margin: EdgeInsets.all(width * 0.07),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(width * 0.10),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.35),
                width: 2,
              ),
            ),
          ),
        ),

        // Center oval
        Center(
          child: Transform.rotate(
            angle: -0.15,
            child: Container(
              width: width * 0.72,
              height: height * 0.62,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(width * 0.40),
              ),
              child: Center(
                child: Transform.rotate(
                  angle: 0.15,
                  child: _CenterValue(
                    label: label,
                    color: color,
                    fontSize: isNumber ? width * 0.50 : width * 0.38,
                  ),
                ),
              ),
            ),
          ),
        ),

        // Top-left corner
        Positioned(
          top: width * 0.06,
          left: width * 0.08,
          child: _CornerLabel(label: corner, color: Colors.white, size: width * 0.18),
        ),

        // Bottom-right corner (rotated 180°)
        Positioned(
          bottom: width * 0.06,
          right: width * 0.08,
          child: Transform.rotate(
            angle: pi,
            child: _CornerLabel(label: corner, color: Colors.white, size: width * 0.18),
          ),
        ),
      ],
    );
  }

  Widget _buildWild() {
    final isD4 = card == 'WD4';
    final label = isD4 ? '+4' : 'WILD';
    final labelSize = isD4 ? width * 0.38 : width * 0.20;

    return Stack(
      children: [
        // 4-color quadrant background
        Column(
          children: [
            Expanded(
              child: Row(
                children: [
                  Expanded(child: Container(color: _kRed)),
                  Expanded(child: Container(color: _kBlue)),
                ],
              ),
            ),
            Expanded(
              child: Row(
                children: [
                  Expanded(child: Container(color: _kYellow)),
                  Expanded(child: Container(color: _kGreen)),
                ],
              ),
            ),
          ],
        ),

        // Inner border ring
        Positioned.fill(
          child: Container(
            margin: EdgeInsets.all(width * 0.07),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(width * 0.10),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.35),
                width: 2,
              ),
            ),
          ),
        ),

        // Center black oval
        Center(
          child: Transform.rotate(
            angle: -0.15,
            child: Container(
              width: width * 0.72,
              height: height * 0.62,
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(width * 0.40),
              ),
              child: Center(
                child: Transform.rotate(
                  angle: 0.15,
                  child: Text(
                    label,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: labelSize,
                      fontWeight: FontWeight.w900,
                      height: 1,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
          ),
        ),

        // Corner labels
        Positioned(
          top: width * 0.06,
          left: width * 0.08,
          child: _CornerLabel(label: isD4 ? '+4' : 'W', color: Colors.white, size: width * 0.18),
        ),
        Positioned(
          bottom: width * 0.06,
          right: width * 0.08,
          child: Transform.rotate(
            angle: pi,
            child: _CornerLabel(label: isD4 ? '+4' : 'W', color: Colors.white, size: width * 0.18),
          ),
        ),
      ],
    );
  }

  // ── Card Back ─────────────────────────────────────────────────────────────────

  Widget _buildBack() {
    return Stack(
      children: [
        Container(color: _kRed),
        Positioned.fill(
          child: Container(
            margin: EdgeInsets.all(width * 0.07),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(width * 0.10),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.3),
                width: 1.5,
              ),
            ),
          ),
        ),
        Center(
          child: Transform.rotate(
            angle: -0.15,
            child: Container(
              width: width * 0.72,
              height: height * 0.62,
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(width * 0.40),
              ),
              child: Center(
                child: Transform.rotate(
                  angle: 0.15,
                  child: Text(
                    'UNO',
                    style: TextStyle(
                      color: _kRed,
                      fontSize: width * 0.22,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.5,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────────

  static String _cardLabel(String value) {
    switch (value) {
      case 'S':  return '🚫';
      case 'R':  return '↺';
      case 'D2': return '+2';
      default:   return value;
    }
  }

  static String _cornerLabel(String value) {
    switch (value) {
      case 'S':  return '⊘';
      case 'R':  return '↺';
      case 'D2': return '+2';
      default:   return value;
    }
  }
}

// ─── Sub-Widgets ──────────────────────────────────────────────────────────────

class _CenterValue extends StatelessWidget {
  final String label;
  final Color color;
  final double fontSize;

  const _CenterValue({
    required this.label,
    required this.color,
    required this.fontSize,
  });

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: TextStyle(
        color: color,
        fontSize: fontSize,
        fontWeight: FontWeight.w900,
        height: 1.0,
      ),
      textAlign: TextAlign.center,
    );
  }
}

class _CornerLabel extends StatelessWidget {
  final String label;
  final Color color;
  final double size;

  const _CornerLabel({
    required this.label,
    required this.color,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: TextStyle(
        color: color,
        fontSize: size,
        fontWeight: FontWeight.w900,
        height: 1.0,
      ),
    );
  }
}

class _DrawPile extends StatelessWidget {
  final int count;
  final bool enabled;

  const _DrawPile({required this.count, this.enabled = false});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Shadow cards behind (depth effect)
        Positioned(
          left: 3, top: 3,
          child: Container(
            width: 85, height: 126,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(11),
            ),
          ),
        ),
        Positioned(
          left: 6, top: 6,
          child: Container(
            width: 85, height: 126,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(11),
            ),
          ),
        ),
        // Actual top card (face down)
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: enabled
              ? BoxDecoration(
                  borderRadius: BorderRadius.circular(11),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.white.withValues(alpha: 0.3),
                      blurRadius: 16,
                      spreadRadius: 2,
                    ),
                  ],
                )
              : null,
          child: UnoCardWidget(
            card: 'back',
            faceDown: true,
            width: 85,
            height: 126,
          ),
        ),
      ],
    );
  }
}

class _TurnIndicator extends StatelessWidget {
  final bool isMyTurn;
  final bool saving;

  const _TurnIndicator({required this.isMyTurn, required this.saving});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        color: isMyTurn
            ? Colors.green.withValues(alpha: 0.2)
            : Colors.orange.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isMyTurn ? Colors.greenAccent : Colors.orange,
          width: 1.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (saving)
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                color: Colors.white54,
                strokeWidth: 2,
              ),
            )
          else
            Text(
              isMyTurn ? '▶' : '⏳',
              style: const TextStyle(fontSize: 14),
            ),
          const SizedBox(width: 8),
          Text(
            isMyTurn ? 'YOUR TURN' : "Partner's turn…",
            style: TextStyle(
              color: isMyTurn ? Colors.greenAccent : Colors.orange,
              fontWeight: FontWeight.w800,
              fontSize: 14,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _ColorIndicator extends StatelessWidget {
  final String color;

  const _ColorIndicator({required this.color});

  @override
  Widget build(BuildContext context) {
    final c = _unoColor(color);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c, width: 1.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 14, height: 14,
            decoration: BoxDecoration(color: c, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Text(
            '${_colorName(color)} color',
            style: TextStyle(
              color: c,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

class _UnoBanner extends StatelessWidget {
  final bool isMe;
  final AnimationController animation;

  const _UnoBanner({required this.isMe, required this.animation});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (ctx, _) {
        final glow = animation.value;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFD32F2F), Color(0xFFFF6B35)],
            ),
            borderRadius: BorderRadius.circular(32),
            boxShadow: [
              BoxShadow(
                color: _kRed.withValues(alpha: 0.3 + glow * 0.5),
                blurRadius: 10 + glow * 20,
                spreadRadius: glow * 4,
              ),
            ],
          ),
          child: Text(
            isMe ? '🃏  UNO!' : '🃏  Partner said UNO!',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.5,
            ),
          ),
        );
      },
    );
  }
}

class _PresenceDot extends StatelessWidget {
  final bool online;

  const _PresenceDot({required this.online});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10, height: 10,
          decoration: BoxDecoration(
            color: online ? Colors.greenAccent : Colors.grey,
            shape: BoxShape.circle,
            boxShadow: online
                ? [
                    BoxShadow(
                      color: Colors.greenAccent.withValues(alpha: 0.6),
                      blurRadius: 8,
                    )
                  ]
                : null,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          online ? 'Online' : 'Away',
          style: TextStyle(
            color: online ? Colors.greenAccent : Colors.grey,
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}

class _ColorPickerButton extends StatelessWidget {
  final String code;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ColorPickerButton({
    required this.code,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 3),
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.6),
                  blurRadius: 16,
                  spreadRadius: 2,
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

class _WinOverlay extends StatelessWidget {
  final bool iWon;
  final int opponentHandCount;
  final VoidCallback onRematch;
  final AnimationController animation;
  final String label;

  const _WinOverlay({
    required this.iWon,
    required this.opponentHandCount,
    required this.onRematch,
    required this.animation,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (ctx, _) => Opacity(
        opacity: animation.value,
        child: Container(
          color: Colors.black.withValues(alpha: 0.88),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    iWon ? '🏆' : '😢',
                    style: const TextStyle(fontSize: 80),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    iWon ? 'YOU WIN!' : 'You Lost',
                    style: TextStyle(
                      color: iWon ? Colors.amber : Colors.redAccent,
                      fontSize: 38,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    iWon
                        ? 'Partner had $opponentHandCount card${opponentHandCount == 1 ? '' : 's'} left!'
                        : '$label emptied their hand!',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 16,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 40),
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: onRematch,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _kRed,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                        elevation: 8,
                      ),
                      child: const Text(
                        'Play Again 🃏',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

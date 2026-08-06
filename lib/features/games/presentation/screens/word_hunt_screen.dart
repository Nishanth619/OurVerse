import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/app_utils.dart';
import '../../../../core/utils/responsive.dart';
import '../../../../shared/providers/app_providers.dart';
import '../../../vibe/presentation/widgets/sync_status_chip.dart';
import '../../../../core/ads/ad_service.dart';
import '../../../../core/services/daily_limits_service.dart';

// ─── Constants ───────────────────────────────────────────────────────────────
const int _kGridCols = 8;
const int _kTotalSeconds = 45;

class WordHuntScreen extends ConsumerStatefulWidget {
  final String spaceId;
  final List<String> memberIds;
  final String deviceId;
  final String spaceType;

  const WordHuntScreen({
    super.key,
    required this.spaceId,
    required this.memberIds,
    required this.deviceId,
    this.spaceType = 'couple',
  });

  @override
  ConsumerState<WordHuntScreen> createState() => _WordHuntScreenState();
}

class _WordHuntScreenState extends ConsumerState<WordHuntScreen> {
  Set<String> _dictionary = {};
  bool _isLoadingDict = true;
  bool _dictError = false; // true if dictionary failed to load

  late final PresenceRepository _presenceRepo;

  @override
  void initState() {
    super.initState();
    _loadDictionary();
    // Consume the play now — the user is actually IN the game.
    DailyLimitsService.consumeGamePlay('wordhunt');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _presenceRepo = ref.read(presenceRepositoryProvider);
      _presenceRepo.setPresent(widget.spaceId, 'word_hunt', widget.deviceId);
    });
  }

  @override
  void dispose() {
    _presenceRepo.setAbsent(widget.spaceId, 'word_hunt', widget.deviceId);
    AdService.instance.showInterstitialIfReady();
    super.dispose();
  }

  Future<void> _loadDictionary() async {
    if (mounted) setState(() { _isLoadingDict = true; _dictError = false; });
    try {
      final String raw = await rootBundle.loadString('assets/dictionary.txt');
      final loaded = raw
          .split('\n')
          .map((w) => w.trim().toUpperCase())
          .where((w) => w.length >= 3)
          .toSet();
      // Validate we actually got words — empty set means the asset is broken
      if (loaded.isEmpty) throw Exception('Dictionary is empty after parsing.');
      _dictionary = loaded;
    } catch (e) {
      debugPrint('Dictionary load failed: $e');
      if (mounted) setState(() => _dictError = true);
    } finally {
      if (mounted) setState(() => _isLoadingDict = false);
    }
  }

  String get _partnerId =>
      widget.memberIds.firstWhere((id) => id != widget.deviceId, orElse: () => '');

  String get _label => widget.spaceType == 'friends' ? 'Bestie' : 'Partner';

  @override
  Widget build(BuildContext context) {
    final sessionAsync = ref.watch(wordHuntStreamProvider(widget.spaceId));
    final partnerPresentAsync = _partnerId.isEmpty
        ? const AsyncData(false)
        : ref.watch(featurePresenceProvider(
            (spaceId: widget.spaceId, featureId: 'word_hunt', partnerId: _partnerId)));
    final partnerPresent = partnerPresentAsync.valueOrNull ?? false;

    return Theme(
      // Word Hunt uses an intentional dark arcade look. We build a fully
      // self-contained dark ThemeData here so it is NOT affected by the
      // system dark mode toggle or our global ThemeMode.light lock.
      data: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1E3A8A),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF121212),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          iconTheme: IconThemeData(color: Colors.white),
          titleTextStyle: TextStyle(
              color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
        ),
      ),
      child: Scaffold(
        backgroundColor: const Color(0xFF121212), // Force dark arcade background
        appBar: AppBar(
        title: const FittedBox(fit: BoxFit.scaleDown, child: Text('Word Hunt Race 🔎', style: TextStyle(color: Colors.white))),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          Center(
            child: SyncStatusChip(
              state: partnerPresent ? SyncState.inSync : SyncState.partnerLeft,
            ),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: SafeArea(
        child: _isLoadingDict
            ? const Center(child: CircularProgressIndicator())
            : _dictError
                // Dictionary failed: show a clear error with retry button
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('📖', style: TextStyle(fontSize: 48)),
                          const SizedBox(height: 16),
                          const Text(
                            'Could not load dictionary',
                            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Word Hunt needs the dictionary to work. Please retry.',
                            style: TextStyle(color: Colors.white70, fontSize: 14),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 24),
                          ElevatedButton.icon(
                            onPressed: _loadDictionary,
                            icon: const Icon(Icons.refresh),
                            label: const Text('Retry'),
                          ),
                        ],
                      ),
                    ),
                  )
                : sessionAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (err, _) => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.wifi_off, color: Colors.white54, size: 48),
                        const SizedBox(height: 16),
                        Text(
                          AppUtils.getFriendlyErrorMessage(err),
                          style: const TextStyle(color: Colors.white70),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
                data: (session) {
                  if (session == null) return _buildLobby(null);

                  final myStart = session.startedAt[widget.deviceId];
                  final myFinish = session.finishedAt[widget.deviceId];

                  if (myStart == null) return _buildLobby(session);

                  if (myFinish == null) {
                    return _ActiveGameView(
                      spaceId: widget.spaceId,
                      deviceId: widget.deviceId,
                      session: session,
                      dictionary: _dictionary,
                    );
                  }

                  // I'm done — waiting for partner?
                  final partnerFinish = session.finishedAt[_partnerId];
                  if (partnerFinish == null) {
                    return _buildWaiting();
                  }

                  return _buildResults(session);
                },
              ),
        ),
      ),
    );
  }

  Widget _buildLobby(WordHuntModel? session) {
    final partnerHasPlayed = session != null &&
        session.finishedAt.containsKey(_partnerId);
    final partnerIsPlaying = session != null &&
        session.startedAt.containsKey(_partnerId) &&
        !session.finishedAt.containsKey(_partnerId);

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
                  Text('🔍',
                      style: TextStyle(fontSize: context.sp(76)),
                      textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  Text(
                    'Word Hunt Race',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: context.sp(28),
                      fontWeight: FontWeight.w900,
                      color: const Color(0xFF1E3A8A), // Blue theme
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
                        if (partnerIsPlaying)
                          const Padding(
                            padding: EdgeInsets.only(bottom: 12),
                            child: Text(
                                '⏳ Your partner is playing... Wait for them!',
                                style: TextStyle(
                                    color: Colors.orange,
                                    fontWeight: FontWeight.bold)),
                          )
                        else if (partnerHasPlayed)
                          const Padding(
                            padding: EdgeInsets.only(bottom: 12),
                            child: Text(
                                '✅ Your partner finished! Start your round!',
                                style: TextStyle(
                                    color: Colors.green,
                                    fontWeight: FontWeight.bold)),
                          ),
                        Text('📜 Rules',
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: context.sp(14))),
                        const SizedBox(height: 8),
                        Text('• Drag across adjacent letters to form words',
                            style: TextStyle(fontSize: context.sp(13))),
                        Text('• Minimum 3 letters per word',
                            style: TextStyle(fontSize: context.sp(13))),
                        Text('• You have exactly 45 seconds',
                            style: TextStyle(fontSize: context.sp(13))),
                        Text('• Longest words score the most points!',
                            style: TextStyle(fontSize: context.sp(13))),
                      ],
                    ),
                  ),
                  const SizedBox(height: 28),
                  ElevatedButton.icon(
                    onPressed: partnerIsPlaying
                        ? null
                        : () async {
                            final repo = ref.read(wordHuntRepositoryProvider);
                            if (session == null) {
                              await repo.startNewGame(widget.spaceId);
                            }
                            await repo.startGameForUser(
                                widget.spaceId, widget.deviceId);
                          },
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      backgroundColor: partnerIsPlaying
                          ? Colors.grey.shade800
                          : const Color(0xFF1E3A8A),
                      foregroundColor: partnerIsPlaying
                          ? Colors.white54
                          : Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                      elevation: 0,
                    ),
                    icon: Icon(
                        partnerIsPlaying
                            ? Icons.hourglass_empty_rounded
                            : Icons.play_arrow_rounded,
                        size: 28),
                    label: Text(
                      partnerIsPlaying
                          ? 'Wait...'
                          : (session == null
                              ? 'Start New Game'
                              : 'Start My Round (0:45)'),
                      style: TextStyle(
                          fontSize: context.sp(17),
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildWaiting() {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Padding(
              padding: const EdgeInsets.all(28.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('⏳',
                      style: TextStyle(fontSize: context.sp(72)),
                      textAlign: TextAlign.center),
                  const SizedBox(height: 24),
                  Text(
                    'Your round is done!\nWaiting for partner to finish...',
                    style: theme.textTheme.headlineSmall?.copyWith(
                        fontSize: context.sp(22)),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 48),
                  OutlinedButton(
                    onPressed: () async {
                      // Confirm before abandoning partner's in-progress round
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Start New Game?'),
                          content: const Text(
                            'Your partner may still be playing their round. '
                            'Starting a new game now will end this session for both of you.\n\n'
                            'Are you sure?',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.of(ctx).pop(false),
                              child: const Text('Wait for Partner'),
                            ),
                            TextButton(
                              style: TextButton.styleFrom(
                                  foregroundColor: Colors.red),
                              onPressed: () => Navigator.of(ctx).pop(true),
                              child: const Text('Start New Game'),
                            ),
                          ],
                        ),
                      );
                      if (confirmed == true && mounted) {
                        await ref
                            .read(wordHuntRepositoryProvider)
                            .startNewGame(widget.spaceId);
                      }
                    },
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      side: const BorderSide(color: Colors.white38),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    child: Text('Start New Game Instead',
                        style: TextStyle(fontSize: context.sp(16))),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildResults(WordHuntModel session) {
    final theme = Theme.of(context);
    final myScore = session.score[widget.deviceId] ?? 0;
    final partnerScore = session.score[_partnerId] ?? 0;
    final isDraw = myScore == partnerScore;
    final iWon = myScore > partnerScore;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 12),
          Text(
            isDraw ? 'It\'s a Draw! 🤝' : (iWon ? 'You Won! 🎉' : 'Partner Won! 😢'),
            style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _ScoreCard(label: 'You', score: myScore, highlight: iWon),
              _ScoreCard(label: 'Partner', score: partnerScore, highlight: !iWon && !isDraw),
            ],
          ),
          const SizedBox(height: 32),
          ElevatedButton(
            onPressed: () async {
              await ref.read(wordHuntRepositoryProvider).startNewGame(widget.spaceId);
            },
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              backgroundColor: AppTheme.accent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            child: const Text('Play Again', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(height: 28),
          _WordList(title: 'Your Words', words: session.wordsFound[widget.deviceId] ?? []),
          const SizedBox(height: 16),
          _WordList(title: "$_label's Words", words: session.wordsFound[_partnerId] ?? []),
        ],
      ),
    );
  }
}

// ─── Score Card ──────────────────────────────────────────────────────────────

class _ScoreCard extends StatelessWidget {
  final String label;
  final int score;
  final bool highlight;
  const _ScoreCard({required this.label, required this.score, required this.highlight});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(label, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Container(
          width: 120,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: highlight ? AppTheme.accent.withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: highlight ? AppTheme.accent : Colors.white.withValues(alpha: 0.1),
              width: 2,
            ),
          ),
          child: Text(
            '$score',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 40,
              fontWeight: FontWeight.w900,
              color: highlight ? AppTheme.accent : Colors.white,
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Word List Widget ─────────────────────────────────────────────────────────

class _WordList extends StatelessWidget {
  final String title;
  final List<String> words;
  const _WordList({required this.title, required this.words});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$title (${words.length})',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: words
              .map((w) => Chip(
                    label: Text(w, style: const TextStyle(fontWeight: FontWeight.w600)),
                    backgroundColor: Colors.white.withValues(alpha: 0.08),
                  ))
              .toList(),
        ),
      ],
    );
  }
}

// ─── Active Game View ─────────────────────────────────────────────────────────

class _ActiveGameView extends ConsumerStatefulWidget {
  final String spaceId;
  final String deviceId;
  final WordHuntModel session;
  final Set<String> dictionary;

  const _ActiveGameView({
    required this.spaceId,
    required this.deviceId,
    required this.session,
    required this.dictionary,
  });

  @override
  ConsumerState<_ActiveGameView> createState() => _ActiveGameViewState();
}

class _ActiveGameViewState extends ConsumerState<_ActiveGameView> {
  late Timer _timer;
  int _secondsLeft = _kTotalSeconds;

  final List<String> _foundWords = [];
  int _currentScore = 0;
  List<int> _selectedPath = [];
  String _currentWord = '';
  bool _wordValid = false;
  bool _wordAlreadyFound = false;

  // Exact pixel bounds of each cell — populated in LayoutBuilder
  final List<Rect> _cellRects = [];

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  void _startTimer() {
    final start = widget.session.startedAt[widget.deviceId]?.toDate() ?? DateTime.now();
    _secondsLeft = _kTotalSeconds - DateTime.now().difference(start).inSeconds;
    if (_secondsLeft < 0) _secondsLeft = 0;

    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _secondsLeft--);
      if (_secondsLeft <= 0) {
        _timer.cancel();
        _submitRound();
      }
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  Future<void> _submitRound() async {
    await ref.read(wordHuntRepositoryProvider).submitRound(
          widget.spaceId,
          widget.deviceId,
          _foundWords,
          _currentScore,
        );
  }

  // ── Touch → cell index ─────────────────────────────────────────────────────

  int? _indexAtOffset(Offset local) {
    for (int i = 0; i < _cellRects.length; i++) {
      if (_cellRects[i].contains(local)) return i;
    }
    return null;
  }

  bool _isAdjacent(int a, int b) {
    final ar = a ~/ _kGridCols, ac = a % _kGridCols;
    final br = b ~/ _kGridCols, bc = b % _kGridCols;
    return (ar - br).abs() <= 1 && (ac - bc).abs() <= 1 && a != b;
  }

  void _onPanUpdate(Offset local) {
    final idx = _indexAtOffset(local);
    if (idx == null) return;

    if (_selectedPath.isEmpty) {
      HapticFeedback.selectionClick();
      setState(() {
        _selectedPath.add(idx);
        _currentWord = widget.session.grid[idx];
        _updateWordStatus();
      });
    } else if (!_selectedPath.contains(idx) && _isAdjacent(_selectedPath.last, idx)) {
      HapticFeedback.selectionClick();
      setState(() {
        _selectedPath.add(idx);
        _currentWord += widget.session.grid[idx];
        _updateWordStatus();
      });
    } else if (_selectedPath.length >= 2 && idx == _selectedPath[_selectedPath.length - 2]) {
      // Backtrack
      setState(() {
        _selectedPath.removeLast();
        _currentWord = _currentWord.substring(0, _currentWord.length - 1);
        _updateWordStatus();
      });
    }
  }

  void _updateWordStatus() {
    _wordValid = _currentWord.length >= 3 && widget.dictionary.contains(_currentWord);
    _wordAlreadyFound = _foundWords.contains(_currentWord);
  }

  void _onPanEnd() {
    if (_currentWord.length >= 3 && widget.dictionary.contains(_currentWord)) {
      if (!_foundWords.contains(_currentWord)) {
        int pts = _scoreForLength(_currentWord.length);
        setState(() {
          _foundWords.add(_currentWord);
          _currentScore += pts;
        });
        HapticFeedback.mediumImpact();
      }
    } else if (_currentWord.isNotEmpty) {
      HapticFeedback.vibrate();
    }
    setState(() {
      _selectedPath.clear();
      _currentWord = '';
      _wordValid = false;
      _wordAlreadyFound = false;
    });
  }

  int _scoreForLength(int len) {
    if (len == 3) return 100;
    if (len == 4) return 300;
    if (len == 5) return 600;
    return 1000; // 6+
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final minutes = _secondsLeft ~/ 60;
    final secs = (_secondsLeft % 60).toString().padLeft(2, '0');
    final isRed = _secondsLeft <= 10;

    Color wordColor = Colors.white54;
    if (_wordAlreadyFound) wordColor = Colors.orangeAccent;
    else if (_wordValid) wordColor = Colors.greenAccent;
    else if (_currentWord.length >= 3) wordColor = Colors.redAccent;

    return Column(
      children: [
        // ── Top Bar ──
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Score', style: theme.textTheme.labelSmall),
                  Text('$_currentScore',
                      style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                decoration: BoxDecoration(
                  color: isRed ? Colors.red.withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: isRed ? Colors.redAccent : Colors.white24),
                ),
                child: Text(
                  '$minutes:$secs',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: isRed ? Colors.redAccent : Colors.white,
                  ),
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('Words', style: theme.textTheme.labelSmall),
                  Text('${_foundWords.length}',
                      style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
                ],
              ),
            ],
          ),
        ),

        // ── Current Word Display ──
        SizedBox(
          height: 48,
          child: Center(
            child: AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 150),
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w900,
                letterSpacing: 6,
                color: wordColor,
              ),
              child: Text(_currentWord.isEmpty ? 'Â·' : _currentWord),
            ),
          ),
        ),

        // ── 8x8 Grid ──
        Expanded(
          flex: 5,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: LayoutBuilder(
              builder: (ctx, constraints) {
                final cellSize = constraints.maxWidth / _kGridCols;

                // Build cell rects for accurate hit-testing
                if (_cellRects.isEmpty || _cellRects.length != _kGridCols * _kGridCols) {
                  _cellRects.clear();
                  final rows = (_kGridCols * _kGridCols) ~/ _kGridCols;
                  for (int r = 0; r < rows; r++) {
                    for (int c = 0; c < _kGridCols; c++) {
                      _cellRects.add(Rect.fromLTWH(
                        c * cellSize,
                        r * cellSize,
                        cellSize,
                        cellSize,
                      ));
                    }
                  }
                }

                return GestureDetector(
                  onPanStart: (d) => _onPanUpdate(d.localPosition),
                  onPanUpdate: (d) => _onPanUpdate(d.localPosition),
                  onPanEnd: (_) => _onPanEnd(),
                  child: SizedBox(
                    width: constraints.maxWidth,
                    height: cellSize * _kGridCols,
                    child: Stack(
                      children: [
                        // Draw connection lines between selected cells
                        if (_selectedPath.length > 1)
                          CustomPaint(
                            size: Size(constraints.maxWidth, cellSize * _kGridCols),
                            painter: _LinePainter(
                              path: _selectedPath,
                              cellSize: cellSize,
                              cols: _kGridCols,
                              color: wordColor,
                            ),
                          ),
                        // Grid cells
                        GridView.builder(
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: _kGridCols,
                          ),
                          itemCount: _kGridCols * _kGridCols,
                          itemBuilder: (_, index) {
                            final isSelected = _selectedPath.contains(index);
                            final isLast = _selectedPath.isNotEmpty && _selectedPath.last == index;
                            return _GridCell(
                              letter: widget.session.grid[index],
                              isSelected: isSelected,
                              isLast: isLast,
                              wordColor: wordColor,
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),

        // ── Found Words ──
        Expanded(
          flex: 2,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.3),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Found Words', style: theme.textTheme.labelLarge),
                const SizedBox(height: 6),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: _foundWords.reversed
                          .map((w) => Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: Chip(
                                  label: Text(w,
                                      style: const TextStyle(
                                          fontSize: 12, fontWeight: FontWeight.bold)),
                                  backgroundColor: Colors.white.withValues(alpha: 0.1),
                                  visualDensity: VisualDensity.compact,
                                ),
                              ))
                          .toList(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Grid Cell ────────────────────────────────────────────────────────────────

class _GridCell extends StatelessWidget {
  final String letter;
  final bool isSelected;
  final bool isLast;
  final Color wordColor;

  const _GridCell({
    required this.letter,
    required this.isSelected,
    required this.isLast,
    required this.wordColor,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 100),
      margin: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: isLast
            ? wordColor.withValues(alpha: 0.35)
            : isSelected
                ? wordColor.withValues(alpha: 0.15)
                : Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isSelected ? wordColor : Colors.white.withValues(alpha: 0.08),
          width: isSelected ? 2 : 1,
        ),
      ),
      child: Center(
        child: Text(
          letter,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w900,
            color: isSelected ? Colors.white : Colors.white70,
          ),
        ),
      ),
    );
  }
}

// ─── Line Painter ─────────────────────────────────────────────────────────────

class _LinePainter extends CustomPainter {
  final List<int> path;
  final double cellSize;
  final int cols;
  final Color color;

  _LinePainter({required this.path, required this.cellSize, required this.cols, required this.color});

  Offset _center(int index) {
    final row = index ~/ cols;
    final col = index % cols;
    return Offset((col + 0.5) * cellSize, (row + 0.5) * cellSize);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: 0.6)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    for (int i = 0; i < path.length - 1; i++) {
      canvas.drawLine(_center(path[i]), _center(path[i + 1]), paint);
    }
  }

  @override
  bool shouldRepaint(_LinePainter old) =>
      old.path != path || old.color != color;
}

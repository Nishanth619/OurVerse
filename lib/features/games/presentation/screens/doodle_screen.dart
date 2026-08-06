import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/doodle_repository.dart';
import '../../../../shared/providers/app_providers.dart';
import '../../../vibe/presentation/widgets/sync_status_chip.dart';
import '../../../../core/ads/ad_service.dart';

// Ã¢â€ â‚¬Ã¢â€ â‚¬Ã¢â€ â‚¬ Drawing Tool Ã¢â€ â‚¬Ã¢â€ â‚¬Ã¢â€ â‚¬Ã¢â€ â‚¬Ã¢â€ â‚¬Ã¢â€ â‚¬Ã¢â€ â‚¬Ã¢â€ â‚¬Ã¢â€ â‚¬Ã¢â€ â‚¬Ã¢â€ â‚¬Ã¢â€ â‚¬Ã¢â€ â‚¬Ã¢â€ â‚¬Ã¢â€ â‚¬Ã¢â€ â‚¬Ã¢â€ â‚¬Ã¢â€ â‚¬Ã¢â€ â‚¬Ã¢â€ â‚¬Ã¢â€ â‚¬Ã¢â€ â‚¬Ã¢â€ â‚¬Ã¢â€ â‚¬Ã¢â€ â‚¬Ã¢â€ â‚¬Ã¢â€ â‚¬Ã¢â€ â‚¬Ã¢â€ â‚¬Ã¢â€ â‚¬Ã¢â€ â‚¬Ã¢â€ â‚¬Ã¢â€ â‚¬Ã¢â€ â‚¬Ã¢â€ â‚¬Ã¢â€ â‚¬Ã¢â€ â‚¬Ã¢â€ â‚¬Ã¢â€ â‚¬Ã¢â€ â‚¬Ã¢â€ â‚¬Ã¢â€ â‚¬Ã¢â€ â‚¬Ã¢â€ â‚¬Ã¢â€ â‚¬Ã¢â€ â‚¬Ã¢â€ â‚¬Ã¢â€ â‚¬Ã¢â€ â‚¬Ã¢â€ â‚¬Ã¢â€ â‚¬Ã¢â€ â‚¬Ã¢â€ â‚¬Ã¢â€ â‚¬Ã¢â€ â‚¬Ã¢â€ â‚¬Ã¢â€ â‚¬Ã¢â€ â‚¬Ã¢â€ â‚¬Ã¢â€ â‚¬Ã¢â€ â‚¬Ã¢â€ â‚¬Ã¢â€ â‚¬

enum DrawingTool { select, freehand, line, rectangle, circle, eraser, fill }

const Map<DrawingTool, IconData> _kToolIcons = {
  DrawingTool.select:    Icons.pan_tool_alt_rounded,
  DrawingTool.freehand:  Icons.edit_rounded,
  DrawingTool.line:      Icons.horizontal_rule_rounded,
  DrawingTool.rectangle: Icons.crop_square_rounded,
  DrawingTool.circle:    Icons.circle_outlined,
  DrawingTool.eraser:    Icons.auto_fix_high_rounded,
  DrawingTool.fill:      Icons.format_color_fill_rounded,
};

const Map<DrawingTool, String> _kToolLabels = {
  DrawingTool.select:    'Select',
  DrawingTool.freehand:  'Pen',
  DrawingTool.line:      'Line',
  DrawingTool.rectangle: 'Rect',
  DrawingTool.circle:    'Circle',
  DrawingTool.eraser:    'Eraser',
  DrawingTool.fill:      'Fill',
};

// Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬ Color Palette Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬

const List<Color> _kPalette = [
  Color(0xFF000000), // Black
  Color(0xFF3A3A3A), // Dark grey
  Color(0xFF8E8E93), // Grey
  Color(0xFFFFFFFF), // White
  Color(0xFFFF3B30), // Red
  Color(0xFFFF9500), // Orange
  Color(0xFFFFCC02), // Yellow
  Color(0xFF34C759), // Green
  Color(0xFF30D158), // Mint
  Color(0xFF5AC8FA), // Sky
  Color(0xFF5B8AF5), // Blue
  Color(0xFF5856D6), // Indigo
  Color(0xFFAF52DE), // Purple
  Color(0xFFFF2D55), // Pink
  Color(0xFFE8647A), // Rose
  Color(0xFF6E4E37), // Brown
];

// Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬ Stroke Sizes Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬

const List<double> _kSizes = [2.0, 5.0, 10.0, 18.0];

// Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬ Screen Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬

class DoodleScreen extends ConsumerStatefulWidget {
  final String spaceId;
  final List<String> memberIds;
  final String deviceId;
  final String spaceType;

  const DoodleScreen({
    super.key,
    required this.spaceId,
    required this.memberIds,
    required this.deviceId,
    this.spaceType = 'couple',
  });

  @override
  ConsumerState<DoodleScreen> createState() => _DoodleScreenState();
}

class _DoodleScreenState extends ConsumerState<DoodleScreen> {
  // Ã¢â€â‚¬Ã¢â€â‚¬ Tool / Appearance state Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬
  DrawingTool _selectedTool = DrawingTool.freehand;
  Color _selectedColor = const Color(0xFF000000);
  double _strokeWidth = 5.0;
  // Fill color: true = filled shape
  bool _fillEnabled = false;

  // Ã¢â€â‚¬Ã¢â€â‚¬ Selection & Transform state Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬
  String? _selectedStrokeId;
  Offset? _dragStartPos;
  double _initialScale = 1.0;
  double _initialRotation = 0.0;
  Offset _initialOffset = Offset.zero;
  String? _activeTransformHandle; // 'move', 'resize', 'rotate'
  final List<DoodleStroke> _redoStack = [];
  final ValueNotifier<DoodleStroke?> _transformingStroke = ValueNotifier(null);
  // Confirmation overlay state
  bool _showingConfirmation = false;
  DoodleStroke? _snapshotBeforeTransform; // for cancel/revert

  // Ã¢â€â‚¬Ã¢â€â‚¬ Canvas state Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬
  List<DoodleStroke> _persistedStrokes = [];

  // Local stroke via ValueNotifier — only repaints canvas, not the whole screen
  final ValueNotifier<List<DoodlePoint>> _currentLocalStroke =
      ValueNotifier([]);

  // Partner's live stroke — ValueNotifier so RTDB updates never call setState
  final ValueNotifier<List<DoodlePoint>> _livePartnerStroke =
      ValueNotifier([]);

  // RTDB batching — prevents spamming the network on every frame
  Timer? _rtdbPushTimer;

  bool _partnerDrawing = false;

  late final DoodleRepository _repo;
  StreamSubscription<List<DoodleStroke>>? _strokesSub;
  StreamSubscription<List<DoodlePoint>>? _livePartnerSub;
  StreamSubscription<bool>? _presenceSub;

  String get _partnerId =>
      widget.memberIds.firstWhere((id) => id != widget.deviceId, orElse: () => '');

  String get _label => widget.spaceType == 'friends' ? 'Bestie' : 'Partner';

  // --------------------------------- Derived tool helpers ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

  /// The color actually painted.
  /// Eraser uses Colors.transparent as sentinel — _makePaint converts it to BlendMode.clear.
  Color get _effectiveColor =>
      _selectedTool == DrawingTool.eraser ? Colors.transparent : _selectedColor;

  /// The tool-type string sent to RTDB/Firestore.
  String get _currentToolType {
    switch (_selectedTool) {
      case DrawingTool.select:
        return 'select';
      case DrawingTool.freehand:
      case DrawingTool.eraser:
        return 'free';
      case DrawingTool.line:      return 'line';
      case DrawingTool.rectangle: return 'rect';
      case DrawingTool.circle:    return 'circle';
      case DrawingTool.fill:      return 'fill';
    }
  }

  /// Whether the current tool is a shape (not freehand/eraser/fill/select).
  bool get _isShape =>
      _selectedTool == DrawingTool.line ||
      _selectedTool == DrawingTool.rectangle ||
      _selectedTool == DrawingTool.circle;

  /// Whether the current tool draws freehand (vs a fixed shape).
  bool get _isFreehand =>
      _selectedTool == DrawingTool.freehand ||
      _selectedTool == DrawingTool.eraser;

  // Ã¢â€â‚¬Ã¢â€â‚¬ Lifecycle Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬

  late final PresenceRepository _presenceRepo;

  @override
  void initState() {
    super.initState();
    _repo = DoodleRepository();
    _subscribeToPersistedStrokes();
    _subscribeToLivePartnerStroke();
    _subscribeToPartnerPresence();
        _presenceRepo = ref.read(presenceRepositoryProvider);
    _presenceRepo.setPresent(widget.spaceId, 'doodle', widget.deviceId);
  }

  void _subscribeToPersistedStrokes() {
    int _lastStrokeCount = 0;
    _strokesSub = _repo.watchStrokes(widget.spaceId).listen((strokes) {
      if (!mounted) return;
      setState(() {
        _persistedStrokes = strokes;
        // If new strokes arrived that belong to the partner, it means they just
        // finished a stroke and persisted it to Firestore. At this point the
        // RTDB live-stroke node is being deleted, but the delete event may
        // arrive a few hundred ms later — causing the partner to see both the
        // live RTDB preview AND the Firestore stroke simultaneously (ghost lines).
        // Fix: eagerly clear the live stroke the moment the persisted stroke appears.
        if (strokes.length > _lastStrokeCount && _partnerId.isNotEmpty) {
          final newStrokes = strokes.skip(_lastStrokeCount);
          final hasPartnerStroke = newStrokes.any((s) => s.deviceId == _partnerId);
          if (hasPartnerStroke) {
            _livePartnerStroke.value = [];
          }
        }
        _lastStrokeCount = strokes.length;
      });
    });
  }

  void _subscribeToLivePartnerStroke() {
    if (_partnerId.isEmpty) return;
    _livePartnerSub =
        _repo.watchLiveStroke(widget.spaceId, _partnerId).listen((pts) {
      // Use the ValueNotifier directly — no setState, no full widget rebuild.
      // The painter's repaint listenable picks this up automatically.
      if (mounted) _livePartnerStroke.value = pts;
    });
  }

  void _subscribeToPartnerPresence() {
    if (_partnerId.isEmpty) return;
    _presenceSub =
        _repo.watchPartnerDrawing(widget.spaceId, _partnerId).listen((v) {
      if (mounted) setState(() => _partnerDrawing = v);
    });
  }

  @override
  void dispose() {
    _strokesSub?.cancel();
    _livePartnerSub?.cancel();
    _presenceSub?.cancel();
    _rtdbPushTimer?.cancel();
    _currentLocalStroke.dispose();
    _livePartnerStroke.dispose();
    _transformingStroke.dispose();
    _repo.setDrawing(widget.spaceId, widget.deviceId, false);
    _repo.clearLiveStroke(widget.spaceId, widget.deviceId);
    _presenceRepo.setAbsent(widget.spaceId, 'doodle', widget.deviceId);
    super.dispose();
  }

  // Ã¢â€â‚¬Ã¢â€â‚¬ Drawing events Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬


  void _onPanStart(DragStartDetails d) {
    // Fill tool — handled via onTapDown, not pan
    if (_selectedTool == DrawingTool.fill) return;

    if (_selectedTool == DrawingTool.select) {
      if (_selectedStrokeId != null) {
        final sIdx = _persistedStrokes.indexWhere((s) => s.id == _selectedStrokeId);
        if (sIdx != -1) {
          final s = _persistedStrokes[sIdx];
          final rb = s.bounds;
          final center = rb.center;

          // Compute the SAME world-space bounding box as the painter
          final corners = [rb.topLeft, rb.topRight, rb.bottomLeft, rb.bottomRight].map((c) {
            final dx = (c.dx - center.dx) * s.scale;
            final dy = (c.dy - center.dy) * s.scale;
            final cosR = math.cos(s.rotation);
            final sinR = math.sin(s.rotation);
            return Offset(
              center.dx + s.offsetX + dx * cosR - dy * sinR,
              center.dy + s.offsetY + dx * sinR + dy * cosR,
            );
          }).toList();

          final minX = corners.map((c) => c.dx).reduce(math.min);
          final minY = corners.map((c) => c.dy).reduce(math.min);
          final maxX = corners.map((c) => c.dx).reduce(math.max);
          final maxY = corners.map((c) => c.dy).reduce(math.max);
          final worldBounds = Rect.fromLTRB(minX - 10, minY - 10, maxX + 10, maxY + 10);

          final resizeHandle = Offset(worldBounds.right, worldBounds.bottom);
          final rotateHandle = Offset(worldBounds.center.dx, worldBounds.top - 28);

          if ((d.localPosition - rotateHandle).distance < 24) {
            _activeTransformHandle = 'rotate';
            _dragStartPos = d.localPosition;
            _initialRotation = s.rotation;
            _transformingStroke.value = s;
            return;
          }
          if ((d.localPosition - resizeHandle).distance < 24) {
            _activeTransformHandle = 'resize';
            _dragStartPos = d.localPosition;
            _initialScale = s.scale;
            _transformingStroke.value = s;
            return;
          }
        }
      }

      DoodleStroke? hitStroke;
      for (final s in _persistedStrokes.reversed) {
        if (s.hitTest(d.localPosition)) {
          hitStroke = s;
          break;
        }
      }
      
      setState(() {
        _selectedStrokeId = hitStroke?.id;
        _showingConfirmation = false;
        if (hitStroke != null) {
          _dragStartPos = d.localPosition;
          _initialScale = hitStroke.scale;
          _initialRotation = hitStroke.rotation;
          _initialOffset = Offset(hitStroke.offsetX, hitStroke.offsetY);
          _activeTransformHandle = 'move';
          _snapshotBeforeTransform = hitStroke;
          _transformingStroke.value = hitStroke;
        } else {
          _snapshotBeforeTransform = null;
        }
      });
      return;
    }

    // Clear any leftover batched live points from a previous stroke so they
    // don't get mixed into this new stroke's RTDB stream.
    _rtdbPushTimer?.cancel();
    _rtdbPushTimer = null;
    // Also clear the RTDB node immediately at stroke start so the partner
    // never sees stale points from a previous stroke.
    _repo.clearLiveStroke(widget.spaceId, widget.deviceId);

    final pt = _makePoint(d.localPosition, isStart: true);
    _currentLocalStroke.value = [pt];
    _repo.setDrawing(widget.spaceId, widget.deviceId, true);
    _scheduleRtdbFlush();
  }

  void _onPanUpdate(DragUpdateDetails d) {
    if (_selectedTool == DrawingTool.select) {
      if (_selectedStrokeId != null && _dragStartPos != null) {
        final strokeIndex = _persistedStrokes.indexWhere((s) => s.id == _selectedStrokeId);
        if (strokeIndex == -1) return;
        final s = _persistedStrokes[strokeIndex];
        
        // The shape center in screen space (accounting for existing offset, ignoring rotation for simplicity)
        final shapeCenter = Offset(
          s.bounds.center.dx + s.offsetX,
          s.bounds.center.dy + s.offsetY,
        );

        if (_activeTransformHandle == 'move') {
          final delta = d.localPosition - _dragStartPos!;
          _transformingStroke.value = s.copyWith(
            offsetX: _initialOffset.dx + delta.dx,
            offsetY: _initialOffset.dy + delta.dy,
          );
        } else if (_activeTransformHandle == 'resize') {
          // Ratio of current distance from center vs initial distance from center
          final initialDist = (_dragStartPos! - shapeCenter).distance;
          final currentDist = (d.localPosition - shapeCenter).distance;
          if (initialDist > 1) {
            final newScale = (_initialScale * currentDist / initialDist).clamp(0.1, 15.0);
            _transformingStroke.value = s.copyWith(scale: newScale);
          }
        } else if (_activeTransformHandle == 'rotate') {
          final startAngle = math.atan2(
            _dragStartPos!.dy - shapeCenter.dy,
            _dragStartPos!.dx - shapeCenter.dx,
          );
          final currentAngle = math.atan2(
            d.localPosition.dy - shapeCenter.dy,
            d.localPosition.dx - shapeCenter.dx,
          );
          _transformingStroke.value = s.copyWith(
            rotation: _initialRotation + (currentAngle - startAngle),
          );
        }
      }
      return;
    }

    final pt = _makePoint(d.localPosition, isStart: false);

    if (_isFreehand) {
      _currentLocalStroke.value = [..._currentLocalStroke.value, pt];
    } else {
      final start = _currentLocalStroke.value.isNotEmpty
          ? _currentLocalStroke.value.first
          : pt;
      _currentLocalStroke.value = [start, pt];
    }

    _scheduleRtdbFlush();
  }

  void _onPanEnd(DragEndDetails _) {
    if (_selectedTool == DrawingTool.select) {
      if (_selectedStrokeId != null && _activeTransformHandle != null && _transformingStroke.value != null) {
        // Apply the transform to _persistedStrokes optimistically
        final transformed = _transformingStroke.value!;
        final strokeIndex = _persistedStrokes.indexWhere((s) => s.id == _selectedStrokeId);
        if (strokeIndex != -1) {
          setState(() {
            _persistedStrokes[strokeIndex] = transformed;
            _showingConfirmation = true;
          });
        }
      }
      _dragStartPos = null;
      _activeTransformHandle = null;
      _transformingStroke.value = null;
      return;
    }

    // Fill tool — handled via onTapDown, ignore pan
    if (_selectedTool == DrawingTool.fill) return;

    // Discard any unpushed live points immediately — the stroke is done.
    // The clearLiveStroke() below will wipe the RTDB node, so there is no
    // point pushing stale buffered points that would arrive after the clear.
    _rtdbPushTimer?.cancel();
    _rtdbPushTimer = null;


    final strokeId = _repo.generateStrokeId(widget.spaceId);
    final stroke = DoodleStroke(
      id: strokeId,
      points: List.of(_currentLocalStroke.value),
      deviceId: widget.deviceId,
      fillColorValue: (_fillEnabled && _isShape)
          ? _selectedColor.toARGB32()
          : null,
    );
    setState(() {
      _persistedStrokes = [..._persistedStrokes, stroke];
      _redoStack.clear();
      _selectedStrokeId = _isShape ? strokeId : null;
    });

    _currentLocalStroke.value = [];

    // Clear RTDB immediately so the partner's live preview disappears the
    // moment this stroke ends — do NOT defer this inside .then(), because
    // the Firestore write takes ~200-400 ms and the user may start a new
    // stroke before it finishes, causing the deferred clear to wipe the
    // next stroke's live data (the ghost-line race condition).
    _repo.clearLiveStroke(widget.spaceId, widget.deviceId);
    _repo.setDrawing(widget.spaceId, widget.deviceId, false);

    // Persist to Firestore — fire and forget. The partner's
    // _subscribeToPersistedStrokes will eagerly clear _livePartnerStroke
    // when this snapshot arrives, so ghost lines are still prevented.
    _repo.persistStroke(widget.spaceId, stroke);
  }

  /// Called when the user taps the canvas with the Fill (bucket) tool.
  void _onFillTap(TapDownDetails d) {
    if (_selectedTool != DrawingTool.fill) return;
    final strokeId = _repo.generateStrokeId(widget.spaceId);
    // A fill stroke has exactly 1 point. The painter draws a full canvas rect.
    final pt = DoodlePoint(
      x: d.localPosition.dx,
      y: d.localPosition.dy,
      isStart: true,
      colorValue: _selectedColor.toARGB32(),
      strokeWidth: 0,
      deviceId: widget.deviceId,
      toolType: 'fill',
    );
    final stroke = DoodleStroke(
      id: strokeId,
      points: [pt],
      deviceId: widget.deviceId,
    );
    setState(() {
      _persistedStrokes = [..._persistedStrokes, stroke];
      _redoStack.clear();
    });
    _repo.persistStroke(widget.spaceId, stroke);
  }

  void _confirmTransform() {
    if (_selectedStrokeId == null) return;
    final strokeIndex = _persistedStrokes.indexWhere((s) => s.id == _selectedStrokeId);
    if (strokeIndex == -1) return;
    final confirmed = _persistedStrokes[strokeIndex];
    setState(() {
      _showingConfirmation = false;
      _selectedStrokeId = null; // Deselect shape after confirm
    });
    _repo.updateStrokeTransform(
      widget.spaceId, confirmed.id,
      confirmed.scale, confirmed.rotation, confirmed.offsetX, confirmed.offsetY,
    );
    _snapshotBeforeTransform = null;
  }

  void _cancelTransform() {
    if (_snapshotBeforeTransform == null || _selectedStrokeId == null) return;
    final strokeIndex = _persistedStrokes.indexWhere((s) => s.id == _selectedStrokeId);
    if (strokeIndex == -1) return;
    setState(() {
      _persistedStrokes[strokeIndex] = _snapshotBeforeTransform!;
      _showingConfirmation = false;
      _selectedStrokeId = null; // Deselect shape after cancel
    });
    _snapshotBeforeTransform = null;
  }

  void _undo() {
    final myStrokes = _persistedStrokes.where((s) => s.deviceId == widget.deviceId).toList();
    if (myStrokes.isEmpty) return;

    final lastStroke = myStrokes.last;

    setState(() {
      _persistedStrokes.remove(lastStroke);
      _redoStack.add(lastStroke);
    });

    _repo.undoStroke(widget.spaceId, lastStroke.id);
  }

  void _redo() {
    if (_redoStack.isEmpty) return;
    
    final stroke = _redoStack.removeLast();
    
    setState(() {
      _persistedStrokes.add(stroke);
    });

    _repo.redoStroke(widget.spaceId, stroke.id);
  }


  DoodlePoint _makePoint(Offset pos, {required bool isStart}) {
    final isEraser = _selectedTool == DrawingTool.eraser;
    return DoodlePoint(
      x: pos.dx,
      y: pos.dy,
      isStart: isStart,
      colorValue: _effectiveColor.toARGB32(),
      strokeWidth: isEraser
          ? (_strokeWidth * 3).clamp(12.0, 48.0)
          : _strokeWidth,
      deviceId: widget.deviceId,
      toolType: _currentToolType,
    );
  }

  // Ã¢â€â‚¬Ã¢â€â‚¬ RTDB throttle Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬

  /// Schedules a throttled push of the CURRENT full stroke to RTDB.
  /// Using a timer instead of pushing on every frame keeps network usage low.
  void _scheduleRtdbFlush() {
    if (_rtdbPushTimer == null || !_rtdbPushTimer!.isActive) {
      _rtdbPushTimer = Timer(const Duration(milliseconds: 50), _flushRtdbPush);
    }
  }

  /// Replaces the RTDB live stroke node with the current full stroke.
  /// Using set() (not push()) guarantees only the current stroke is stored —
  /// no accumulation across strokes, no ghost blobs.
  void _flushRtdbPush() {
    _rtdbPushTimer = null;
    final pts = _currentLocalStroke.value;
    if (pts.isEmpty) return;
    _repo.pushLiveStroke(widget.spaceId, widget.deviceId, pts);
  }

  // Ã¢â€â‚¬Ã¢â€â‚¬ Clear canvas Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬

  Future<void> _clearCanvas() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const FittedBox(fit: BoxFit.scaleDown, child: Text('Clear Canvas?')),
        content: const Text(
            'This wipes the canvas for both of you. Are you sure?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Clear',
                  style: TextStyle(color: Colors.redAccent))),
        ],
      ),
    );
    if (confirmed == true) {
      _currentLocalStroke.value = [];
      _livePartnerStroke.value = [];
      setState(() {
        _persistedStrokes.clear();
      });
      await _repo.clearCanvas(widget.spaceId);
      AdService.instance.showInterstitialIfReady();
    }
  }

  // Ã¢â€â‚¬Ã¢â€â‚¬ Build Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬

  @override
  Widget build(BuildContext context) {
    final partnerPresentAsync = _partnerId.isEmpty
        ? const AsyncData(false)
        : ref.watch(featurePresenceProvider(
            (spaceId: widget.spaceId, featureId: 'doodle', partnerId: _partnerId)));
    final partnerPresent = partnerPresentAsync.valueOrNull ?? false;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Color(0xFF2A1020)),
        title: const Text(
          'Doodle with Me ✨',
          style: TextStyle(
              color: Color(0xFF2A1020), fontWeight: FontWeight.w800),
        ),
        actions: [
          Center(
            child: SyncStatusChip(
              state: partnerPresent ? SyncState.inSync : SyncState.partnerLeft,
            ),
          ),
          IconButton(
            icon: Icon(Icons.undo_rounded,
                color: _persistedStrokes.any((s) => s.deviceId == widget.deviceId)
                    ? const Color(0xFF8B5E6A)
                    : const Color(0xFFE5D6DB)),
            onPressed: _undo,
            tooltip: 'Undo',
          ),
          IconButton(
            icon: Icon(Icons.redo_rounded,
                color: _redoStack.isNotEmpty
                    ? const Color(0xFF8B5E6A)
                    : const Color(0xFFE5D6DB)),
            onPressed: _redo,
            tooltip: 'Redo',
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded,
                color: Color(0xFF8B5E6A)),
            onPressed: _clearCanvas,
            tooltip: 'Clear Canvas',
          ),
        ],
      ),
      body: Column(
        children: [
          // Ã¢â€â‚¬Ã¢â€â‚¬ Canvas Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬
          Expanded(
            child: Stack(
              children: [
                // Drawing surface
                SizedBox.expand(
                  child: GestureDetector(
                    onPanStart: _onPanStart,
                    onPanUpdate: _onPanUpdate,
                    onPanEnd: _onPanEnd,
                    onTapDown: _onFillTap,
                    child: RepaintBoundary(
                      child: CustomPaint(
                        painter: _DoodlePainter(
                          persistedStrokes: _persistedStrokes,
                          currentLocalStroke: _currentLocalStroke,
                          livePartnerStroke: _livePartnerStroke,
                          selectedStrokeId: _selectedStrokeId,
                          transformingStroke: _transformingStroke,
                        ),
                      ),
                    ),
                  ),
                ),

                // Partner drawing indicator
                if (_partnerDrawing)
                  Positioned(
                    top: 12,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF5B8AF5).withValues(alpha: 0.9),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF5B8AF5)
                                  .withValues(alpha: 0.3),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            )
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 10,
                              height: 10,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                    Colors.white),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text('$_label is drawing...',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                    ),
                  ),

                // Ã¢â€â‚¬Ã¢â€â‚¬ Placement Confirmation Overlay Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬
                if (_showingConfirmation)
                  Positioned(
                    bottom: 16,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: AnimatedScale(
                        scale: _showingConfirmation ? 1.0 : 0.8,
                        duration: const Duration(milliseconds: 180),
                        curve: Curves.easeOutBack,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1C1C1E).withValues(alpha: 0.92),
                            borderRadius: BorderRadius.circular(32),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.25),
                                blurRadius: 20,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Cancel button
                              _ConfirmButton(
                                icon: Icons.close_rounded,
                                label: 'Cancel',
                                color: const Color(0xFFFF453A),
                                onTap: _cancelTransform,
                              ),
                              const SizedBox(width: 4),
                              // Confirm button
                              _ConfirmButton(
                                icon: Icons.check_rounded,
                                label: 'Done',
                                color: const Color(0xFF30D158),
                                onTap: _confirmTransform,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // Ã¢â€â‚¬Ã¢â€â‚¬ Bottom Toolbar Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬
          _buildToolbar(),
        ],
      ),
    );
  }

  // Ã¢â€â‚¬Ã¢â€â‚¬ Toolbar Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬

  void _showSizePicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Brush Size', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF2A1020))),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: _kSizes.map((size) => GestureDetector(
                    onTap: () {
                      setState(() => _strokeWidth = size);
                      Navigator.pop(context);
                    },
                    child: Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        color: _strokeWidth == size ? const Color(0xFFF0E6EA) : Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _strokeWidth == size ? const Color(0xFF8B5E6A) : Colors.transparent,
                          width: 2,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Container(
                        width: size,
                        height: size,
                        decoration: BoxDecoration(
                          color: _effectiveColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  )).toList(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Show the shapes picker bottom sheet
  void _showShapesPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Shapes',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF2A1020))),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    DrawingTool.line,
                    DrawingTool.rectangle,
                    DrawingTool.circle,
                  ].map((t) {
                    final selected = _selectedTool == t;
                    const accent = Color(0xFFE8647A);
                    return GestureDetector(
                      onTap: () {
                        setState(() => _selectedTool = t);
                        Navigator.pop(ctx);
                      },
                      child: Column(
                        children: [
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            width: 64,
                            height: 64,
                            decoration: BoxDecoration(
                              color: selected
                                  ? accent.withValues(alpha: 0.12)
                                  : const Color(0xFFF5F0F2),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: selected
                                    ? accent
                                    : Colors.transparent,
                                width: 2,
                              ),
                            ),
                            child: Icon(
                              _kToolIcons[t]!,
                              size: 30,
                              color: selected ? accent : const Color(0xFF8B7080),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _kToolLabels[t]!,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: selected ? accent : const Color(0xFF8B7080),
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildToolbar() {
    final bottom = MediaQuery.of(context).padding.bottom;
    // Determine if a shape tool is currently active
    final shapeActive = _isShape;
    const accent = Color(0xFFE8647A);

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFF0E6EA), width: 1.5)),
      ),
      padding: EdgeInsets.fromLTRB(12, 12, 12, 12 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Ã¢â€â‚¬Ã¢â€â‚¬ Row 1: Tool tiles Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Select
              _ToolTile(
                icon: Icons.pan_tool_alt_rounded,
                label: 'Select',
                selected: _selectedTool == DrawingTool.select,
                onTap: () => setState(() => _selectedTool = DrawingTool.select),
              ),
              // Pen
              _ToolTile(
                icon: Icons.edit_rounded,
                label: 'Pen',
                selected: _selectedTool == DrawingTool.freehand,
                onTap: () => setState(() => _selectedTool = DrawingTool.freehand),
              ),
              // Shapes — opens picker modal, shows active shape icon
              _ToolTile(
                icon: shapeActive
                    ? _kToolIcons[_selectedTool]!
                    : Icons.category_rounded,
                label: 'Shapes',
                selected: shapeActive,
                onTap: _showShapesPicker,
              ),
              // Fill (Bucket)
              _ToolTile(
                icon: Icons.format_color_fill_rounded,
                label: 'Fill',
                selected: _selectedTool == DrawingTool.fill,
                onTap: () => setState(() => _selectedTool = DrawingTool.fill),
              ),
              // Eraser
              _ToolTile(
                icon: Icons.auto_fix_high_rounded,
                label: 'Eraser',
                selected: _selectedTool == DrawingTool.eraser,
                onTap: () => setState(() => _selectedTool = DrawingTool.eraser),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Ã¢â€â‚¬Ã¢â€â‚¬ Row 2: Option tiles (Brush Size + Shape Fill) Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬
          Row(
            children: [
              // Brush Size tile
              GestureDetector(
                onTap: _showSizePicker,
                child: _OptionTile(
                  child: Center(
                    child: Container(
                      width: (_strokeWidth * 0.9).clamp(4.0, 20.0),
                      height: (_strokeWidth * 0.9).clamp(4.0, 20.0),
                      decoration: const BoxDecoration(
                        color: Color(0xFF2A1020),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                  label: 'Size',
                ),
              ),
              const SizedBox(width: 8),

              // Shape Fill tile — only fully enabled for shape tools
              GestureDetector(
                onTap: () {
                  if (_isShape) setState(() => _fillEnabled = !_fillEnabled);
                },
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 200),
                  opacity: _isShape ? 1.0 : 0.35,
                  child: _OptionTile(
                    active: _fillEnabled && _isShape,
                    activeColor: accent,
                    child: Icon(
                      _fillEnabled && _isShape
                          ? Icons.format_color_fill_rounded
                          : Icons.format_color_reset_rounded,
                      color: _fillEnabled && _isShape
                          ? accent
                          : const Color(0xFF8B7080),
                      size: 22,
                    ),
                    label: 'Shape Fill',
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Ã¢â€â‚¬Ã¢â€â‚¬ Row 3: Color palette Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬
          SizedBox(
            height: 34,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _kPalette.length,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (_, i) {
                final c = _kPalette[i];
                final isSelected = _selectedColor == c &&
                    _selectedTool != DrawingTool.eraser;
                return GestureDetector(
                  onTap: () => setState(() {
                    _selectedColor = c;
                    if (_selectedTool == DrawingTool.eraser) {
                      _selectedTool = DrawingTool.freehand;
                    }
                  }),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: c,
                      border: Border.all(
                        color: isSelected
                            ? const Color(0xFFE8647A)
                            : c == Colors.white
                                ? const Color(0xFFCCC0C4)
                                : Colors.transparent,
                        width: isSelected ? 2.5 : 1,
                      ),
                      boxShadow: isSelected
                          ? [
                              BoxShadow(
                                color: c.withValues(alpha: 0.5),
                                blurRadius: 6,
                                spreadRadius: 1,
                              )
                            ]
                          : null,
                    ),
                    child: isSelected
                        ? Icon(
                            Icons.check_rounded,
                            size: 16,
                            color: c == Colors.white || c == Colors.yellow
                                ? Colors.black
                                : Colors.white,
                          )
                        : null,
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


// Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬ Tool Tile Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬
/// A tall, labeled icon tile used for the main tools row in the bottom bar.
class _ToolTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ToolTile({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFFE8647A);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: selected ? accent.withValues(alpha: 0.10) : const Color(0xFFF5F0F2),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? accent.withValues(alpha: 0.6) : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 22,
              color: selected ? accent : const Color(0xFF8B7080),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w600,
                color: selected ? accent : const Color(0xFF8B7080),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬ Option Tile Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬
/// A small square tile for option controls (brush size, shape fill).
class _OptionTile extends StatelessWidget {
  final Widget child;
  final String label;
  final bool active;
  final Color activeColor;

  const _OptionTile({
    required this.child,
    required this.label,
    this.active = false,
    this.activeColor = const Color(0xFFE8647A),
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: active ? activeColor.withValues(alpha: 0.12) : const Color(0xFFF0EBEF),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: active ? activeColor.withValues(alpha: 0.6) : const Color(0xFFCCC0C4).withValues(alpha: 0.5),
              width: 1.5,
            ),
          ),
          child: child,
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w600,
            color: active ? activeColor : const Color(0xFF8B7080),
          ),
        ),
      ],
    );
  }
}

extension DoodleStrokeBounds on DoodleStroke {
  Rect get bounds {
    if (points.isEmpty) return Rect.zero;
    if (points.length == 1) return Rect.fromCircle(center: Offset(points[0].x, points[0].y), radius: points[0].strokeWidth);
    
    final tt = points.last.toolType;
    if (tt == 'rect' || tt == 'circle' || tt == 'line') {
      final p1 = points.first;
      final p2 = points.last;
      return Rect.fromPoints(Offset(p1.x, p1.y), Offset(p2.x, p2.y));
    }
    
    double minX = double.infinity, minY = double.infinity;
    double maxX = double.negativeInfinity, maxY = double.negativeInfinity;
    for (final p in points) {
      if (p.x < minX) minX = p.x;
      if (p.y < minY) minY = p.y;
      if (p.x > maxX) maxX = p.x;
      if (p.y > maxY) maxY = p.y;
    }
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  bool hitTest(Offset pos) {
    if (points.isEmpty) return false;
    final tt = points.first.toolType;
    if (tt != 'rect' && tt != 'circle' && tt != 'line') return false; // ONLY SHAPES

    final b = bounds;
    final center = b.center;
    
    double px = pos.dx - center.dx - offsetX;
    double py = pos.dy - center.dy - offsetY;
    
    final cosR = math.cos(-rotation);
    final sinR = math.sin(-rotation);
    double rx = px * cosR - py * sinR;
    double ry = px * sinR + py * cosR;
    
    rx /= scale;
    ry /= scale;
    
    rx += center.dx;
    ry += center.dy;
    
    return b.inflate(20.0).contains(Offset(rx, ry));
  }
}

// Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬ CustomPainter Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬

class _DoodlePainter extends CustomPainter {
  final List<DoodleStroke> persistedStrokes;
  final ValueNotifier<List<DoodlePoint>> currentLocalStroke;
  final ValueNotifier<List<DoodlePoint>> livePartnerStroke;
  final String? selectedStrokeId;
  final ValueNotifier<DoodleStroke?>? transformingStroke;

  _DoodlePainter({
    required this.persistedStrokes,
    required this.currentLocalStroke,
    required this.livePartnerStroke,
    this.selectedStrokeId,
    this.transformingStroke,
  }) : super(
          repaint: Listenable.merge([
            currentLocalStroke,
            livePartnerStroke,
            if (transformingStroke != null) transformingStroke,
          ]),
        );

  @override
  void paint(Canvas canvas, Size size) {
    // saveLayer is required for BlendMode.clear (eraser) to composite against the layer.
    canvas.saveLayer(Rect.fromLTWH(0, 0, size.width, size.height), Paint());

    // 1. History — draw fill strokes first (they act as background layers)
    for (final stroke in persistedStrokes) {
      if (stroke.points.isEmpty) continue;
      if (stroke.points.first.toolType == 'fill') {
        // Full canvas fill layer
        final fillPaint = Paint()
          ..color = Color(stroke.points.first.colorValue)
          ..style = PaintingStyle.fill;
        canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), fillPaint);
      }
    }

    // 2. History — regular strokes on top of fills
    for (final stroke in persistedStrokes) {
      if (stroke.points.isEmpty) continue;
      if (stroke.points.first.toolType == 'fill') continue; // already drawn
      if (transformingStroke != null && transformingStroke!.value?.id == stroke.id) continue;
      _drawStroke(canvas, stroke, isSelected: stroke.id == selectedStrokeId);
    }
    
    // Transforming stroke (draw over history)
    if (transformingStroke != null && transformingStroke!.value != null) {
      _drawStroke(canvas, transformingStroke!.value!, isSelected: true);
    }

    // 3. Current local stroke (via ValueNotifier - no setState needed)
    _drawStroke(canvas, DoodleStroke(id: '', points: currentLocalStroke.value, deviceId: ''));

    // 4. Partner's live stroke from RTDB (via ValueNotifier — no setState)
    _drawStroke(canvas, DoodleStroke(id: '', points: livePartnerStroke.value, deviceId: ''));


    canvas.restore();
  }

  void _drawStroke(Canvas canvas, DoodleStroke stroke, {bool isSelected = false}) {
    if (stroke.points.isEmpty) return;
    final toolType = stroke.points.first.toolType;

    canvas.save();

    final rawBounds = stroke.bounds;
    final center = rawBounds.center;

    // Apply transform: translate to center, rotate, scale, translate back
    canvas.translate(center.dx + stroke.offsetX, center.dy + stroke.offsetY);
    canvas.rotate(stroke.rotation);
    canvas.scale(stroke.scale);
    canvas.translate(-center.dx, -center.dy);

    if (toolType == 'free') {
      _drawFreehand(canvas, stroke.points);
    } else if (stroke.points.length >= 2) {
      _drawShape(canvas, toolType, stroke, stroke.points.first, stroke.points.last);
    }

    canvas.restore(); // ← Back to world space before drawing overlay

    // Only draw selection overlay for shapes (not freehand)
    if (isSelected && toolType != 'free') {
      // Compute the WORLD-SPACE bounding box of the transformed shape
      // by computing all 4 corners and inflating
      final corners = [
        rawBounds.topLeft,
        rawBounds.topRight,
        rawBounds.bottomLeft,
        rawBounds.bottomRight,
      ].map((c) {
        // Rotate and scale each corner around the center
        final dx = (c.dx - center.dx) * stroke.scale;
        final dy = (c.dy - center.dy) * stroke.scale;
        final cosR = math.cos(stroke.rotation);
        final sinR = math.sin(stroke.rotation);
        return Offset(
          center.dx + stroke.offsetX + dx * cosR - dy * sinR,
          center.dy + stroke.offsetY + dx * sinR + dy * cosR,
        );
      }).toList();

      double minX = corners.map((c) => c.dx).reduce(math.min);
      double minY = corners.map((c) => c.dy).reduce(math.min);
      double maxX = corners.map((c) => c.dx).reduce(math.max);
      double maxY = corners.map((c) => c.dy).reduce(math.max);
      final worldBounds = Rect.fromLTRB(minX - 10, minY - 10, maxX + 10, maxY + 10);

      final selectionPaint = Paint()
        ..color = const Color(0xFF5B8AF5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8;

      canvas.drawRect(worldBounds, selectionPaint);

      // Ã¢â€â‚¬Ã¢â€â‚¬ Resize handle (bottom-right) Ã¢â€â‚¬Ã¢â€â‚¬
      final resizeCenter = Offset(worldBounds.right, worldBounds.bottom);
      canvas.drawCircle(resizeCenter, 8, Paint()..color = const Color(0xFF5B8AF5)..style = PaintingStyle.fill);
      canvas.drawCircle(resizeCenter, 8, Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 2);

      // Ã¢â€â‚¬Ã¢â€â‚¬ Rotate handle (top-center) Ã¢â€â‚¬Ã¢â€â‚¬
      final rotateHandlePos = Offset(worldBounds.center.dx, worldBounds.top - 28);
      canvas.drawLine(
        Offset(worldBounds.center.dx, worldBounds.top),
        rotateHandlePos,
        Paint()..color = const Color(0xFF34C759)..strokeWidth = 1.8..style = PaintingStyle.stroke,
      );
      canvas.drawCircle(rotateHandlePos, 8, Paint()..color = const Color(0xFF34C759)..style = PaintingStyle.fill);
      canvas.drawCircle(rotateHandlePos, 8, Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 2);
    }
  }

  // Draws a smooth freehand path through all points.
  void _drawFreehand(Canvas canvas, List<DoodlePoint> points) {
    Path? path;
    Paint? paint;

    for (final pt in points) {
      if (pt.isStart || path == null) {
        if (path != null && paint != null) canvas.drawPath(path, paint);
        path = Path()..moveTo(pt.x, pt.y);
        paint = _makePaint(Color(pt.colorValue), pt.strokeWidth);
      } else {
        path.lineTo(pt.x, pt.y);
      }
    }

    if (path != null && paint != null) canvas.drawPath(path, paint);
  }

  // Renders a geometric shape using only start and end points.
  void _drawShape(Canvas canvas, String toolType, DoodleStroke stroke,
      DoodlePoint start, DoodlePoint end) {
    final paint = _makePaint(Color(start.colorValue), start.strokeWidth);
    final s = Offset(start.x, start.y);
    final e = Offset(end.x, end.y);
    
    Paint? fillPaint;
    if (stroke.fillColorValue != null) {
      fillPaint = Paint()
        ..color = Color(stroke.fillColorValue!)
        ..style = PaintingStyle.fill;
    }

    switch (toolType) {
      case 'line':
        canvas.drawLine(s, e, paint);
        // Draw arrow cap for line tool
        _drawArrowHead(canvas, s, e, paint);
        break;
      case 'rect':
        final rrect = RRect.fromRectAndRadius(
          Rect.fromPoints(s, e),
          const Radius.circular(3),
        );
        if (fillPaint != null) canvas.drawRRect(rrect, fillPaint);
        canvas.drawRRect(rrect, paint);
        break;
      case 'circle':
        final rect = Rect.fromPoints(s, e);
        if (fillPaint != null) canvas.drawOval(rect, fillPaint);
        canvas.drawOval(rect, paint);
        break;
    }
  }

  // Draws a small arrowhead at the end of a line.
  void _drawArrowHead(Canvas canvas, Offset start, Offset end, Paint paint) {
    const arrowSize = 12.0;
    final angle = math.atan2(end.dy - start.dy, end.dx - start.dx);
    final arrowPath = Path()
      ..moveTo(end.dx, end.dy)
      ..lineTo(
        end.dx - arrowSize * math.cos(angle - 0.4),
        end.dy - arrowSize * math.sin(angle - 0.4),
      )
      ..moveTo(end.dx, end.dy)
      ..lineTo(
        end.dx - arrowSize * math.cos(angle + 0.4),
        end.dy - arrowSize * math.sin(angle + 0.4),
      );
    canvas.drawPath(arrowPath, paint);
  }

  Paint _makePaint(Color color, double strokeWidth) {
    final paint = Paint()
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke
      ..isAntiAlias = true;

    // Transparent color is the eraser sentinel — use BlendMode.clear to truly erase pixels.
    if (color.a == 0) {
      paint.blendMode = BlendMode.clear;
    } else {
      paint.color = color;
    }
    return paint;
  }

  @override
  bool shouldRepaint(_DoodlePainter old) =>
      old.persistedStrokes != persistedStrokes ||
      old.livePartnerStroke != livePartnerStroke ||
      old.selectedStrokeId != selectedStrokeId;
}

class _ConfirmButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ConfirmButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        splashColor: color.withValues(alpha: 0.2),
        highlightColor: color.withValues(alpha: 0.1),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

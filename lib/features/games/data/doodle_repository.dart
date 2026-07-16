import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart';

// ─── Date Key ────────────────────────────────────────────────────────────────

String _todayKey() {
  final now = DateTime.now();
  return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
}

// ─── Doodle Point Model ──────────────────────────────────────────────────────

class DoodlePoint {
  final double x;
  final double y;
  final bool isStart;   // true = start of new stroke, false = continuation
  final int colorValue;
  final double strokeWidth;
  final String deviceId;
  /// Tool type: 'free' | 'line' | 'rect' | 'circle'
  final String toolType;

  const DoodlePoint({
    required this.x,
    required this.y,
    required this.isStart,
    required this.colorValue,
    required this.strokeWidth,
    required this.deviceId,
    this.toolType = 'free',
  });

  Map<String, dynamic> toMap() => {
        'x': x,
        'y': y,
        'isStart': isStart,
        'color': colorValue,
        'sw': strokeWidth,
        'did': deviceId,
        'tt': toolType,
      };

  factory DoodlePoint.fromMap(Map<String, dynamic> m) => DoodlePoint(
        x: (m['x'] as num).toDouble(),
        y: (m['y'] as num).toDouble(),
        isStart: m['isStart'] as bool? ?? false,
        colorValue: m['color'] as int? ?? 0xFF000000,
        strokeWidth: (m['sw'] as num?)?.toDouble() ?? 4.0,
        deviceId: m['did'] as String? ?? '',
        toolType: m['tt'] as String? ?? 'free',
      );
}

// ─── Doodle Stroke Model (completed stroke stored in Firestore) ───────────────

class DoodleStroke {
  final String id;
  final List<DoodlePoint> points;
  final String deviceId;
  final bool isDeleted;
  final double scale;
  final double rotation;
  final double offsetX;
  final double offsetY;
  /// Null = no fill (stroke only). Set to a color value to fill the shape.
  final int? fillColorValue;

  const DoodleStroke({
    required this.id,
    required this.points,
    required this.deviceId,
    this.isDeleted = false,
    this.scale = 1.0,
    this.rotation = 0.0,
    this.offsetX = 0.0,
    this.offsetY = 0.0,
    this.fillColorValue,
  });

  Map<String, dynamic> toMap() => {
        'pts': points.map((p) => p.toMap()).toList(),
        'did': deviceId,
        'del': isDeleted,
        's': scale,
        'r': rotation,
        'ox': offsetX,
        'oy': offsetY,
        if (fillColorValue != null) 'fc': fillColorValue,
      };

  factory DoodleStroke.fromMap(String id, Map<String, dynamic> m) {
    final rawPts = m['pts'] as List<dynamic>? ?? [];
    return DoodleStroke(
      id: id,
      points: rawPts
          .map((e) => DoodlePoint.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList(),
      deviceId: m['did'] as String? ?? '',
      isDeleted: m['del'] as bool? ?? false,
      scale: (m['s'] as num?)?.toDouble() ?? 1.0,
      rotation: (m['r'] as num?)?.toDouble() ?? 0.0,
      offsetX: (m['ox'] as num?)?.toDouble() ?? 0.0,
      offsetY: (m['oy'] as num?)?.toDouble() ?? 0.0,
      fillColorValue: m['fc'] as int?,
    );
  }

  /// Returns a copy of this stroke with the given fields replaced.
  DoodleStroke copyWith({
    String? id,
    List<DoodlePoint>? points,
    String? deviceId,
    bool? isDeleted,
    double? scale,
    double? rotation,
    double? offsetX,
    double? offsetY,
    int? fillColorValue,
    bool clearFill = false,
  }) {
    return DoodleStroke(
      id: id ?? this.id,
      points: points ?? this.points,
      deviceId: deviceId ?? this.deviceId,
      isDeleted: isDeleted ?? this.isDeleted,
      scale: scale ?? this.scale,
      rotation: rotation ?? this.rotation,
      offsetX: offsetX ?? this.offsetX,
      offsetY: offsetY ?? this.offsetY,
      fillColorValue: clearFill ? null : (fillColorValue ?? this.fillColorValue),
    );
  }
}

// ─── Doodle Repository ───────────────────────────────────────────────────────
//
// TWO-TIER SYNC ARCHITECTURE:
//
//   Layer 1 — RTDB (Firebase Realtime Database)
//     Path: doodles/{spaceId}/live/{deviceId}
//     Purpose: Stream individual points with ~50ms latency while drawing.
//     Data is EPHEMERAL — cleared when the stroke ends.
//
//   Layer 2 — Firestore
//     Path: spaces/{spaceId}/doodles/{date}/strokes (subcollection)
//     Purpose: Persist completed strokes for canvas replay on load.
//     Data is PERMANENT until the canvas is cleared.
//
// ─────────────────────────────────────────────────────────────────────────────

class DoodleRepository {
  final FirebaseFirestore _db;
  final FirebaseDatabase _rtdb;

  DoodleRepository({
    FirebaseFirestore? db,
    FirebaseDatabase? rtdb,
  })  : _db = db ?? FirebaseFirestore.instance,
        _rtdb = rtdb ?? FirebaseDatabase.instance;

  // ── RTDB helpers ──────────────────────────────────────────────────────────

  /// The RTDB path where a device streams its live in-progress stroke.
  DatabaseReference _liveRef(String spaceId, String deviceId) =>
      _rtdb.ref('doodles/$spaceId/live/$deviceId');

  /// The RTDB path where a device advertises drawing presence.
  DatabaseReference _presenceRef(String spaceId, String deviceId) =>
      _rtdb.ref('doodles/$spaceId/presence/$deviceId');

  // ── Firestore helpers ─────────────────────────────────────────────────────

  /// Firestore subcollection: one document per completed stroke.
  CollectionReference _strokesRef(String spaceId) {
    final today = _todayKey();
    return _db
        .collection('spaces')
        .doc(spaceId)
        .collection('doodles')
        .doc(today)
        .collection('strokes');
  }

  /// Firestore meta document (for clear operations).
  DocumentReference _canvasMeta(String spaceId) {
    final today = _todayKey();
    return _db
        .collection('spaces')
        .doc(spaceId)
        .collection('doodles')
        .doc(today);
  }

  // ── LAYER 1: RTDB — Live stroke streaming ─────────────────────────────────

  /// Replaces the entire live stroke node with the current in-progress stroke.
  /// Uses .set() so only the CURRENT stroke is stored — no accumulation,
  /// no ghost blobs on the partner's screen across multiple strokes.
  Future<void> pushLiveStroke(
      String spaceId, String deviceId, List<DoodlePoint> points) async {
    if (points.isEmpty) {
      await _liveRef(spaceId, deviceId).remove();
      return;
    }
    // Store as an integer-keyed map to preserve insertion order.
    final ptsMap = {
      for (var i = 0; i < points.length; i++) '$i': points[i].toMap(),
    };
    await _liveRef(spaceId, deviceId).set({'pts': ptsMap});
  }

  /// Streams the partner's live in-progress stroke from RTDB.
  /// Fires whenever the partner pushes an update \u2014 ultra low latency.
  Stream<List<DoodlePoint>> watchLiveStroke(
      String spaceId, String partnerId) {
    return _liveRef(spaceId, partnerId).onValue.map((event) {
      final snap = event.snapshot;
      if (!snap.exists || snap.value == null) return <DoodlePoint>[];

      final data = snap.value as Map<dynamic, dynamic>;
      final ptsRaw = data['pts'];
      if (ptsRaw == null) return <DoodlePoint>[];

      Iterable<dynamic> items;
      if (ptsRaw is List) {
        items = ptsRaw.where((e) => e != null);
      } else if (ptsRaw is Map) {
        final sorted = ptsRaw.entries.toList()
          ..sort((a, b) => int.parse(a.key.toString())
              .compareTo(int.parse(b.key.toString())));
        items = sorted.map((e) => e.value);
      } else {
        return <DoodlePoint>[];
      }
      
      return items
          .map((e) => DoodlePoint.fromMap(
              Map<String, dynamic>.from(e as Map)))
          .toList();
    });
  }

  /// Clears the RTDB live stroke node after a stroke is completed.
  /// Call this on onPanEnd after persisting to Firestore.
  Future<void> clearLiveStroke(String spaceId, String deviceId) async {
    await _liveRef(spaceId, deviceId).remove();
  }

  // ── LAYER 1B: RTDB Presence (replaces Firestore setDrawing) ──────────────

  /// Signals to partner that this device is actively drawing.
  Future<void> setDrawing(
      String spaceId, String deviceId, bool isDrawing) async {
    await _presenceRef(spaceId, deviceId).set(isDrawing);
  }

  /// Streams whether the partner is currently drawing.
  Stream<bool> watchPartnerDrawing(String spaceId, String partnerId) {
    return _presenceRef(spaceId, partnerId)
        .onValue
        .map((event) => event.snapshot.value as bool? ?? false);
  }

  // ── LAYER 2: Firestore — Persist completed strokes ────────────────────────

  String generateStrokeId(String spaceId) {
    return _strokesRef(spaceId).doc().id;
  }

  /// Persists a completed stroke to Firestore when the user lifts their finger.
  /// Each stroke is its own document — no growing arrays, no write contention.
  Future<void> persistStroke(String spaceId, DoodleStroke stroke) async {
    if (stroke.points.isEmpty) return;
    await _strokesRef(spaceId).doc(stroke.id).set({
      ...stroke.toMap(),
      'ts': FieldValue.serverTimestamp(),
    });
  }

  /// Streams all persisted strokes for today's canvas.
  /// Used for initial load and to add newly completed strokes.
  Stream<List<DoodleStroke>> watchStrokes(String spaceId) {
    return _strokesRef(spaceId)
        .orderBy('ts')
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => DoodleStroke.fromMap(d.id, d.data() as Map<String, dynamic>))
            .where((s) => !s.isDeleted)
            .toList());
  }

  Future<void> undoStroke(String spaceId, String strokeId) async {
    await _strokesRef(spaceId).doc(strokeId).update({'del': true});
  }

  Future<void> redoStroke(String spaceId, String strokeId) async {
    await _strokesRef(spaceId).doc(strokeId).update({'del': false});
  }

  Future<void> updateStrokeTransform(String spaceId, String strokeId, double scale, double rotation, double offsetX, double offsetY) async {
    await _strokesRef(spaceId).doc(strokeId).update({
      's': scale,
      'r': rotation,
      'ox': offsetX,
      'oy': offsetY,
    });
  }

  Future<void> updateStrokeFill(String spaceId, String strokeId, int? fillColorValue) async {
    if (fillColorValue != null) {
      await _strokesRef(spaceId).doc(strokeId).update({'fc': fillColorValue});
    } else {
      await _strokesRef(spaceId).doc(strokeId).update({'fc': FieldValue.delete()});
    }
  }

  /// Clears the entire canvas: deletes all stroke documents + RTDB live data.
  Future<void> clearCanvas(String spaceId) async {
    // Delete all Firestore stroke documents in a batch
    final snaps = await _strokesRef(spaceId).get();
    final batch = _db.batch();
    for (final doc in snaps.docs) {
      batch.delete(doc.reference);
    }
    // Update/create the meta doc to signal the clear
    batch.set(_canvasMeta(spaceId), {
      'clearedAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();

    // Also clear RTDB live strokes for this space
    await _rtdb.ref('doodles/$spaceId/live').remove();
  }
}

import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';

// ─── Flash Entry Model ────────────────────────────────────────────────────────

class FlashEntry {
  final String deviceId;
  final String photoUrl;
  final DateTime uploadedAt;

  const FlashEntry({
    required this.deviceId,
    required this.photoUrl,
    required this.uploadedAt,
  });

  factory FlashEntry.fromMap(Map<String, dynamic> m) => FlashEntry(
        deviceId: m['deviceId'] as String? ?? '',
        photoUrl: m['photoUrl'] as String? ?? '',
        uploadedAt:
            (m['uploadedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      );

  Map<String, dynamic> toMap() => {
        'deviceId': deviceId,
        'photoUrl': photoUrl,
        'uploadedAt': FieldValue.serverTimestamp(),
      };
}

// ─── Flash Day Model ─────────────────────────────────────────────────────────

class FlashDay {
  final Map<String, FlashEntry> entries; // deviceId → FlashEntry
  final int streak;

  const FlashDay({required this.entries, required this.streak});

  bool hasFlashed(String deviceId) => entries.containsKey(deviceId);

  bool get bothFlashed => entries.length >= 2;

  FlashEntry? entryFor(String deviceId) => entries[deviceId];
}

// ─── Flash Repository ─────────────────────────────────────────────────────────

class FlashRepository {
  final FirebaseFirestore _db;

  FlashRepository({FirebaseFirestore? db})
      : _db = db ?? FirebaseFirestore.instance;

  String _todayKey() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  DocumentReference _flashDocRef(String spaceId) => _db
      .collection('spaces')
      .doc(spaceId)
      .collection('flashes')
      .doc(_todayKey());

  DocumentReference _spaceRef(String spaceId) =>
      _db.collection('spaces').doc(spaceId);

  // ── Stream today's flash state ────────────────────────────────────────────

  Stream<FlashDay> watchToday(String spaceId) {
    return _flashDocRef(spaceId).snapshots().asyncMap((snap) async {
      final spaceDoc = await _spaceRef(spaceId).get();
      final streak =
          (spaceDoc.data() as Map<String, dynamic>?)?['flashStreak'] as int? ??
              0;

      if (!snap.exists) return FlashDay(entries: {}, streak: streak);

      final data = snap.data() as Map<String, dynamic>? ?? {};
      final rawEntries = data['entries'] as Map<String, dynamic>? ?? {};

      final entries = rawEntries.map((key, val) => MapEntry(
            key,
            FlashEntry.fromMap(Map<String, dynamic>.from(val as Map)),
          ));

      return FlashDay(entries: entries, streak: streak);
    });
  }

  // ── Process photo (Base64) + save entry ─────────────────────────────────

  Future<String> processPhotoToBase64(File imageFile) async {
    final bytes = await imageFile.readAsBytes();
    final base64String = base64Encode(bytes);
    return base64String;
  }

  Future<void> submitFlash({
    required String spaceId,
    required String deviceId,
    required String photoUrl,
    required List<String> allMemberIds,
  }) async {
    final flashRef = _flashDocRef(spaceId);

    await flashRef.set({
      'entries': {
        deviceId: FlashEntry(
          deviceId: deviceId,
          photoUrl: photoUrl,
          uploadedAt: DateTime.now(),
        ).toMap(),
      },
      'date': _todayKey(),
    }, SetOptions(merge: true));

    // Check if both members have flashed → increment streak
    final snap = await flashRef.get();
    final data = snap.data() as Map<String, dynamic>? ?? {};
    final entries = (data['entries'] as Map<String, dynamic>?) ?? {};

    final allFlashed = allMemberIds.every((id) => entries.containsKey(id));
    if (allFlashed && !(data['streakAwarded'] as bool? ?? false)) {
      // Mark streak as awarded so we don't double-count
      await flashRef.update({'streakAwarded': true});
      await _spaceRef(spaceId)
          .update({'flashStreak': FieldValue.increment(1)});
    }
  }

  // ── Reset streak (called if a day is skipped) ─────────────────────────────
  // This is checked passively when opening the screen

  Future<void> checkAndResetStreakIfNeeded(String spaceId) async {
    final spaceDoc = await _spaceRef(spaceId).get();
    final data = spaceDoc.data() as Map<String, dynamic>? ?? {};
    final lastFlashDate = data['lastFlashDate'] as String?;
    final today = _todayKey();

    if (lastFlashDate == null) return;

    // Parse last flash date
    final parts = lastFlashDate.split('-');
    if (parts.length != 3) return;
    final lastDate = DateTime(
      int.parse(parts[0]),
      int.parse(parts[1]),
      int.parse(parts[2]),
    );
    final todayDate = DateTime.now();
    final diff = todayDate.difference(lastDate).inDays;

    // If more than 1 day gap → reset streak
    if (diff > 1) {
      await _spaceRef(spaceId).update({'flashStreak': 0});
    }

    // Update last flash date
    await _spaceRef(spaceId).update({'lastFlashDate': today});
  }
}

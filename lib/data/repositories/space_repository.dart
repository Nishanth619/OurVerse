import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import '../../core/constants/app_constants.dart';
import '../../core/utils/app_utils.dart';
import '../models/models.dart';
import '../services/auth_service.dart';

class SpaceRepository {

  final FirebaseFirestore _db;
  final AuthService _auth;

  /// [auth] is injected so the repository is properly testable and doesn't
  /// create its own silent dependencies internally.
  SpaceRepository({
    FirebaseFirestore? db,
    AuthService? auth,
  })  : _db = db ?? FirebaseFirestore.instance,
        _auth = auth ?? AuthService();

  CollectionReference get _spaces =>
      _db.collection(AppConstants.spacesCollection);

  // ─── Create ────────────────────────────────────────────────────────────────

  Future<SpaceModel> createSpace({required String type}) async {
    final deviceId = await _auth.getOrCreateDeviceId();
    final inviteCode = AppUtils.generateInviteCode();

    final docRef = await _spaces.add({
      'inviteCode': inviteCode,
      'type': type,
      'memberDeviceIds': [deviceId],
      'createdAt': FieldValue.serverTimestamp(),
      'currentStreak': 0,
      'lastAnsweredDate': null,
    });

    await _auth.saveSpaceId(docRef.id);
    await ensureRtdbMembership(docRef.id);

    final snap = await docRef.get();
    return SpaceModel.fromFirestore(snap);
  }

  // ─── Join ──────────────────────────────────────────────────────────────────

  Future<SpaceModel?> joinSpace({required String inviteCode}) async {
    final upper = inviteCode.trim().toUpperCase();

    final query = await _spaces.where('inviteCode', isEqualTo: upper).limit(1).get();
    if (query.docs.isEmpty) {
      throw Exception('Code not found. Check and try again.');
    }

    final docRef = query.docs.first.reference;
    final deviceId = await _auth.getOrCreateDeviceId();

    await _db.runTransaction((tx) async {
      final snap = await tx.get(docRef);
      if (!snap.exists) throw Exception('Space not found');
      
      final data = snap.data() as Map<String, dynamic>? ?? {};
      final members = List<String>.from(data['memberDeviceIds'] ?? []);
      
      if (!members.contains(deviceId)) {
        if (data['type'] == 'couple' && members.length >= 2) {
          throw Exception('This couple space is already full.');
        }
        members.add(deviceId);
        tx.update(docRef, {'memberDeviceIds': members});
      }
    });

    await ensureRtdbMembership(docRef.id);
    await _auth.saveSpaceId(docRef.id);
    return getSpace(docRef.id);
  }

  // ─── Read ──────────────────────────────────────────────────────────────────

  Stream<SpaceModel?> watchSpace(String spaceId) {
    return _spaces.doc(spaceId).snapshots().map((snap) {
      if (!snap.exists) return null;
      return SpaceModel.fromFirestore(snap);
    });
  }

  Future<SpaceModel?> getSpace(String spaceId) async {
    final snap = await _spaces.doc(spaceId).get();
    if (!snap.exists) return null;
    return SpaceModel.fromFirestore(snap);
  }

  Future<void> ensureRtdbMembership(String spaceId) async {
    if (spaceId.isEmpty) return;
    try {
      final deviceId = await _auth.getOrCreateDeviceId();
      if (deviceId.isNotEmpty) {
        final rtdb = FirebaseDatabase.instance;
        await rtdb.ref('spaceMembers/$spaceId/$deviceId').set(true);
      }
    } catch (e) {
      debugPrint('[SpaceRepository] RTDB membership sync failed: $e');
    }
  }

  Future<void> updateSpaceName(String spaceId, String name) async {
    await _spaces.doc(spaceId).update({'spaceName': name.trim()});
  }

  // ─── Streak ────────────────────────────────────────────────────────────────

  Future<void> updateStreak(String spaceId) async {
    final today = AppUtils.todayKey();
    final snap = await _spaces.doc(spaceId).get();
    if (!snap.exists) return;

    final space = SpaceModel.fromFirestore(snap);

    // Already updated today — idempotent guard
    if (space.lastAnsweredDate == today) return;

    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    final yesterdayKey =
        '${yesterday.year}-${yesterday.month.toString().padLeft(2, '0')}-${yesterday.day.toString().padLeft(2, '0')}';

    if (space.lastAnsweredDate == yesterdayKey) {
      // Consecutive day — increment streak
      await _spaces.doc(spaceId).update({
        'currentStreak': space.currentStreak + 1,
        'lastAnsweredDate': today,
        'lostStreak': 0, // Clear any pending lost streak
        'streakReviveAdsWatched': 0,
      });
    } else {
      // Chain broken — save the lost streak so user can revive it
      final brokenStreak = space.currentStreak;
      await _spaces.doc(spaceId).update({
        'currentStreak': 1, // Start fresh at 1 (they answered today)
        'lastAnsweredDate': today,
        'lostStreak': brokenStreak > 1 ? brokenStreak : 0,
        'streakReviveAdsWatched': 0,
      });
    }
  }

  /// Called when a user watches a rewarded ad to recover a broken streak.
  /// If all 3 ads are watched, the lost streak is fully restored.
  Future<void> watchStreakReviveAd(String spaceId) async {
    final snap = await _spaces.doc(spaceId).get();
    if (!snap.exists) return;
    final space = SpaceModel.fromFirestore(snap);
    if (space.lostStreak <= 0) return;

    final adsWatched = space.streakReviveAdsWatched + 1;

    if (adsWatched >= 3) {
      // All 3 ads watched — restore the lost streak!
      await _spaces.doc(spaceId).update({
        'currentStreak': space.lostStreak,
        'lostStreak': 0,
        'streakReviveAdsWatched': 0,
      });
    } else {
      await _spaces.doc(spaceId).update({
        'streakReviveAdsWatched': adsWatched,
      });
    }
  }

}


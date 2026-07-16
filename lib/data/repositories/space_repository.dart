import 'package:cloud_firestore/cloud_firestore.dart';
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

    final snap = await docRef.get();
    return SpaceModel.fromFirestore(snap);
  }

  // ─── Join ──────────────────────────────────────────────────────────────────

  Future<SpaceModel?> joinSpace({required String inviteCode}) async {
    // Ensure we have a valid anonymous auth session before doing any Firestore work
    final deviceId = await _auth.getOrCreateDeviceId();
    final upper = inviteCode.trim().toUpperCase();

    QuerySnapshot query;
    try {
      query = await _spaces
          .where('inviteCode', isEqualTo: upper)
          .limit(1)
          .get();
    } catch (e) {
      // Re-throw with a clearer message so the UI can surface it
      throw Exception('Failed to search for invite code. Check your internet connection. ($e)');
    }

    if (query.docs.isEmpty) return null;

    final doc = query.docs.first;
    final space = SpaceModel.fromFirestore(doc);

    // Already a member? Re-join silently (idempotent)
    if (!space.memberDeviceIds.contains(deviceId)) {
      await doc.reference.update({
        'memberDeviceIds': FieldValue.arrayUnion([deviceId]),
      });
    }

    await _auth.saveSpaceId(doc.id);
    final updated = await doc.reference.get();
    return SpaceModel.fromFirestore(updated);
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

    final newStreak = space.lastAnsweredDate == yesterdayKey
        ? space.currentStreak + 1
        : 1; // Reset if chain broken

    await _spaces.doc(spaceId).update({
      'currentStreak': newStreak,
      'lastAnsweredDate': today,
    });
  }
}

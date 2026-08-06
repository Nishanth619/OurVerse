import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../../core/constants/app_constants.dart';
import '../../core/utils/app_utils.dart';
import '../../core/utils/isolate_parser.dart';
import '../models/models.dart';
import '../services/notification_service.dart';

class QuestionRepository {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  DocumentReference _spaceRef(String spaceId) =>
      _db.collection(AppConstants.spacesCollection).doc(spaceId);

  // ─── Questions ─────────────────────────────────────────────────────────────

  /// Gets or picks today's question for a space.
  /// If no question exists for today, picks a random unused one from Firestore.
  /// Falls back to hardcoded questions if Firestore bank is empty.
  /// [spaceType] = 'couple' | 'friends' — determines which question bank to use.
  Future<QuestionModel> getTodayQuestion(String spaceId, {String spaceType = 'couple'}) async {
    final today = AppUtils.todayKey();
    final answerRef = _spaceRef(spaceId)
        .collection(AppConstants.dailyAnswersCollection)
        .doc(today);

    try {
      final answerSnap = await answerRef.get();

      String? questionId;
      if (answerSnap.exists) {
        final data = answerSnap.data();
        questionId = data?['questionId'] as String?;
      }

      if (questionId != null && questionId.isNotEmpty) {
        return _getQuestionById(questionId, spaceType: spaceType);
      }

      // No question assigned yet — pick one and store it
      final question = await _pickQuestion(spaceId, spaceType: spaceType);
      await answerRef.set({
        'questionId': question.id,
        'answers': {},
        'revealed': false,
      }, SetOptions(merge: true));
      return question;
    } catch (e) {
      // Network or permission error — return a local fallback so the card
      // still shows rather than hiding entirely.
      debugPrint('getTodayQuestion error: $e');
      return spaceType == 'friends'
          ? QuestionModel.fallbackFriendsQuestions.first
          : QuestionModel.fallbackQuestions.first;
    }
  }

  Future<QuestionModel> _pickQuestion(String spaceId, {String spaceType = 'couple'}) async {
    final isFriends = spaceType == 'friends';
    final collection = isFriends
        ? AppConstants.questionsFriendsCollection
        : AppConstants.questionsCollection;

    // Get all used question IDs for this space
    final answersSnap = await _spaceRef(spaceId)
        .collection(AppConstants.dailyAnswersCollection)
        .get();
    final usedIds = answersSnap.docs.map((d) {
      return (d.data())['questionId'] as String? ?? '';
    }).toSet();

    // Get questions from Firestore that haven't been used
    final questionsSnap =
        await _db.collection(collection).limit(50).get();

    List<QuestionModel> available;
    if (questionsSnap.docs.isNotEmpty) {
      final rawDocs = questionsSnap.docs.map((d) {
        return {'id': d.id, ...d.data()};
      }).toList();

      // Multi-threading: Offload JSON parsing to a background Isolate
      // to keep the main UI thread at a smooth 90/120 FPS
      final all = await IsolateParser.parseList(rawDocs, QuestionModel.fromMap);

      available = all.where((q) => !usedIds.contains(q.id)).toList();
      if (available.isEmpty) available = all; // Cycle if all used
    } else {
      // Use hardcoded fallback
      final all = isFriends
          ? QuestionModel.fallbackFriendsQuestions
          : QuestionModel.fallbackQuestions;
      available = all.where((q) => !usedIds.contains(q.id)).toList();
      if (available.isEmpty) available = all;
    }

    available.shuffle();
    return available.first;
  }

  Future<QuestionModel> _getQuestionById(String id, {String spaceType = 'couple'}) async {
    if (id.isEmpty) return QuestionModel.fallbackQuestions.first;

    final isFriends = spaceType == 'friends';
    final collection = isFriends
        ? AppConstants.questionsFriendsCollection
        : AppConstants.questionsCollection;

    // Try Firestore first
    try {
      final snap = await _db.collection(collection).doc(id).get();
      if (snap.exists) return QuestionModel.fromFirestore(snap);
    } catch (_) {}

    // Fall back to hardcoded
    final fallback = isFriends
        ? QuestionModel.fallbackFriendsQuestions
        : QuestionModel.fallbackQuestions;
    return fallback.firstWhere(
      (q) => q.id == id,
      orElse: () => fallback.first,
    );
  }

  // ─── Answers ───────────────────────────────────────────────────────────────

  Stream<DailyAnswerModel?> watchTodayAnswers(String spaceId) {
    final today = AppUtils.todayKey();
    return _spaceRef(spaceId)
        .collection(AppConstants.dailyAnswersCollection)
        .doc(today)
        .snapshots()
        .map((snap) {
      if (!snap.exists) return null;
      return DailyAnswerModel.fromFirestore(snap);
    });
  }

  Future<void> submitAnswer({
    required String spaceId,
    required String deviceId,
    required String answerText,
    required List<String> allMemberIds,
  }) async {
    final today = AppUtils.todayKey();
    final answerRef = _spaceRef(spaceId)
        .collection(AppConstants.dailyAnswersCollection)
        .doc(today);

    await answerRef.update({
      'answers.$deviceId': {
        'text': answerText.trim(),
        'submittedAt': FieldValue.serverTimestamp(),
      },
    });

    // Check if all members have answered → auto-reveal
    final snap = await answerRef.get();
    final data = snap.data() ?? {};
    final answers = (data['answers'] as Map<String, dynamic>?) ?? {};

    final allAnswered = allMemberIds.every((id) => answers.containsKey(id));
    if (allAnswered) {
      await answerRef.update({'revealed': true});
    }
  }

  // ─── Moods ─────────────────────────────────────────────────────────────────

  Stream<DailyMoodModel?> watchTodayMoods(String spaceId) {
    final today = AppUtils.todayKey();
    return _spaceRef(spaceId)
        .collection(AppConstants.moodsCollection)
        .doc(today)
        .snapshots()
        .map((snap) {
      if (!snap.exists) return null;
      return DailyMoodModel.fromFirestore(snap);
    });
  }

  Future<void> submitMood({
    required String spaceId,
    required String deviceId,
    required String emoji,
  }) async {
    final today = AppUtils.todayKey();
    await _spaceRef(spaceId)
        .collection(AppConstants.moodsCollection)
        .doc(today)
        .set({
      'entries': {
        deviceId: {
          'emoji': emoji,
          'submittedAt': FieldValue.serverTimestamp(),
        }
      }
    }, SetOptions(merge: true));

    // Ping the partner via Vercel backend for background push notification
    try {
      final spaceSnap = await _spaceRef(spaceId).get();
      if (spaceSnap.exists) {
        final spaceData = spaceSnap.data();
        if (spaceData != null) {
          final data = spaceData as Map<String, dynamic>;
          final members = List<String>.from(data['memberDeviceIds'] ?? []);
          final partnerId = members.where((id) => id != deviceId).firstOrNull;
          if (partnerId != null) {
            await NotificationService.pingPartnerViaVercel(
              emoji,
              partnerId,
              spaceId: spaceId,
            );
          }
        }
      }
    } catch (e) {
      print('Failed to ping partner: $e');
    }
  }
}

import 'package:cloud_firestore/cloud_firestore.dart';
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
  Future<QuestionModel> getTodayQuestion(String spaceId) async {
    final today = AppUtils.todayKey();
    final answerRef = _spaceRef(spaceId)
        .collection(AppConstants.dailyAnswersCollection)
        .doc(today);

    final answerSnap = await answerRef.get();

    String questionId;
    if (answerSnap.exists) {
      questionId = (answerSnap.data() as Map<String, dynamic>)['questionId'];
    } else {
      // Pick and assign a question
      final question = await _pickQuestion(spaceId);
      await answerRef.set({
        'questionId': question.id,
        'answers': {},
        'revealed': false,
      });
      return question;
    }

    return _getQuestionById(questionId);
  }

  Future<QuestionModel> _pickQuestion(String spaceId) async {
    // Get all used question IDs for this space
    final answersSnap = await _spaceRef(spaceId)
        .collection(AppConstants.dailyAnswersCollection)
        .get();
    final usedIds = answersSnap.docs.map((d) {
      return (d.data())['questionId'] as String? ?? '';
    }).toSet();

    // Get questions from Firestore that haven't been used
    final questionsSnap = await _db
        .collection(AppConstants.questionsCollection)
        .limit(50)
        .get();

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
      final all = QuestionModel.fallbackQuestions;
      available = all.where((q) => !usedIds.contains(q.id)).toList();
      if (available.isEmpty) available = all;
    }

    available.shuffle();
    return available.first;
  }

  Future<QuestionModel> _getQuestionById(String id) async {
    // Try Firestore first
    try {
      final snap = await _db
          .collection(AppConstants.questionsCollection)
          .doc(id)
          .get();
      if (snap.exists) return QuestionModel.fromFirestore(snap);
    } catch (_) {}

    // Fall back to hardcoded
    return QuestionModel.fallbackQuestions.firstWhere(
      (q) => q.id == id,
      orElse: () => QuestionModel.fallbackQuestions.first,
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

    final allAnswered =
        allMemberIds.every((id) => answers.containsKey(id));
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
            // Check if partner has disabled mood pings
            final tokenDoc = await FirebaseFirestore.instance.collection('deviceTokens').doc(partnerId).get();
            final partnerWantsPings = tokenDoc.data()?['receiveMoodPings'] ?? true;
            
            if (partnerWantsPings) {
              await NotificationService.pingPartnerViaVercel(emoji, partnerId);
            }
          }
        }
      }
    } catch (e) {
      print('Failed to ping partner: $e');
    }
  }
}

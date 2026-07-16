import 'package:cloud_firestore/cloud_firestore.dart';

// ─── Space ───────────────────────────────────────────────────────────────────

class SpaceModel {
  final String id;
  final String inviteCode;
  final String type; // 'couple' | 'friends'
  final String spaceName;
  final List<String> memberDeviceIds;
  final DateTime createdAt;
  final int currentStreak;
  final String? lastAnsweredDate; // 'yyyy-MM-dd'

  const SpaceModel({
    required this.id,
    required this.inviteCode,
    required this.type,
    this.spaceName = '',
    required this.memberDeviceIds,
    required this.createdAt,
    required this.currentStreak,
    this.lastAnsweredDate,
  });

  factory SpaceModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return SpaceModel(
      id: doc.id,
      inviteCode: data['inviteCode'] ?? '',
      type: data['type'] ?? 'couple',
      spaceName: data['spaceName'] ?? '',
      memberDeviceIds: List<String>.from(data['memberDeviceIds'] ?? []),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      currentStreak: (data['currentStreak'] ?? 0) as int,
      lastAnsweredDate: data['lastAnsweredDate'],
    );
  }

  Map<String, dynamic> toMap() => {
        'inviteCode': inviteCode,
        'type': type,
        'spaceName': spaceName,
        'memberDeviceIds': memberDeviceIds,
        'createdAt': FieldValue.serverTimestamp(),
        'currentStreak': currentStreak,
        'lastAnsweredDate': lastAnsweredDate,
      };

  SpaceModel copyWith({
    String? id,
    String? inviteCode,
    String? type,
    String? spaceName,
    List<String>? memberDeviceIds,
    DateTime? createdAt,
    int? currentStreak,
    String? lastAnsweredDate,
  }) =>
      SpaceModel(
        id: id ?? this.id,
        inviteCode: inviteCode ?? this.inviteCode,
        type: type ?? this.type,
        spaceName: spaceName ?? this.spaceName,
        memberDeviceIds: memberDeviceIds ?? this.memberDeviceIds,
        createdAt: createdAt ?? this.createdAt,
        currentStreak: currentStreak ?? this.currentStreak,
        lastAnsweredDate: lastAnsweredDate ?? this.lastAnsweredDate,
      );
}

// ─── Daily Answer ─────────────────────────────────────────────────────────────

class AnswerEntry {
  final String text;
  final DateTime submittedAt;

  const AnswerEntry({required this.text, required this.submittedAt});

  factory AnswerEntry.fromMap(Map<String, dynamic> map) => AnswerEntry(
        text: map['text'] ?? '',
        submittedAt: (map['submittedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      );

  Map<String, dynamic> toMap() => {
        'text': text,
        'submittedAt': FieldValue.serverTimestamp(),
      };
}

class DailyAnswerModel {
  final String questionId;
  final Map<String, AnswerEntry> answers; // deviceId -> AnswerEntry
  final bool revealed;

  const DailyAnswerModel({
    required this.questionId,
    required this.answers,
    required this.revealed,
  });

  factory DailyAnswerModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final rawAnswers = (data['answers'] as Map<String, dynamic>?) ?? {};
    return DailyAnswerModel(
      questionId: data['questionId'] ?? '',
      answers: rawAnswers.map(
        (k, v) => MapEntry(k, AnswerEntry.fromMap(v as Map<String, dynamic>)),
      ),
      revealed: data['revealed'] ?? false,
    );
  }

  /// Returns true only when every member in [memberIds] has submitted an answer.
  bool allAnsweredBy(List<String> memberIds) =>
      memberIds.isNotEmpty && memberIds.every((id) => answers.containsKey(id));

  bool hasAnswered(String deviceId) => answers.containsKey(deviceId);
}

// ─── Mood ─────────────────────────────────────────────────────────────────────

class MoodEntry {
  final String emoji;
  final DateTime submittedAt;

  const MoodEntry({required this.emoji, required this.submittedAt});

  factory MoodEntry.fromMap(Map<String, dynamic> map) => MoodEntry(
        emoji: map['emoji'] ?? '😊',
        submittedAt: (map['submittedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      );

  Map<String, dynamic> toMap() => {
        'emoji': emoji,
        'submittedAt': FieldValue.serverTimestamp(),
      };
}

class DailyMoodModel {
  final Map<String, MoodEntry> entries; // deviceId -> MoodEntry

  const DailyMoodModel({required this.entries});

  factory DailyMoodModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final rawEntries = (data['entries'] as Map<String, dynamic>?) ?? {};
    return DailyMoodModel(
      entries: rawEntries.map(
        (k, v) => MapEntry(k, MoodEntry.fromMap(v as Map<String, dynamic>)),
      ),
    );
  }

  bool hasMood(String deviceId) => entries.containsKey(deviceId);
}

// ─── Question ─────────────────────────────────────────────────────────────────

class QuestionModel {
  final String id;
  final String text;
  final String category;

  const QuestionModel({
    required this.id,
    required this.text,
    required this.category,
  });

  factory QuestionModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return QuestionModel.fromMap({...data, 'id': doc.id});
  }

  factory QuestionModel.fromMap(Map<String, dynamic> data) {
    return QuestionModel(
      id: data['id'] ?? '',
      text: data['text'] ?? '',
      category: data['category'] ?? 'fun',
    );
  }

  /// Production-grade question bank — 200 questions across 6 categories.
  /// Enough for ~7 months of daily questions without repeating.
  static List<QuestionModel> get fallbackQuestions => [
        // ── Fun & Playful ───────────────────────────────────────────
        const QuestionModel(id: 'q001', text: 'What made you genuinely laugh today?', category: 'fun'),
        const QuestionModel(id: 'q002', text: 'If our relationship had a movie genre, what would it be?', category: 'fun'),
        const QuestionModel(id: 'q003', text: 'If you could only eat one meal for the rest of your life, what would it be?', category: 'fun'),
        const QuestionModel(id: 'q004', text: 'What is your most embarrassing talent that you are secretly proud of?', category: 'fun'),
        const QuestionModel(id: 'q005', text: 'If you were a superhero, what would your power be and what would your villain name be?', category: 'fun'),
        const QuestionModel(id: 'q006', text: 'What is the weirdest food combination you actually enjoy?', category: 'fun'),
        const QuestionModel(id: 'q007', text: 'If you had to describe your personality as a weather pattern, what would it be today?', category: 'fun'),
        const QuestionModel(id: 'q008', text: 'What song would play as the intro theme to your life right now?', category: 'fun'),
        const QuestionModel(id: 'q009', text: 'If you had to survive a zombie apocalypse, what is the first thing you would grab?', category: 'fun'),
        const QuestionModel(id: 'q010', text: 'What is the most ridiculous hill you will die on?', category: 'fun'),
        const QuestionModel(id: 'q011', text: 'If you could swap lives with any fictional character for a week, who would it be?', category: 'fun'),
        const QuestionModel(id: 'q012', text: 'What is one thing you have always wanted to try but felt too embarrassed to admit?', category: 'fun'),
        const QuestionModel(id: 'q013', text: 'If our relationship were a dish, what ingredients would it have?', category: 'fun'),
        const QuestionModel(id: 'q014', text: 'What is a totally mundane thing that brings you irrational joy?', category: 'fun'),
        const QuestionModel(id: 'q015', text: 'If you could be the world best at one useless skill, what would it be?', category: 'fun'),
        const QuestionModel(id: 'q016', text: 'What is one thing from your childhood that you still do secretly as an adult?', category: 'fun'),
        const QuestionModel(id: 'q017', text: 'If you had to pick one item from a museum to steal for purely sentimental reasons, what would it be?', category: 'fun'),
        const QuestionModel(id: 'q018', text: 'What would the title of your autobiography be?', category: 'fun'),
        const QuestionModel(id: 'q019', text: 'If you were a dog, what breed would you be and why?', category: 'fun'),
        const QuestionModel(id: 'q020', text: 'What is a rule you absolutely refuse to follow, even if it is harmless?', category: 'fun'),
        const QuestionModel(id: 'q021', text: 'If you could redesign any room in your ideal home from scratch, which room would it be?', category: 'fun'),
        const QuestionModel(id: 'q022', text: 'What app on your phone do you spend the most time on that you are slightly ashamed of?', category: 'fun'),
        const QuestionModel(id: 'q023', text: 'If you could add one class to every school curriculum, what would it be?', category: 'fun'),
        const QuestionModel(id: 'q024', text: 'What is something you always say you will do but never actually do?', category: 'fun'),
        const QuestionModel(id: 'q025', text: 'If you could instantly master one sport or physical activity, what would it be?', category: 'fun'),
        const QuestionModel(id: 'q026', text: 'What is the most unexpected thing that has ever made you cry in a good way?', category: 'fun'),
        const QuestionModel(id: 'q027', text: 'If you had a warning label, what would it say?', category: 'fun'),
        const QuestionModel(id: 'q028', text: 'What habit do you have that you think is completely normal but others find strange?', category: 'fun'),
        const QuestionModel(id: 'q029', text: 'If you could change one thing about how the internet works, what would it be?', category: 'fun'),
        const QuestionModel(id: 'q030', text: 'What is the most spontaneous thing you have ever done on a weekday?', category: 'fun'),
        const QuestionModel(id: 'q031', text: 'If you won a lifetime supply of one thing, what would you choose?', category: 'fun'),
        const QuestionModel(id: 'q032', text: 'What song, no matter what, instantly puts you in a good mood?', category: 'fun'),
        const QuestionModel(id: 'q033', text: 'What is your most controversial food opinion?', category: 'fun'),
        const QuestionModel(id: 'q034', text: 'If you could time travel to any era for just one day, where would you go?', category: 'fun'),
        const QuestionModel(id: 'q035', text: 'What is one thing you genuinely believe you could win a competition in?', category: 'fun'),
        const QuestionModel(id: 'q036', text: 'If you had to replace your handshake with a different greeting, what would it be?', category: 'fun'),
        const QuestionModel(id: 'q037', text: 'If you were a season, which one would you be this week and why?', category: 'fun'),
        const QuestionModel(id: 'q038', text: 'What is something you bought that you thought was amazing, but turned out to be completely useless?', category: 'fun'),
        const QuestionModel(id: 'q039', text: 'What was the last thing that made you stop and stare in wonder?', category: 'fun'),
        const QuestionModel(id: 'q040', text: 'If you had to describe today as a color, what color would it be?', category: 'fun'),

        // ── Deep & Meaningful ──────────────────────────────────
        const QuestionModel(id: 'q041', text: 'What is something you are proud of that you have never told anyone about?', category: 'deep'),
        const QuestionModel(id: 'q042', text: 'When do you feel the most like yourself?', category: 'deep'),
        const QuestionModel(id: 'q043', text: 'What is one thing you need more of in your life right now, and why?', category: 'deep'),
        const QuestionModel(id: 'q044', text: 'What small, everyday thing is making your life better lately?', category: 'deep'),
        const QuestionModel(id: 'q045', text: 'Is there something you have always wanted to say to me but never found the right moment?', category: 'deep'),
        const QuestionModel(id: 'q046', text: 'What belief about yourself took the longest to unlearn?', category: 'deep'),
        const QuestionModel(id: 'q047', text: 'What does home feel like to you — is it a place, a person, or a feeling?', category: 'deep'),
        const QuestionModel(id: 'q048', text: 'What is something you genuinely want to get better at this year?', category: 'deep'),
        const QuestionModel(id: 'q049', text: 'What part of your past do you think about more often than you should?', category: 'deep'),
        const QuestionModel(id: 'q050', text: 'What does love look like in action to you, not just in words?', category: 'deep'),
        const QuestionModel(id: 'q051', text: 'What are three qualities in yourself that you genuinely admire?', category: 'deep'),
        const QuestionModel(id: 'q052', text: 'What has been quietly weighing on your mind this week?', category: 'deep'),
        const QuestionModel(id: 'q053', text: 'If you could give your younger self one piece of advice, what would it be?', category: 'deep'),
        const QuestionModel(id: 'q054', text: 'What does a perfect ordinary Tuesday look like to you, five years from now?', category: 'deep'),
        const QuestionModel(id: 'q055', text: 'What is one thing about the world that genuinely restores your faith in people?', category: 'deep'),
        const QuestionModel(id: 'q056', text: 'When did you last feel completely at peace? What were you doing?', category: 'deep'),
        const QuestionModel(id: 'q057', text: 'What is a version of yourself you are still working toward becoming?', category: 'deep'),
        const QuestionModel(id: 'q058', text: 'What is something you have forgiven yourself for that took a long time to forgive?', category: 'deep'),
        const QuestionModel(id: 'q059', text: 'Is there something about me that I might not know is important to you?', category: 'deep'),
        const QuestionModel(id: 'q060', text: 'What does being truly understood by another person feel like to you?', category: 'deep'),
        const QuestionModel(id: 'q061', text: 'What is one moment from this year that you want to hold onto forever?', category: 'deep'),
        const QuestionModel(id: 'q062', text: 'What are you currently most afraid of, and how are you dealing with it?', category: 'deep'),
        const QuestionModel(id: 'q063', text: 'What is a value you hold that most people in your life do not know about?', category: 'deep'),
        const QuestionModel(id: 'q064', text: 'What is the kindest thing a stranger has ever done for you?', category: 'deep'),
        const QuestionModel(id: 'q065', text: 'What part of yourself do you think I bring out the most?', category: 'deep'),
        const QuestionModel(id: 'q066', text: 'What is something you admire about the way you handle hard situations?', category: 'deep'),
        const QuestionModel(id: 'q067', text: 'What memory from your childhood still makes you feel warm?', category: 'deep'),
        const QuestionModel(id: 'q068', text: 'When you imagine us a decade from now, what does that picture look like?', category: 'deep'),
        const QuestionModel(id: 'q069', text: 'What is your definition of true success — not the world version, yours?', category: 'deep'),
        const QuestionModel(id: 'q070', text: 'What does vulnerability mean to you, and is it easy or hard for you?', category: 'deep'),
        const QuestionModel(id: 'q071', text: 'What is one thing you wish the world understood about you that it does not?', category: 'deep'),
        const QuestionModel(id: 'q072', text: 'What is something you have learned about yourself from being in this relationship?', category: 'deep'),
        const QuestionModel(id: 'q073', text: 'What is one thing I do that makes you feel safest with me?', category: 'deep'),
        const QuestionModel(id: 'q074', text: 'What is your favorite memory of us so far?', category: 'deep'),
        const QuestionModel(id: 'q075', text: 'When did you first realize you were falling for me?', category: 'deep'),
        const QuestionModel(id: 'q076', text: 'What do you think is our biggest strength as a couple?', category: 'deep'),
        const QuestionModel(id: 'q077', text: 'What is something about me that surprised you in a good way?', category: 'deep'),
        const QuestionModel(id: 'q078', text: 'What makes you feel most proud to call me yours?', category: 'deep'),
        const QuestionModel(id: 'q079', text: 'What does being in this relationship bring out in you that nothing else does?', category: 'deep'),
        const QuestionModel(id: 'q080', text: 'If you had to describe what we mean to each other in just three words, what would they be?', category: 'deep'),

        // ── Spicy & Revealing ─────────────────────────────────
        const QuestionModel(id: 'q081', text: 'What is a strong opinion you have that you know is a little controversial?', category: 'spicy'),
        const QuestionModel(id: 'q082', text: 'What is the one thing I do that secretly drives you a little crazy?', category: 'spicy'),
        const QuestionModel(id: 'q083', text: 'What is something you have said I am fine about when you were absolutely not fine?', category: 'spicy'),
        const QuestionModel(id: 'q084', text: 'What is a boundary you have in this relationship that you have never explicitly stated?', category: 'spicy'),
        const QuestionModel(id: 'q085', text: 'What is something you have pretended to like just to avoid conflict?', category: 'spicy'),
        const QuestionModel(id: 'q086', text: 'What is the most honest thing you could say about how you are feeling right now?', category: 'spicy'),
        const QuestionModel(id: 'q087', text: 'What is a red flag in a person that you once overlooked and should not have?', category: 'spicy'),
        const QuestionModel(id: 'q088', text: 'Is there anything about our dynamic that you wish were slightly different?', category: 'spicy'),
        const QuestionModel(id: 'q089', text: 'What is one expectation you have of me that you have never actually voiced?', category: 'spicy'),
        const QuestionModel(id: 'q090', text: 'What is one argument we have had that you feel was never truly resolved?', category: 'spicy'),
        const QuestionModel(id: 'q091', text: 'What is something you have needed from me lately that you felt too awkward to ask for?', category: 'spicy'),
        const QuestionModel(id: 'q092', text: 'What is the bravest thing you have done in this relationship?', category: 'spicy'),
        const QuestionModel(id: 'q093', text: 'What is something you find genuinely hard to talk about, and why?', category: 'spicy'),
        const QuestionModel(id: 'q094', text: 'What does your inner critic tell you most often, and is any part of it true?', category: 'spicy'),
        const QuestionModel(id: 'q095', text: 'What is something about the future that genuinely scares you?', category: 'spicy'),
        const QuestionModel(id: 'q096', text: 'What is an insecurity you have that you rarely let anyone see?', category: 'spicy'),
        const QuestionModel(id: 'q097', text: 'What is something that happened in your past that still quietly influences how you act today?', category: 'spicy'),
        const QuestionModel(id: 'q098', text: 'What is the most uncomfortable truth you have had to accept about yourself?', category: 'spicy'),
        const QuestionModel(id: 'q099', text: 'What is one thing you have always wanted to ask me but held back from asking?', category: 'spicy'),
        const QuestionModel(id: 'q100', text: 'When do you feel the least understood by me?', category: 'spicy'),
        const QuestionModel(id: 'q101', text: 'What is something I do that makes you feel the most loved — and is it happening enough?', category: 'spicy'),
        const QuestionModel(id: 'q102', text: 'What is one thing you are currently not telling me because you worry about how I will react?', category: 'spicy'),
        const QuestionModel(id: 'q103', text: 'How do you actually handle anger — what does it look like behind closed doors?', category: 'spicy'),
        const QuestionModel(id: 'q104', text: 'What is the most important thing to you in a relationship that you feel is non-negotiable?', category: 'spicy'),
        const QuestionModel(id: 'q105', text: 'What is something you think we still need to get better at as a team?', category: 'spicy'),
        const QuestionModel(id: 'q106', text: 'What is something you have done in this relationship that you wish you could redo?', category: 'spicy'),
        const QuestionModel(id: 'q107', text: 'What is a version of yourself you are hiding from the world right now?', category: 'spicy'),
        const QuestionModel(id: 'q108', text: 'What does jealousy or insecurity look like for you, and how do you handle it?', category: 'spicy'),
        const QuestionModel(id: 'q109', text: 'What is your love language, and do you feel like I speak it well enough?', category: 'spicy'),
        const QuestionModel(id: 'q110', text: 'What is something you learned from our last disagreement?', category: 'spicy'),

        // ── Growth & Dreams ──────────────────────────────────
        const QuestionModel(id: 'q111', text: 'What is one goal you have set for yourself this month?', category: 'growth'),
        const QuestionModel(id: 'q112', text: 'What dream have you put on hold that you still think about?', category: 'growth'),
        const QuestionModel(id: 'q113', text: 'What skill do you most want to develop in the next year?', category: 'growth'),
        const QuestionModel(id: 'q114', text: 'What does your ideal version of yourself look like, and what is one thing you are doing to get there?', category: 'growth'),
        const QuestionModel(id: 'q115', text: 'What is one thing you gave up on that you wonder if you should revisit?', category: 'growth'),
        const QuestionModel(id: 'q116', text: 'What is a habit you want to build that would genuinely change your daily life?', category: 'growth'),
        const QuestionModel(id: 'q117', text: 'What does financial security look like to you, and how close do you feel to it?', category: 'growth'),
        const QuestionModel(id: 'q118', text: 'What book, podcast, or video has genuinely changed how you think recently?', category: 'growth'),
        const QuestionModel(id: 'q119', text: 'Where do you see yourself professionally in five years, and does that excite or scare you?', category: 'growth'),
        const QuestionModel(id: 'q120', text: 'What is one thing you want to stop doing that is holding you back?', category: 'growth'),
        const QuestionModel(id: 'q121', text: 'What is a cause or mission you feel genuinely passionate about?', category: 'growth'),
        const QuestionModel(id: 'q122', text: 'If you could learn anything for free in one year, what would you choose?', category: 'growth'),
        const QuestionModel(id: 'q123', text: 'What does your morning routine look like right now, and does it set you up well?', category: 'growth'),
        const QuestionModel(id: 'q124', text: 'What is a decision you are currently overthinking?', category: 'growth'),
        const QuestionModel(id: 'q125', text: 'Who in your life is a role model for how you want to grow, and why?', category: 'growth'),
        const QuestionModel(id: 'q126', text: 'What is a project or idea you have been sitting on that you wish you had started already?', category: 'growth'),
        const QuestionModel(id: 'q127', text: 'What is one thing you want our life together to look like in three years that we have not talked about yet?', category: 'growth'),
        const QuestionModel(id: 'q128', text: 'What is something you recently failed at, and what did it teach you?', category: 'growth'),
        const QuestionModel(id: 'q129', text: 'What is your relationship with money, and where does it come from?', category: 'growth'),
        const QuestionModel(id: 'q130', text: 'What is one area of your mental health you feel like you have made real progress in?', category: 'growth'),
        const QuestionModel(id: 'q131', text: 'What is something you believe in strongly enough to change your life for?', category: 'growth'),
        const QuestionModel(id: 'q132', text: 'What is a fear that has actually stopped you from pursuing something important?', category: 'growth'),
        const QuestionModel(id: 'q133', text: 'What lesson from the past year are you carrying into the next one?', category: 'growth'),
        const QuestionModel(id: 'q134', text: 'What kind of person do you want to be known as at the end of your career?', category: 'growth'),
        const QuestionModel(id: 'q135', text: 'What is one sacrifice you have made for your growth that you are genuinely proud of?', category: 'growth'),
        const QuestionModel(id: 'q136', text: 'What is a perspective shift that completely changed how you see something?', category: 'growth'),
        const QuestionModel(id: 'q137', text: 'If you could eliminate one thing from your routine to have more time, what would it be?', category: 'growth'),
        const QuestionModel(id: 'q138', text: 'What does the best version of our relationship look like in five years?', category: 'growth'),
        const QuestionModel(id: 'q139', text: 'What is something your future self would thank your present self for doing right now?', category: 'growth'),
        const QuestionModel(id: 'q140', text: 'What is one thing you want to create, build, or leave behind in this world?', category: 'growth'),

        // ── Long Distance & Deep Connection ───────────────────────
        const QuestionModel(id: 'q141', text: 'What part of your day do you most wish I was physically there for?', category: 'ldr'),
        const QuestionModel(id: 'q142', text: 'When you think of me right now, what is the first image that comes to mind?', category: 'ldr'),
        const QuestionModel(id: 'q143', text: 'What is something you want to do with me the moment we are in the same place again?', category: 'ldr'),
        const QuestionModel(id: 'q144', text: 'What moment from the last time we were together do you replay most often?', category: 'ldr'),
        const QuestionModel(id: 'q145', text: 'What is one thing the distance has taught you about yourself that you did not expect?', category: 'ldr'),
        const QuestionModel(id: 'q146', text: 'How do you know when you need more connection from me, and what does that look like?', category: 'ldr'),
        const QuestionModel(id: 'q147', text: 'What is one ordinary thing you miss doing with me?', category: 'ldr'),
        const QuestionModel(id: 'q148', text: 'What is one thing you have been doing alone that you cannot wait to share with me in person?', category: 'ldr'),
        const QuestionModel(id: 'q149', text: 'What is something you feel like you cannot fully express through a screen?', category: 'ldr'),
        const QuestionModel(id: 'q150', text: 'What is a place you want to take me someday that I do not know about yet?', category: 'ldr'),
        const QuestionModel(id: 'q151', text: 'What song makes you think of me most right now?', category: 'ldr'),
        const QuestionModel(id: 'q152', text: 'How has loving me changed the way you see the world?', category: 'ldr'),
        const QuestionModel(id: 'q153', text: 'What is something about my everyday life that you genuinely wish you could witness?', category: 'ldr'),
        const QuestionModel(id: 'q154', text: 'What does the idea of finally being in the same city feel like to you right now?', category: 'ldr'),
        const QuestionModel(id: 'q155', text: 'When you hear something funny, who is the first person you want to tell, and why?', category: 'ldr'),
        const QuestionModel(id: 'q156', text: 'What does a perfect evening look like to you when we are finally together?', category: 'ldr'),
        const QuestionModel(id: 'q157', text: 'What is the hardest thing about loving someone from far away?', category: 'ldr'),
        const QuestionModel(id: 'q158', text: 'What is one new thing you have discovered about yourself since we got together?', category: 'ldr'),
        const QuestionModel(id: 'q159', text: 'What is a small ritual you have that helps you feel close to me even when we are apart?', category: 'ldr'),
        const QuestionModel(id: 'q160', text: 'What is one tradition you want us to build together over the years?', category: 'ldr'),

        // ── Self-Reflection & Identity ───────────────────────────
        const QuestionModel(id: 'q161', text: 'What is one thing you genuinely like about yourself that you rarely say out loud?', category: 'deep'),
        const QuestionModel(id: 'q162', text: 'What do you think is the most misunderstood thing about your personality?', category: 'deep'),
        const QuestionModel(id: 'q163', text: 'Who in your life has had the single biggest impact on who you are today?', category: 'deep'),
        const QuestionModel(id: 'q164', text: 'What does your relationship with yourself look like right now — are you being kind to yourself?', category: 'deep'),
        const QuestionModel(id: 'q165', text: 'What is something you are learning to accept about yourself?', category: 'growth'),
        const QuestionModel(id: 'q166', text: 'What emotion do you find the hardest to sit with, and how do you usually cope?', category: 'spicy'),
        const QuestionModel(id: 'q167', text: 'What part of your identity has changed the most in the last two years?', category: 'deep'),
        const QuestionModel(id: 'q168', text: 'When you are at your absolute best, what does that version of you look like?', category: 'deep'),
        const QuestionModel(id: 'q169', text: 'What is one thing you have stopped caring about that used to take up a lot of mental energy?', category: 'deep'),
        const QuestionModel(id: 'q170', text: 'What is something you believe about yourself now that you could not have believed five years ago?', category: 'growth'),
        const QuestionModel(id: 'q171', text: 'What kind of parent, partner, or friend do you most aspire to be?', category: 'deep'),
        const QuestionModel(id: 'q172', text: 'What is one thing that consistently drains your energy, and can you protect yourself from it?', category: 'growth'),
        const QuestionModel(id: 'q173', text: 'What does joy look like for you, and are you allowing yourself enough of it?', category: 'deep'),
        const QuestionModel(id: 'q174', text: 'What is one simple thing that consistently brings you peace?', category: 'deep'),
        const QuestionModel(id: 'q175', text: 'What is something you would do more of if you stopped worrying about what people thought?', category: 'spicy'),
        const QuestionModel(id: 'q176', text: 'What does healing look like for you right now, in any area of life?', category: 'deep'),
        const QuestionModel(id: 'q177', text: 'What is the most important relationship in your life outside of ours, and why?', category: 'deep'),
        const QuestionModel(id: 'q178', text: 'What is a genuinely good day for you — describe it from morning to night?', category: 'fun'),
        const QuestionModel(id: 'q179', text: 'What is something you have always wanted to be asked, but no one ever asks?', category: 'deep'),
        const QuestionModel(id: 'q180', text: 'What is the single thing you most want me to understand about you?', category: 'deep'),

        // ── Bonus: Random Sparks ──────────────────────────────────
        const QuestionModel(id: 'q181', text: 'What is the best piece of advice you have ever received, and did you actually follow it?', category: 'deep'),
        const QuestionModel(id: 'q182', text: 'If you could live in any city in the world for one year, where would you choose?', category: 'fun'),
        const QuestionModel(id: 'q183', text: 'What is something you secretly find beautiful that others might overlook?', category: 'deep'),
        const QuestionModel(id: 'q184', text: 'What is a question you ask yourself often but have never found the answer to?', category: 'deep'),
        const QuestionModel(id: 'q185', text: 'What would you attempt if you knew you could not fail?', category: 'growth'),
        const QuestionModel(id: 'q186', text: 'What is your love language for yourself — how do you care for you?', category: 'deep'),
        const QuestionModel(id: 'q187', text: 'If you could have dinner with anyone alive or dead, who would it be and why?', category: 'fun'),
        const QuestionModel(id: 'q188', text: 'What is a hobby you had as a kid that you miss?', category: 'fun'),
        const QuestionModel(id: 'q189', text: 'What has been the most defining moment of your life so far?', category: 'deep'),
        const QuestionModel(id: 'q190', text: 'What is something you do every day that you think most people underestimate?', category: 'deep'),
        const QuestionModel(id: 'q191', text: 'What is a word that does not exist yet that you wish it did?', category: 'fun'),
        const QuestionModel(id: 'q192', text: 'If you could only keep five possessions, what would they be?', category: 'deep'),
        const QuestionModel(id: 'q193', text: 'What is one thing on your bucket list that feels genuinely achievable this year?', category: 'growth'),
        const QuestionModel(id: 'q194', text: 'What is a film, book, or song that changed how you see relationships?', category: 'deep'),
        const QuestionModel(id: 'q195', text: 'What is the most romantic thing you think a person can do — no clichés?', category: 'deep'),
        const QuestionModel(id: 'q196', text: 'What is your guilty pleasure that you are actually not that guilty about?', category: 'fun'),
        const QuestionModel(id: 'q197', text: 'If you could have one superpower just for today, what would you use it for?', category: 'fun'),
        const QuestionModel(id: 'q198', text: 'What is something beautiful that happened this week that you almost missed?', category: 'deep'),
        const QuestionModel(id: 'q199', text: 'What is a small thing you do for yourself that is entirely just for you?', category: 'deep'),
        const QuestionModel(id: 'q200', text: 'What is one thing about us that makes you smile every time you think about it?', category: 'deep'),
      ];
}

// ─── WYR Session ─────────────────────────────────────────────────────────────

class WyrSession {
  final String id;
  final int questionIndex;
  final Map<String, String> choices; // deviceId -> 'A' | 'B'
  final bool revealed;

  const WyrSession({
    required this.id,
    required this.questionIndex,
    required this.choices,
    required this.revealed,
  });

  factory WyrSession.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return WyrSession(
      id: doc.id,
      questionIndex: (data['questionIndex'] ?? 0) as int,
      choices: Map<String, String>.from(data['choices'] ?? {}),
      revealed: data['revealed'] ?? false,
    );
  }

  bool allAnsweredBy(List<String> memberIds) =>
      memberIds.isNotEmpty && memberIds.every((id) => choices.containsKey(id));

  bool hasAnswered(String deviceId) => choices.containsKey(deviceId);
}

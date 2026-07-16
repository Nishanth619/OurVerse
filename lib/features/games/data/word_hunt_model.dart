import 'package:cloud_firestore/cloud_firestore.dart';

class WordHuntModel {
  final String id;
  final List<String> grid; // 16 letters
  final Map<String, Timestamp> startedAt;
  final Map<String, Timestamp> finishedAt;
  final Map<String, List<String>> wordsFound;
  final Map<String, int> score;
  final Timestamp createdAt;

  WordHuntModel({
    required this.id,
    required this.grid,
    required this.startedAt,
    required this.finishedAt,
    required this.wordsFound,
    required this.score,
    required this.createdAt,
  });

  factory WordHuntModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    
    // Safely cast maps
    Map<String, Timestamp> safeStartedAt = {};
    if (data['startedAt'] != null) {
      (data['startedAt'] as Map<String, dynamic>).forEach((k, v) {
        if (v is Timestamp) safeStartedAt[k] = v;
      });
    }

    Map<String, Timestamp> safeFinishedAt = {};
    if (data['finishedAt'] != null) {
      (data['finishedAt'] as Map<String, dynamic>).forEach((k, v) {
        if (v is Timestamp) safeFinishedAt[k] = v;
      });
    }

    Map<String, List<String>> safeWordsFound = {};
    if (data['wordsFound'] != null) {
      (data['wordsFound'] as Map<String, dynamic>).forEach((k, v) {
        if (v is List) {
          safeWordsFound[k] = List<String>.from(v);
        }
      });
    }

    Map<String, int> safeScore = {};
    if (data['score'] != null) {
      (data['score'] as Map<String, dynamic>).forEach((k, v) {
        if (v is int) safeScore[k] = v;
        if (v is double) safeScore[k] = v.toInt();
      });
    }

    return WordHuntModel(
      id: doc.id,
      grid: List<String>.from(data['grid'] ?? []),
      startedAt: safeStartedAt,
      finishedAt: safeFinishedAt,
      wordsFound: safeWordsFound,
      score: safeScore,
      createdAt: data['createdAt'] as Timestamp? ?? Timestamp.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'grid': grid,
      'startedAt': startedAt,
      'finishedAt': finishedAt,
      'wordsFound': wordsFound,
      'score': score,
      'createdAt': createdAt,
    };
  }
}

import 'package:cloud_firestore/cloud_firestore.dart';

class SnakesLaddersSession {
  final String id;
  final String redPlayerId;
  final String bluePlayerId;
  final String turn;
  final int diceValue;
  final bool hasRolled;
  final int redPosition;
  final int bluePosition;
  final String status; // 'waiting', 'playing', 'red_won', 'blue_won'
  final Timestamp createdAt;
  final Map<int, int> snakes;
  final Map<int, int> ladders;

  SnakesLaddersSession({
    required this.id,
    required this.redPlayerId,
    required this.bluePlayerId,
    required this.turn,
    required this.diceValue,
    required this.hasRolled,
    required this.redPosition,
    required this.bluePosition,
    required this.status,
    required this.createdAt,
    required this.snakes,
    required this.ladders,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'redPlayerId': redPlayerId,
      'bluePlayerId': bluePlayerId,
      'turn': turn,
      'diceValue': diceValue,
      'hasRolled': hasRolled,
      'redPosition': redPosition,
      'bluePosition': bluePosition,
      'status': status,
      'createdAt': createdAt,
      'snakes': snakes.map((key, value) => MapEntry(key.toString(), value)),
      'ladders': ladders.map((key, value) => MapEntry(key.toString(), value)),
    };
  }

  factory SnakesLaddersSession.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    
    Map<int, int> parseMap(dynamic mapData) {
      if (mapData == null || mapData is! Map) return {};
      final map = <int, int>{};
      mapData.forEach((key, value) {
        final intKey = int.tryParse(key.toString());
        final intVal = value is int ? value : int.tryParse(value.toString());
        if (intKey != null && intVal != null) {
          map[intKey] = intVal;
        }
      });
      return map;
    }

    return SnakesLaddersSession(
      id: doc.id,
      redPlayerId: data['redPlayerId'] as String? ?? '',
      bluePlayerId: data['bluePlayerId'] as String? ?? '',
      turn: data['turn'] as String? ?? '',
      diceValue: data['diceValue'] as int? ?? 0,
      hasRolled: data['hasRolled'] as bool? ?? false,
      redPosition: data['redPosition'] as int? ?? 0,
      bluePosition: data['bluePosition'] as int? ?? 0,
      status: data['status'] as String? ?? 'waiting',
      createdAt: data['createdAt'] as Timestamp? ?? Timestamp.now(),
      snakes: parseMap(data['snakes']),
      ladders: parseMap(data['ladders']),
    );
  }

  SnakesLaddersSession copyWith({
    String? turn,
    int? diceValue,
    bool? hasRolled,
    int? redPosition,
    int? bluePosition,
    String? status,
  }) {
    return SnakesLaddersSession(
      id: id,
      redPlayerId: redPlayerId,
      bluePlayerId: bluePlayerId,
      turn: turn ?? this.turn,
      diceValue: diceValue ?? this.diceValue,
      hasRolled: hasRolled ?? this.hasRolled,
      redPosition: redPosition ?? this.redPosition,
      bluePosition: bluePosition ?? this.bluePosition,
      status: status ?? this.status,
      createdAt: createdAt,
      snakes: snakes,
      ladders: ladders,
    );
  }
}

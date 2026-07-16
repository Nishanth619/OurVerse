import 'dart:math';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// ─── WYR Entry Model ─────────────────────────────────────────────────────────

class WyrEntry {
  final String optionA;
  final String optionB;

  const WyrEntry({required this.optionA, required this.optionB});
}

// ─── Provider ─────────────────────────────────────────────────────────────────

final wyrQuestionsProvider = Provider<List<WyrEntry>>((_) {
  final now = DateTime.now();
  final seed = now.year * 10000 + now.month * 100 + now.day;
  final random = Random(seed);
  final shuffled = List<WyrEntry>.from(wyrQuestions)..shuffle(random);
  return shuffled.take(10).toList();
});

// ─── Question Bank (30+) ──────────────────────────────────────────────────────

const List<WyrEntry> wyrQuestions = [
  // ── Silly / Light ──
  WyrEntry(optionA: 'Always be 10 min late', optionB: 'Always be 20 min early'),
  WyrEntry(optionA: 'Speak every language', optionB: 'Play every instrument'),
  WyrEntry(optionA: 'Live without music', optionB: 'Live without movies'),
  WyrEntry(optionA: 'Have a rewind button', optionB: 'Have a pause button'),
  WyrEntry(optionA: 'Always be cold', optionB: 'Always be hot'),
  WyrEntry(optionA: 'Be invisible for a day', optionB: 'Read minds for a day'),
  WyrEntry(optionA: 'Lose all your photos', optionB: 'Lose all your contacts'),
  WyrEntry(optionA: 'Only eat sweet food', optionB: 'Only eat savory food'),
  WyrEntry(optionA: 'Have a photographic memory', optionB: 'Be able to forget anything on demand'),
  WyrEntry(optionA: 'Always have to sing instead of talk', optionB: 'Always have to dance instead of walk'),
  WyrEntry(optionA: 'Never use social media again', optionB: 'Only communicate via social media'),
  WyrEntry(optionA: 'Have unlimited coffee', optionB: 'Have unlimited sleep'),
  WyrEntry(optionA: 'Be fluent in every language', optionB: 'Be an expert in every sport'),

  // ── Couple / Relationship ──
  WyrEntry(optionA: 'Surprise trip with no destination told', optionB: 'Plan every detail together'),
  WyrEntry(optionA: 'Stay in with movies every Friday', optionB: 'Go out every Friday, somewhere new'),
  WyrEntry(optionA: 'Always know what the other is thinking', optionB: 'Keep full private thoughts but always feel connected'),
  WyrEntry(optionA: 'Have the same sense of humor', optionB: 'Have the same taste in music'),
  WyrEntry(optionA: 'Write each other letters once a week', optionB: 'Video call every single day'),

  // ── Deep / Introspective ──
  WyrEntry(optionA: "Know when you'll die", optionB: "Know how you'll die"),
  WyrEntry(optionA: 'Be wildly successful but unknown', optionB: 'Be famous but struggle financially'),
  WyrEntry(optionA: 'Relive your best memory once more', optionB: 'Erase your worst memory forever'),
  WyrEntry(optionA: 'Have 10 genuine close friends', optionB: 'Have 1 person who knows everything about you'),
  WyrEntry(optionA: 'Live 100 years with an average life', optionB: 'Live 50 years with an extraordinary life'),
  WyrEntry(optionA: 'Always tell the truth', optionB: 'Always do what you feel is right'),

  // ── Fun Hypothetical ──
  WyrEntry(optionA: 'Live in a city with no traffic ever', optionB: 'Live in the countryside with no noise ever'),
  WyrEntry(optionA: 'Only ever travel by plane', optionB: 'Only ever travel by train'),
  WyrEntry(optionA: 'Have a personal chef', optionB: 'Have a personal driver'),
  WyrEntry(optionA: 'Know every recipe by heart', optionB: 'Never need to cook — food appears on demand'),
  WyrEntry(optionA: 'Always feel fully rested after 4 hours of sleep', optionB: 'Never need to eat — get all nutrition from water'),
  WyrEntry(optionA: 'Travel back to any point in history for one week', optionB: 'Travel forward to any point in the future for one week'),
  WyrEntry(optionA: 'Meet your favorite fictional character', optionB: 'Enter your favorite fictional world'),
];

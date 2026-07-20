import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/stream_model.dart';
import '../data/stream_repository.dart';

final streamRepositoryProvider = Provider<StreamRepository>(
  (_) => StreamRepository(),
);

final streamSessionProvider =
    StreamProvider.family<StreamSession?, String>((ref, spaceId) {
  return ref.watch(streamRepositoryProvider).watchSession(spaceId);
});

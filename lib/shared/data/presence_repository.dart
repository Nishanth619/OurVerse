import 'package:firebase_database/firebase_database.dart';

/// Manages partner presence tracking across the entire app.
/// RTDB Schema: spaces/{spaceId}/presence/{featureId}/{deviceId} = true
class PresenceRepository {
  final FirebaseDatabase _rtdb;

  PresenceRepository({FirebaseDatabase? rtdb})
      : _rtdb = rtdb ?? FirebaseDatabase.instance;

  DatabaseReference _presenceRef(String spaceId, String featureId, String deviceId) =>
      _rtdb.ref('spaces/$spaceId/presence/$featureId/$deviceId');

  /// Marks a device as actively viewing a specific feature (e.g. 'ludo', 'chat').
  Future<void> setPresent(String spaceId, String featureId, String deviceId) async {
    final ref = _presenceRef(spaceId, featureId, deviceId);
    await ref.set(true);
    // Automatically remove presence if the app crashes or user hard-closes it.
    await ref.onDisconnect().remove();
  }

  /// Removes the device's presence from a specific feature.
  Future<void> setAbsent(String spaceId, String featureId, String deviceId) async {
    final ref = _presenceRef(spaceId, featureId, deviceId);
    await ref.remove();
    ref.onDisconnect().cancel();
  }

  /// Streams true if the partner is currently looking at this specific feature.
  Stream<bool> watchPartnerPresence(String spaceId, String featureId, String partnerId) {
    if (partnerId.isEmpty) return Stream.value(false);
    return _presenceRef(spaceId, featureId, partnerId)
        .onValue
        .map((event) => event.snapshot.value == true);
  }
}

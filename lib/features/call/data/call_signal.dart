// ─── Call Signal Model ──────────────────────────────────────────────────────

/// State of a call stored in Firebase RTDB.
enum CallState {
  ringing,
  active,
  declined,
  ended,
  missed,
}

/// Represents the signaling data for an ongoing or pending call.
/// Stored at: spaces/{spaceId}/call/signal
class CallSignal {
  final String callerId;
  final String callerName;
  final CallState state;
  final String? offerSdp;
  final String? answerSdp;
  final int startedAt; // ms since epoch

  const CallSignal({
    required this.callerId,
    required this.callerName,
    required this.state,
    required this.startedAt,
    this.offerSdp,
    this.answerSdp,
  });

  factory CallSignal.fromMap(Map<dynamic, dynamic> map) {
    return CallSignal(
      callerId: map['callerId'] as String? ?? '',
      callerName: map['callerName'] as String? ?? 'Your partner',
      state: _stateFromString(map['state'] as String? ?? 'ringing'),
      offerSdp: map['offerSdp'] as String?,
      answerSdp: map['answerSdp'] as String?,
      startedAt: map['startedAt'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toMap() => {
        'callerId': callerId,
        'callerName': callerName,
        'state': state.name,
        'startedAt': startedAt,
        if (offerSdp != null) 'offerSdp': offerSdp,
        if (answerSdp != null) 'answerSdp': answerSdp,
      };

  CallSignal copyWith({
    String? callerId,
    String? callerName,
    CallState? state,
    String? offerSdp,
    String? answerSdp,
    int? startedAt,
  }) {
    return CallSignal(
      callerId: callerId ?? this.callerId,
      callerName: callerName ?? this.callerName,
      state: state ?? this.state,
      offerSdp: offerSdp ?? this.offerSdp,
      answerSdp: answerSdp ?? this.answerSdp,
      startedAt: startedAt ?? this.startedAt,
    );
  }

  static CallState _stateFromString(String s) {
    return CallState.values.firstWhere(
      (e) => e.name == s,
      orElse: () => CallState.ended,
    );
  }
}

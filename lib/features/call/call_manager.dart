import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'data/call_repository.dart';
import 'data/call_signal.dart';
import '../../data/services/notification_service.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import '../chat/data/chat_repository.dart';

// ─── State ────────────────────────────────────────────────────────────────────

enum CallManagerState {
  idle,
  requestingPermission,
  calling,    // outgoing: offer sent, waiting for answer
  ringing,    // incoming: offer received, waiting for local accept/decline
  connecting, // SDP handshake done, establishing ICE
  connected,  // audio flowing
  ended,
  declined,
  failed,
}

// ─── Call Manager ─────────────────────────────────────────────────────────────

/// Core class that drives WebRTC peer-to-peer voice calls.
///
/// Lifecycle:
///   idle → [startCall/receiveCall] → calling/ringing → connecting → connected → ended
///
/// Keep this alive in a Riverpod [Provider] at the root scope so it
/// survives screen transitions.
class CallManager {
  final CallRepository _repo;
  final ChatRepository? _chatRepo;

  CallManager({CallRepository? repo, ChatRepository? chatRepo}) 
    : _repo = repo ?? CallRepository(),
      _chatRepo = chatRepo {
    _initCallKit();
  }

  void _initCallKit() {
    FlutterCallkitIncoming.onEvent.listen((CallEvent? event) async {
      switch (event?.event) {
        case Event.actionCallAccept:
          final spaceId = event?.body['extra']['spaceId'];
          if (spaceId != null && spaceId == _spaceId) {
            // Read offer SDP from RTDB
            final signal = await _repo.getCallSignalOnce(spaceId);
            if (signal != null && signal.offerSdp != null) {
              await acceptCall(signal.offerSdp!);
            }
          }
          break;
        case Event.actionCallDecline:
          final spaceId = event?.body['extra']['spaceId'];
          if (spaceId != null && spaceId == _spaceId) {
            await declineCall();
          }
          break;
        case Event.actionCallEnded:
          final spaceId = event?.body['extra']['spaceId'];
          if (spaceId != null && spaceId == _spaceId) {
            await hangUp();
          }
          break;
        default:
          break;
      }
    });
  }

  // ── Public state streams ───────────────────────────────────────────────────

  final _stateCtrl = StreamController<CallManagerState>.broadcast();
  final _durationCtrl = StreamController<Duration>.broadcast();

  Stream<CallManagerState> get stateStream => _stateCtrl.stream;
  Stream<Duration> get durationStream => _durationCtrl.stream;

  CallManagerState get currentState => _state;
  bool get isMuted => _isMuted;
  bool get isSpeaker => _isSpeaker;
  String get remoteDisplayName => _remoteDisplayName;
  String get spaceId => _spaceId;

  // ── Private state ──────────────────────────────────────────────────────────

  CallManagerState _state = CallManagerState.idle;
  bool _isMuted = false;
  bool _isSpeaker = false;
  String _remoteDisplayName = '';
  String _myDisplayName = '';
  String _spaceId = '';
  String _myDeviceId = '';
  String _remoteDeviceId = ''; // the partner's deviceId for ICE candidate exchange

  RTCPeerConnection? _pc;
  MediaStream? _localStream;
  Timer? _durationTimer;
  Duration _elapsed = Duration.zero;

  StreamSubscription<CallSignal?>? _signalSub;
  StreamSubscription<Map<String, dynamic>>? _iceSub;

  // ── Free ICE servers (STUN = Google free; TURN = openrelay free tier) ─────

  static const _iceServers = <Map<String, dynamic>>[
    {'urls': 'stun:stun.l.google.com:19302'},
    {'urls': 'stun:stun1.l.google.com:19302'},
    {
      'urls': 'turn:openrelay.metered.ca:80',
      'username': 'openrelayproject',
      'credential': 'openrelayproject',
    },
    {
      'urls': 'turn:openrelay.metered.ca:443',
      'username': 'openrelayproject',
      'credential': 'openrelayproject',
    },
    {
      'urls': 'turn:openrelay.metered.ca:443?transport=tcp',
      'username': 'openrelayproject',
      'credential': 'openrelayproject',
    },
  ];

  // ── API ───────────────────────────────────────────────────────────────────

  /// Called by the caller.
  Future<void> startCall({
    required String spaceId,
    required String myDeviceId,
    required String myName,
    String remoteDeviceId = '',
  }) async {
    if (_state != CallManagerState.idle) return;
    _spaceId = spaceId;
    _myDeviceId = myDeviceId;
    _myDisplayName = myName;
    _remoteDeviceId = remoteDeviceId;

    _setState(CallManagerState.requestingPermission);

    // Mic permission
    final mic = await _requestMicPermission();
    if (!mic) {
      _setState(CallManagerState.failed);
      return;
    }

    _setState(CallManagerState.calling);

    await _createPeerConnection();
    await _captureLocalAudio();

    // Create SDP offer
    final offer = await _pc!.createOffer({'offerToReceiveAudio': true});
    await _pc!.setLocalDescription(offer);

    // Write to RTDB
    await _repo.startCall(
      spaceId: spaceId,
      callerId: myDeviceId,
      callerName: myName,
      offerSdp: offer.sdp!,
    );

    // Ping partner via Push Notification to wake CallKit
    if (remoteDeviceId.isNotEmpty) {
      await NotificationService.pingPartnerForCall(remoteDeviceId, spaceId, myName);
    }

    // Listen for answer from callee
    _signalSub = _repo.watchSignal(spaceId).listen(_onSignalChanged);

    // Auto-timeout after 45 seconds with no answer
    Future<void>.delayed(const Duration(seconds: 45), () {
      if (_state == CallManagerState.calling) {
        debugPrint('[CallManager] No answer after 45s — ending call');
        _logCallHistory('missed');
        hangUp();
      }
    });
  }

  /// Called by the callee when the incoming call signal is detected.
  /// This only updates internal state — doesn't send audio yet.
  void receiveIncomingCall({
    required String spaceId,
    required String callerName,
    required String myDeviceId,
    required String callerDeviceId,
  }) {
    if (_state != CallManagerState.idle) return;
    _spaceId = spaceId;
    _myDeviceId = myDeviceId;
    _remoteDeviceId = callerDeviceId;
    _remoteDisplayName = callerName;
    _setState(CallManagerState.ringing);
  }

  /// Callee accepts — capture mic, create answer, connect.
  Future<void> acceptCall(String offerSdp) async {
    if (_state != CallManagerState.ringing) return;

    final mic = await _requestMicPermission();
    if (!mic) {
      await declineCall();
      return;
    }

    _setState(CallManagerState.connecting);

    await _createPeerConnection();
    await _captureLocalAudio();

    // Set remote offer
    await _pc!.setRemoteDescription(
      RTCSessionDescription(offerSdp, 'offer'),
    );

    // Create answer
    final answer = await _pc!.createAnswer({'offerToReceiveAudio': true});
    await _pc!.setLocalDescription(answer);

    // Write answer to RTDB
    await _repo.answerCall(
      spaceId: _spaceId,
      answerSdp: answer.sdp!,
    );

    // Listen for ICE candidates from caller
    _iceSub = _repo
        .watchIceCandidates(_spaceId, _remoteDeviceId)
        .listen(_onRemoteIceCandidate);

    // Listen for call end
    _signalSub = _repo.watchSignal(_spaceId).listen(_onSignalChanged);
  }

  /// Callee declines.
  Future<void> declineCall() async {
    _logCallHistory('declined');
    await _repo.declineCall(_spaceId);
    _cleanUp(CallManagerState.declined);
  }

  /// Either peer hangs up.
  Future<void> hangUp() async {
    if (_state == CallManagerState.idle) return;

    if (_state == CallManagerState.calling && _remoteDeviceId.isNotEmpty) {
      await NotificationService.pingPartnerForEndCall(_remoteDeviceId, _spaceId);
    }
    
    if (_state == CallManagerState.connected) {
      _logCallHistory('ended', duration: _elapsed.inSeconds);
    }

    await _repo.endCall(_spaceId);
    _cleanUp(CallManagerState.ended);
  }

  /// Toggle microphone mute.
  void toggleMute() {
    if (_localStream == null) return;
    _isMuted = !_isMuted;
    for (final track in _localStream!.getAudioTracks()) {
      track.enabled = !_isMuted;
    }
  }

  /// Toggle speaker vs earpiece.
  Future<void> toggleSpeaker() async {
    _isSpeaker = !_isSpeaker;
    await Helper.setSpeakerphoneOn(_isSpeaker);
  }

  // ── Private helpers ────────────────────────────────────────────────────────

  Future<void> _createPeerConnection() async {
    _pc = await createPeerConnection(
      {'iceServers': _iceServers},
      {'optional': []},
    );

    _pc!.onIceCandidate = (candidate) {
      _repo.sendIceCandidate(
        spaceId: _spaceId,
        fromDeviceId: _myDeviceId,
        candidateMap: candidate.toMap(),
      );
    };

    _pc!.onConnectionState = (state) {
      debugPrint('[CallManager] connection state: $state');
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        _setState(CallManagerState.connected);
        _startDurationTimer();
      } else if (state ==
              RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          state ==
              RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
        debugPrint('[CallManager] Connection dropped — ending call');
        hangUp();
      }
    };

    _pc!.onTrack = (event) {
      // Remote audio track received — WebRTC plays it automatically
      debugPrint('[CallManager] Remote track received: ${event.track.kind}');
    };
  }

  Future<void> _captureLocalAudio() async {
    _localStream = await navigator.mediaDevices.getUserMedia({
      'audio': {
        'echoCancellation': true,
        'noiseSuppression': true,
        'autoGainControl': true,
      },
      'video': false,
    });
    for (final track in _localStream!.getAudioTracks()) {
      _pc!.addTrack(track, _localStream!);
    }
  }

  void _onSignalChanged(CallSignal? signal) {
    if (signal == null) {
      _cleanUp(CallManagerState.ended);
      return;
    }

    switch (signal.state) {
      case CallState.active:
        // Caller side: answer received — set remote description
        if (_state == CallManagerState.calling && signal.answerSdp != null) {
          // The callee's device ID comes from who wrote the answer — we stored caller's device ID
          // Remote for the caller is the callee = whoever is not _myDeviceId
          // We store it from the signal's callerId is us; remote wrote answer but we don't know their deviceId
          // We pass remoteDeviceId when starting call (partner's deviceId)
          _pc!
              .setRemoteDescription(
                RTCSessionDescription(signal.answerSdp!, 'answer'),
              )
              .then((_) => _setState(CallManagerState.connecting));

          // Now listen for ICE from callee
          _iceSub = _repo
              .watchIceCandidates(_spaceId, _remoteDeviceId)
              .listen(_onRemoteIceCandidate);
        }
        break;
      case CallState.declined:
        _cleanUp(CallManagerState.declined);
        break;
      case CallState.ended:
        _cleanUp(CallManagerState.ended);
        break;
      default:
        break;
    }
  }

  void _onRemoteIceCandidate(Map<String, dynamic> candidateMap) {
    if (candidateMap.isEmpty) return;
    final candidate = RTCIceCandidate(
      candidateMap['candidate'] as String? ?? '',
      candidateMap['sdpMid'] as String? ?? '',
      candidateMap['sdpMLineIndex'] as int? ?? 0,
    );
    _pc?.addCandidate(candidate).catchError((e) {
      debugPrint('[CallManager] addCandidate error: $e');
    });
  }


  void _startDurationTimer() {
    _elapsed = Duration.zero;
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _elapsed += const Duration(seconds: 1);
      _durationCtrl.add(_elapsed);
    });
  }

  void _setState(CallManagerState state) {
    _state = state;
    _stateCtrl.add(state);
  }

  void _cleanUp(CallManagerState finalState) {
    _signalSub?.cancel();
    _iceSub?.cancel();
    _durationTimer?.cancel();
    _repo.clearIce(_spaceId, _myDeviceId).ignore();

    _localStream?.getTracks().forEach((t) => t.stop());
    _localStream?.dispose();
    _localStream = null;

    _pc?.close();
    _pc = null;

    _isMuted = false;
    _isSpeaker = false;

    _setState(finalState);

    // Reset to idle after a short delay so UI can show end state
    Future<void>.delayed(const Duration(seconds: 2), () {
      if (_state == finalState) _setState(CallManagerState.idle);
    });
  }

  void _logCallHistory(String callState, {int? duration}) {
    if (_chatRepo == null || _spaceId.isEmpty || _myDeviceId.isEmpty) return;
    // We only log if we have the name (i.e. caller or callee properly initialized)
    final name = _myDisplayName.isNotEmpty ? _myDisplayName : 'Partner';
    
    _chatRepo!.sendCallMessage(
      spaceId: _spaceId,
      senderId: _myDeviceId,
      senderName: name,
      callState: callState,
      callDuration: duration,
    ).catchError((e) {
      debugPrint('[CallManager] Failed to log call history: $e');
    });
  }

  Future<bool> _requestMicPermission() async {
    try {
      // flutter_webrtc wraps getUserMedia with permission request
      final test = await navigator.mediaDevices.getUserMedia({
        'audio': true,
        'video': false,
      });
      test.getTracks().forEach((t) => t.stop());
      test.dispose();
      return true;
    } catch (e) {
      debugPrint('[CallManager] Mic permission denied: $e');
      return false;
    }
  }

  void dispose() {
    _cleanUp(CallManagerState.idle);
    _stateCtrl.close();
    _durationCtrl.close();
  }
}

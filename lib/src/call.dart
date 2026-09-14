import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

import 'constants/api_endpoints.dart';
import 'constants/ice_servers.dart';
import 'enums/call_state.dart';
import 'models/call_options.dart';
import 'models/ws_message.dart';

/// Represents a single VoIP call session with dedicated WebSocket signaling
/// and WebRTC peer connection.
///
/// Each call has its own:
/// - Native WebSocket connection for signaling (authenticated via `call_token`)
/// - `RTCPeerConnection` for media
/// - State machine tracking call lifecycle
///
/// This is a Dart port of the browser SDK's `Call` class, adapted for
/// `flutter_webrtc` instead of browser WebRTC APIs.
class Call {
  /// Create a new Call instance.
  ///
  /// Typically called internally by [FiretellClient], not by consumers directly.
  Call({
    required this.iceServers,
    CallOptions options = const CallOptions(),
  })  : to = options.to,
        from = options.from,
        fromName = options.fromName,
        fromAvatar = options.fromAvatar,
        isVideo = options.isVideo,
        isTransfer = options.isTransfer,
        transferReason = options.transferReason;

  // ─── Public Properties ────────────────────────────────────────────

  /// Call identifier assigned by the server.
  String? callId;

  /// Destination number or extension.
  final String to;

  /// Caller number.
  String from;

  /// Caller display name.
  String fromName;

  /// Caller avatar URL.
  String? fromAvatar;

  /// Whether this is a video call.
  bool isVideo;

  /// Whether this call was transferred.
  bool isTransfer;

  /// Reason for transfer.
  String? transferReason;

  /// Whether the call is currently active.
  bool active = false;

  /// Whether the local microphone is muted.
  bool isMuted = false;

  /// Remote SDP description received from the server.
  RTCSessionDescription? remoteDescription;

  /// ICE servers configuration for the peer connection.
  final List<Map<String, dynamic>> iceServers;

  // ─── Event Streams ─────────────────────────────────────────────────

  final _stateController =
      StreamController<({CallState state, String? reason, Map<String, dynamic>? data})>.broadcast();
  final _localStreamController =
      StreamController<MediaStream?>.broadcast();
  final _remoteStreamController =
      StreamController<MediaStream?>.broadcast();
  final _muteController = StreamController<bool>.broadcast();
  final _mediaStateController = StreamController<String>.broadcast();

  /// Stream of call state changes.
  Stream<({CallState state, String? reason, Map<String, dynamic>? data})>
      get onStateChange => _stateController.stream;

  /// Stream of local media stream changes (null when track is released).
  Stream<MediaStream?> get onLocalStream => _localStreamController.stream;

  /// Stream of remote media stream changes (null when track is released).
  Stream<MediaStream?> get onRemoteStream => _remoteStreamController.stream;

  /// Stream of mute state changes.
  Stream<bool> get onMuteChange => _muteController.stream;

  /// Stream of ICE connection state changes.
  Stream<String> get onMediaState => _mediaStateController.stream;

  // ─── Private State ─────────────────────────────────────────────────

  CallState _state = CallState.none;
  RTCPeerConnection? _peerConnection;
  WebSocketChannel? _wsChannel;
  StreamSubscription<dynamic>? _wsSubscription;
  MediaStream? _localStream;
  MediaStream? _remoteStream;
  bool _destroying = false;
  Completer<void>? _connectCompleter;
  Timer? _authTimeout;
  String? _currentRemoteSetupRole;

  /// Current call state.
  CallState get callState => _state;

  /// Whether the call is currently on hold.
  bool get isHold => _state == CallState.onHold;

  /// Local media stream (microphone / camera).
  MediaStream? get localStream => _localStream;

  /// Remote media stream (other party's audio).
  MediaStream? get remoteStream => _remoteStream;

  // ─── WebSocket Signaling ──────────────────────────────────────────

  /// Open dedicated native WebSocket signaling connection for this call
  /// session and authenticate with `call_token` within 3 seconds.
  Future<void> connectSignaling(String wsUrl, String callToken) async {
    _connectCompleter = Completer<void>();

    try {
      _wsChannel = WebSocketChannel.connect(Uri.parse(wsUrl));
      await _wsChannel!.ready;

      // Must authenticate within 3 seconds
      _authTimeout = Timer(const Duration(seconds: 3), () {
        if (_connectCompleter != null && !_connectCompleter!.isCompleted) {
          _wsChannel?.sink.close();
          _wsChannel = null;
          _connectCompleter!.completeError(
            TimeoutException(
              'Call WebSocket authentication timed out after 3s',
            ),
          );
        }
      });

      // Listen for WS messages
      _wsSubscription = _wsChannel!.stream.listen(
        (dynamic message) {
          try {
            final json = jsonDecode(message as String) as Map<String, dynamic>;
            final msg = WsEventMessage.fromJson(json);
            _handleWsMessage(msg);
          } catch (e) {
            developer.log(
              'Call.connectSignaling: JSON parse error: $e',
              name: 'FiretellSDK',
            );
          }
        },
        onDone: () {
          _authTimeout?.cancel();
          _wsChannel = null;
          if (active && !_destroying) {
            destroy(sendHangup: false);
          }
        },
        onError: (Object error) {
          _authTimeout?.cancel();
          _emitState(CallState.error, reason: 'WebSocket error');
          if (_connectCompleter != null && !_connectCompleter!.isCompleted) {
            _connectCompleter!.completeError(error);
          }
        },
      );

      // Send session.connect handshake
      sendWsEvent('session.connect', {'call_token': callToken});

      return await _connectCompleter!.future;
    } catch (e) {
      _authTimeout?.cancel();
      if (_connectCompleter != null && !_connectCompleter!.isCompleted) {
        _connectCompleter!.completeError(e);
      }
      rethrow;
    }
  }

  /// Send a JSON event message over this call's WebSocket.
  void sendWsEvent(String event, [Map<String, dynamic>? data]) {
    if (_wsChannel != null) {
      _wsChannel!.sink.add(jsonEncode(
        WsEventMessage(event: event, data: data ?? {}).toJson(),
      ));
    }
  }

  // ─── WS Message Handler ────────────────────────────────────────────

  void _handleWsMessage(WsEventMessage msg) {
    final data = msg.data;

    switch (msg.event) {
      case 'session.connected':
        _authTimeout?.cancel();
        if (_connectCompleter != null && !_connectCompleter!.isCompleted) {
          _connectCompleter!.complete();
        }

      case 'session.error':
        developer.log(
          'Call: session.error: $data',
          name: 'FiretellSDK',
        );
        _emitState(
          CallState.error,
          reason: data?['message'] as String? ?? 'Session error',
        );

      case 'call.offer':
        if (data != null) {
          final sdpInit = _extractSdpInit(data);
          if (sdpInit != null) {
            remoteDescription = sdpInit;
            // Set remote SDP immediately for early media (ringback tone)
            _setRemoteDescription(sdpInit);
          }
          if (data['from'] != null) {
            from = (data['from'] is Map)
                ? (data['from'] as Map)['number']?.toString() ?? from
                : data['from'].toString();
          }
          if (data['from_name'] != null) {
            fromName = data['from_name'].toString();
          }
          if (data['from_avatar'] != null) {
            fromAvatar = data['from_avatar']?.toString();
          }
          if (data['is_video'] != null) {
            isVideo = data['is_video'] == true;
          }
          if (data['is_transfer'] != null) {
            isTransfer = data['is_transfer'] == true;
          }
          if (data['transfer_reason'] != null) {
            transferReason = data['transfer_reason'].toString();
          }
        }
        _state = CallState.ringing;
        _emitState(CallState.ringing, data: data);

      case 'call.answered':
        final sdpInit = _extractSdpInit(data);
        if (sdpInit != null) {
          _setRemoteDescription(sdpInit);
        }
        _state = CallState.active;
        active = true;
        _emitState(CallState.answered, data: data);

      case 'call.held':
        final sdpInit = _extractSdpInit(data);
        if (sdpInit != null) {
          _setRemoteDescription(sdpInit);
        }
        _state = CallState.onHold;
        _emitState(CallState.onHold, data: data);

      case 'call.unheld':
        final sdpInit = _extractSdpInit(data);
        if (sdpInit != null) {
          _setRemoteDescription(sdpInit);
        }
        _state = CallState.active;
        _emitState(CallState.active, data: data);

      case 'call.ended' || 'call.rejected' || 'call.canceled':
        _state = CallState.ended;
        final reason = data?['reason'] as String? ?? msg.event;
        _emitState(CallState.ended, reason: reason, data: data);
        destroy(sendHangup: false);

      case 'call.sdp':
        final sdpInit = _extractSdpInit(data);
        if (sdpInit != null) {
          _setRemoteDescription(sdpInit);
        }

      case 'call.state':
        final sdpInit = _extractSdpInit(data);
        if (sdpInit != null) {
          _setRemoteDescription(sdpInit);
        }
        if (data?['state'] != null) {
          // Map server state string to our enum
          final stateStr = data!['state'].toString().toLowerCase();
          final nextState = _parseCallState(stateStr);
          _state = nextState == CallState.answered
              ? CallState.active
              : nextState;
        }
        _emitState(_state, data: data);
    }
  }

  // ─── Outbound Call ─────────────────────────────────────────────────

  /// Start an outbound call.
  ///
  /// Initiates WebRTC media, gathers Full ICE candidates, then returns
  /// the full SDP offer to be sent by [FiretellClient.makeCall].
  Future<RTCSessionDescription> prepareOffer() async {
    active = true;
    _state = CallState.initiated;

    await _setupWebrtcMedia(audio: true, video: isVideo);
    final offer = await _peerConnection!.createOffer({});
    await _peerConnection!.setLocalDescription(offer);

    // Wait for all ICE candidates (Full ICE, not Trickle)
    return _getSDPFull();
  }

  // ─── Accept Incoming Call ──────────────────────────────────────────

  /// Accept an incoming call.
  ///
  /// Sets up WebRTC media, applies the remote SDP offer, creates an answer,
  /// gathers Full ICE candidates, and sends `call.answer` over WebSocket.
  Future<void> accept() async {
    if (callId == null) throw StateError('callId is missing');
    if (remoteDescription == null) {
      throw StateError('remoteDescription is missing');
    }

    try {
      await _setupWebrtcMedia(audio: true, video: isVideo);
      await _setRemoteDescription(remoteDescription!);
      final answer = await _peerConnection!.createAnswer({});
      await _peerConnection!.setLocalDescription(answer);
      final sdp = await _getSDPFull();

      sendWsEvent('call.answer', {'sdp': sdp.sdp});

      active = true;
      _state = CallState.answered;
    } catch (e) {
      active = false;
      _state = CallState.error;
      destroy(sendHangup: false);
      rethrow;
    }
  }

  // ─── Reject ────────────────────────────────────────────────────────

  /// Reject an incoming call via WebSocket.
  Future<void> reject() async {
    if (callId != null && _wsChannel != null) {
      sendWsEvent('call.reject', {});
    }
    destroy(sendHangup: false);
  }

  /// Reject an incoming call via fast HTTP endpoint.
  ///
  /// This is preferred over WebSocket reject when the app is in background
  /// or when no WS connection is established (e.g., push-triggered reject).
  /// Uses the `call_token` from the push payload as Bearer token.
  ///
  /// Completes in ~50ms vs several seconds for WS-based reject.
  Future<void> rejectViaHttp({
    required String baseUrl,
    required String callToken,
  }) async {
    if (callId == null) return;

    final uri = Uri.parse(
      '$baseUrl${ApiEndpoints.reject(callId!)}',
    );
    try {
      await http.post(
        uri,
        headers: {
          'Authorization': 'Bearer $callToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'reason': 'declined'}),
      );
    } catch (_) {
      // Best-effort — ignore network errors during reject
    }
    destroy(sendHangup: false);
  }

  // ─── Hang Up ───────────────────────────────────────────────────────

  /// Hang up the active call.
  Future<void> hangup() async {
    if (!active) return;
    active = false;
    if (callId != null && _wsChannel != null) {
      sendWsEvent('call.hangup', {});
    }
    destroy(sendHangup: false);
  }

  // ─── DTMF ──────────────────────────────────────────────────────────

  /// Send a DTMF tone digit.
  ///
  /// [digit] — `0-9`, `*`, `#`, `A-D`.
  /// [duration] — Duration in milliseconds (default 250).
  void sendDTMF(String digit, {int duration = 250}) {
    if (!active) throw StateError('Cannot send DTMF: call is not active');
    if (callId == null) return;
    sendWsEvent('call.dtmf', {'digit': digit, 'duration': duration});
  }

  // ─── Mute / Unmute ─────────────────────────────────────────────────

  /// Mute the local microphone.
  Future<void> mute() async {
    if (!active) throw StateError('Cannot mute: call is not active');
    if (_localStream != null) {
      for (final track in _localStream!.getAudioTracks()) {
        track.enabled = false;
      }
    }
    isMuted = true;
    sendWsEvent('call.mute', {'muted': true});
    _muteController.add(true);
  }

  /// Unmute the local microphone.
  Future<void> unmute() async {
    if (!active) throw StateError('Cannot unmute: call is not active');
    if (_localStream != null) {
      for (final track in _localStream!.getAudioTracks()) {
        track.enabled = true;
      }
    }
    isMuted = false;
    sendWsEvent('call.mute', {'muted': false});
    _muteController.add(false);
  }

  /// Toggle mute state.
  Future<void> toggleMute() async {
    if (isMuted) {
      await unmute();
    } else {
      await mute();
    }
  }

  // ─── Hold / Unhold ─────────────────────────────────────────────────

  /// Put the call on hold via SDP renegotiation.
  ///
  /// Changes transceiver direction to `sendonly`, creates a new offer,
  /// gathers Full ICE, and sends `call.hold` with the updated SDP.
  Future<void> onhold() async {
    if (callId == null) return;
    final pc = _peerConnection;
    if (pc == null) return;

    final transceivers = await pc.getTransceivers();
    for (final t in transceivers) {
      if (t.sender.track != null) {
        await t.setDirection(TransceiverDirection.SendOnly);
      }
    }

    final offer = await pc.createOffer({});
    await pc.setLocalDescription(offer);
    final sdp = await _getSDPFull();
    sendWsEvent('call.hold', {'sdp': sdp.sdp});
    _state = CallState.onHold;
    _emitState(CallState.onHold);
  }

  /// Resume a held call via SDP renegotiation.
  Future<void> unhold() async {
    if (_state != CallState.onHold) {
      throw StateError('Call is not on hold');
    }
    if (callId == null) return;
    final pc = _peerConnection;
    if (pc == null) return;

    final transceivers = await pc.getTransceivers();
    for (final t in transceivers) {
      if (t.sender.track != null) {
        await t.setDirection(TransceiverDirection.SendRecv);
      }
    }

    final offer = await pc.createOffer({});
    await pc.setLocalDescription(offer);
    final sdp = await _getSDPFull();
    sendWsEvent('call.unhold', {'sdp': sdp.sdp});
    _state = CallState.active;
    _emitState(CallState.active);
  }

  // ─── Transfer ──────────────────────────────────────────────────────

  /// Transfer the active call to another target.
  ///
  /// [target] — extension number, agent username, team ID (`te_...`),
  /// or SIP account ID (`si_...`).
  Future<void> transfer(String target, {String? reason}) async {
    if (!active) throw StateError('Cannot transfer: call is not active');
    if (target.isEmpty) throw ArgumentError('Target is required');
    if (callId == null) return;

    sendWsEvent('call.transfer', {
      'target': target,
      if (reason != null) 'reason': reason,
    });
    active = false;
    _cleanupPeerConnection();
    _state = CallState.ended;
    _emitState(CallState.ended, reason: 'Transferred');
  }

  // ─── Destroy / Cleanup ─────────────────────────────────────────────

  /// Destroy and clean up this call instance.
  ///
  /// Closes the WebRTC peer connection, stops media tracks, closes
  /// the dedicated WebSocket, and clears all event listeners.
  Future<void> destroy({bool sendHangup = true}) async {
    if (_destroying) return;
    _destroying = true;

    if (sendHangup && active && callId != null && _wsChannel != null) {
      sendWsEvent('call.hangup', {});
    }
    active = false;

    // Close dedicated call WebSocket
    _wsSubscription?.cancel();
    _wsSubscription = null;
    try {
      _wsChannel?.sink.close();
    } catch (_) {
      // Ignore WS close errors during cleanup
    }
    _wsChannel = null;

    _authTimeout?.cancel();
    _authTimeout = null;

    _cleanupPeerConnection();

    if (_state != CallState.ended && _state != CallState.error) {
      _state = CallState.ended;
      _emitState(CallState.ended, reason: 'Local Hangup');
    }

    // Close stream controllers
    _stateController.close();
    _localStreamController.close();
    _remoteStreamController.close();
    _muteController.close();
    _mediaStateController.close();
  }

  // ─── WebRTC Internals ──────────────────────────────────────────────

  /// Set the remote SDP description on the peer connection.
  Future<void> _setRemoteDescription(RTCSessionDescription sdp) async {
    try {
      final pc = _peerConnection;
      if (pc == null) return;

      // Skip duplicate stable-state answer
      final signalingState = pc.signalingState;
      if (sdp.type == 'answer' &&
          signalingState == RTCSignalingState.RTCSignalingStateStable) {
        return;
      }

      var sdpText = sdp.sdp ?? '';

      // Preserve established DTLS setup role during renegotiation
      // (same logic as browser SDK to prevent 'Failed to set SSL role')
      final setupMatch =
          RegExp(r'a=setup:(active|passive|actpass)').firstMatch(sdpText);
      if (setupMatch != null) {
        final role = setupMatch.group(1)!;
        if (_currentRemoteSetupRole == null) {
          if (role == 'active' || role == 'passive') {
            _currentRemoteSetupRole = role;
          }
        } else if ((role == 'active' || role == 'passive') &&
            role != _currentRemoteSetupRole) {
          sdpText = sdpText.replaceAll(
            RegExp(r'a=setup:(active|passive|actpass)'),
            'a=setup:$_currentRemoteSetupRole',
          );
        }
      }

      await pc.setRemoteDescription(
        RTCSessionDescription(sdpText, sdp.type),
      );
    } catch (e) {
      developer.log(
        'Call: setRemoteDescription error: $e',
        name: 'FiretellSDK',
      );
    }
  }

  /// Setup WebRTC media (getUserMedia + RTCPeerConnection).
  Future<void> _setupWebrtcMedia({
    required bool audio,
    bool video = false,
  }) async {
    _cleanupPeerConnection();

    final iceConfig = iceServers.isNotEmpty
        ? iceServers
        : defaultIceServers;

    _peerConnection = await createPeerConnection({
      'iceServers': iceConfig,
      'sdpSemantics': 'unified-plan',
    });

    _peerConnection!.onIceConnectionState = (state) {
      if (!_mediaStateController.isClosed) {
        _mediaStateController.add(state.toString());
      }
    };

    _peerConnection!.onTrack = (event) {
      if (event.streams.isNotEmpty) {
        _remoteStream = event.streams[0];
      } else {
        // When no stream is provided, add track to existing remote stream
        // or handle gracefully without creating a new one
        if (_remoteStream != null) {
          _remoteStream!.addTrack(event.track);
        } else {
          // Create remote stream asynchronously and add track
          createLocalMediaStream('remote').then((stream) {
            _remoteStream = stream;
            _remoteStream!.addTrack(event.track);
            if (!_remoteStreamController.isClosed) {
              _remoteStreamController.add(_remoteStream);
            }
          });
          return;
        }
      }
      if (!_remoteStreamController.isClosed) {
        _remoteStreamController.add(_remoteStream);
      }
    };

    if (audio || video) {
      _localStream = await navigator.mediaDevices.getUserMedia({
        'audio': audio,
        'video': video,
      });

      for (final track in _localStream!.getTracks()) {
        await _peerConnection!.addTrack(track, _localStream!);
      }

      if (!_localStreamController.isClosed) {
        _localStreamController.add(_localStream);
      }
    } else {
      // Receive-only mode (e.g., supervision listen mode)
      await _peerConnection!.addTransceiver(
        kind: RTCRtpMediaType.RTCRtpMediaTypeAudio,
        init: RTCRtpTransceiverInit(
          direction: TransceiverDirection.RecvOnly,
        ),
      );
    }
  }

  /// Wait for all ICE candidates to be gathered and return the full SDP.
  ///
  /// Firetell's media server requires Full ICE (not Trickle ICE).
  /// Matches the browser SDK's `_getSDPFull()` implementation.
  Future<RTCSessionDescription> _getSDPFull() async {
    final pc = _peerConnection!;
    final completer = Completer<RTCSessionDescription>();
    var isFinished = false;
    Timer? timeoutTimer;
    Timer? fallbackTimer;

    Future<void> finish() async {
      if (isFinished) return;
      isFinished = true;
      pc.onIceCandidate = null;
      pc.onIceGatheringState = null;
      timeoutTimer?.cancel();
      fallbackTimer?.cancel();

      final localDesc = await pc.getLocalDescription();
      if (localDesc != null && !completer.isCompleted) {
        completer.complete(localDesc);
      } else if (!completer.isCompleted) {
        completer.completeError(
          StateError('No local description after ICE gathering'),
        );
      }
    }

    // Check if gathering already complete
    if (pc.iceGatheringState ==
        RTCIceGatheringState.RTCIceGatheringStateComplete) {
      final localDesc = await pc.getLocalDescription();
      if (localDesc != null) return localDesc;
    }

    // Hard safety timeout of 6 seconds
    timeoutTimer = Timer(const Duration(seconds: 6), () async {
      final desc = await pc.getLocalDescription();
      if (desc != null) {
        await finish();
      } else if (!completer.isCompleted) {
        completer.completeError(
          TimeoutException('ICE gathering timed out after 6s'),
        );
      }
    });

    // Fallback: 3s if srflx or relay candidate already found
    fallbackTimer = Timer(const Duration(seconds: 3), () async {
      final desc = await pc.getLocalDescription();
      if (desc != null &&
          desc.sdp != null &&
          (desc.sdp!.contains('typ srflx') ||
              desc.sdp!.contains('typ relay'))) {
        await finish();
      }
    });

    pc.onIceCandidate = (candidate) {
      if (candidate.candidate == null || candidate.candidate!.isEmpty) {
        // Null candidate signals ICE gathering complete
        finish();
      }
    };

    pc.onIceGatheringState = (state) {
      if (state == RTCIceGatheringState.RTCIceGatheringStateComplete) {
        finish();
      }
    };

    return completer.future;
  }

  /// Cleanup the peer connection and stop all media tracks.
  void _cleanupPeerConnection() {
    isMuted = false;
    _currentRemoteSetupRole = null;

    if (_peerConnection != null) {
      _peerConnection!.onIceCandidate = null;
      _peerConnection!.onIceConnectionState = null;
      _peerConnection!.onIceGatheringState = null;
      _peerConnection!.onConnectionState = null;
      _peerConnection!.onTrack = null;
      _peerConnection!.close();
      _peerConnection = null;
    }

    if (_localStream != null) {
      for (final track in _localStream!.getTracks()) {
        track.stop();
      }
      _localStream!.dispose();
      _localStream = null;
      if (!_localStreamController.isClosed) {
        _localStreamController.add(null);
      }
    }

    if (_remoteStream != null) {
      _remoteStream = null;
      if (!_remoteStreamController.isClosed) {
        _remoteStreamController.add(null);
      }
    }
  }

  // ─── Helpers ───────────────────────────────────────────────────────

  void _emitState(
    CallState state, {
    String? reason,
    Map<String, dynamic>? data,
  }) {
    if (!_stateController.isClosed) {
      _stateController.add((state: state, reason: reason, data: data));
    }
  }

  /// Extract a valid `RTCSessionDescription` from WS event data.
  ///
  /// Handles multiple formats:
  /// - `{ sdp: { type, sdp } }` (nested)
  /// - `{ type, sdp }` (flat)
  /// - `{ sdp: "<raw SDP string>" }` (string only)
  RTCSessionDescription? _extractSdpInit(Map<String, dynamic>? data) {
    if (data == null) return null;

    // Nested: { sdp: { type, sdp } }
    if (data['sdp'] is Map) {
      final sdpObj = data['sdp'] as Map<String, dynamic>;
      if (sdpObj['sdp'] is String) {
        return RTCSessionDescription(
          sdpObj['sdp'] as String,
          (sdpObj['type'] as String?) ?? 'answer',
        );
      }
    }

    // String SDP: { sdp: "v=0\r\n..." }
    if (data['sdp'] is String) {
      return RTCSessionDescription(
        data['sdp'] as String,
        (data['type'] as String?) ?? 'answer',
      );
    }

    return null;
  }

  /// Parse a state string from server into [CallState] enum.
  CallState _parseCallState(String state) {
    switch (state) {
      case 'initiated':
        return CallState.initiated;
      case 'trying':
        return CallState.trying;
      case 'ringing':
        return CallState.ringing;
      case 'answered':
        return CallState.answered;
      case 'active':
        return CallState.active;
      case 'onhold' || 'held':
        return CallState.onHold;
      case 'ended' || 'completed':
        return CallState.ended;
      case 'canceled':
        return CallState.cancel;
      default:
        return CallState.none;
    }
  }
}

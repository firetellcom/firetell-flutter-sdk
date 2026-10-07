import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

import 'constants/api_endpoints.dart';
import 'constants/ice_servers.dart';
import 'constants/signaling.dart';
import 'enums/call_state.dart';
import 'enums/signaling_status.dart';
import 'models/call_options.dart';
import 'models/ws_message.dart';
import 'utils/jwt_decoder.dart';

/// Resolves the ICE servers to use right before a peer connection is created
/// (e.g. `FiretellClient.ensureIceServers`, which refreshes expiring TURN
/// credentials).
typedef IceServersProvider = Future<List<Map<String, dynamic>>> Function();

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
  ///
  /// [iceServersProvider] — optional; awaited right before the
  /// `RTCPeerConnection` is created so TURN credentials are fresh. Falls back
  /// to [iceServers] if it fails or returns an empty list.
  ///
  /// [fallbackTokenProvider] — optional; returns the agent JWT used for
  /// `session.connect` when the signaling WebSocket is resumed after the
  /// `call_token` has expired.
  Call({
    required this.iceServers,
    this.iceServersProvider,
    this.fallbackTokenProvider,
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

  /// Whether the speakerphone is turned on (vs earpiece).
  bool isSpeakerOn = false;

  /// Whether the local camera is turned off / muted.
  bool isCameraOff = false;

  /// Remote SDP description received from the server.
  RTCSessionDescription? remoteDescription;

  /// ICE servers configuration for the peer connection.
  ///
  /// Updated with the result of [iceServersProvider] when media is set up.
  List<Map<String, dynamic>> iceServers;

  /// Optional async source of fresh ICE servers (see [IceServersProvider]).
  final IceServersProvider? iceServersProvider;

  /// Optional source of the agent JWT, used as `call_token` fallback when
  /// resuming signaling after the original `call_token` expired.
  final String? Function()? fallbackTokenProvider;

  // ─── Event Streams ─────────────────────────────────────────────────

  final _stateController =
      StreamController<({CallState state, String? reason, Map<String, dynamic>? data})>.broadcast();
  final _localStreamController =
      StreamController<MediaStream?>.broadcast();
  final _remoteStreamController =
      StreamController<MediaStream?>.broadcast();
  final _muteController = StreamController<bool>.broadcast();
  final _cameraController = StreamController<bool>.broadcast();
  final _speakerController = StreamController<bool>.broadcast();
  final _mediaStateController = StreamController<String>.broadcast();
  final _signalingController = StreamController<
      ({SignalingStatus status, int attempt, int? closeCode})>.broadcast();

  /// Stream of call state changes.
  Stream<({CallState state, String? reason, Map<String, dynamic>? data})>
      get onStateChange => _stateController.stream;

  /// Stream of local media stream changes (null when track is released).
  Stream<MediaStream?> get onLocalStream => _localStreamController.stream;

  /// Stream of remote media stream changes (null when track is released).
  Stream<MediaStream?> get onRemoteStream => _remoteStreamController.stream;

  /// Stream of mute state changes.
  Stream<bool> get onMuteChange => _muteController.stream;

  /// Stream of camera state changes (true = camera off, false = camera on).
  Stream<bool> get onCameraChange => _cameraController.stream;

  /// Stream of speakerphone state changes.
  Stream<bool> get onSpeakerChange => _speakerController.stream;

  /// Stream of ICE connection state changes.
  Stream<String> get onMediaState => _mediaStateController.stream;

  /// Stream of signaling WebSocket keep-alive / reconnect status.
  ///
  /// Emits [SignalingStatus.reconnecting] (with attempt number and the close
  /// code that triggered it), [SignalingStatus.reconnected] or
  /// [SignalingStatus.failed] (the call is then ended).
  Stream<({SignalingStatus status, int attempt, int? closeCode})>
      get onSignaling => _signalingController.stream;

  /// Whether the signaling WebSocket is currently reconnecting.
  bool get isReconnecting => _reconnecting;

  // ─── Private State ─────────────────────────────────────────────────

  CallState _state = CallState.none;
  RTCPeerConnection? _peerConnection;
  WebSocketChannel? _wsChannel;
  StreamSubscription<dynamic>? _wsSubscription;
  MediaStream? _localStream;
  MediaStream? _remoteStream;
  bool _destroying = false;
  String? _currentRemoteSetupRole;

  // Signaling connection state (keep-alive / reconnect)
  String? _wsUrl;
  String? _callToken;
  bool _signalingReady = false;
  bool _reconnecting = false;
  int _reconnectAttempt = 0;
  DateTime _reconnectStartedAt = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _reconnectTimer;
  Timer? _pingTimer;
  DateTime _lastWsMessageAt = DateTime.fromMillisecondsSinceEpoch(0);
  final List<WsEventMessage> _wsOutbox = [];

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
  ///
  /// The connection is kept alive with periodic `session.ping` and is
  /// automatically reconnected (resuming the same call via
  /// `session.connect {call_token, call_id, reconnect: true}`) if it drops
  /// unexpectedly. See [onSignaling].
  Future<void> connectSignaling(String wsUrl, String callToken) async {
    _wsUrl = wsUrl;
    _callToken = callToken;
    await _openSignalingSocket(isReconnect: false);
  }

  /// Send a JSON event message over this call's WebSocket.
  ///
  /// While signaling is reconnecting, events are queued (up to 50) and
  /// flushed after the session is resumed.
  void sendWsEvent(String event, [Map<String, dynamic>? data]) {
    final msg = WsEventMessage(event: event, data: data ?? {});
    final channel = _wsChannel;
    if (channel != null && _signalingReady) {
      channel.sink.add(jsonEncode(msg.toJson()));
      return;
    }
    if (_reconnecting && _wsOutbox.length < SignalingConfig.outboxLimit) {
      _wsOutbox.add(msg);
    }
  }

  /// Open a signaling socket and complete once `session.connected` arrives.
  Future<void> _openSignalingSocket({required bool isReconnect}) async {
    final url = _wsUrl;
    if (url == null) throw StateError('Missing signaling ws_url');

    final completer = Completer<void>();
    final channel = WebSocketChannel.connect(Uri.parse(url));
    _wsChannel = channel;
    Timer? authTimer;

    void fail(Object error) {
      authTimer?.cancel();
      if (!completer.isCompleted) completer.completeError(error);
    }

    void startAuthTimer() {
      authTimer ??= Timer(SignalingConfig.authTimeout, () {
        if (completer.isCompleted) return;
        _detachChannel(channel);
        fail(TimeoutException(
          'Call WebSocket authentication timed out after '
          '${SignalingConfig.authTimeout.inSeconds}s',
        ));
      });
    }

    // Reconnect attempts include the TCP/TLS handshake in the auth window so
    // a dead network cannot stall the reconnect loop.
    if (isReconnect) startAuthTimer();

    _wsSubscription = channel.stream.listen(
      (dynamic message) {
        if (!identical(_wsChannel, channel)) return;
        _lastWsMessageAt = DateTime.now();
        final WsEventMessage msg;
        try {
          msg = WsEventMessage.fromJson(
            jsonDecode(message as String) as Map<String, dynamic>,
          );
        } catch (e) {
          developer.log(
            'Call.connectSignaling: JSON parse error: $e',
            name: 'FiretellSDK',
          );
          return;
        }

        if (msg.event == 'session.connected') {
          authTimer?.cancel();
          _signalingReady = true;
          _startWsPing();
          _flushWsOutbox();
          if (!completer.isCompleted) completer.complete();
          return;
        }

        if (msg.event == 'session.error' && _reconnecting && !_signalingReady) {
          // Failed reconnect attempt: let the retry loop handle it without
          // surfacing a call error.
          developer.log(
            'Call: session.error during reconnect: ${msg.data}',
            name: 'FiretellSDK',
          );
          _detachChannel(channel);
          fail(StateError('session.error during reconnect'));
          return;
        }

        _handleWsMessage(msg);
      },
      onError: (Object error) {
        if (!identical(_wsChannel, channel)) return;
        // Only surface as a call error for the initial connection; drops
        // mid-call are handled by reconnect.
        if (!isReconnect && !_signalingReady) {
          _emitState(CallState.error, reason: 'WebSocket error');
        }
        fail(error);
      },
      onDone: () {
        fail(StateError('Call WebSocket closed (code=${channel.closeCode})'));
        if (!identical(_wsChannel, channel)) return; // superseded / detached
        _wsChannel = null;
        _wsSubscription = null;
        _handleSignalingClose(channel.closeCode ?? 1006);
      },
    );

    try {
      await channel.ready;
    } catch (e) {
      if (identical(_wsChannel, channel)) _detachChannel(channel);
      fail(e);
      return completer.future;
    }

    if (!identical(_wsChannel, channel) || completer.isCompleted) {
      return completer.future;
    }

    startAuthTimer();
    // session.connect bypasses the outbox / ready check.
    channel.sink.add(jsonEncode(WsEventMessage(
      event: 'session.connect',
      data: _buildSessionConnectData(isReconnect: isReconnect),
    ).toJson()));

    return completer.future;
  }

  /// Build `session.connect` payload. On reconnect, include `call_id` so the
  /// server resumes the existing session, and fall back to the agent JWT if
  /// the `call_token` has expired.
  Map<String, dynamic> _buildSessionConnectData({required bool isReconnect}) {
    var token = _callToken;
    if (isReconnect && token != null && JwtDecoder.isExpired(token)) {
      final fallback = fallbackTokenProvider?.call();
      if (fallback != null && fallback.isNotEmpty) token = fallback;
    }
    return {
      'call_token': token,
      if (isReconnect && callId != null) 'call_id': callId,
      if (isReconnect) 'reconnect': true,
    };
  }

  void _handleSignalingClose(int code) {
    _stopWsPing();
    final wasReady = _signalingReady;
    _signalingReady = false;

    if (_destroying) return;
    // A reconnect attempt failed: the attempt loop schedules the next try.
    if (_reconnecting) return;

    if (wasReady && _shouldReconnect(code)) {
      _beginReconnect(code);
      return;
    }

    if (active) destroy(sendHangup: false);
  }

  bool _shouldReconnect(int code) {
    // 1000 / 1005: intentional close (server ended or transferred the session)
    if (code == 1000 || code == 1005) return false;
    if (_state == CallState.ended || _state == CallState.error) return false;
    return _wsUrl != null && _callToken != null && callId != null;
  }

  void _beginReconnect(int code) {
    _reconnecting = true;
    _reconnectAttempt = 0;
    _reconnectStartedAt = DateTime.now();
    _scheduleReconnectAttempt(code);
  }

  void _scheduleReconnectAttempt([int? code]) {
    if (_destroying) return;

    final elapsed = DateTime.now().difference(_reconnectStartedAt);
    final remaining = SignalingConfig.reconnectWindow - elapsed;
    if (remaining <= Duration.zero) {
      _failReconnect();
      return;
    }

    var delay = SignalingConfig.reconnectBaseDelay * (1 << _reconnectAttempt);
    if (delay > SignalingConfig.reconnectMaxDelay) {
      delay = SignalingConfig.reconnectMaxDelay;
    }
    if (delay > remaining) delay = remaining;

    _reconnectAttempt++;
    _emitSignaling(SignalingStatus.reconnecting, closeCode: code);

    _reconnectTimer = Timer(delay, () {
      _reconnectTimer = null;
      if (_destroying) return;
      _openSignalingSocket(isReconnect: true).then((_) {
        if (_destroying) return;
        _reconnecting = false;
        _emitSignaling(SignalingStatus.reconnected);
        _reconnectAttempt = 0;
      }, onError: (Object _) {
        _scheduleReconnectAttempt();
      });
    });
  }

  void _failReconnect() {
    _reconnecting = false;
    _wsOutbox.clear();
    _emitSignaling(SignalingStatus.failed);
    _state = CallState.ended;
    _emitState(CallState.ended, reason: 'Signaling connection lost');
    destroy(sendHangup: false);
  }

  void _flushWsOutbox() {
    if (_wsOutbox.isEmpty) return;
    final queued = List<WsEventMessage>.of(_wsOutbox);
    _wsOutbox.clear();
    for (final msg in queued) {
      sendWsEvent(msg.event, msg.data);
    }
  }

  /// Periodic app-level ping (server replies `session.pong`). Also detects
  /// half-open connections: no inbound message for 60s => reconnect.
  void _startWsPing() {
    _stopWsPing();
    _lastWsMessageAt = DateTime.now();
    _pingTimer = Timer.periodic(SignalingConfig.pingInterval, (_) {
      final channel = _wsChannel;
      if (channel == null) return;
      if (DateTime.now().difference(_lastWsMessageAt) >
          SignalingConfig.idleTimeout) {
        developer.log(
          'Call[$callId] signaling idle timeout, reconnecting',
          name: 'FiretellSDK',
        );
        _detachChannel(channel);
        _handleSignalingClose(SignalingConfig.closeDeadConnection);
        return;
      }
      sendWsEvent('session.ping', {});
    });
  }

  void _stopWsPing() {
    _pingTimer?.cancel();
    _pingTimer = null;
  }

  /// Stop listening to and close a socket without triggering close handling.
  void _detachChannel(WebSocketChannel channel, [int? closeCode]) {
    if (identical(_wsChannel, channel)) {
      _wsSubscription?.cancel();
      _wsSubscription = null;
      _wsChannel = null;
    }
    try {
      channel.sink.close(closeCode);
    } catch (_) {
      // Ignore WS close errors during cleanup
    }
  }

  void _emitSignaling(SignalingStatus status, {int? closeCode}) {
    if (!_signalingController.isClosed) {
      _signalingController.add(
        (status: status, attempt: _reconnectAttempt, closeCode: closeCode),
      );
    }
  }

  // ─── WS Message Handler ────────────────────────────────────────────

  void _handleWsMessage(WsEventMessage msg) {
    final data = msg.data;

    switch (msg.event) {
      case 'session.pong':
        // Keep-alive reply; activity timestamp already updated.
        break;

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
          } else if (sdpInit?.sdp != null &&
              RegExp(r'm=video [1-9]').hasMatch(sdpInit!.sdp!)) {
            isVideo = true;
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

      case 'call.camera':
        final enabled = data?['enabled'] != false;
        // Broadcast camera state event for remote camera toggle
        _emitState(_state, data: {'event': 'camera', 'enabled': enabled});

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
      // Auto-detect video from remote offer if isVideo was false
      if (!isVideo &&
          remoteDescription?.sdp != null &&
          RegExp(r'm=video [1-9]').hasMatch(remoteDescription!.sdp!)) {
        isVideo = true;
      }

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

  // ─── Speakerphone ──────────────────────────────────────────────────

  /// Turn speakerphone on or off.
  ///
  /// When [enable] is true, audio routes to device loudspeaker.
  /// When [enable] is false, audio routes to earpiece.
  Future<void> setSpeakerphoneOn(bool enable) async {
    await Helper.setSpeakerphoneOn(enable);
    isSpeakerOn = enable;
    if (!_speakerController.isClosed) {
      _speakerController.add(enable);
    }
  }

  /// Toggle speakerphone state.
  Future<void> toggleSpeaker() async {
    await setSpeakerphoneOn(!isSpeakerOn);
  }

  // ─── Video & Camera ────────────────────────────────────────────────

  /// Mute local video track (turns off camera transmission).
  Future<void> muteVideo() async {
    final stream = _localStream;
    if (stream == null) return;
    for (final track in stream.getVideoTracks()) {
      track.enabled = false;
    }
    isCameraOff = true;
    sendWsEvent('call.camera', {'muted': true});
    if (!_cameraController.isClosed) {
      _cameraController.add(true);
    }
  }

  /// Unmute local video track (resumes camera transmission).
  Future<void> unmuteVideo() async {
    final stream = _localStream;
    if (stream == null) return;
    for (final track in stream.getVideoTracks()) {
      track.enabled = true;
    }
    isCameraOff = false;
    sendWsEvent('call.camera', {'muted': false});
    if (!_cameraController.isClosed) {
      _cameraController.add(false);
    }
  }

  /// Toggle camera transmission on/off.
  Future<void> toggleCamera() async {
    if (isCameraOff) {
      await unmuteVideo();
    } else {
      await muteVideo();
    }
  }

  /// Switch between front and back camera.
  Future<void> switchCamera() async {
    final stream = _localStream;
    if (stream == null) return;
    final videoTracks = stream.getVideoTracks();
    if (videoTracks.isEmpty) return;
    await Helper.switchCamera(videoTracks[0]);
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

    // Stop keep-alive / reconnect machinery
    _stopWsPing();
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _reconnecting = false;
    _signalingReady = false;
    _wsOutbox.clear();

    // Close dedicated call WebSocket (1000 = intentional, server cleans up
    // immediately instead of waiting for the reconnect grace period)
    final channel = _wsChannel;
    if (channel != null) _detachChannel(channel, 1000);

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
    _cameraController.close();
    _speakerController.close();
    _mediaStateController.close();
    _signalingController.close();
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
    // Make sure TURN credentials are fresh before creating the peer connection
    await _resolveIceServers();

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

  /// Resolve ICE servers from [iceServersProvider] (if any). Never throws;
  /// keeps the current [iceServers] on failure.
  Future<void> _resolveIceServers() async {
    final provider = iceServersProvider;
    if (provider == null) return;
    try {
      final servers = await provider();
      if (servers.isNotEmpty) iceServers = servers;
    } catch (e) {
      developer.log(
        'Call: failed to resolve ICE servers, using cached: $e',
        name: 'FiretellSDK',
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
    isCameraOff = false;
    if (isSpeakerOn) {
      try {
        Helper.setSpeakerphoneOn(false);
      } catch (_) {}
      isSpeakerOn = false;
    }
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

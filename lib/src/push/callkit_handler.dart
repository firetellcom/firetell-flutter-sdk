import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter_callkit_incoming/entities/call_event.dart';
import 'package:flutter_callkit_incoming/entities/call_kit_params.dart';
import 'package:flutter_callkit_incoming/entities/ios_params.dart';
import 'package:flutter_callkit_incoming/entities/android_params.dart';
import 'package:flutter_callkit_incoming/entities/notification_params.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';

import '../call.dart';
import '../firetell_client.dart';
import '../models/call_ring_params.dart';

/// Callback invoked when a push-originated call is successfully connected
/// and ready for media (after user answers on CallKit / lock screen).
typedef OnCallConnected = void Function(Call call);

/// Callback invoked when a call is declined or ended from the native UI.
typedef OnCallDeclined = void Function(String callId);

/// Callback invoked when a call times out or an error occurs.
typedef OnCallError = void Function(String callId, Object error);

/// Bridges `flutter_callkit_incoming` (CallKit on iOS / ConnectionService on
/// Android) with the Firetell SDK's WebRTC call lifecycle.
///
/// Handles the critical **locked screen → answer → WebRTC connect** flow:
///
/// ```
/// VoIP Push → showIncomingCall() → User swipes "Answer" on lock screen
///   → CallKit EVENT_ACTION_CALL_ACCEPT
///   → handlePushIncomingCall() → connectSignaling() → accept() → media flows
/// ```
///
/// Usage:
/// ```dart
/// final callKitHandler = CallKitHandler(client: firetellClient);
///
/// callKitHandler.onCallConnected = (call) {
///   // Navigate to in-call screen, attach remote audio renderer
/// };
///
/// callKitHandler.onCallDeclined = (callId) {
///   // Dismiss any pending UI
/// };
///
/// // When VoIP push arrives:
/// final ringParams = CallRingParams.fromFcmData(pushData);
/// await callKitHandler.showIncomingCall(ringParams);
/// ```
class CallKitHandler {
  CallKitHandler({
    required this.client,
  }) {
    _listenCallKitEvents();
  }

  /// The Firetell client instance used to create call sessions.
  final FiretellClient client;

  /// Called when a push-originated call is answered and WebRTC is ready.
  OnCallConnected? onCallConnected;

  /// Called when a call is declined from the native call UI.
  OnCallDeclined? onCallDeclined;

  /// Called when an error occurs during call setup.
  OnCallError? onCallError;

  /// Active ring params indexed by call ID, kept for lookup on answer/decline.
  final Map<String, CallRingParams> _pendingCalls = {};

  /// Active Call instances being set up (prevents duplicate answer handling).
  final Map<String, Call> _connectingCalls = {};

  StreamSubscription<CallEvent?>? _callKitSubscription;

  /// Show the native incoming call UI (CallKit on iOS, notification on Android).
  ///
  /// Call this when a VoIP push notification is received.
  /// The handler will automatically manage answer/decline/timeout events.
  Future<void> showIncomingCall(CallRingParams params) async {
    _pendingCalls[params.callId] = params;

    final callKitParams = CallKitParams(
      id: params.callId,
      nameCaller: params.callerName.isNotEmpty
          ? params.callerName
          : params.callerNumber,
      handle: params.callerNumber,
      type: params.isVideo ? 1 : 0, // 0 = audio, 1 = video
      duration: params.ringTimeoutSecs * 1000,
      extra: params.toMap(),
      ios: const IOSParams(
        supportsVideo: false,
        maximumCallGroups: 1,
        maximumCallsPerCallGroup: 1,
        audioSessionMode: 'voiceChat',
        audioSessionActive: true,
        audioSessionPreferredSampleRate: 44100.0,
        audioSessionPreferredIOBufferDuration: 0.005,
        ringtonePath: null,
      ),
      android: const AndroidParams(
        isShowLogo: false,
        ringtonePath: null,
        backgroundColor: '#1a1a2e',
        actionColor: '#4fd1c5',
        isShowFullLockedScreen: true,
        isShowCallID: true,
      ),
      notification: const NotificationParams(
        showNotification: true,
        isShowMissedCallNotification: true,
      ),
    );

    await FlutterCallkitIncoming.showCallkitIncoming(callKitParams);
  }

  /// Dismiss the native incoming call UI for a specific call.
  Future<void> dismissIncomingCall(String callId) async {
    _pendingCalls.remove(callId);
    await FlutterCallkitIncoming.endCall(callId);
  }

  /// Dismiss all pending incoming call UIs.
  Future<void> dismissAllCalls() async {
    _pendingCalls.clear();
    await FlutterCallkitIncoming.endAllCalls();
  }

  /// Clean up resources. Call this when the handler is no longer needed.
  void dispose() {
    _callKitSubscription?.cancel();
    _callKitSubscription = null;
    _pendingCalls.clear();
    _connectingCalls.clear();
  }

  // ─── CallKit Event Listener ────────────────────────────────────────

  void _listenCallKitEvents() {
    _callKitSubscription =
        FlutterCallkitIncoming.onEvent.listen((CallEvent? event) {
      if (event == null) return;

      switch (event.event) {
        case Event.actionCallAccept:
          _handleAccept(event);
        case Event.actionCallDecline:
          _handleDecline(event);
        case Event.actionCallEnded:
          _handleEnded(event);
        case Event.actionCallTimeout:
          _handleTimeout(event);
        default:
          break;
      }
    });
  }

  /// User tapped "Answer" on CallKit UI (including locked screen).
  ///
  /// This is the critical path: must quickly connect WS + setup WebRTC
  /// before the call times out on the server side.
  Future<void> _handleAccept(CallEvent event) async {
    final callId = _extractCallId(event);
    if (callId == null) return;

    final params = _pendingCalls.remove(callId);
    if (params == null) {
      developer.log(
        'CallKitHandler: No pending call found for $callId',
        name: 'FiretellSDK',
      );
      return;
    }

    // Prevent duplicate answer handling
    if (_connectingCalls.containsKey(callId)) return;

    try {
      // 1. Connect per-call WebSocket (authenticated via call_token)
      final call = await client.handlePushIncomingCall(params);
      _connectingCalls[callId] = call;

      // 2. Setup WebRTC media + send SDP answer
      await call.accept();

      _connectingCalls.remove(callId);

      // 3. Notify consumer — call is live, media flowing
      onCallConnected?.call(call);
    } catch (e) {
      _connectingCalls.remove(callId);
      developer.log(
        'CallKitHandler: Failed to connect call $callId: $e',
        name: 'FiretellSDK',
      );
      // End the CallKit call since WebRTC setup failed
      await FlutterCallkitIncoming.endCall(callId);
      onCallError?.call(callId, e);
    }
  }

  /// User tapped "Decline" on CallKit UI.
  ///
  /// Uses fast HTTP reject (no WS needed) — ~50ms response time.
  Future<void> _handleDecline(CallEvent event) async {
    final callId = _extractCallId(event);
    if (callId == null) return;

    final params = _pendingCalls.remove(callId);
    if (params == null) return;

    // Fast HTTP reject using call_token — no WebSocket needed
    final call = Call(iceServers: client.iceServers);
    call.callId = callId;
    await call.rejectViaHttp(
      baseUrl: client.baseUrl,
      callToken: params.callToken,
    );

    onCallDeclined?.call(callId);
  }

  /// Call ended from the native UI (e.g. user pulled down notification).
  Future<void> _handleEnded(CallEvent event) async {
    final callId = _extractCallId(event);
    if (callId == null) return;

    _pendingCalls.remove(callId);

    // If there's an active call, hang it up
    final activeCall = client.activeCalls[callId];
    if (activeCall != null) {
      await activeCall.hangup();
    }

    // If there's a connecting call, destroy it
    final connectingCall = _connectingCalls.remove(callId);
    if (connectingCall != null) {
      await connectingCall.destroy(sendHangup: true);
    }
  }

  /// Call timed out (ring expired).
  Future<void> _handleTimeout(CallEvent event) async {
    final callId = _extractCallId(event);
    if (callId == null) return;

    _pendingCalls.remove(callId);
    _connectingCalls.remove(callId);

    developer.log(
      'CallKitHandler: Call $callId timed out',
      name: 'FiretellSDK',
    );
  }

  String? _extractCallId(CallEvent event) {
    final body = event.body as Map<String, dynamic>?;
    return body?['id']?.toString() ?? body?['callId']?.toString();
  }
}

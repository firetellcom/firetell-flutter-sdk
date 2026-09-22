import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter_callkit_incoming/entities/call_event.dart' as callkit;
import 'package:flutter_callkit_incoming/entities/call_kit_params.dart';
import 'package:flutter_callkit_incoming/entities/ios_params.dart';
import 'package:flutter_callkit_incoming/entities/android_params.dart';
import 'package:flutter_callkit_incoming/entities/notification_params.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';

import '../call.dart';
import '../firetell_client.dart';
import '../models/call_ring_params.dart';
import '../utils/call_id_mapper.dart';

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
///   → CallKit EventActionCallAccept
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

  /// Active ring params indexed by **server call ID**, kept for lookup on
  /// answer/decline.
  final Map<String, CallRingParams> _pendingCalls = {};

  /// Active Call instances being set up (prevents duplicate answer handling).
  /// Also indexed by **server call ID**.
  final Map<String, Call> _connectingCalls = {};

  StreamSubscription<callkit.CallEvent?>? _callKitSubscription;

  /// Convenience accessor for the call ID mapper singleton.
  final _mapper = CallIdMapper.instance;

  /// Show the native incoming call UI (CallKit on iOS, notification on Android).
  ///
  /// Call this when a VoIP push notification is received.
  /// The handler will automatically manage answer/decline/timeout events.
  ///
  /// On iOS, CallKit requires the call ID to be a UUID. This method
  /// automatically maps [params.callId] (the server format, e.g.
  /// `call_xxxxxxxx`) to a generated UUID via [CallIdMapper], so that
  /// all internal operations (WebSocket, HTTP reject) continue using
  /// the server call ID.
  Future<void> showIncomingCall(CallRingParams params) async {
    // Store pending call by server call ID (used by WS / HTTP operations).
    _pendingCalls[params.callId] = params;

    // iOS CallKit requires a UUID — map server ID → UUID and persist the
    // mapping so we can reverse-lookup on accept/decline/end events.
    final iosUuid = _mapper.register(params.callId);

    developer.log(
      'CallKitHandler: showIncomingCall serverCallId=${params.callId} iosUuid=$iosUuid',
      name: 'FiretellSDK',
    );

    final callKitParams = CallKitParams(
      id: iosUuid,
      nameCaller: params.callerName.isNotEmpty
          ? params.callerName
          : params.callerNumber,
      handle: params.callerNumber,
      type: params.isVideo ? 1 : 0, // 0 = audio, 1 = video
      duration: params.ringTimeoutSecs * 1000,
      // Store the full params map in `extra` so we can reconstruct
      // CallRingParams even if the app was killed and restarted.
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
      missedCallNotification: const NotificationParams(
        showNotification: true,
        isShowCallback: true,
      ),
      callingNotification: const NotificationParams(
        showNotification: true,
      ),
    );

    await FlutterCallkitIncoming.showCallkitIncoming(callKitParams);
  }

  /// Dismiss the native incoming call UI for a specific call.
  ///
  /// [serverCallId] is the Firetell server call ID (e.g. `call_xxxxxxxx`).
  /// The corresponding iOS UUID is resolved automatically.
  Future<void> dismissIncomingCall(String serverCallId) async {
    _pendingCalls.remove(serverCallId);
    // Resolve the iOS UUID that was registered when showIncomingCall() ran.
    final iosUuid = _mapper.uuidFromServerId(serverCallId) ?? serverCallId;
    _mapper.remove(serverCallId);
    await FlutterCallkitIncoming.endCall(iosUuid);
  }

  /// Dismiss all pending incoming call UIs.
  Future<void> dismissAllCalls() async {
    _pendingCalls.clear();
    _mapper.clear();
    await FlutterCallkitIncoming.endAllCalls();
  }

  /// Clean up resources. Call this when the handler is no longer needed.
  void dispose() {
    _callKitSubscription?.cancel();
    _callKitSubscription = null;
    _pendingCalls.clear();
    _connectingCalls.clear();
    _mapper.clear();
  }

  // ─── CallKit Event Listener ────────────────────────────────────────

  void _listenCallKitEvents() {
    _callKitSubscription =
        FlutterCallkitIncoming.onEvent.listen((callkit.CallEvent? event) {
      if (event == null) return;

      switch (event) {
        case callkit.CallEventActionCallAccept():
          _handleAccept(event);
        case callkit.CallEventActionCallDecline():
          _handleDecline(event);
        case callkit.CallEventActionCallEnded():
          _handleEnded(event);
        case callkit.CallEventActionCallTimeout():
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
  Future<void> _handleAccept(callkit.CallEvent event) async {
    final serverCallId = _extractServerCallId(event);
    if (serverCallId == null) return;

    var params = _pendingCalls.remove(serverCallId);
    if (params == null && event is callkit.CallEventActionCallAccept) {
      // Fallback: reconstruct from the `extra` map we stored in showIncomingCall.
      final extra = event.callKitParams.extra;
      if (extra != null) {
        params = CallRingParams.fromMap(extra);
      }
    }
    if (params == null) {
      developer.log(
        'CallKitHandler: No pending call found for serverCallId=$serverCallId',
        name: 'FiretellSDK',
      );
      return;
    }

    // Prevent duplicate answer handling
    if (_connectingCalls.containsKey(serverCallId)) return;

    // Resolve iOS UUID for any CallKit calls needed in the error path.
    final iosUuid =
        _mapper.uuidFromServerId(serverCallId) ?? serverCallId;

    try {
      // 1. Connect per-call WebSocket (authenticated via call_token)
      final call = await client.handlePushIncomingCall(params);
      _connectingCalls[serverCallId] = call;

      // 2. Setup WebRTC media + send SDP answer
      await call.accept();

      _connectingCalls.remove(serverCallId);
      _mapper.remove(serverCallId);

      // 3. Notify consumer — call is live, media flowing
      onCallConnected?.call(call);
    } catch (e) {
      _connectingCalls.remove(serverCallId);
      _mapper.remove(serverCallId);
      developer.log(
        'CallKitHandler: Failed to connect call serverCallId=$serverCallId: $e',
        name: 'FiretellSDK',
      );
      // End the CallKit call (by iOS UUID) since WebRTC setup failed.
      await FlutterCallkitIncoming.endCall(iosUuid);
      onCallError?.call(serverCallId, e);
    }
  }

  /// User tapped "Decline" on CallKit UI.
  ///
  /// Uses fast HTTP reject (no WS needed) — ~50ms response time.
  Future<void> _handleDecline(callkit.CallEvent event) async {
    final serverCallId = _extractServerCallId(event);
    if (serverCallId == null) return;

    var params = _pendingCalls.remove(serverCallId);
    if (params == null && event is callkit.CallEventActionCallDecline) {
      final extra = event.callKitParams.extra;
      if (extra != null) {
        params = CallRingParams.fromMap(extra);
      }
    }

    _mapper.remove(serverCallId);

    if (params == null) return;

    // Fast HTTP reject using call_token — no WebSocket needed
    final call = Call(iceServers: client.iceServers);
    call.callId = serverCallId;
    await call.rejectViaHttp(
      baseUrl: client.baseUrl,
      callToken: params.callToken,
    );

    onCallDeclined?.call(serverCallId);
  }

  /// Call ended from the native UI (e.g. user pulled down notification).
  Future<void> _handleEnded(callkit.CallEvent event) async {
    final serverCallId = _extractServerCallId(event);
    if (serverCallId == null) return;

    _pendingCalls.remove(serverCallId);
    _mapper.remove(serverCallId);

    // If there's an active call, hang it up
    final activeCall = client.activeCalls[serverCallId];
    if (activeCall != null) {
      await activeCall.hangup();
    }

    // If there's a connecting call, destroy it
    final connectingCall = _connectingCalls.remove(serverCallId);
    if (connectingCall != null) {
      await connectingCall.destroy(sendHangup: true);
    }
  }

  /// Call timed out (ring expired).
  Future<void> _handleTimeout(callkit.CallEvent event) async {
    final serverCallId = _extractServerCallId(event);
    if (serverCallId == null) return;

    _pendingCalls.remove(serverCallId);
    _connectingCalls.remove(serverCallId);
    _mapper.remove(serverCallId);

    developer.log(
      'CallKitHandler: Call serverCallId=$serverCallId timed out',
      name: 'FiretellSDK',
    );
  }

  /// Extract the **server call ID** from a CallKit event.
  ///
  /// CallKit events carry an iOS UUID as the call identifier. This method
  /// resolves that UUID back to the Firetell server call ID using
  /// [CallIdMapper]. If the UUID is not found in the mapper (e.g. on
  /// Android where IDs are not UUIDs, or for non-push calls), the raw
  /// value from the event is returned as a fallback.
  String? _extractServerCallId(callkit.CallEvent event) {
    final rawId = _extractRawCallKitId(event);
    if (rawId == null) return null;

    // Attempt to resolve iOS UUID → server call ID.
    final serverId = _mapper.serverIdFromUuid(rawId);
    if (serverId != null) return serverId;

    // Fallback: the raw ID may already be a server call ID (Android, or
    // outbound calls that never went through showIncomingCall).
    return rawId;
  }

  /// Extract the raw ID string directly from the CallKit event payload.
  String? _extractRawCallKitId(callkit.CallEvent event) {
    if (event is callkit.CallEventActionCallAccept) {
      return event.callKitParams.id;
    } else if (event is callkit.CallEventActionCallDecline) {
      return event.callKitParams.id;
    } else if (event is callkit.CallEventActionCallEnded) {
      return event.callKitParams.id;
    } else if (event is callkit.CallEventActionCallTimeout) {
      return event.id;
    } else if (event is callkit.CallEventActionCallConnected) {
      return event.id;
    } else if (event is callkit.CallEventActionCallCallback) {
      return event.id;
    } else if (event is callkit.CallEventActionCallIncoming) {
      return event.callKitParams.id;
    } else if (event is callkit.CallEventActionCallStart) {
      return event.callKitParams.id;
    } else if (event is callkit.CallEventActionCallCustom) {
      return event.body['id']?.toString() ?? event.body['callId']?.toString();
    }
    return null;
  }
}

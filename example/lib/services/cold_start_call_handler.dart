import 'dart:async';

import 'package:firetell_flutter_sdk/firetell_flutter_sdk.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_callkit_incoming/entities/call_event.dart' as callkit;
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';

/// Handles the **cold-start answer** flow when the app is completely killed
/// and a VoIP push wakes it.
///
/// The push payload already contains everything needed:
/// - `ws_url` — per-call WebSocket signaling URL
/// - `call_token` — JWT for WebSocket authentication
/// - `call_id` — unique call identifier
///
/// So we can connect the call **directly** without:
/// - ❌ No `FiretellClient` needed
/// - ❌ No stored credentials needed
/// - ❌ No SSE stream needed
/// - ❌ No workspace metadata fetch needed
///
/// Timeline:
/// ```
/// App killed → VoIP push → native CallKit UI on lock screen
///   → User swipes "Answer"
///   → iOS/Android cold-starts the app
///   → main() → ColdStartCallHandler.initialize()
///   → CallEventActionCallAccept fires
///   → Call(iceServers) → connectSignaling(ws_url, call_token)
///   → call.accept() → audio flows ✅
/// ```
class ColdStartCallHandler {
  ColdStartCallHandler._();

  static StreamSubscription<callkit.CallEvent?>? _subscription;

  /// The call that was connected during cold start.
  /// HomeScreen can pick this up when it mounts.
  static Call? activeCall;

  /// Callback for when a push-originated call is connected.
  /// Set this from your UI layer to navigate to the call screen.
  static void Function(Call call)? onCallConnected;

  /// Initialize the global CallKit event listener.
  ///
  /// Call this in `main()` BEFORE `runApp()`.
  static void initialize() {
    _subscription?.cancel();
    _subscription =
        FlutterCallkitIncoming.onEvent.listen(_handleCallKitEvent);
  }

  static void dispose() {
    _subscription?.cancel();
    _subscription = null;
  }

  static Future<void> _handleCallKitEvent(callkit.CallEvent? event) async {
    if (event == null) return;

    switch (event) {
      case callkit.CallEventActionCallAccept():
        await _handleAccept(event);
      case callkit.CallEventActionCallDecline():
        await _handleDecline(event);
      default:
        break;
    }
  }

  /// User answered from CallKit UI (lock screen / background).
  ///
  /// Uses `ws_url` + `call_token` directly from the push payload —
  /// no FiretellClient or stored credentials needed.
  static Future<void> _handleAccept(callkit.CallEventActionCallAccept event) async {
    final callId = event.callKitParams.id;
    final extra = event.callKitParams.extra;
    if (extra == null) return;

    debugPrint('ColdStartCallHandler: Answering $callId');

    try {
      final params = CallRingParams.fromMap(extra);

      // ws_url and call_token come directly from the push payload
      final wsUrl = params.wsUrl;
      final callToken = params.callToken;

      if (wsUrl == null || wsUrl.isEmpty || callToken.isEmpty) {
        debugPrint('ColdStartCallHandler: Missing ws_url or call_token');
        FlutterCallkitIncoming.endCall(callId);
        return;
      }

      // Load cached ICE servers (workspace TURN) or fall back to defaults
      final iceServers = await IceServerCache.load();

      final call = Call(
        iceServers: iceServers,
        options: CallOptions(
          to: params.calleeNumber,
          from: params.callerNumber,
          fromName: params.callerName,
          fromAvatar: params.callerAvatar,
          isVideo: params.isVideo,
          isTransfer: params.isTransfer,
          transferReason: params.transferReason,
        ),
      );
      call.callId = callId;

      // Connect WS (3s auth timeout) + accept (WebRTC setup)
      await call.connectSignaling(wsUrl, callToken);
      await call.accept();

      activeCall = call;
      debugPrint('ColdStartCallHandler: Call $callId connected ✅');

      onCallConnected?.call(call);
    } catch (e) {
      debugPrint('ColdStartCallHandler: Failed to answer $callId: $e');
      FlutterCallkitIncoming.endCall(callId);
    }
  }

  /// User declined from CallKit UI — fast HTTP reject using call_token.
  static Future<void> _handleDecline(callkit.CallEventActionCallDecline event) async {
    final callId = event.callKitParams.id;
    final extra = event.callKitParams.extra;
    if (extra == null) return;

    debugPrint('ColdStartCallHandler: Declining $callId');

    final callToken = extra['call_token'] as String?;
    final wsUrl = extra['ws_url'] as String?;

    if (callToken != null && wsUrl != null) {
      // Extract base URL from ws_url (wss://host/ws → https://host)
      final baseUrl = _wsUrlToBaseUrl(wsUrl);
      if (baseUrl != null) {
        final call = Call(iceServers: []);
        call.callId = callId;
        await call.rejectViaHttp(
          baseUrl: baseUrl,
          callToken: callToken,
        );
      }
    }
  }

  /// Convert WebSocket URL to HTTP base URL.
  /// `wss://ws_123.firetell.app/ws` → `https://ws_123.firetell.app`
  static String? _wsUrlToBaseUrl(String wsUrl) {
    try {
      final uri = Uri.parse(wsUrl);
      final scheme = uri.scheme == 'wss' ? 'https' : 'http';
      return '$scheme://${uri.host}${uri.port != 443 && uri.port != 80 ? ':${uri.port}' : ''}';
    } catch (_) {
      return null;
    }
  }
}

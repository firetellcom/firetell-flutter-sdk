import 'dart:async';

import 'package:firetell_flutter_sdk/firetell_flutter_sdk.dart';
import 'package:flutter/material.dart';
import 'package:flutter_callkit_incoming/entities/call_event.dart' as callkit;
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';

import '../screens/call_screen.dart';
import '../screens/video_call_screen.dart';

/// Handles the **cold-start answer** flow when the app is completely killed
/// and a VoIP push wakes it.
///
/// Handles the critical edge-case:
/// **App killed → phone locked → answer from lock screen → user talks for
/// a few seconds → user unlocks device**.
///
/// When the device is unlocked (`AppLifecycleState.resumed`), automatically
/// routes to [CallScreen] or [VideoCallScreen] so the user has full in-call controls.
class ColdStartCallHandler {
  ColdStartCallHandler._();

  static StreamSubscription<callkit.CallEvent?>? _subscription;
  static _ColdStartLifecycleObserver? _lifecycleObserver;

  /// Global navigator key used to push CallScreen / VideoCallScreen when
  /// the app transitions to foreground after user unlocks device.
  static GlobalKey<NavigatorState>? navigatorKey;

  /// The call that was connected during cold start.
  static Call? activeCall;

  /// Whether the in-call screen is currently displayed.
  static bool isCallScreenPresented = false;

  /// Callback for when a push-originated call is connected.
  static void Function(Call call)? onCallConnected;

  /// Initialize the global CallKit event listener and lifecycle observer.
  ///
  /// Call this in `main()` BEFORE `runApp()`.
  static void initialize({GlobalKey<NavigatorState>? navKey}) {
    navigatorKey = navKey;
    _subscription?.cancel();
    _subscription =
        FlutterCallkitIncoming.onEvent.listen(_handleCallKitEvent);

    if (_lifecycleObserver == null) {
      _lifecycleObserver = _ColdStartLifecycleObserver();
      WidgetsBinding.instance.addObserver(_lifecycleObserver!);
    }
  }

  static void dispose() {
    _subscription?.cancel();
    _subscription = null;
    if (_lifecycleObserver != null) {
      WidgetsBinding.instance.removeObserver(_lifecycleObserver!);
      _lifecycleObserver = null;
    }
  }

  /// Automatically navigate to the in-call screen if an active call exists
  /// and is not already displayed (e.g., when the user unlocks the device).
  static void checkAndNavigateToActiveCall() {
    final call = activeCall;
    if (call == null || !call.active || isCallScreenPresented) return;

    final nav = navigatorKey?.currentState;
    if (nav == null) return;

    isCallScreenPresented = true;
    nav.push(
      MaterialPageRoute(
        builder: (_) => call.isVideo
            ? VideoCallScreen(call: call)
            : CallScreen(call: call),
      ),
    ).then((_) {
      isCallScreenPresented = false;
    });
  }

  static Future<void> _handleCallKitEvent(callkit.CallEvent? event) async {
    if (event == null) return;

    switch (event) {
      case callkit.CallEventActionCallAccept():
        if (activeCall != null &&
            activeCall!.callId == event.callKitParams.id) {
          // User tapped into the app while call is already connected
          checkAndNavigateToActiveCall();
        } else {
          await _handleAccept(event);
        }
      case callkit.CallEventActionCallDecline():
        await _handleDecline(event);
      case callkit.CallEventActionCallEnded():
        if (activeCall != null &&
            activeCall!.callId == event.callKitParams.id) {
          await activeCall?.hangup();
          activeCall = null;
          isCallScreenPresented = false;
        }
      case callkit.CallEventActionCallCustom():
        // User tapped CallKit ongoing notification / banner
        checkAndNavigateToActiveCall();
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

      // Listen for call termination to reset activeCall state
      call.onStateChange.listen((stateEvent) {
        if (stateEvent.state == CallState.ended ||
            stateEvent.state == CallState.error ||
            stateEvent.state == CallState.cancel) {
          if (activeCall?.callId == call.callId) {
            activeCall = null;
            isCallScreenPresented = false;
          }
        }
      });

      onCallConnected?.call(call);

      // Try navigating immediately if the app is already in foreground / unlocked
      WidgetsBinding.instance.addPostFrameCallback((_) {
        checkAndNavigateToActiveCall();
      });
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

/// Listens for app resume events (e.g. user unlocking device while a call is active)
/// and triggers navigation to the active call screen.
class _ColdStartLifecycleObserver with WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ColdStartCallHandler.checkAndNavigateToActiveCall();
    }
  }
}

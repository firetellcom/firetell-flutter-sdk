import 'dart:async';

import 'package:firetell_flutter_sdk/firetell_flutter_sdk.dart';
import 'package:flutter/material.dart';
import 'package:flutter_callkit_incoming/entities/call_event.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';


import '../services/push_notification_service.dart';
import 'call_screen.dart';
import 'dialpad_screen.dart';

/// Home screen — shows connection status, incoming call events, and
/// provides access to the dial pad.
///
/// Also wires up:
/// - Push token registration (FCM / APNs)
/// - CallKit event listener for push-originated answer/decline
/// - SSE incoming call dialog for foreground calls
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.client, required this.session});

  final FiretellClient client;
  final Session session;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final CallKitHandler _callKitHandler;
  late final StreamSubscription<SseConnectionState> _connectionSub;
  StreamSubscription<CallEvent?>? _callKitEventSub;
  SseConnectionState _connectionState = SseConnectionState.connecting;
  final List<String> _eventLog = [];

  @override
  void initState() {
    super.initState();

    // 1. Register push tokens with Firetell backend
    _registerPushTokens();

    // 2. Listen to SSE connection state
    _connectionSub = widget.client.onConnectionState.listen((state) {
      setState(() => _connectionState = state);
      _log('SSE: ${state.name}');
    });

    // 3. Setup CallKit handler for the SDK-level WS+WebRTC flow
    _callKitHandler = CallKitHandler(client: widget.client);

    _callKitHandler.onCallConnected = (call) {
      _log('Call connected: ${call.callId}');
      _navigateToCallScreen(call);
    };

    _callKitHandler.onCallDeclined = (callId) {
      _log('Call declined: $callId');
    };

    _callKitHandler.onCallError = (callId, error) {
      _log('Call error: $callId — $error');
    };

    // 4. Listen for CallKit events from push-originated calls
    //
    // When the app is in background/terminated and a VoIP push arrives:
    //   background handler → showIncomingCallFromPush() → native CallKit UI
    //   user answers → EVENT_ACTION_CALL_ACCEPT fires HERE in foreground
    //
    // We need to intercept this and connect WS + WebRTC.
    _callKitEventSub =
        FlutterCallkitIncoming.onEvent.listen(_handleCallKitEvent);

    // 5. Check if app was opened from a missed CallKit action
    _checkPendingCallKitActions();

    // 6. Listen to incoming call offers (SSE foreground flow)
    widget.client.onCallOffer.listen((call) {
      _log('Call offer: ${call.callId} from ${call.fromName}');
      _showIncomingCallDialog(call);
    });

    // 7. Listen to call lifecycle events
    widget.client.onCallRing.listen((params) {
      _log('Ring: ${params.callerName} (${params.callerNumber})');
    });

    widget.client.onCallEnded.listen((data) {
      _log('Ended: ${data['call_id'] ?? data['id'] ?? ''}');
    });

    widget.client.onCallCanceled.listen((data) {
      _log('Canceled: ${data['call_id'] ?? data['id'] ?? ''}');
      // Dismiss CallKit UI if still showing
      final callId =
          data['call_id']?.toString() ?? data['id']?.toString();
      if (callId != null) {
        FlutterCallkitIncoming.endCall(callId);
      }
    });
  }

  @override
  void dispose() {
    _connectionSub.cancel();
    _callKitEventSub?.cancel();
    _callKitHandler.dispose();
    super.dispose();
  }

  // ─── Push Registration ─────────────────────────────────────────────

  Future<void> _registerPushTokens() async {
    try {
      await PushNotificationService.initialize(client: widget.client);
      _log('Push tokens registered');
    } catch (e) {
      _log('Push registration failed: $e');
    }
  }

  // ─── CallKit Event Handler (Push-originated calls) ─────────────────

  Future<void> _handleCallKitEvent(CallEvent? event) async {
    if (event == null) return;

    switch (event.event) {
      case Event.actionCallAccept:
        await _handlePushCallAccept(event);
      case Event.actionCallDecline:
        await _handlePushCallDecline(event);
      case Event.actionCallEnded:
        _handlePushCallEnded(event);
      case Event.actionCallTimeout:
        _handlePushCallTimeout(event);
      default:
        break;
    }
  }

  /// User answered from CallKit UI (could be from lock screen / background).
  ///
  /// The `extra` map in CallKitParams contains the original push payload
  /// (CallRingParams.toMap()), so we have call_token and ws_url to
  /// connect the per-call WebSocket.
  Future<void> _handlePushCallAccept(CallEvent event) async {
    final body = event.body as Map<String, dynamic>?;
    if (body == null) return;

    final callId = body['id']?.toString();
    final extra = body['extra'] as Map<String, dynamic>?;

    if (callId == null || extra == null) {
      _log('Accept: missing callId or extra data');
      return;
    }

    // Check if this call is already being handled by CallKitHandler
    if (widget.client.activeCalls.containsKey(callId)) {
      _log('Accept: call $callId already active, skipping');
      return;
    }

    _log('Answering push call: $callId');

    try {
      // Reconstruct CallRingParams from the extra data stored in CallKitParams
      final params = CallRingParams.fromMap(extra);

      // Connect WS + setup WebRTC + send call.answer
      final call = await widget.client.handlePushIncomingCall(params);
      await call.accept();

      _log('Push call connected: $callId');
      _navigateToCallScreen(call);
    } catch (e) {
      _log('Push call accept failed: $e');
      // End CallKit call since setup failed
      FlutterCallkitIncoming.endCall(callId);
    }
  }

  /// User declined from CallKit UI — fast HTTP reject, no WS needed.
  Future<void> _handlePushCallDecline(CallEvent event) async {
    final body = event.body as Map<String, dynamic>?;
    final callId = body?['id']?.toString();
    final extra = body?['extra'] as Map<String, dynamic>?;

    if (callId == null || extra == null) return;

    _log('Declining push call: $callId');

    final callToken = extra['call_token'] as String?;
    if (callToken != null) {
      final call = Call(iceServers: widget.client.iceServers);
      call.callId = callId;
      await call.rejectViaHttp(
        baseUrl: widget.client.baseUrl,
        callToken: callToken,
      );
    }
  }

  void _handlePushCallEnded(CallEvent event) {
    final body = event.body as Map<String, dynamic>?;
    final callId = body?['id']?.toString();
    if (callId == null) return;

    final call = widget.client.activeCalls[callId];
    if (call != null) {
      call.hangup();
    }
  }

  void _handlePushCallTimeout(CallEvent event) {
    final body = event.body as Map<String, dynamic>?;
    final callId = body?['id']?.toString();
    if (callId != null) {
      _log('Push call timed out: $callId');
    }
  }

  /// Check for pending CallKit actions when app launches
  /// (e.g., user answered from terminated state, app is now in foreground).
  Future<void> _checkPendingCallKitActions() async {
    final activeCalls = await FlutterCallkitIncoming.activeCalls();
    if (activeCalls is List && activeCalls.isNotEmpty) {
      _log('Found ${activeCalls.length} pending CallKit call(s)');
      // These will be handled by the onEvent listener above
    }
  }

  // ─── UI Helpers ────────────────────────────────────────────────────

  void _log(String message) {
    final now = DateTime.now();
    final time =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
    setState(() {
      _eventLog.insert(0, '[$time] $message');
      if (_eventLog.length > 50) _eventLog.removeLast();
    });
  }

  void _navigateToCallScreen(Call call) {
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CallScreen(call: call),
      ),
    );
  }

  /// Show in-app incoming call dialog (foreground SSE flow).
  ///
  /// This is used when the app is in foreground and the incoming call
  /// arrives via SSE (not push). Push-originated calls use native
  /// CallKit UI instead.
  void _showIncomingCallDialog(Call call) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Incoming Call'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.phone_callback, size: 48),
            const SizedBox(height: 16),
            Text(
              call.fromName.isNotEmpty ? call.fromName : call.from,
              style: Theme.of(ctx).textTheme.titleLarge,
            ),
            if (call.from.isNotEmpty)
              Text(call.from,
                  style: Theme.of(ctx).textTheme.bodyMedium),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: () async {
              Navigator.of(ctx).pop();
              await call.reject();
              _log('Rejected: ${call.callId}');
            },
            icon: const Icon(Icons.call_end, color: Colors.red),
            label: const Text('Decline'),
          ),
          FilledButton.icon(
            onPressed: () async {
              Navigator.of(ctx).pop();
              try {
                await call.accept();
                _log('Accepted: ${call.callId}');
                _navigateToCallScreen(call);
              } catch (e) {
                _log('Accept error: $e');
              }
            },
            icon: const Icon(Icons.call),
            label: const Text('Answer'),
          ),
        ],
      ),
    );
  }

  Future<void> _logout() async {
    try {
      final deviceId = await DeviceIdHelper.getOrCreate();
      await PushTokenService.logout(
        baseUrl: widget.client.baseUrl,
        jwt: widget.client.jwt,
        deviceId: deviceId,
      );
    } catch (_) {
      // Best-effort logout
    }

    widget.client.destroy();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const _LoggedOutScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isConnected = _connectionState == SseConnectionState.connected;

    return Scaffold(
      appBar: AppBar(
        title: Text('Agent: ${widget.session.username}'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Icon(
              Icons.circle,
              size: 12,
              color: isConnected ? Colors.green : Colors.orange,
            ),
          ),
          IconButton(
            onPressed: _logout,
            icon: const Icon(Icons.logout),
            tooltip: 'Logout',
          ),
        ],
      ),
      body: Column(
        children: [
          // Status card
          Card(
            margin: const EdgeInsets.all(16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(
                    isConnected ? Icons.cloud_done : Icons.cloud_off,
                    color: isConnected ? Colors.green : Colors.orange,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isConnected ? 'Connected' : 'Connecting...',
                          style: theme.textTheme.titleMedium,
                        ),
                        Text(
                          widget.session.domain,
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '${widget.client.activeCalls.length} active',
                    style: theme.textTheme.labelLarge,
                  ),
                ],
              ),
            ),
          ),

          // Event log
          Expanded(
            child: _eventLog.isEmpty
                ? const Center(
                    child: Text(
                      'No events yet.\nMake a call or wait for incoming calls.',
                      textAlign: TextAlign.center,
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _eventLog.length,
                    itemBuilder: (_, i) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Text(
                        _eventLog[i],
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      ),

      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => DialpadScreen(client: widget.client),
            ),
          );
        },
        icon: const Icon(Icons.dialpad),
        label: const Text('Dial'),
      ),
    );
  }
}

class _LoggedOutScreen extends StatelessWidget {
  const _LoggedOutScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.logout, size: 64),
            const SizedBox(height: 16),
            const Text('Logged out'),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () {
                // This should navigate back to LoginScreen
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(
                    builder: (_) => const _LoggedOutScreen(),
                  ),
                );
              },
              child: const Text('Login again'),
            ),
          ],
        ),
      ),
    );
  }
}

# Incoming Calls

Incoming calls can arrive through two channels depending on app state:

| App State | Channel | Mechanism |
|-----------|---------|-----------|
| **Foreground** | SSE stream | `client.onCallRing` |
| **Background / Killed** | VoIP Push | FCM (Android) / APNs (iOS) |

## Foreground — SSE Stream

When the app is in the foreground, incoming calls arrive via the SSE real-time event stream:

```dart
// Listen for incoming call ring notifications
client.onCallRing.listen((CallRingParams params) {
  print('Incoming call from ${params.callerName} (${params.callerNumber})');
  print('Call ID: ${params.callId}');
  print('Is video: ${params.isVideo}');
  print('Is transfer: ${params.isTransfer}');

  // Show your incoming call UI...
});
```

### CallRingParams

| Property | Type | Description |
|----------|------|-------------|
| `callId` | `String` | Unique call ID |
| `callToken` | `String` | JWT for per-call WebSocket auth |
| `wsUrl` | `String?` | WebSocket URL for signaling |
| `callerNumber` | `String` | Caller's phone number or extension |
| `callerName` | `String` | Caller's display name |
| `callerAvatar` | `String?` | Caller's avatar URL |
| `calleeNumber` | `String` | Destination number |
| `calleeName` | `String` | Destination display name |
| `isTransfer` | `bool` | Whether this is a transferred call |
| `transferReason` | `String?` | Transfer reason (if applicable) |
| `isVideo` | `bool` | Whether this is a video call |
| `ringTimeoutSecs` | `int` | Ring timeout in seconds (default: 30) |

### Accepting a Call

```dart
// Create call session and connect WebSocket
final call = await client.handlePushIncomingCall(params);

// Setup WebRTC + send SDP answer
await call.accept();

// Call is now active — audio flowing
call.onStateChange.listen((event) {
  if (event.state == CallState.active) {
    print('Call connected!');
  }
});
```

### Declining a Call

**Option 1: WebSocket reject** (app is connected)

```dart
final call = await client.handlePushIncomingCall(params);
await call.reject();
```

**Option 2: HTTP reject** (faster, no WS needed — preferred for push)

```dart
final call = Call(iceServers: client.iceServers);
call.callId = params.callId;
await call.rejectViaHttp(
  baseUrl: client.baseUrl,
  callToken: params.callToken,
);
```

The HTTP reject completes in ~50ms vs several seconds for WebSocket-based reject.

## Background / Killed — VoIP Push

When the app is in the background or completely terminated, calls arrive via push notifications. See the dedicated [VoIP Push Notifications](voip-push.md) guide for full setup.

### Quick Overview

```dart
// In main.dart — top-level background handler
@pragma('vm:entry-point')
Future<void> _backgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();

  if (message.data['event'] == 'call.ring') {
    final params = CallRingParams.fromFcmData(message.data);
    // Show native incoming call UI
    await FlutterCallkitIncoming.showCallkitIncoming(/* ... */);
  }
}
```

### Parsing Push Payloads

```dart
// From FCM (Android)
final params = CallRingParams.fromFcmData(message.data);

// From APNs (iOS)
final params = CallRingParams.fromApnsPayload(payload);

// From a generic Map
final params = CallRingParams.fromMap(data);
```

### CallCancelParams (Dismiss notification)

```dart
// When a call.canceled or call.ended push arrives
final cancelParams = CallCancelParams.fromFcmData(message.data);
await FlutterCallkitIncoming.endCall(cancelParams.callId);
```

## Incoming Call State Machine

```
Inbound call:

  none → ringing → answered → active → ended
                                 ↕
                              onHold
```

## Next Steps

- [VoIP Push Notifications](voip-push.md) — Full FCM + APNs setup
- [Call Controls](call-controls.md) — Mute, hold, DTMF, transfer

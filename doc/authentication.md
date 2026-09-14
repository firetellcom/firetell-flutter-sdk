# Authentication

## Overview

The Firetell Flutter SDK authenticates using a workspace domain and an agent/client JWT token. The JWT is issued by the your backend and contains the user's identity, workspace ID, and permissions.

## Initializing the Client

```dart
import 'package:firetell_flutter_sdk/firetell_flutter_sdk.dart';

final client = FiretellClient(
  jwt: 'eyJhbGciOiJIUzI1NiIs...',
  domain: 'ws_abc123.firetell.app',
);
```

### Parameters

| Parameter | Type     | Required | Description                                                                                                   |
| --------- | -------- | -------- | ------------------------------------------------------------------------------------------------------------- |
| `jwt`     | `String` | ✅       | Agent/Client JWT issued by your backend                                                                       |
| `domain`  | `String` | ✅       | Workspace API domain. Accepts bare domain (`ws_abc.firetell.app`) or full URL (`https://ws_abc.firetell.app`) |

### What happens during initialization

1. The JWT is decoded to extract `sub` (user ID), `domain`, and `exp` (expiration)
2. A `GET` request is made to `{domain}/api/v1/workspace/metadata` to fetch:
   - `ws_servers` — list of WebSocket server URLs
   - `ice_servers` — STUN/TURN servers for WebRTC (cached locally for push calls)
3. The SSE event stream is connected for real-time workspace events
4. The `ready` future completes with a `Session` object

## Waiting for Ready

```dart
try {
  final session = await client.ready;
  print('Authenticated as: ${session.username}');
  print('Domain: ${session.domain}');
  print('Expires at: ${DateTime.fromMillisecondsSinceEpoch(session.expiresAt)}');
} catch (e) {
  print('Authentication failed: $e');
}
```

## Session Object

```dart
class Session {
  final String sessionId;
  final String username;
  final String displayName;
  final String domain;
  final int expiresAt; // Unix timestamp in milliseconds
}
```

## JWT Payload

The decoded JWT contains:

```dart
class JwtPayload {
  final String sub;        // User ID
  final String domain;     // Workspace domain
  final int iat;           // Issued at (Unix seconds)
  final int exp;           // Expires at (Unix seconds)
  final String aud;        // agent-api or client-api
}
```

You can access the decoded JWT:

```dart
final payload = client.jwtPayload;
print('User ID: ${payload?.sub}');
print('Domain: ${payload?.domain}');
print('Audience: ${payload?.aud}');
```

## SSE Connection State

Monitor the real-time event stream connection:

```dart
client.onConnectionState.listen((state) {
  switch (state) {
    case SseConnectionState.connecting:
      print('Connecting...');
    case SseConnectionState.connected:
      print('Connected ✅');
    case SseConnectionState.disconnected:
      print('Disconnected');
    case SseConnectionState.reconnecting:
      print('Reconnecting...');
    case SseConnectionState.error:
      print('Connection error');
  }
});

// Check current state
print('Connected: ${client.isConnected}');
```

## Logout

```dart
// Graceful logout — hangs up active calls, closes SSE, notifies server
client.logout();

// Full destroy — no server communication, cleanup only
client.destroy();
```

## Error Handling

```dart
client.onError.listen((error) {
  print('Client error: $error');

  // Special case: SSE connection limit exceeded
  // (e.g., same agent logged in on too many devices)
});
```

## Next Steps

- [Outbound Calls](outbound-calls.md)
- [Incoming Calls](incoming-calls.md)

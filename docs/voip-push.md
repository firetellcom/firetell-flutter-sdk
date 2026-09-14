# VoIP Push Notifications

## Overview

VoIP push notifications wake the app when an incoming call arrives while the app is in the background or completely terminated. The SDK supports:

- **Android**: Firebase Cloud Messaging (FCM) data messages
- **iOS**: APNs VoIP push via PushKit (handled by `flutter_callkit_incoming`)

## Architecture

```
Incoming call → Firetell Backend
                    │
        ┌───────────┴───────────┐
        ▼                       ▼
   FCM (Android)          APNs VoIP (iOS)
        │                       │
        ▼                       ▼
  Background Handler     PushKit Delegate
        │                       │
        ▼                       ▼
  flutter_callkit_incoming      │
  (full-screen notification)    │
        │                       ▼
        │              CallKit UI (native)
        │                       │
        └───────────┬───────────┘
                    ▼
          User answers / declines
                    │
        ┌───────────┴───────────┐
        ▼                       ▼
    Answer:                 Decline:
    Call(ws_url, call_token)  rejectViaHttp(call_token)
    → connectSignaling        → POST /calls/{id}/reject
    → accept()                → ~50ms ✅
    → audio flows ✅
```

## Setup

### 1. Firebase Configuration

Follow the standard Firebase Flutter setup:

```bash
flutter pub add firebase_core firebase_messaging
flutterfire configure
```

### 2. Register Push Tokens

After the user logs in and `client.ready` resolves:

```dart
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firetell_flutter_sdk/firetell_flutter_sdk.dart';

Future<void> registerPushTokens(FiretellClient client) async {
  // Request permission (iOS)
  await FirebaseMessaging.instance.requestPermission(
    alert: true,
    badge: true,
    sound: true,
    criticalAlert: true,
  );

  final deviceId = await DeviceIdHelper.getOrCreate();
  final fcmToken = await FirebaseMessaging.instance.getToken();

  if (fcmToken != null) {
    // Register VoIP push token (for call.ring)
    await PushTokenService.registerVoipPushToken(
      baseUrl: client.baseUrl,
      jwt: client.jwt,
      pushToken: fcmToken,
      deviceId: deviceId,
      platform: Platform.isIOS ? 'ios' : 'android',
    );

    // Register notification token (for call.canceled / call.ended)
    await PushTokenService.registerNotificationPushToken(
      baseUrl: client.baseUrl,
      jwt: client.jwt,
      notificationToken: fcmToken,
      deviceId: deviceId,
      platform: Platform.isIOS ? 'ios' : 'android',
    );
  }

  // Handle token refresh
  FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
    await PushTokenService.registerVoipPushToken(
      baseUrl: client.baseUrl,
      jwt: client.jwt,
      pushToken: newToken,
      deviceId: deviceId,
      platform: Platform.isIOS ? 'ios' : 'android',
    );
  });
}
```

### 3. Background Message Handler

**MUST be a top-level function** — runs in a separate isolate:

```dart
// main.dart

@pragma('vm:entry-point')
Future<void> _backgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();

  final event = message.data['event'] as String?;

  if (event == 'call.ring') {
    final params = CallRingParams.fromFcmData(message.data);
    // Show native incoming call UI
    await _showIncomingCallUI(params);
  } else if (event == 'call.canceled' || event == 'call.ended') {
    final callId = message.data['call_id'] as String?;
    if (callId != null) {
      await FlutterCallkitIncoming.endCall(callId);
    }
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  FirebaseMessaging.onBackgroundMessage(_backgroundHandler);
  runApp(const MyApp());
}
```

### 4. Show Native Incoming Call UI

```dart
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';

Future<void> _showIncomingCallUI(CallRingParams params) async {
  final callKitParams = CallKitParams(
    id: params.callId,
    nameCaller: params.callerName.isNotEmpty
        ? params.callerName
        : params.callerNumber,
    handle: params.callerNumber,
    type: params.isVideo ? 1 : 0,
    duration: params.ringTimeoutSecs * 1000,
    extra: params.toMap(), // ← IMPORTANT: stores ws_url + call_token
    ios: const IOSParams(
      supportsVideo: false,
      maximumCallGroups: 1,
      maximumCallsPerCallGroup: 1,
      audioSessionMode: 'voiceChat',
      audioSessionActive: true,
      audioSessionPreferredSampleRate: 44100.0,
      audioSessionPreferredIOBufferDuration: 0.005,
    ),
    android: const AndroidParams(
      isShowFullLockedScreen: true,
      isShowCallID: true,
    ),
  );

  await FlutterCallkitIncoming.showCallkitIncoming(callKitParams);
}
```

> **Critical:** The `extra: params.toMap()` stores the push payload (including `ws_url` and `call_token`) inside the `CallKitParams`. This is how the answer handler retrieves them later.

### 5. Handle Answer / Decline

Listen for CallKit events at the `main()` level to handle cold start:

```dart
// main.dart — BEFORE runApp()
FlutterCallkitIncoming.onEvent.listen((CallEvent? event) async {
  if (event == null) return;

  switch (event.event) {
    case Event.actionCallAccept:
      await _handleAnswer(event);
    case Event.actionCallDecline:
      await _handleDecline(event);
    default:
      break;
  }
});
```

#### Answering from Push (Cold Start)

```dart
Future<void> _handleAnswer(CallEvent event) async {
  final body = event.body as Map<String, dynamic>?;
  final extra = body?['extra'] as Map<String, dynamic>?;
  if (extra == null) return;

  final params = CallRingParams.fromMap(extra);

  // Load cached ICE servers (saved by FiretellClient during normal use)
  final iceServers = await IceServerCache.load();

  // Create Call directly — no FiretellClient needed
  final call = Call(
    iceServers: iceServers,
    options: CallOptions(
      to: params.calleeNumber,
      from: params.callerNumber,
      fromName: params.callerName,
    ),
  );
  call.callId = params.callId;

  // Connect WS + accept — uses ws_url + call_token from push payload
  await call.connectSignaling(params.wsUrl!, params.callToken);
  await call.accept();

  // Audio is now flowing ✅
}
```

#### Declining from Push

```dart
Future<void> _handleDecline(CallEvent event) async {
  final body = event.body as Map<String, dynamic>?;
  final extra = body?['extra'] as Map<String, dynamic>?;
  if (extra == null) return;

  final callId = body?['id']?.toString();
  final callToken = extra['call_token'] as String?;
  final wsUrl = extra['ws_url'] as String?;

  if (callId != null && callToken != null && wsUrl != null) {
    // Extract base URL: wss://host/ws → https://host
    final uri = Uri.parse(wsUrl);
    final baseUrl = '${uri.scheme == 'wss' ? 'https' : 'http'}://${uri.host}';

    final call = Call(iceServers: []);
    call.callId = callId;
    await call.rejectViaHttp(baseUrl: baseUrl, callToken: callToken);
  }
}
```

## Push Payload Format

### call.ring

```json
{
  "event": "call.ring",
  "call_id": "cl_abc123",
  "call_token": "eyJhbGci...",
  "ws_url": "wss://ws_abc.firetell.app/ws",
  "from": {
    "number": "+1234567890",
    "name": "John Doe",
    "avatar": "https://..."
  },
  "to": {
    "number": "1001",
    "name": "Agent Smith"
  },
  "is_video": false,
  "is_transfer": false
}
```

### call.canceled / call.ended

```json
{
  "event": "call.canceled",
  "call_id": "cl_abc123"
}
```

## ICE Server Caching

The SDK automatically caches workspace ICE servers (including TURN credentials) to local storage when `FiretellClient` fetches workspace metadata. On cold start, `IceServerCache.load()` returns the cached servers so push-originated calls use the workspace's TURN servers instead of only public STUN servers.

```dart
// Automatic — FiretellClient does this on init
// Manual usage:
final servers = await IceServerCache.load(); // cached or defaults
await IceServerCache.save(myServers);        // manual cache
await IceServerCache.clear();                // on logout
```

## Device ID

The SDK generates or retrieves a unique device ID for push token registration:

```dart
// Uses native device ID (iOS identifierForVendor / Android androidId)
// Falls back to UUID stored in SharedPreferences
final deviceId = await DeviceIdHelper.getOrCreate();

// Clear on logout
await DeviceIdHelper.clear();
```

## Logout — Unregister Tokens

```dart
await PushTokenService.logout(
  baseUrl: client.baseUrl,
  jwt: client.jwt,
  deviceId: await DeviceIdHelper.getOrCreate(),
);
```

This removes the device's push tokens server-side so it no longer receives incoming call pushes.

## Next Steps

- [Architecture](architecture.md)

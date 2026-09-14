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
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
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
  final isIOS = !kIsWeb && Platform.isIOS;

  // 1. Obtain VoIP Push Token
  // - iOS: Apple PushKit token (raw 64-character hex string) via flutter_callkit_incoming
  // - Android: FCM High-Priority Data message token
  String? voipToken;
  if (isIOS) {
    try {
      final token = await FlutterCallkitIncoming.getDevicePushTokenVoIP();
      if (token.isNotEmpty) voipToken = token;
    } catch (e) {
      debugPrint('Failed to get iOS VoIP token: $e');
    }
  } else {
    voipToken = await FirebaseMessaging.instance.getToken();
  }

  // Register VoIP push token (for call.ring)
  if (voipToken != null && voipToken.isNotEmpty) {
    await PushTokenService.registerVoipPushToken(
      baseUrl: client.baseUrl,
      jwt: client.jwt,
      pushToken: voipToken,
      deviceId: deviceId,
      platform: isIOS ? 'ios' : 'android',
    );
  }

  // 2. Register notification token (for call.canceled / call.ended)
  final fcmToken = await FirebaseMessaging.instance.getToken();
  if (fcmToken != null && fcmToken.isNotEmpty) {
    await PushTokenService.registerNotificationPushToken(
      baseUrl: client.baseUrl,
      jwt: client.jwt,
      notificationToken: fcmToken,
      deviceId: deviceId,
      platform: isIOS ? 'ios' : 'android',
    );
  }
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

## Handling Device Unlock During Active Call

A common mobile VoIP workflow is:
1. App is killed, phone is locked.
2. VoIP push arrives → Native CallKit / lock screen UI appears.
3. User swipes **"Answer"** on the lock screen.
4. OS wakes the app in the background → WebRTC media connects → user speaks for several seconds while the phone remains locked.
5. User **unlocks the device**.

When the phone is unlocked, the Flutter app transitions from background to foreground (`AppLifecycleState.resumed`). To ensure the user immediately sees the in-call screen instead of a blank or login screen, use `WidgetsBindingObserver` with a global `navigatorKey`:

```dart
// 1. In main.dart — provide a root navigator key:
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();

  // Initialize cold start handler with navigatorKey
  ColdStartCallHandler.initialize(navKey: rootNavigatorKey);

  runApp(MaterialApp(
    navigatorKey: rootNavigatorKey,
    home: const HomeScreen(),
  ));
}

// 2. In ColdStartCallHandler — observe app lifecycle:
class ColdStartLifecycleObserver with WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // User unlocked device — auto-push in-call screen
      ColdStartCallHandler.checkAndNavigateToActiveCall();
    }
  }
}
```

This ensures uninterrupted audio during lock-screen conversation, and instantaneous navigation to the in-call UI (audio or video) the moment the user unlocks their device.

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

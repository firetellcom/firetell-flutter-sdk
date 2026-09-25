# Firetell Flutter WebRTC SDK

A Flutter SDK for building VoIP-enabled mobile applications with the [Firetell](https://firetell.com) platform. Supports audio and video calls, camera controls (switch camera, mute/unmute video), hold, mute, DTMF, call transfer, and VoIP push notifications (FCM & APNs) with native WebSocket event-based signaling.

## Features

- **Authentication** — Workspace domain + JWT-based authentication
- **Outbound Calls** — Initiate audio and video calls via REST API + WebRTC
- **Video Calls** — Full video calling with local Picture-in-Picture preview, remote video rendering, camera switching (front/back), and video mute/unmute
- **Phone Numbers (DIDs)** — Query agent/team accessible numbers to use as outbound Caller ID
- **Incoming Calls** — Accept/reject via WebSocket or VoIP push notifications (auto-detects audio vs video)
- **Call Controls** — Mute, speakerphone (loudspeaker/earpiece), camera toggle, switch camera, hold/unhold, DTMF, transfer
- **VoIP Push** — FCM (Android) and APNs VoIP (iOS) push notification support
- **Full ICE** — Complete ICE candidate gathering before SDP exchange
- **Real-time Events** — SSE stream for workspace events (agent state, call ring, etc.)

## Installation

### Requirements

| Component | Minimum |
| --- | --- |
| Flutter | `3.38.1` |
| Dart | `3.10.0` |
| iOS | `15.0` |
| Android | API 24 with `compileSdk` 36 and `targetSdk` 36 |

> [!WARNING]
> **VERSION REQUIREMENTS:** Do not rely on the lower Flutter, Dart or iOS values
> currently declared in `pubspec.yaml`. The resolved native dependencies require
> Flutter `3.38.1` or newer, Dart `3.10.0` or newer, iOS `15.0` or newer, and
> Android `compileSdk`/`targetSdk` 36. An iOS target below 15 fails during pod
> installation.

Add to your `pubspec.yaml`:

```yaml
dependencies:
  firetell_flutter_sdk: ^1.1.1
```

See [INSTALLATION.MD](doc/INSTALLATION.MD) for complete Android/iOS setup,
CallKit UUID requirements and the production validation checklist.

## Quick Start

### 1. Initialize the Client

```dart
import 'package:firetell_flutter_sdk/firetell_flutter_sdk.dart';

final client = FiretellClient(
  jwt: 'your_agent_or_client_jwt_token',
  domain: 'your_workspace.firetell.app',
);

// Wait for initialization
final session = await client.ready;
print('Connected as ${session.username}');
```

### 2. Make an Outbound Call

```dart
// Fetch accessible phone numbers (DIDs) for Caller ID
final phoneNumbers = await client.getPhoneNumbers();
final callerId = phoneNumbers.firstOrNull?.number; // e.g. '+14155552671'

final call = await client.makeOutboundCall(
  to: '+1234567890',
  from: callerId, // Outbound Caller ID (required for PSTN/mobile calls)
);

// Listen for call state changes
call.onStateChange.listen((event) {
  print('Call state: ${event.state}');
  if (event.state == CallState.active) {
    print('Call connected!');
  }
});

// Hang up
await call.hangup();
```

### 3. Handle Incoming Calls (SSE — Foreground)

```dart
client.onCallRing.listen((params) async {
  print('Incoming call from ${params.callerName} (${params.callerNumber})');

  final call = await client.handlePushIncomingCall(params);

  // Call this after the user taps "Answer" in your incoming-call UI.
  await call.accept();
});
```

### 4. Handle Incoming Calls (VoIP Push — Background)

```dart
// Parse the push payload
final ringParams = CallRingParams.fromFcmData(pushData);

// Show native incoming call UI via flutter_callkit_incoming
// ...

// When user answers:
final call = await client.handlePushIncomingCall(ringParams);
await call.accept();

// When user declines (fast HTTP reject, no WS needed):
final tempCall = Call(iceServers: client.iceServers);
tempCall.callId = ringParams.callId;
await tempCall.rejectViaHttp(
  baseUrl: client.baseUrl,
  callToken: ringParams.callToken,
);
```

### 5. Register Push Tokens

```dart
// Register VoIP push token (on every cold launch / token refresh)
await PushTokenService.registerVoipPushToken(
  baseUrl: client.baseUrl,
  jwt: client.jwt,
  pushToken: fcmToken, // or APNs VoIP token
  deviceId: await DeviceIdHelper.getOrCreate(),
  platform: 'android', // or 'ios'
);

// Register notification token (for call.canceled / call.ended dismissal)
await PushTokenService.registerNotificationPushToken(
  baseUrl: client.baseUrl,
  jwt: client.jwt,
  notificationToken: fcmToken,
  deviceId: await DeviceIdHelper.getOrCreate(),
  platform: 'android',
);
```

## Call Controls

```dart
// Mute / Unmute
await call.mute();
await call.unmute();
await call.toggleMute();

// Speakerphone (Loudspeaker / Earpiece)
await call.setSpeakerphoneOn(true);  // Turn on loudspeaker
await call.setSpeakerphoneOn(false); // Route back to earpiece
await call.toggleSpeaker();
print('Speaker active: ${call.isSpeakerOn}');

// Video & Camera Controls
await call.switchCamera();           // Switch front / back camera
await call.muteVideo();              // Turn off camera
await call.unmuteVideo();            // Turn on camera
await call.toggleCamera();           // Toggle camera on/off
print('Camera off: ${call.isCameraOff}');

// Hold / Unhold
await call.onhold();
await call.unhold();

// DTMF
call.sendDTMF('1');
call.sendDTMF('#');

// Transfer
await call.transfer('+1987654321', reason: 'Customer request');

// Hang up
await call.hangup();
```

## Call State Machine

```
Outbound: none → initiated → ringing → answered → active → ended
Inbound:  none → ringing → answered → active → ended
Hold:     active ↔ onHold
```

## WebSocket Signaling Protocol

The SDK uses the same native WebSocket event-based JSON signaling protocol as the Firetell browser SDK:

| Event               | Direction       | Description                                            |
| ------------------- | --------------- | ------------------------------------------------------ |
| `session.connect`   | Client → Server | Authenticate with `call_token` (must be within 3s)     |
| `session.connected` | Server → Client | Authentication ACK                                     |
| `call.offer`        | Client → Server | SDP Offer (audio / video)                              |
| `call.answer`       | Client → Server | SDP Answer                                             |
| `call.hold`         | Client → Server | Hold call (with renegotiated SDP)                      |
| `call.unhold`       | Client → Server | Unhold call (with renegotiated SDP)                    |
| `call.hangup`       | Client → Server | End call                                               |
| `call.reject`       | Client → Server | Reject incoming call                                   |
| `call.mute`         | Client → Server | Mute/unmute microphone notification                    |
| `call.camera`       | Client ⇄ Server | Camera state change notification (`muted: true/false`) |
| `call.dtmf`         | Client → Server | DTMF digit                                             |
| `call.transfer`     | Client → Server | Transfer call                                          |

## Architecture

```
FiretellClient
├── REST API (POST /api/v1/call-center/calls → call_id, call_token, ws_url)
├── SSE Stream (GET /stream → real-time workspace events)
└── Call (per-call instance)
    ├── Native WebSocket (ws_url, authenticated via call_token)
    └── RTCPeerConnection (flutter_webrtc, Full ICE)
```

## Platform Setup

### Android

Add to `AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.RECORD_AUDIO" />
<uses-permission android:name="android.permission.CAMERA" />
<uses-permission android:name="android.permission.MODIFY_AUDIO_SETTINGS" />

<!-- Bluetooth headset audio routing (Required for Android 12+) -->
<uses-permission android:name="android.permission.BLUETOOTH" android:maxSdkVersion="30" />
<uses-permission android:name="android.permission.BLUETOOTH_ADMIN" android:maxSdkVersion="30" />
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
```

### iOS

Add to `Info.plist`:

```xml
<key>NSMicrophoneUsageDescription</key>
<string>Firetell needs microphone access for VoIP calls</string>
<key>NSCameraUsageDescription</key>
<string>Firetell needs camera access for video calls</string>
<key>UIBackgroundModes</key>
<array>
  <string>voip</string>
  <string>audio</string>
  <string>fetch</string>
  <string>remote-notification</string>
</array>
```

## License

MIT — see [LICENSE](LICENSE) for details.

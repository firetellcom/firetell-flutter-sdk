# Getting Started

## Requirements

- Dart SDK `>=3.10.0`
- Flutter SDK `>=3.38.1`
- iOS 15.0+
- Android API 24+ with `compileSdk` 36 and `targetSdk` 36
- A Firetell workspace with agent/client JWT

> [!WARNING]
> **CHECK THESE VERSIONS BEFORE INSTALLING:** The effective minimums come from
> the resolved dependencies and are higher than the package's current
> `pubspec.yaml` constraints. In particular, `flutter_callkit_incoming 3.1.6`
> requires iOS 15.0 and `device_info_plus 13.2.0` requires Flutter 3.38.1 with
> Dart 3.10.0.

See [INSTALLATION.MD](INSTALLATION.MD) for the complete compatibility matrix,
native project configuration and release validation checklist.

## Installation

Add the SDK to your `pubspec.yaml`:

```yaml
dependencies:
  firetell_flutter_sdk: ^1.1.1
```

Then run:

```bash
flutter pub get
```

## Platform Setup

### Android

Add to `android/app/src/main/AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.RECORD_AUDIO" />
<uses-permission android:name="android.permission.CAMERA" />
<uses-permission android:name="android.permission.MODIFY_AUDIO_SETTINGS" />

<!-- Bluetooth headset audio routing (Required for Android 12+) -->
<uses-permission android:name="android.permission.BLUETOOTH" android:maxSdkVersion="30" />
<uses-permission android:name="android.permission.BLUETOOTH_ADMIN" android:maxSdkVersion="30" />
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />

<!-- Required for VoIP push notifications -->
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
<uses-permission android:name="android.permission.VIBRATE" />
<uses-permission android:name="android.permission.USE_FULL_SCREEN_INTENT" />
```

### iOS

Add to `ios/Runner/Info.plist`:

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

Enable **Push Notifications** and **Background Modes** capabilities in Xcode.

## Quick Start

```dart
import 'package:firetell_flutter_sdk/firetell_flutter_sdk.dart';

// 1. Create client
final client = FiretellClient(
  jwt: 'your_agent_or_client_jwt_token',
  domain: 'your_workspace.firetell.app',
);

// 2. Wait for initialization (fetches workspace metadata + ICE servers)
final session = await client.ready;
print('Connected as ${session.username}');

// 3. Make a call
final call = await client.makeOutboundCall(to: '+1234567890');

// 4. Listen for state changes
call.onStateChange.listen((event) {
  print('State: ${event.state}');
});

// 5. Hang up
await call.hangup();
```

## Next Steps

- [Installation](INSTALLATION.MD) — Toolchain and native platform setup
- [Authentication](AUTHENTICATION.MD) — JWT auth and session management
- [Outbound Calls](OUTBOUND_CALLS.MD) — Making calls
- [Incoming Calls](INCOMING_CALLS.MD) — Handling inbound calls (SSE + push)
- [Call Controls](CALL_CONTROLS.MD) — Mute, hold, DTMF, transfer
- [VoIP Push Notifications](VOIP_PUSH.MD) — FCM and APNs setup
- [Architecture](ARCHITECTURE.MD) — SDK internals and signaling protocol

# Installation and native requirements

This guide covers the effective toolchain and native platform requirements for
`firetell_flutter_sdk` 1.1.1. These requirements include the constraints of the
SDK's resolved native dependencies, so they can be higher than the values shown
in the package's own `environment` section.

## Version compatibility

| Component | Minimum or required value | Notes |
| --- | --- | --- |
| Flutter | `3.38.1` | Required by `device_info_plus 13.2.0`. The SDK has also been build-tested with Flutter `3.41.4`. |
| Dart | `3.10.0` | Required by `device_info_plus 13.2.0`. |
| iOS deployment target | `15.0` | Required by the resolved `flutter_callkit_incoming 3.1.6`. Set this on the app target and in CocoaPods. |
| Android `minSdk` | `24` | Recommended baseline for this SDK's VoIP and WebRTC use cases. |
| Android `compileSdk` | `36` | Required by the resolved `flutter_webrtc 1.6.2+hotfix.3` Android build. |
| Android `targetSdk` | `36` | Required for new apps and updates submitted to Google Play from August 31, 2026. |

> [!WARNING]
> **THE EFFECTIVE MINIMUMS ARE HIGHER THAN THE PACKAGE CONSTRAINTS.** The package
> currently declares Dart `>=3.0.0` and Flutter `>=3.10.0`, but the resolved
> `device_info_plus 13.2.0` dependency requires Dart `>=3.10.0` and Flutter
> `>=3.38.1`. Use the values in the table above when configuring a consumer app.

See the official [Google Play target API requirements](https://developer.android.com/google/play/requirements/target-sdk)
when preparing a store release because this policy changes over time.

Run these commands before integrating the SDK:

```bash
flutter --version
dart --version
```

If an existing application is below one of these versions, upgrade its Flutter
toolchain and native targets before running `flutter pub get`.

## Install the package

Install the published release:

```yaml
dependencies:
  firetell_flutter_sdk: ^1.1.1
```

Or pin a Git integration to a tag or commit:

```yaml
dependencies:
  firetell_flutter_sdk:
    git:
      url: https://github.com/firetellcom/firetell-flutter-sdk.git
      ref: v1.1.1
```

Then resolve dependencies:

```bash
flutter clean
flutter pub get
```

Commit `pubspec.lock` in an application repository. This prevents a transitive
native dependency upgrade from silently changing the minimum iOS or Android
version used by a production build.

> [!WARNING]
> Running `flutter pub upgrade` can resolve a newer native plugin and raise the
> required Flutter, Dart, iOS or Android version. Review `pubspec.lock` and run
> both native builds after every dependency update.

## Android setup

Configure the application module in `android/app/build.gradle.kts`:

```kotlin
android {
    compileSdk = 36

    defaultConfig {
        minSdk = 24
        targetSdk = 36
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}
```

If the project uses Groovy, apply the equivalent values in
`android/app/build.gradle`:

```groovy
android {
    compileSdkVersion 36

    defaultConfig {
        minSdkVersion 24
        targetSdkVersion 36
    }

    compileOptions {
        sourceCompatibility JavaVersion.VERSION_17
        targetCompatibility JavaVersion.VERSION_17
    }
}
```

> [!WARNING]
> **ANDROID SDK 36 IS REQUIRED FOR THIS DEPENDENCY SET.** Changing only
> `minSdk` is insufficient. Install Android SDK Platform 36 and configure both
> `compileSdk` and `targetSdk` as shown above. Google Play requires API 36 for
> new apps and updates from August 31, 2026.

Add the media and network permissions to
`android/app/src/main/AndroidManifest.xml`:

```xml
<uses-feature android:name="android.hardware.camera" android:required="false" />
<uses-feature android:name="android.hardware.camera.autofocus" android:required="false" />

<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
<uses-permission android:name="android.permission.CHANGE_NETWORK_STATE" />
<uses-permission android:name="android.permission.RECORD_AUDIO" />
<uses-permission android:name="android.permission.CAMERA" />
<uses-permission android:name="android.permission.MODIFY_AUDIO_SETTINGS" />

<uses-permission
    android:name="android.permission.BLUETOOTH"
    android:maxSdkVersion="30" />
<uses-permission
    android:name="android.permission.BLUETOOTH_ADMIN"
    android:maxSdkVersion="30" />
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
```

Request microphone, camera, Bluetooth and notification permissions at runtime
before using the associated feature. Incoming-call notifications also require
the CallKit/ConnectionService configuration described in
[VOIP_PUSH.MD](VOIP_PUSH.MD).

For release builds, preserve the native CallKit classes in
`android/app/proguard-rules.pro`:

```proguard
-keep class com.hiennv.flutter_callkit_incoming.** { *; }
```

## iOS setup

### Set the deployment target to iOS 15

> [!WARNING]
> **iOS 15.0 IS A HARD MINIMUM.** The resolved
> `flutter_callkit_incoming 3.1.6` pod declares iOS 15.0. If the Runner target,
> Podfile or any build configuration remains below 15.0, `pod install` or the
> Xcode build can fail with an incompatible deployment-target error.

Open `ios/Runner.xcworkspace` in Xcode, select the **Runner** target, and set
**iOS Deployment Target** to `15.0` for every build configuration.

For a CocoaPods project, also set the platform in `ios/Podfile`:

```ruby
platform :ios, '15.0'
```

Keep every pod target on the same minimum version:

```ruby
post_install do |installer|
  installer.pods_project.targets.each do |target|
    flutter_additional_ios_build_settings(target)

    target.build_configurations.each do |config|
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '15.0'
    end
  end
end
```

After changing the deployment target, refresh the native dependencies:

```bash
flutter clean
flutter pub get
cd ios
pod install --repo-update
cd ..
```

Add the usage descriptions and background modes to `ios/Runner/Info.plist`:

```xml
<key>NSMicrophoneUsageDescription</key>
<string>This app uses the microphone for voice calls.</string>
<key>NSCameraUsageDescription</key>
<string>This app uses the camera for video calls.</string>
<key>UIBackgroundModes</key>
<array>
  <string>voip</string>
  <string>audio</string>
  <string>remote-notification</string>
</array>
```

In Xcode, enable the **Push Notifications** capability and the required
**Background Modes** for the Runner target. Configure APNs and PushKit as
described in [VOIP_PUSH.MD](VOIP_PUSH.MD).

### CallKit identifier requirement

The `id` passed to iOS CallKit must be a valid UUID. Keep the Firetell server
`call_id` in `CallKitParams.extra`; do not use the server ID as the CallKit UUID.
When handling accept, decline or end events, read the server ID back from
`extra` or maintain an explicit UUID-to-call-ID mapping.

```dart
final callKitUuid = CallIdMapper.instance.register(ringParams.callId);

final params = CallKitParams(
  id: callKitUuid,
  nameCaller: ringParams.callerName,
  handle: ringParams.callerNumber,
  extra: ringParams.toMap(),
);
```

Register one global CallKit event listener for the application. Multiple
listeners can process the same accept or decline event more than once and open
duplicate signaling connections. Remove the mapping only after the call has
ended:

```dart
CallIdMapper.instance.remove(ringParams.callId);
```

## Initialize and dispose the SDK

Wait for `ready` before calling APIs that require workspace metadata:

```dart
final client = FiretellClient(
  jwt: jwt,
  domain: 'your-workspace.firetell.app',
);

final session = await client.ready;
print('Connected as ${session.username}');
```

For an outgoing call:

```dart
final call = await client.makeOutboundCall(
  to: '+1234567890',
  from: '+1098765432',
);

call.onStateChange.listen((event) {
  print('Call state: ${event.state}');
});
```

For a foreground incoming call, use the ring parameters to create the call
session before accepting it:

```dart
client.onCallRing.listen((ringParams) async {
  final call = await client.handlePushIncomingCall(ringParams);

  // Call this after the user taps Answer in your UI.
  await call.accept();
});
```

Clean up the client when the authenticated session ends:

```dart
await client.logout();
```

## Validate a consumer application

Run the checks from the consuming Flutter application, including at least one
real Android device and one real iPhone because simulators cannot validate the
complete push, CallKit and audio-route lifecycle:

```bash
flutter analyze
flutter test
flutter build apk --release
flutter build ios --release --no-codesign
```

Before shipping, test foreground, background and terminated incoming calls;
accept, decline, timeout and remote hang-up; microphone and camera permissions;
Bluetooth routing; token refresh; logout; and application relaunch.

## Related guides

- [GETTING_STARTED.MD](GETTING_STARTED.MD)
- [AUTHENTICATION.MD](AUTHENTICATION.MD)
- [INCOMING_CALLS.MD](INCOMING_CALLS.MD)
- [OUTBOUND_CALLS.MD](OUTBOUND_CALLS.MD)
- [CALL_CONTROLS.MD](CALL_CONTROLS.MD)
- [VOIP_PUSH.MD](VOIP_PUSH.MD)
- [ARCHITECTURE.MD](ARCHITECTURE.MD)

# Changelog

All notable changes to the `firetell_flutter_sdk` package will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.3] - 2026-09-14

### Added

- **Speakerphone Control**:
  - Added `isSpeakerOn` boolean property to [Call](lib/src/call.dart) to check current speaker status.
  - Added `setSpeakerphoneOn(bool enable)` to route audio between device loudspeaker and earpiece.
  - Added `toggleSpeaker()` convenience method to toggle speakerphone on/off.
  - Added `onSpeakerChange` broadcast stream to listen for speaker state changes.
  - Automatically resets speakerphone to earpiece on call cleanup.
- **Phone Numbers (DIDs) & Caller ID Support**:
  - Added `PhoneNumber`, `PhoneNumberCapabilities`, and `PhoneNumbersResponse` models.
  - Added `client.getPhoneNumbers({page, limit})` and `client.getPhoneNumbersResponse({page, limit})` to fetch agent/team accessible phone numbers for outbound Caller ID (`from`).
  - Updated example `DialpadScreen` to automatically fetch available DIDs and provide an interactive Caller ID dropdown selector when dialing outbound.
- **Backend Device Push Token Cleanup on Logout**:
  - Upgraded `FiretellClient.logout({deviceId})` to an asynchronous method that calls `POST /api/v1/me/logout` with `device_id` to unregister push tokens on the server, ensuring the device stops receiving VoIP incoming calls after logout.
  - Automatically resolves `deviceId` from `DeviceIdHelper.getOrCreate()` if not explicitly specified.
- **Example Application**:
  - Added a dedicated Speaker/Earpiece toggle button with live state feedback to the active call screen.
  - Added dynamic Caller ID selector on the Dial Pad screen.
  - Streamlined logout flow via `await client.logout()`.

## [1.0.2] - 2026-09-14

### Changed

- **Upgraded Dependencies**:
  - Updated to modern packages: `flutter_callkit_incoming: ^3.1.5`, `flutter_webrtc: ^1.6.2`, `web_socket_channel: ^3.0.3`, `http: ^1.6.0`, `uuid: ^4.6.0`, `shared_preferences: ^2.5.5`, `device_info_plus: ^13.2.0`.
- **flutter_callkit_incoming 3.x Compatibility**:
  - Adapted `CallKitHandler` and example handlers to support `flutter_callkit_incoming 3.x` sealed class event hierarchy (`CallEventActionCallAccept`, `CallEventActionCallDecline`, etc.).
  - Configured `missedCallNotification:` and `callingNotification:` in `CallKitParams`.
  - Resolved `CallEvent` naming conflict with SDK's internal enum via explicit namespace aliasing.

### Fixed

- **WebRTC Local Description Handling**:
  - Fixed `localDescription` getter error in `flutter_webrtc` by utilizing asynchronous `await pc.getLocalDescription()`.
- **Linter & Code Health**:
  - Fixed `unawaited_return_in_try_block` lint in WebSocket connect handshake.
  - Replaced unhandled `catchError` with clean `unawaited` try/catch block in `FiretellClient`.
  - Added unnamed `library;` directive for Dart 3 library doc comment compliance.
  - Renamed documentation directory to `doc/` and main markdown file to `README.md` per pub.dev package layout guidelines.

## [1.0.1] - 2026-09-14

### Fixed

- **iOS VoIP Push Token Registration**:
  - Differentiated Apple PushKit VoIP tokens (`PKPushRegistry`) from standard Firebase FCM tokens.
  - Used `FlutterCallkitIncoming.getDevicePushTokenVoIP()` to obtain the raw 64-character hex APNs VoIP token on iOS for `POST /api/v1/me/devices/voip-push-token`.
  - Maintained FCM token registration for standard notification push (`POST /api/v1/me/devices/notification-push-token`) to handle background call cancellations (`call.canceled`) and endings (`call.ended`) across both iOS and Android.
  - Updated FCM token refresh listener to automatically synchronize updated tokens based on the running platform.

## [1.0.0] - 2026-09-14

### Added

- **Core WebRTC Calling**:
  - `FiretellClient` class for managing sessions, tokens, device registrations, and SSE event streaming.
  - `Call` class implementing full WebRTC lifecycle (`makeCall`, `accept`, `reject`, `hangup`, `hold`/`unhold`, `mute`/`unmute`, `sendDTMF`).
  - Native WebSocket per-call signaling protocol using event-based messages (`session.connect`, `call.offer`, `call.answer`, `call.ice_candidate`, `call.hangup`).
  - Full ICE candidate gathering before sending SDP offer/answer for maximum NAT traversal reliability.

- **VoIP Push Notification & Cold-Start Support**:
  - `PushTokenService` for registering device VoIP push tokens (`fcm_voip`, `apns_voip`, `fcm_data`) with backend REST API.
  - `DeviceIdHelper` providing persistent unique device UUID identification across app restarts (`SharedPreferences`).
  - `IceServerCache` for offline and cold-start STUN/TURN server caching.
  - `CallKitHandler` and `ColdStartCallHandler` patterns enabling instant incoming call connection from locked screen or killed app state using push payload credentials (`ws_url` and `call_token`).

- **Reactive Event Streams**:
  - Stream-based client events: `onCallOffer`, `onCallAccepted`, `onCallEnded`, `onCallRejected`, `onCallRinging`.
  - Granular call state streams: `onStateChanged`, `onRemoteStream`, `onLocalStream`, `onEvent`.

- **Comprehensive Example App**:
  - Complete Flutter demo app covering login, push token registration, incoming call notification with CallKit, active call UI, and audio stream routing.

- **Documentation**:
  - Internal architecture, WebRTC call flow diagrams, and VoIP push integration guides under `docs/`.

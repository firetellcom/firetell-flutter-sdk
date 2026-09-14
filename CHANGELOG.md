# Changelog

All notable changes to the `firetell_flutter_sdk` package will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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

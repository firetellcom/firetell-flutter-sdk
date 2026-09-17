# Architecture

## SDK Structure

```
firetell_flutter_sdk/
├── lib/
│   ├── firetell_flutter_sdk.dart          # Public API barrel export
│   └── src/
│       ├── firetell_client.dart            # Main client (REST + SSE + call mgmt)
│       ├── call.dart                       # Per-call WebRTC + WS signaling
│       ├── constants/
│       │   ├── api_endpoints.dart          # REST API endpoints
│       │   └── ice_servers.dart            # Default STUN/TURN servers
│       ├── enums/
│       │   ├── call_state.dart             # Call lifecycle states
│       │   ├── call_event.dart             # Call stream event types
│       │   └── client_event.dart           # Client-level event types
│       ├── models/
│       │   ├── session.dart                # Auth session
│       │   ├── call_options.dart           # Call configuration
│       │   ├── call_ring_params.dart       # Incoming call + push payload
│       │   ├── make_call_response.dart     # REST call creation response
│       │   ├── jwt_payload.dart            # Decoded JWT
│       │   └── ws_message.dart             # WebSocket message envelope
│       ├── push/
│       │   ├── push_token_service.dart     # Token registration REST API
│       │   └── callkit_handler.dart        # flutter_callkit_incoming bridge
│       └── utils/
│           ├── jwt_decoder.dart            # JWT base64 decode
│           ├── sse_stream_client.dart       # SSE via HTTP with reconnect
│           ├── device_id.dart              # Native device ID helper
│           └── ice_server_cache.dart        # Local ICE server cache
```

## Component Architecture

```
┌──────────────────────────────────────────────────────────────┐
│                       FiretellClient                          │
│                                                              │
│  ┌──────────────┐  ┌───────────────┐  ┌──────────────────┐  │
│  │  REST Client  │  │  SSE Stream   │  │  Active Calls    │  │
│  │  (http pkg)   │  │  (http pkg)   │  │  Map<id, Call>   │  │
│  │               │  │               │  │                  │  │
│  │ POST /calls   │  │ GET /stream   │  │  ┌────────────┐  │  │
│  │ → call_token  │  │ → call.ring   │  │  │   Call      │  │  │
│  │ → ws_url      │  │ → call.ended  │  │  │            │  │  │
│  │               │  │ → agent.state │  │  │  WS + RTC  │  │  │
│  └──────────────┘  └───────────────┘  │  └────────────┘  │  │
│                                        └──────────────────┘  │
└──────────────────────────────────────────────────────────────┘

Per-Call Architecture:
┌───────────────────────────────────────────────────────────────┐
│                          Call                                  │
│                                                               │
│  ┌────────────────────────┐  ┌─────────────────────────────┐  │
│  │   WebSocketChannel     │  │     RTCPeerConnection       │  │
│  │   (per-call WS)        │  │     (flutter_webrtc)        │  │
│  │                        │  │                             │  │
│  │   session.connect ───► │  │   getUserMedia              │  │
│  │   call.offer      ───► │  │   createOffer / Answer      │  │
│  │   call.answer     ───► │  │   setLocalDescription       │  │
│  │   call.hold       ───► │  │   setRemoteDescription      │  │
│  │   call.hangup     ───► │  │   Full ICE gathering        │  │
│  │   ◄─── call.answer     │  │   onTrack (remote audio)    │  │
│  │   ◄─── call.offer      │  │                             │  │
│  └────────────────────────┘  └─────────────────────────────┘  │
└───────────────────────────────────────────────────────────────┘
```

## WebSocket Signaling Protocol

The SDK uses a **native WebSocket event-based JSON protocol** — not JSON-RPC, not Verto, not Socket.IO.

### Message Format

```json
{
  "event": "call.offer",
  "data": {
    "sdp": "v=0\r\no=- ..."
  }
}
```

### Event Reference

| Event               | Direction       | Data                  | Description                      |
| ------------------- | --------------- | --------------------- | -------------------------------- |
| `session.connect`   | Client → Server | `{ call_token }`      | Authenticate (must be within 3s) |
| `session.connected` | Server → Client | `{}`                  | Authentication ACK               |
| `call.offer`        | Client → Server | `{ sdp }`             | SDP Offer (outbound)             |
| `call.offer`        | Server → Client | `{ sdp }`             | SDP Offer (inbound, early media) |
| `call.answer`       | Client → Server | `{ sdp }`             | SDP Answer                       |
| `call.answer`       | Server → Client | `{ sdp }`             | Remote SDP Answer                |
| `call.hold`         | Client → Server | `{ sdp }`             | Hold (renegotiated SDP)          |
| `call.unhold`       | Client → Server | `{ sdp }`             | Unhold (renegotiated SDP)        |
| `call.hangup`       | Client → Server | `{}`                  | End call                         |
| `call.reject`       | Client → Server | `{}`                  | Reject incoming call             |
| `call.mute`         | Client → Server | `{ muted }`           | Mute state notification          |
| `call.dtmf`         | Client → Server | `{ digit }`           | DTMF digit                       |
| `call.transfer`     | Client → Server | `{ target, reason? }` | Transfer call                    |
| `call.ringing`      | Server → Client | `{}`                  | Destination ringing              |
| `call.trying`       | Server → Client | `{}`                  | SIP TRYING                       |
| `call.ended`        | Server → Client | `{ reason? }`         | Call ended                       |

### Connection Lifecycle

```
1. Open WebSocket to ws_url
2. Send session.connect with call_token (WITHIN 3 SECONDS)
3. Receive session.connected
4. Send/receive call events
5. On call.ended or call.hangup → close WebSocket
```

## Full ICE Gathering

The SDK uses **Full ICE** (not Trickle ICE). All ICE candidates are gathered before sending the SDP.

### Gathering Strategy

```
createOffer() → setLocalDescription() → wait for ICE gathering
                                              │
                              ┌────────────────┼─────────────────┐
                              ▼                ▼                 ▼
                         Complete          3s timeout         6s hard
                         (null candidate   (srflx/relay      timeout
                          or state =        found, good      (safety
                          complete)         enough)           fallback)
                              │                │                 │
                              └────────────────┴─────────────────┘
                                              │
                                              ▼
                                     Return local SDP
                                     (with all candidates)
```

### Why Full ICE?

Firetell's signaling server expects a complete SDP with all ICE candidates embedded. Trickle ICE is not supported.

## DTLS Role Preservation

During hold/unhold SDP renegotiation, the DTLS `a=setup:` role from the remote SDP must be preserved to prevent `Failed to set SSL role` errors:

- Remote sends `a=setup:active` → we use `a=setup:passive` in our answer
- On hold renegotiation, the new SDP must maintain the same DTLS role
- The SDK tracks this via `_currentRemoteSetupRole`

## SSE Stream

The SSE (Server-Sent Events) stream provides real-time workspace events:

```
GET /stream
Authorization: Bearer {jwt}
Accept: text/event-stream
```

### Events

| Event           | Description                             |
| --------------- | --------------------------------------- |
| `call.ring`     | Incoming call for this agent            |
| `call.created`  | New call in workspace                   |
| `call.started`  | Call ringing at destination             |
| `call.answered` | Call was answered                       |
| `call.ended`    | Call ended                              |
| `call.canceled` | Call canceled (before answer)           |
| `agent.state`   | Agent state changed                     |
| `system.ping`   | Keep-alive (ignored)                    |
| `system.error`  | Server error (e.g., SSE_LIMIT_EXCEEDED) |

### Reconnection

The SSE client uses exponential backoff with jitter:

- Initial delay: 1s
- Max delay: 30s
- Backoff multiplier: 2x
- Auto-reconnect on connection loss

## REST API Endpoints

| Method | Path                                      | Description                               |
| ------ | ----------------------------------------- | ----------------------------------------- |
| `GET`  | `/api/v1/workspace/metadata`              | Workspace metadata (ICE servers, WS URLs) |
| `POST` | `/api/v1/call-center/calls`               | Create outbound call                      |
| `POST` | `/api/v1/call-center/calls/{id}/reject`   | Reject call (HTTP, no WS)                 |
| `POST` | `/api/v1/call-center/calls/{id}/transfer` | Transfer call (REST fallback)             |
| `GET`  | `/stream`                                 | SSE event stream                          |
| `POST` | `/api/v1/me/voip-push-token`              | Register VoIP push token                  |
| `POST` | `/api/v1/me/notification-push-token`      | Register notification push token          |
| `POST` | `/api/v1/me/logout`                       | Logout + remove push tokens               |

## Dependencies

| Package                    | Purpose                             |
| -------------------------- | ----------------------------------- |
| `flutter_webrtc`           | WebRTC peer connection + media      |
| `web_socket_channel`       | Per-call WebSocket signaling        |
| `http`                     | REST API + SSE stream               |
| `uuid`                     | Call session IDs                    |
| `shared_preferences`       | Device ID + ICE server cache        |
| `device_info_plus`         | Native device ID (iOS/Android)      |
| `flutter_callkit_incoming` | Native CallKit/ConnectionService UI |

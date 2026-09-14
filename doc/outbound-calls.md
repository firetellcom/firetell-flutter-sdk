# Outbound Calls

## Making a Call

```dart
final call = await client.makeOutboundCall(
  to: '+1234567890',      // Phone number, extension, or SIP URI
  from: '1001',           // Optional: caller extension
  isVideo: false,         // Optional: video call (default: audio)
);
```

### What happens internally

1. **WebRTC setup** — `getUserMedia()` acquires the microphone
2. **Full ICE gathering** — SDP offer is created and ICE candidates are gathered to completion
3. **REST API call** — `POST /api/v1/call-center/calls` with the destination number
4. **WebSocket connect** — Per-call WS is opened using the `call_token` from the REST response
5. **SDP offer sent** — The gathered SDP is sent via `call.offer` WebSocket event

### Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `to` | `String` | ✅ | Destination: phone number (`+1234567890`), extension (`1001`), agent username, team ID (`te_...`), or SIP account (`si_...`) |
| `from` | `String` | ❌ | Caller ID or extension number |
| `isVideo` | `bool` | ❌ | Enable video (default: `false`) |

## Listening to Call State

```dart
call.onStateChange.listen((event) {
  switch (event.state) {
    case CallState.initiated:
      print('Call initiated');
    case CallState.trying:
      print('Trying...');
    case CallState.ringing:
      print('Ringing at destination');
    case CallState.answered:
      print('Call answered, connecting media...');
    case CallState.active:
      print('Call active — media flowing ✅');
    case CallState.ended:
      print('Call ended. Reason: ${event.reason}');
    case CallState.error:
      print('Call error: ${event.reason}');
    case CallState.cancel:
      print('Call canceled');
    default:
      break;
  }
});
```

## Call State Machine

```
Outbound call:

  none → initiated → trying → ringing → answered → active → ended
                                                       ↕
                                                    onHold
```

## Accessing Call Properties

```dart
print('Call ID: ${call.callId}');
print('To: ${call.to}');
print('From: ${call.from}');
print('State: ${call.callState}');
print('Active: ${call.active}');
print('Muted: ${call.isMuted}');
print('On hold: ${call.isHold}');
```

## Handling the Remote Audio Stream

```dart
call.onRemoteStream.listen((stream) {
  if (stream != null) {
    // For audio calls, the stream plays automatically through the device speaker.
    // For video calls, attach to a RTCVideoRenderer.
  }
});
```

## Ending a Call

```dart
await call.hangup();
```

## Error Handling

```dart
try {
  final call = await client.makeOutboundCall(to: '+1234567890');
} catch (e) {
  print('Failed to make call: $e');
  // Common errors:
  // - Network unreachable
  // - Invalid JWT / expired token
  // - Insufficient credits
  // - Invalid destination number
}
```

## Next Steps

- [Incoming Calls](incoming-calls.md)
- [Call Controls](call-controls.md) — Mute, hold, DTMF, transfer

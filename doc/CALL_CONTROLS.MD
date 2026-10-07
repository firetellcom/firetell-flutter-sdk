# Call Controls

All call control methods are available on the `Call` instance.

## Mute / Unmute

Muting disables the local microphone track. The remote party hears silence.

```dart
// Mute
await call.mute();

// Unmute
await call.unmute();

// Toggle
await call.toggleMute();

// Check current state
print('Muted: ${call.isMuted}');
```

### Listen for mute changes

```dart
call.onMuteChange.listen((bool muted) {
  print(muted ? 'Microphone muted' : 'Microphone unmuted');
});
```

> **Note:** Muting sends a `call.mute` event to the server so the remote party's UI can show a mute indicator.

## Speakerphone (Loudspeaker / Earpiece)

Toggle audio output between the device speakerphone (loudspeaker) and earpiece.

```dart
// Turn speakerphone ON
await call.setSpeakerphoneOn(true);

// Turn speakerphone OFF (route to earpiece)
await call.setSpeakerphoneOn(false);

// Toggle speakerphone state
await call.toggleSpeaker();

// Check current state
print('Speaker active: ${call.isSpeakerOn}');
```

### Listen for speaker changes

```dart
call.onSpeakerChange.listen((bool speakerOn) {
  print(speakerOn ? 'Switched to speakerphone' : 'Switched to earpiece');
});
```

## Hold / Unhold

Holding a call uses SDP renegotiation — the transceiver direction changes to `sendonly` (hold) or `sendrecv` (unhold), and a new SDP with fully-gathered ICE candidates is sent to the server.

```dart
// Put on hold
await call.onhold();

// Resume
await call.unhold();

// Check state
print('On hold: ${call.isHold}');
// or
print('State: ${call.callState}'); // CallState.onHold
```

### Hold state machine

```
active ←→ onHold
```

### What happens internally

1. Transceiver direction changed (`sendrecv` → `sendonly` for hold)
2. New SDP offer created
3. Full ICE re-gathering
4. `call.hold` / `call.unhold` event sent via WebSocket with new SDP
5. DTLS setup role preserved to prevent `Failed to set SSL role` errors

## DTMF

Send DTMF (Dual-Tone Multi-Frequency) digits during an active call:

```dart
// Send a single digit
call.sendDTMF('1');
call.sendDTMF('#');
call.sendDTMF('*');

// Example: navigate an IVR menu
for (final digit in '12345#'.split('')) {
  call.sendDTMF(digit);
  await Future.delayed(const Duration(milliseconds: 200));
}
```

### Valid DTMF characters

`0-9`, `*`, `#`, `A-D`

> **Note:** DTMF is sent via WebSocket signaling (`call.dtmf` event), not via RFC 2833 RTP events.

## Call Transfer

Transfer the active call to another destination:

```dart
// Transfer to an extension
await call.transfer('1002');

// Transfer to a phone number
await call.transfer('+1987654321');

// Transfer to a team
await call.transfer('te_abc123');

// Transfer with reason
await call.transfer('1002', reason: 'Customer requested billing dept');
```

### Transfer via REST API (fallback)

If you don't have an active `Call` instance:

```dart
await client.sendTransfer(
  callId,
  '+1987654321',
  reason: 'Agent unavailable',
);
```

### Valid transfer targets

| Target | Format | Example |
|--------|--------|---------|
| Extension | number | `1001` |
| Phone number | E.164 | `+1234567890` |
| Agent username | string | `agent_john` |
| Team ID | `te_` prefix | `te_abc123` |
| SIP account | `si_` prefix | `si_xyz789` |

## Hangup

End the active call:

```dart
await call.hangup();
```

This sends a `call.hangup` event via WebSocket and cleans up WebRTC resources.

## Call State Reference

| State | Description |
|-------|-------------|
| `CallState.none` | Initial state |
| `CallState.initiated` | Outbound call started |
| `CallState.trying` | SIP TRYING received |
| `CallState.ringing` | Ringing at destination |
| `CallState.answered` | Callee answered, connecting media |
| `CallState.active` | Media flowing, call is live |
| `CallState.onHold` | Call is on hold |
| `CallState.ended` | Call ended normally |
| `CallState.error` | Call failed |
| `CallState.cancel` | Call was canceled before answer |

## Next Steps

- [VoIP Push Notifications](VOIP_PUSH.MD)
- [Architecture](ARCHITECTURE.MD)

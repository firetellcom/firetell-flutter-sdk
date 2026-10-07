/// Per-call signaling WebSocket connection status, emitted by
/// `Call.onSignaling` while the SDK keeps the connection alive.
enum SignalingStatus {
  /// Connection dropped unexpectedly; a reconnect attempt is scheduled.
  reconnecting,

  /// Connection resumed (`session.connect` with `reconnect: true` succeeded).
  reconnected,

  /// Reconnect window elapsed without success; the call is ended.
  failed,
}

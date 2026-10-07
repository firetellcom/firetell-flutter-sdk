/// Per-call WebSocket signaling timings (keep-alive / reconnect).
///
/// Mirrors firetell-client-sdk `call.ts`. Internal (not exported); values are
/// mutable only so tests can shorten them — call [reset] after changing.
class SignalingConfig {
  SignalingConfig._();

  /// Must receive `session.connected` within this window after opening the socket.
  static Duration authTimeout = _authTimeout;

  /// App-level keep-alive; must stay well below Cloudflare's 100s idle timeout.
  static Duration pingInterval = _pingInterval;

  /// No inbound message for this long => connection considered dead.
  static Duration idleTimeout = _idleTimeout;

  /// Total reconnect window; must be shorter than server DISCONNECT_GRACE_MS (15s).
  static Duration reconnectWindow = _reconnectWindow;

  static Duration reconnectBaseDelay = _reconnectBaseDelay;
  static Duration reconnectMaxDelay = _reconnectMaxDelay;

  /// Max events queued while signaling is reconnecting.
  static const outboxLimit = 50;

  /// Custom close code used when the SDK drops a dead connection itself.
  static const closeDeadConnection = 4000;

  static const _authTimeout = Duration(seconds: 3);
  static const _pingInterval = Duration(seconds: 25);
  static const _idleTimeout = Duration(seconds: 60);
  static const _reconnectWindow = Duration(seconds: 14);
  static const _reconnectBaseDelay = Duration(milliseconds: 500);
  static const _reconnectMaxDelay = Duration(seconds: 4);

  /// Restore production defaults.
  static void reset() {
    authTimeout = _authTimeout;
    pingInterval = _pingInterval;
    idleTimeout = _idleTimeout;
    reconnectWindow = _reconnectWindow;
    reconnectBaseDelay = _reconnectBaseDelay;
    reconnectMaxDelay = _reconnectMaxDelay;
  }
}

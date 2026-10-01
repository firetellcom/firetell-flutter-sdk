/// Client-level event names emitted by the [FiretellClient] class.
enum ClientEvent {
  /// Session authenticated and ready.
  session,

  /// Error occurred.
  error,

  /// Incoming call ring notification (from SSE).
  callRing,

  /// Incoming call offer with SDP (from per-call WebSocket).
  callOffer,

  /// New call created in workspace.
  callCreated,

  /// Call started (ringing at destination).
  callStarted,

  /// Call answered.
  callAnswered,

  /// Call ended.
  callEnded,

  /// Call canceled (before answer).
  callCanceled,

  /// Agent state changed.
  agentState,

  /// Agent state was forcefully changed by supervisor.
  agentStateForced,

  /// SSE connection state changed.
  connectionState,

  /// Inbound SMS/MMS message received from client.
  messageReceived,

  /// Outbound SMS/MMS message sent by an agent in workspace.
  messageSent,

  /// Message delivery status updated (queued, sent, delivered, failed).
  messageUpdated,

  /// Conversation thread updated (status, assignment, unread count).
  conversationUpdated,
}

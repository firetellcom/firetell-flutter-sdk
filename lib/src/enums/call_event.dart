/// Call-level event names emitted by the [Call] class.
enum CallEvent {
  /// Call state changed.
  state,

  /// Local media stream available or cleared.
  localStream,

  /// Remote media stream available or cleared.
  remoteStream,

  /// ICE connection state changed.
  mediaState,

  /// Mute/unmute state changed.
  mute,
}

/// Call lifecycle states matching the Firetell signaling protocol.
///
/// State machine:
/// ```
/// Outbound: none → initiated → ringing → answered → active → ended/error
/// Inbound:  none → ringing → answered → active → ended/error
/// Hold:     active → onHold → active
/// ```
enum CallState {
  /// No call state set.
  none,

  /// Call has been initiated (REST API called, WS connecting).
  initiated,

  /// Server is attempting to reach the destination.
  trying,

  /// Remote party is ringing.
  ringing,

  /// Call has been answered (SDP exchange complete).
  answered,

  /// Call is active with bidirectional media flowing.
  active,

  /// Call is on hold (SDP renegotiated to sendonly).
  onHold,

  /// Call has ended normally.
  ended,

  /// An error occurred during the call.
  error,

  /// Call was canceled before being answered.
  cancel,
}

/// Response from `POST /api/v1/call-center/calls` (REST make-call endpoint).
class MakeCallResponse {
  const MakeCallResponse({
    required this.callId,
    required this.status,
    required this.callToken,
    required this.wsUrl,
    required this.expiresIn,
  });

  factory MakeCallResponse.fromJson(Map<String, dynamic> json) {
    return MakeCallResponse(
      callId: json['call_id'] as String? ?? '',
      status: json['status'] as String? ?? '',
      callToken: json['call_token'] as String? ?? '',
      wsUrl: json['ws_url'] as String? ?? '',
      expiresIn: (json['expires_in'] as num?)?.toInt() ?? 0,
    );
  }

  /// Unique call identifier.
  final String callId;

  /// Call initiation status.
  final String status;

  /// Short-lived JWT for per-call WebSocket authentication.
  final String callToken;

  /// WebSocket URL for this call's signaling session.
  final String wsUrl;

  /// Token expiration in seconds.
  final int expiresIn;

  @override
  String toString() =>
      'MakeCallResponse(callId: $callId, status: $status)';
}

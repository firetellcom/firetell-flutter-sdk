/// Parsed `call.ring` push notification / SSE event payload.
///
/// This model is used to parse both FCM data messages (all string values)
/// and APNs VoIP push dictionaries (mixed types).
class CallRingParams {
  const CallRingParams({
    required this.callId,
    required this.callToken,
    this.wsUrl,
    this.ringTimeoutSecs = 30,
    this.callerNumber = '',
    this.callerName = '',
    this.callerAvatar,
    this.calleeNumber = '',
    this.calleeName = '',
    this.isTransfer = false,
    this.transferReason,
    this.isVideo = false,
    this.workspaceId,
  });

  /// Parse from FCM data-only message (all values are strings).
  factory CallRingParams.fromFcmData(Map<String, dynamic> data) {
    return CallRingParams(
      callId: data['call_id'] as String? ?? '',
      callToken: data['call_token'] as String? ?? '',
      wsUrl: data['ws_url'] as String?,
      ringTimeoutSecs:
          int.tryParse(data['ring_timeout_secs']?.toString() ?? '') ?? 30,
      callerNumber: data['caller_number'] as String? ?? '',
      callerName: data['caller_name'] as String? ?? '',
      callerAvatar: _nullIfEmpty(data['caller_avatar'] as String?),
      calleeNumber: data['callee_number'] as String? ?? '',
      calleeName: data['callee_name'] as String? ?? '',
      isTransfer: data['is_transfer']?.toString().toLowerCase() == 'true',
      transferReason: _nullIfEmpty(data['transfer_reason'] as String?),
      isVideo: data['is_video']?.toString().toLowerCase() == 'true',
      workspaceId: data['workspace_id'] as String?,
    );
  }

  /// Parse from APNs VoIP push dictionary (mixed types).
  factory CallRingParams.fromApnsPayload(Map<String, dynamic> data) {
    return CallRingParams(
      callId: data['call_id'] as String? ?? '',
      callToken: data['call_token'] as String? ?? '',
      wsUrl: data['ws_url'] as String?,
      ringTimeoutSecs: (data['ring_timeout_secs'] as num?)?.toInt() ?? 30,
      callerNumber: data['caller_number'] as String? ?? '',
      callerName: data['caller_name'] as String? ?? '',
      callerAvatar: _nullIfEmpty(data['caller_avatar']?.toString()),
      calleeNumber: data['callee_number'] as String? ?? '',
      calleeName: data['callee_name'] as String? ?? '',
      isTransfer: data['is_transfer'] == true,
      transferReason: _nullIfEmpty(data['transfer_reason']?.toString()),
      isVideo: data['is_video'] == true,
      workspaceId: data['workspace_id'] as String?,
    );
  }

  /// Parse from a generic map (auto-detects FCM string-only vs APNs mixed).
  factory CallRingParams.fromMap(Map<String, dynamic> data) {
    // FCM sends ring_timeout_secs as String; APNs sends as int.
    if (data['ring_timeout_secs'] is String) {
      return CallRingParams.fromFcmData(data);
    }
    return CallRingParams.fromApnsPayload(data);
  }

  final String callId;
  final String callToken;
  final String? wsUrl;
  final int ringTimeoutSecs;
  final String callerNumber;
  final String callerName;
  final String? callerAvatar;
  final String calleeNumber;
  final String calleeName;
  final bool isTransfer;
  final String? transferReason;
  final bool isVideo;
  final String? workspaceId;

  Map<String, dynamic> toMap() => {
        'call_id': callId,
        'call_token': callToken,
        'ws_url': wsUrl,
        'ring_timeout_secs': ringTimeoutSecs,
        'caller_number': callerNumber,
        'caller_name': callerName,
        'caller_avatar': callerAvatar,
        'callee_number': calleeNumber,
        'callee_name': calleeName,
        'is_transfer': isTransfer,
        'transfer_reason': transferReason,
        'is_video': isVideo,
        'workspace_id': workspaceId,
      };

  @override
  String toString() =>
      'CallRingParams(callId: $callId, from: $callerName <$callerNumber>)';

  static String? _nullIfEmpty(String? value) =>
      (value == null || value.isEmpty) ? null : value;
}

/// Parsed `call.canceled` or `call.ended` push notification payload.
class CallCancelParams {
  const CallCancelParams({
    required this.callId,
    required this.event,
    this.reason,
    this.workspaceId,
    this.timestamp,
  });

  factory CallCancelParams.fromMap(Map<String, dynamic> data) {
    return CallCancelParams(
      callId: data['call_id'] as String? ?? '',
      event: data['event'] as String? ?? 'call.canceled',
      reason: data['reason'] as String?,
      workspaceId: data['workspace_id'] as String?,
      timestamp: data['timestamp'] as String?,
    );
  }

  final String callId;

  /// Either `"call.canceled"` or `"call.ended"`.
  final String event;

  /// Cancellation reason (e.g. `"caller_hangup"`, `"timeout"`,
  /// `"answered_elsewhere"`).
  final String? reason;
  final String? workspaceId;
  final String? timestamp;

  @override
  String toString() =>
      'CallCancelParams(callId: $callId, event: $event, reason: $reason)';
}

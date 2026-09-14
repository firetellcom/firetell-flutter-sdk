/// REST and SSE API endpoint paths used by the SDK.
///
/// All paths are relative to the workspace base URL
/// (e.g. `https://{workspace_id}.firetell.app`).
class ApiEndpoints {
  ApiEndpoints._();

  /// Workspace metadata (ws_servers, ice_servers).
  static const workspaceMetadata = '/api/v1';

  /// Agent login (username/password → JWT).
  static const authLogin = '/api/v1/auth/login';

  /// REST make-call endpoint.
  static const makeCall = '/api/v1/call-center/calls';

  /// SSE realtime events stream.
  static const eventStream = '/stream';

  /// Agent phone numbers (DIDs).
  static const phoneNumbers = '/api/v1/call-center/phone-numbers';

  /// Register VoIP push token.
  static const voipPushToken = '/api/v1/me/devices/voip-push-token';

  /// Register notification push token.
  static const notificationPushToken =
      '/api/v1/me/devices/notification-push-token';

  /// Agent logout (invalidates session + removes push tokens).
  static const agentLogout = '/api/v1/me/logout';

  /// Call reject (fast HTTP reject using call_token).
  static String reject(String callId) =>
      '/api/v1/call-center/calls/$callId/reject';

  /// Call transfer.
  static String transfer(String callId) =>
      '/api/v1/call-center/calls/$callId/transfer';

  /// Call supervision.
  static String supervision(String callId, String mode) =>
      '/api/v1/call-center/calls/$callId/$mode';

  /// Stop supervision.
  static String supervisionStop(String callId) =>
      '/api/v1/call-center/calls/$callId/supervision';
}

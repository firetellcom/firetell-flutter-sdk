import 'dart:convert';

import 'package:http/http.dart' as http;

/// Helper service for registering/unregistering VoIP push tokens
/// with the Firetell Agent API.
///
/// Usage:
/// ```dart
/// await PushTokenService.registerVoipPushToken(
///   baseUrl: 'https://ws_123.firetell.app',
///   jwt: agentJwt,
///   pushToken: fcmOrApnsToken,
///   deviceId: deviceId,
///   platform: 'android', // or 'ios'
/// );
/// ```
class PushTokenService {
  PushTokenService._();

  /// Register a VoIP push notification token.
  ///
  /// Calls `POST /api/v1/me/devices/voip-push-token`.
  static Future<void> registerVoipPushToken({
    required String baseUrl,
    required String jwt,
    required String pushToken,
    required String deviceId,
    required String platform,
    String? osVersion,
    String? appVersion,
    String? deviceModel,
  }) async {
    final uri = Uri.parse('$baseUrl/api/v1/me/devices/voip-push-token');
    final response = await http.post(
      uri,
      headers: {
        'Authorization': 'Bearer $jwt',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'push_token': pushToken,
        'device_id': deviceId,
        'platform': platform,
        if (osVersion != null) 'os_version': osVersion,
        if (appVersion != null) 'app_version': appVersion,
        if (deviceModel != null) 'device_model': deviceModel,
      }),
    );

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw PushTokenException(
        'Failed to register VoIP push token: '
        'HTTP ${response.statusCode} ${response.body}',
      );
    }
  }

  /// Register a standard notification push token (for `call.canceled` /
  /// `call.ended` background dismissal).
  ///
  /// Calls `POST /api/v1/me/devices/notification-push-token`.
  static Future<void> registerNotificationPushToken({
    required String baseUrl,
    required String jwt,
    required String notificationToken,
    required String deviceId,
    required String platform,
  }) async {
    final uri =
        Uri.parse('$baseUrl/api/v1/me/devices/notification-push-token');
    final response = await http.post(
      uri,
      headers: {
        'Authorization': 'Bearer $jwt',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'notification_push_token': notificationToken,
        'device_id': deviceId,
        'platform': platform,
      }),
    );

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw PushTokenException(
        'Failed to register notification push token: '
        'HTTP ${response.statusCode} ${response.body}',
      );
    }
  }

  /// Agent logout — invalidates the session and removes push tokens
  /// server-side so the device no longer wakes for inbound calls.
  ///
  /// Calls `POST /api/v1/me/logout`.
  static Future<void> logout({
    required String baseUrl,
    required String jwt,
    required String deviceId,
  }) async {
    final uri = Uri.parse('$baseUrl/api/v1/me/logout');
    final response = await http.post(
      uri,
      headers: {
        'Authorization': 'Bearer $jwt',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'device_id': deviceId,
      }),
    );

    if (response.statusCode != 200 && response.statusCode != 204) {
      throw PushTokenException(
        'Logout failed: HTTP ${response.statusCode} ${response.body}',
      );
    }
  }
}

/// Exception thrown when a push token operation fails.
class PushTokenException implements Exception {
  const PushTokenException(this.message);

  final String message;

  @override
  String toString() => 'PushTokenException: $message';
}

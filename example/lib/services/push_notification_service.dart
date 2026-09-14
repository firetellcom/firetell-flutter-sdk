import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firetell_flutter_sdk/firetell_flutter_sdk.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_callkit_incoming/entities/call_kit_params.dart';
import 'package:flutter_callkit_incoming/entities/ios_params.dart';
import 'package:flutter_callkit_incoming/entities/android_params.dart';
import 'package:flutter_callkit_incoming/entities/notification_params.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';

/// Service that bridges platform push notifications (FCM / APNs) with
/// the Firetell SDK and flutter_callkit_incoming.
///
/// Responsible for:
/// 1. Requesting push permissions and obtaining tokens
/// 2. Registering tokens with the Firetell backend
/// 3. Showing/dismissing native incoming call UI from push payloads
/// 4. Handling foreground FCM messages
class PushNotificationService {
  PushNotificationService._();

  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;

  // ─── Initialization ────────────────────────────────────────────────

  /// Initialize push notifications and register tokens with the
  /// Firetell backend.
  ///
  /// Call this AFTER successful login (`client.ready` resolved).
  static Future<void> initialize({
    required FiretellClient client,
  }) async {
    // 1. Request permission (iOS requires explicit permission)
    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      criticalAlert: true, // Required for VoIP call alerts
    );

    if (settings.authorizationStatus == AuthorizationStatus.denied) {
      debugPrint('Push notification permission denied');
      return;
    }

    // 2. Get tokens
    final deviceId = await DeviceIdHelper.getOrCreate();

    if (!kIsWeb && Platform.isIOS) {
      // iOS: Get APNs token for VoIP push
      // Note: flutter_callkit_incoming handles PushKit VoIP token internally
      // We register the FCM token for call.canceled / call.ended notifications
      final apnsToken = await _messaging.getAPNSToken();
      debugPrint('APNs token: $apnsToken');
    }

    // FCM token (works on both Android and iOS)
    final fcmToken = await _messaging.getToken();
    if (fcmToken != null) {
      debugPrint('FCM token: $fcmToken');

      // Register VoIP push token
      await PushTokenService.registerVoipPushToken(
        baseUrl: client.baseUrl,
        jwt: client.jwt,
        pushToken: fcmToken,
        deviceId: deviceId,
        platform: Platform.isIOS ? 'ios' : 'android',
      );

      // Register notification token (for call.canceled / call.ended)
      await PushTokenService.registerNotificationPushToken(
        baseUrl: client.baseUrl,
        jwt: client.jwt,
        notificationToken: fcmToken,
        deviceId: deviceId,
        platform: Platform.isIOS ? 'ios' : 'android',
      );
    }

    // 3. Listen for token refresh
    _messaging.onTokenRefresh.listen((newToken) async {
      debugPrint('FCM token refreshed: $newToken');
      try {
        await PushTokenService.registerVoipPushToken(
          baseUrl: client.baseUrl,
          jwt: client.jwt,
          pushToken: newToken,
          deviceId: deviceId,
          platform: Platform.isIOS ? 'ios' : 'android',
        );
      } catch (e) {
        debugPrint('Failed to re-register push token: $e');
      }
    });

    // 4. Handle foreground FCM messages
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      debugPrint('FCM foreground message: ${message.data}');
      _handleForegroundMessage(message, client);
    });

    // 5. Handle app opened from notification tap (terminated → foreground)
    final initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) {
      debugPrint('App opened from push: ${initialMessage.data}');
      // The call.ring push has already triggered CallKit UI via
      // the background handler. CallKitHandler.onCallConnected will
      // fire when user answers.
    }
  }

  // ─── Foreground FCM Handler ────────────────────────────────────────

  static void _handleForegroundMessage(
    RemoteMessage message,
    FiretellClient client,
  ) {
    final event = message.data['event'] as String?;

    if (event == 'call.canceled' || event == 'call.ended') {
      final callId = message.data['call_id'] as String?;
      if (callId != null) {
        // Dismiss any pending incoming call UI
        FlutterCallkitIncoming.endCall(callId);

        // Cleanup SDK call if exists
        final call = client.activeCalls[callId];
        if (call != null) {
          call.destroy(sendHangup: false);
          client.activeCalls.remove(callId);
        }
      }
    }
    // Note: call.ring in foreground is handled by SSE → client.onCallRing,
    // no need to duplicate here.
  }

  // ─── Static Push Handlers (called from background isolate) ─────────

  /// Show native incoming call UI from a push notification payload.
  ///
  /// Called from the top-level FCM background message handler.
  /// This runs in a SEPARATE ISOLATE — no access to client instance.
  static Future<void> showIncomingCallFromPush(CallRingParams params) async {
    final callKitParams = CallKitParams(
      id: params.callId,
      nameCaller: params.callerName.isNotEmpty
          ? params.callerName
          : params.callerNumber,
      handle: params.callerNumber,
      type: params.isVideo ? 1 : 0,
      duration: params.ringTimeoutSecs * 1000,
      extra: params.toMap(),
      ios: const IOSParams(
        supportsVideo: false,
        maximumCallGroups: 1,
        maximumCallsPerCallGroup: 1,
        audioSessionMode: 'voiceChat',
        audioSessionActive: true,
        audioSessionPreferredSampleRate: 44100.0,
        audioSessionPreferredIOBufferDuration: 0.005,
      ),
      android: const AndroidParams(
        isShowLogo: false,
        backgroundColor: '#1a1a2e',
        actionColor: '#4fd1c5',
        isShowFullLockedScreen: true,
        isShowCallID: false,
        isCustomNotification: false,
      ),
      notification: const NotificationParams(
        showNotification: true,
        isShowMissedCallNotification: true,
      ),
    );

    await FlutterCallkitIncoming.showCallkitIncoming(callKitParams);
  }

  /// Dismiss native incoming call UI when call is canceled/ended.
  ///
  /// Called from the top-level FCM background message handler.
  static Future<void> dismissCallFromPush(String callId) async {
    await FlutterCallkitIncoming.endCall(callId);
  }
}

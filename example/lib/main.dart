import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firetell_flutter_sdk/firetell_flutter_sdk.dart';
import 'package:flutter/material.dart';

import 'services/cold_start_call_handler.dart';
import 'services/push_notification_service.dart';
import 'screens/login_screen.dart';

/// Top-level FCM background message handler.
///
/// MUST be a top-level function (not a class method).
/// Runs in a SEPARATE ISOLATE when app is killed or in background.
@pragma('vm:entry-point')
Future<void> _firebaseBackgroundMessageHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  debugPrint('FCM background: ${message.data}');

  final event = message.data['event'] as String?;

  if (event == 'call.ring') {
    final params = CallRingParams.fromFcmData(message.data);
    await PushNotificationService.showIncomingCallFromPush(params);
  } else if (event == 'call.canceled' || event == 'call.ended') {
    final callId = message.data['call_id'] as String?;
    if (callId != null) {
      await PushNotificationService.dismissCallFromPush(callId);
    }
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();

  // Register background FCM handler BEFORE runApp
  FirebaseMessaging.onBackgroundMessage(_firebaseBackgroundMessageHandler);

  // Global CallKit event listener — captures answer/decline from lock screen
  // even before any screen mounts. Uses ws_url + call_token from push payload
  // directly, no FiretellClient needed.
  ColdStartCallHandler.initialize();

  runApp(const FiretellExampleApp());
}

class FiretellExampleApp extends StatelessWidget {
  const FiretellExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Firetell SDK Example',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF4fd1c5),
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      home: const LoginScreen(),
    );
  }
}

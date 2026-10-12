import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import '../firebase_options.dart';

/// Service managing Firebase Cloud Messaging (FCM) notifications.
class NotificationService {
  static String? _fcmToken;

  /// Cached FCM Device Token.
  static String? get fcmToken => _fcmToken;

  /// Initialize Firebase and request notification permissions on supported platforms.
  static Future<void> initialize() async {
    // Only Android and iOS are configured for Firebase
    if (defaultTargetPlatform != TargetPlatform.android &&
        defaultTargetPlatform != TargetPlatform.iOS) {
      debugPrint('[FCM] Push notifications not active on $defaultTargetPlatform (mobile only).');
      return;
    }

    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );

      final messaging = FirebaseMessaging.instance;

      // Request notification permissions (required for Android 13+)
      final settings = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );

      debugPrint('[FCM] Notification authorization status: ${settings.authorizationStatus}');

      // Get device FCM token
      _fcmToken = await messaging.getToken();
      debugPrint('[FCM] Device Token: $_fcmToken');

      // Listen for token refreshes
      messaging.onTokenRefresh.listen((newToken) {
        _fcmToken = newToken;
        debugPrint('[FCM] Token refreshed: $newToken');
      });

      // Handle foreground notifications
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        debugPrint('[FCM] Received foreground message: ${message.notification?.title}');
      });

    } catch (e) {
      debugPrint('[FCM] Failed to initialize Firebase Messaging: $e');
    }
  }
}

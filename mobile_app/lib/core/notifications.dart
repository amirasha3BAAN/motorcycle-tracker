import 'package:firebase_messaging/firebase_messaging.dart';

class FCMNotificationService {
  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final String _deviceId = 'MOTO-ESP32-98A7B6';

  static Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
    print('📦 [FCM Background Message] ID: ${message.messageId}');
    if (message.notification != null) {
      print('[FCM Background Message] Title: ${message.notification!.title}');
      print('[FCM Background Message] Body: ${message.notification!.body}');
    }
  }

  Future<void> initialize() async {
    try {
      // 1. Request notifications permission for iOS / Android 13+
      NotificationSettings settings = await _fcm.requestPermission(
        alert: true,
        announcement: false,
        badge: true,
        carPlay: false,
        criticalAlert: true,
        provisional: false,
        sound: true,
      );

      print('[FCM] Notification authorization status: ${settings.authorizationStatus}');

      // 2. Fetch the registration token (for target device debugging)
      String? token = await _fcm.getToken();
      print('[FCM Token] Your Device Token: $token');

      // 3. Register background handler
      FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

      // 4. Handle foreground notifications
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        print('🔔 [FCM Foreground Message] Received inside app!');
        if (message.notification != null) {
          print('[FCM Foreground] Title: ${message.notification!.title}');
          print('[FCM Foreground] Body: ${message.notification!.body}');
        }
      });

      // 5. Handle when a notification is clicked to open the app
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        print('📬 [FCM Opened App] User tapped a notification.');
      });

      // 6. Automatically subscribe to this motorcycle's specific alert topic
      final String alertTopic = 'alerts_$_deviceId';
      await _fcm.subscribeToTopic(alertTopic);
      print('[FCM] Subscribed successfully to topic: "$alertTopic"');

    } catch (e) {
      print('[FCM Error] Skipping registration (running in local sandbox environment): $e');
    }
  }
}

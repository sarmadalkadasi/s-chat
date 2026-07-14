import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class LocalNotificationManager {
  static final FlutterLocalNotificationsPlugin _notificationsPlugin =
  FlutterLocalNotificationsPlugin();

  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'local_chat_channel',
    'Direct Chat Messages',
    description: 'Triggers when a new Firestore message is detected locally.',
    importance: Importance.max,
  );

  static Future<void> initialize() async {
    const AndroidInitializationSettings androidSettings =
    AndroidInitializationSettings('@mipmap/ic_launcher');

    const DarwinInitializationSettings iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const InitializationSettings settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    // FIX 1: Removed 'settings:' because it uses positional parameters
    await _notificationsPlugin.initialize(settings: settings);

    // FIX 2: Corrected the platform implementation class name (removed "Local")
    await _notificationsPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_channel);

    // FIX 3: Corrected the platform implementation class name here as well
    await _notificationsPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  // 4. Call this method to show the actual popup banner
  static void showNotification({required String title, required String body}) {
    // FIX 4: Removed named parameter labels ('id:', 'title:', 'body:', 'notificationDetails:')
    // because show() uses standard positional arguments
    _notificationsPlugin.show(
      id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title: title,
      body: body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _channel.id,
          _channel.name,
          channelDescription: _channel.description,
          importance: Importance.max,
          priority: Priority.high,
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentSound: true,
          presentBadge: true,
        ),
      ),
    );
  }
}
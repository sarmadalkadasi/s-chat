import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class LocalNotificationManager {
  static final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'local_chat_channel',
    'Direct Chat Messages',
    description: 'Triggers when a new Supabase message is detected locally.',
    importance: Importance.max,
  );

  static String? _activeChatId;
  static void Function(String chatId)? _onNotificationTap;

  /// Sets the currently active chat ID to suppress notifications for the open screen
  static void setActiveChatId(String? chatId) {
    _activeChatId = chatId;
  }

  /// Register callback when user taps a notification
  static void setOnNotificationTap(void Function(String chatId) onTap) {
    _onNotificationTap = onTap;
  }

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

    await _notificationsPlugin.initialize(
      settings: settings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        final payload = response.payload;
        if (payload != null && payload.isNotEmpty) {
          _onNotificationTap?.call(payload);
        }
      },
    );

    await _notificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_channel);

    await _notificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  /// Shows notification banner unless the user is actively viewing the same chat
  static Future<void> showNotification({
    required String title,
    required String body,
    String? chatId,
  }) async {
    // Suppress notification if user is currently inside the same chat
    if (chatId != null && _activeChatId == chatId) {
      return;
    }

    final int notificationId =
        DateTime.now().millisecondsSinceEpoch & 0x7FFFFFFF;

    await _notificationsPlugin.show(
      id: notificationId,
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
      payload: chatId,
    );
  }
}

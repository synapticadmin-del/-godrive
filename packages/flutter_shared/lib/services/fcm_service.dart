import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

/// FCM initialization, token registration and local notification display
/// shared by both Rider and Captain apps.
class FcmService {
  FcmService._();

  static final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();

  /// Channel used for foreground FCM notifications.
  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'synaptic_go_default',
    'Synaptic Go',
    description: 'Trip updates, offers and payments',
    importance: Importance.high,
  );

  /// Initialize Firebase, FCM and local-notifications plugin.
  static Future<void> init({
    Future<void> Function(String token)? onToken,
    void Function(Map<String, dynamic> data)? onTap,
  }) async {
    try {
      await Firebase.initializeApp();
      await _local.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        ),
        onDidReceiveNotificationResponse: _onLocalTap,
      );
      await _local
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(_channel);

      // Foreground handler
      FirebaseMessaging.onMessage.listen(_handleForeground);
      // Background/terminated tap → open payload
      FirebaseMessaging.onMessageOpenedApp.listen((m) => onTap?.call(m.data));
      _pendingTapHandler = onTap;

      // Initial notification (app opened from terminated via notification)
      final initial = await FirebaseMessaging.instance.getInitialMessage();
      if (initial != null) {
        onTap?.call(initial.data);
      }

      final settings = await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        announcement: false,
        carPlay: false,
        provisional: false,
      );
      if (kDebugMode) {
        print('[FCM] permission: ${settings.authorizationStatus}');
      }

      final token = await FirebaseMessaging.instance.getToken();
      if (token != null && onToken != null) await onToken(token);

      if (onToken != null) {
        FirebaseMessaging.instance.onTokenRefresh.listen(onToken);
      }
    } catch (e) {
      if (kDebugMode) {
        print('[FCM init error] $e');
      }
    }
  }

  // route foreground messages to local notifications plugin
  static void _handleForeground(RemoteMessage message) {
    final notif = message.notification;
    final title = notif?.title ?? 'Synaptic Go';
    final body = notif?.body ?? '';
    _local.show(
      message.hashCode,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channel.id,
          _channel.name,
          channelDescription: _channel.description,
          icon: '@mipmap/ic_launcher',
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
      payload: message.data.toString(),
    );
  }

  static void Function(Map<String, dynamic> data)? _pendingTapHandler;
  static void _onLocalTap(NotificationResponse response) {
    if (_pendingTapHandler != null) {
      _pendingTapHandler!({'rawPayload': response.payload});
    }
  }
}

@pragma('vm:entry-point')
Future<void> fcmBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp();
    if (kDebugMode) {
      print('[FCM bg] ${message.messageId}');
    }
  } catch (_) {}
}
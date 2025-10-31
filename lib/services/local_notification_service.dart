import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/material.dart';

/// Local Notification Service - 100% NO CLOUD
/// Sends notifications when AI detects trading opportunities
class LocalNotificationService {
  static final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  static bool _initialized = false;

  /// Initialize local notifications
  static Future<void> initialize() async {
    if (_initialized) return;

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _notifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );

    _initialized = true;
    debugPrint('✅ Local Notifications initialized');
  }

  /// Request permissions (iOS)
  static Future<bool> requestPermissions() async {
    final result = await _notifications
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        );

    return result ?? true; // Android doesn't need runtime permission
  }

  /// Show AI opportunity alert
  static Future<void> showOpportunityAlert({
    required String coin,
    required double confidence,
    required String action,
    required String timeframe,
  }) async {
    await initialize();

    // Choose emoji and color based on action
    final emoji = action == 'BUY' ? '🚀' : action == 'SELL' ? '📉' : '⏸️';
    final actionText = action == 'BUY' ? 'BUY Signal' : action == 'SELL' ? 'SELL Signal' : 'HOLD';

    const androidDetails = AndroidNotificationDetails(
      'ai_opportunities',
      'AI Trading Opportunities',
      channelDescription: 'Notifications for high-confidence AI predictions',
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      icon: '@mipmap/ic_launcher',
      color: Color(0xFF2196F3),
      styleInformation: BigTextStyleInformation(''),
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      interruptionLevel: InterruptionLevel.timeSensitive,
    );

    await _notifications.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      '$emoji $actionText: $coin',
      '${(confidence * 100).toStringAsFixed(1)}% confidence @ $timeframe - Tap to view',
      const NotificationDetails(android: androidDetails, iOS: iosDetails),
      payload: 'ai_prediction:$coin:$timeframe',
    );

    debugPrint('🔔 Notification sent: $action $coin @ ${(confidence * 100).toStringAsFixed(1)}%');
  }

  /// Show momentum alert
  static Future<void> showMomentumAlert({
    required String coin,
    required double momentum,
    required String trend,
  }) async {
    await initialize();

    final emoji = trend.contains('ACCELERATING') ? '📈' : '📉';

    const androidDetails = AndroidNotificationDetails(
      'ai_momentum',
      'AI Momentum Alerts',
      channelDescription: 'Notifications for significant confidence changes',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      playSound: true,
      icon: '@mipmap/ic_launcher',
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    await _notifications.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      '$emoji $trend: $coin',
      'Confidence ${momentum > 0 ? "increased" : "decreased"} by ${(momentum.abs() * 100).toStringAsFixed(1)}%',
      const NotificationDetails(android: androidDetails, iOS: iosDetails),
    );

    debugPrint('🔔 Momentum notification: $trend $coin (${(momentum * 100).toStringAsFixed(1)}%)');
  }

  /// Handle notification tap
  static void _onNotificationTapped(NotificationResponse response) {
    debugPrint('📱 Notification tapped: ${response.payload}');
    // TODO: Navigate to AI Prediction screen
    // You can use a NavigatorKey or event bus to navigate
  }

  /// Cancel all notifications
  static Future<void> cancelAll() async {
    await _notifications.cancelAll();
    debugPrint('🔕 All notifications cancelled');
  }

  /// Check if notifications are enabled
  static Future<bool> areNotificationsEnabled() async {
    if (!_initialized) await initialize();

    // Check Android
    final androidImpl = _notifications.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (androidImpl != null) {
      final enabled = await androidImpl.areNotificationsEnabled();
      return enabled ?? false;
    }

    // iOS always returns true if permission granted during init
    return true;
  }
}

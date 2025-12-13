import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io' show Platform;

/// Local Notification Service - 100% NO CLOUD
/// Sends notifications when AI detects trading opportunities
class LocalNotificationService {
  static final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  static bool _initialized = false;

  /// Initialize local notifications (does NOT request permissions)
  static Future<void> initialize() async {
    if (_initialized) return;

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    // iOS: Don't request permissions during initialization
    // We'll request them explicitly when user toggles "Enable AI Alerts"
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false,  // Changed to false
      requestBadgePermission: false,  // Changed to false
      requestSoundPermission: false,  // Changed to false
      // Show notifications even when app is in foreground (once permission is granted)
      defaultPresentAlert: true,
      defaultPresentBadge: true,
      defaultPresentSound: true,
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

  /// Request permissions - iOS uses native API, Android uses system settings
  static Future<bool> requestPermissions() async {
    await initialize();

    debugPrint('🔔 Requesting notification permissions...');

    if (kIsWeb) {
      debugPrint('⚠️  Notifications not supported on web');
      return false;
    }

    // iOS: Use flutter_local_notifications native API (most reliable)
    if (Platform.isIOS) {
      debugPrint('🔔 iOS: Requesting permissions via native API...');

      final iosImpl = _notifications.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();

      if (iosImpl == null) {
        debugPrint('❌ iOS plugin not available');
        return false;
      }

      // Request permissions
      final granted = await iosImpl.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );

      debugPrint('🔔 iOS permission result: $granted');
      return granted ?? false;
    }

    // Android: Request permission on Android 13+ (API 33+)
    if (Platform.isAndroid) {
      debugPrint('🔔 Android: Requesting notification permissions...');

      final androidImpl = _notifications.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

      if (androidImpl == null) {
        debugPrint('❌ Android plugin not available');
        return false;
      }

      // First check if already enabled
      var enabled = await androidImpl.areNotificationsEnabled();
      debugPrint('🔔 Android notifications currently enabled: $enabled');

      // On Android 13+ (API 33+), we need to explicitly request permission
      if (enabled != true) {
        debugPrint('🔔 Android: Requesting POST_NOTIFICATIONS permission...');
        final granted = await androidImpl.requestNotificationsPermission();
        debugPrint('🔔 Android permission request result: $granted');
        enabled = granted;
      }

      return enabled ?? false;
    }

    return false;
  }

  /// Show AI opportunity alert
  static Future<void> showOpportunityAlert({
    required String coin,
    required double confidence,
    required String action,
    required String timeframe,
  }) async {
    await initialize();

    // Request permissions if not already granted (iOS)
    await requestPermissions();

    // Premium 2025 design - subtle, professional
    final emoji = action == 'BUY' ? '📈' : action == 'SELL' ? '📉' : '⏸️';
    final actionText = action == 'BUY' ? 'Strong Buy' : action == 'SELL' ? 'Strong Sell' : 'Hold Position';
    final confidencePercent = (confidence * 100).toStringAsFixed(0);

    // Color based on action
    final color = action == 'BUY'
        ? const Color(0xFF10B981) // Premium green
        : action == 'SELL'
            ? const Color(0xFFEF4444) // Premium red
            : const Color(0xFF6366F1); // Premium indigo

    final androidDetails = AndroidNotificationDetails(
      'ai_opportunities',
      'AI Trading Signals',
      channelDescription: 'Premium AI-powered trading opportunities',
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      icon: '@mipmap/ic_launcher',
      color: color,
      styleInformation: BigTextStyleInformation(
        'AI detected a $confidencePercent% confidence $actionText signal for $coin on the $timeframe timeframe.\n\nTap to view detailed analysis and market insights.',
        contentTitle: '$emoji $coin $actionText',
        summaryText: 'MyTradeMate AI',
      ),
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      interruptionLevel: InterruptionLevel.timeSensitive,
      threadIdentifier: 'ai_trading_signals',
    );

    // Generate unique ID for each coin to prevent notifications from replacing each other
    final notificationId = coin.hashCode.abs();

    await _notifications.show(
      notificationId,
      '$emoji $coin $actionText',
      '$action @ $confidencePercent% • $timeframe',
      NotificationDetails(android: androidDetails, iOS: iosDetails),
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

    // Premium 2025 design
    final isAccelerating = trend.contains('ACCELERATING');
    final emoji = isAccelerating ? '⚡' : '⚠️';
    final trendText = isAccelerating ? 'Momentum Surge' : 'Trend Reversal';
    final momentumPercent = (momentum.abs() * 100).toStringAsFixed(0);
    final direction = momentum > 0 ? 'up' : 'down';

    // Color based on momentum
    final color = isAccelerating
        ? const Color(0xFF10B981) // Premium green
        : const Color(0xFFEF4444); // Premium red

    final androidDetails = AndroidNotificationDetails(
      'ai_momentum',
      'AI Momentum Alerts',
      channelDescription: 'Premium AI momentum change detection',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      playSound: true,
      icon: '@mipmap/ic_launcher',
      color: color,
      styleInformation: BigTextStyleInformation(
        'AI confidence shifted $direction by $momentumPercent% for $coin.\n\nMarket conditions may be changing - review your position.',
        contentTitle: '$emoji $coin $trendText',
        summaryText: 'MyTradeMate AI',
      ),
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      threadIdentifier: 'ai_momentum',
    );

    // Generate unique ID for each coin (offset by 1000000 to avoid collision with opportunity alerts)
    final notificationId = coin.hashCode.abs() + 1000000;

    await _notifications.show(
      notificationId,
      '$emoji $coin $trendText',
      '$momentumPercent% $direction',
      NotificationDetails(android: androidDetails, iOS: iosDetails),
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

    if (kIsWeb) return false;

    // Check Android
    if (Platform.isAndroid) {
      final androidImpl = _notifications.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (androidImpl != null) {
        final enabled = await androidImpl.areNotificationsEnabled();
        return enabled ?? false;
      }
    }

    // Check iOS
    if (Platform.isIOS) {
      final iosImpl = _notifications.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      if (iosImpl != null) {
        // Check notification settings
        final settings = await iosImpl.checkPermissions();
        return settings?.isEnabled ?? false;
      }
    }

    return false;
  }
}

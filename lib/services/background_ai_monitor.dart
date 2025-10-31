import 'package:workmanager/workmanager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import 'package:mytrademate/ml/crypto_ml_service.dart';
import 'package:mytrademate/services/local_notification_service.dart';

/// Background AI Monitor - Monitors crypto opportunities 24/7
/// 100% LOCAL - No cloud, no server, runs on device
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    debugPrint('🔄 Background AI Monitor running...');

    try {
      // Check if monitoring is enabled
      final prefs = await SharedPreferences.getInstance();
      final enabled = prefs.getBool('ai_alerts_enabled') ?? false;

      if (!enabled) {
        debugPrint('⏸️  AI Alerts disabled - skipping check');
        return Future.value(true);
      }

      // Get monitored coins (default: BTC, ETH, SOL)
      final coinsJson = prefs.getStringList('monitored_coins') ?? ['BTC', 'ETH', 'SOL'];

      // Get confidence threshold (default: 58%)
      final threshold = prefs.getDouble('confidence_threshold') ?? 0.58;

      // Get timeframe (default: 4h)
      final timeframe = prefs.getString('alert_timeframe') ?? '4h';

      // Initialize ML service
      final mlService = CryptoMLService();
      await mlService.initialize();

      // Get previous confidences for momentum detection
      final prevConfidences = <String, double>{};
      for (final coin in coinsJson) {
        prevConfidences[coin] = prefs.getDouble('prev_confidence_$coin') ?? 0.0;
      }

      // Check each coin
      for (final coin in coinsJson) {
        try {
          final prediction = await mlService.getPrediction(
            coin: coin,
            symbol: '${coin}EUR',
            timeframe: timeframe,
            silent: true, // Don't print debug logs in background
          );

          final currentConfidence = prediction.confidence;
          final previousConfidence = prevConfidences[coin] ?? 0.0;
          final momentum = currentConfidence - previousConfidence;

          // Save current confidence for next check
          await prefs.setDouble('prev_confidence_$coin', currentConfidence);

          // ALERT 1: High confidence opportunity
          if (currentConfidence > threshold &&
              previousConfidence < threshold - 0.05) {
            await LocalNotificationService.showOpportunityAlert(
              coin: coin,
              confidence: currentConfidence,
              action: prediction.action,
              timeframe: timeframe,
            );
          }

          // ALERT 2: Strong momentum (>3% change)
          if (momentum.abs() > 0.03) {
            final trend = momentum > 0 ? '📈 ACCELERATING' : '📉 REVERSAL RISK';
            await LocalNotificationService.showMomentumAlert(
              coin: coin,
              momentum: momentum,
              trend: trend,
            );
          }

          debugPrint('✅ $coin: ${(currentConfidence * 100).toStringAsFixed(1)}% (momentum: ${(momentum * 100).toStringAsFixed(1)}%)');
        } catch (e) {
          debugPrint('❌ Error checking $coin: $e');
        }
      }

      debugPrint('✅ Background check complete');
      return Future.value(true);
    } catch (e) {
      debugPrint('❌ Background task error: $e');
      return Future.value(false);
    }
  });
}

/// Background AI Monitor Service
class BackgroundAIMonitor {
  static const String _taskName = 'ai_monitoring_task';

  /// Initialize background monitoring
  static Future<void> initialize() async {
    await Workmanager().initialize(
      callbackDispatcher,
      isInDebugMode: false, // Set to true for debugging
    );
    debugPrint('✅ Background AI Monitor initialized');
  }

  /// Start monitoring
  static Future<void> startMonitoring({
    Duration frequency = const Duration(minutes: 30),
  }) async {
    await Workmanager().registerPeriodicTask(
      _taskName,
      _taskName,
      frequency: frequency,
      initialDelay: const Duration(minutes: 1), // First check after 1 minute
      constraints: Constraints(
        networkType: NetworkType.connected, // Requires internet for price data
        requiresBatteryNotLow: true, // Don't drain battery
      ),
      existingWorkPolicy: ExistingWorkPolicy.replace,
    );

    // Save enabled state
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('ai_alerts_enabled', true);

    debugPrint('🚀 Background monitoring started (every ${frequency.inMinutes} minutes)');
  }

  /// Stop monitoring
  static Future<void> stopMonitoring() async {
    await Workmanager().cancelByUniqueName(_taskName);

    // Save disabled state
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('ai_alerts_enabled', false);

    debugPrint('⏹️  Background monitoring stopped');
  }

  /// Check if monitoring is active
  static Future<bool> isMonitoring() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('ai_alerts_enabled') ?? false;
  }

  /// Update monitored coins
  static Future<void> setMonitoredCoins(List<String> coins) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('monitored_coins', coins);
    debugPrint('📝 Monitored coins updated: $coins');
  }

  /// Update confidence threshold
  static Future<void> setConfidenceThreshold(double threshold) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('confidence_threshold', threshold);
    debugPrint('📝 Confidence threshold updated: ${(threshold * 100).toStringAsFixed(0)}%');
  }

  /// Update alert timeframe
  static Future<void> setAlertTimeframe(String timeframe) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('alert_timeframe', timeframe);
    debugPrint('📝 Alert timeframe updated: $timeframe');
  }

  /// Get current settings
  static Future<Map<String, dynamic>> getSettings() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'enabled': prefs.getBool('ai_alerts_enabled') ?? false,
      'coins': prefs.getStringList('monitored_coins') ?? ['BTC', 'ETH', 'SOL'],
      'threshold': prefs.getDouble('confidence_threshold') ?? 0.58,
      'timeframe': prefs.getString('alert_timeframe') ?? '4h',
    };
  }
}

import 'dart:io' show Platform;
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

      // Get exchange name (default: binance)
      final exchangeName = prefs.getString('ai_alerts_exchange') ?? 'binance';

      // Build correct symbol based on exchange
      String buildSymbol(String coin, String exchange) {
        switch (exchange.toLowerCase()) {
          case 'kraken':
            // Kraken uses XBT for Bitcoin
            final krakenCoin = coin == 'BTC' ? 'XBT' : coin;
            return '${krakenCoin}EUR';
          case 'coinbase':
            // Coinbase uses hyphen separator
            return '$coin-EUR';
          case 'binance':
          default:
            // Binance uses direct concatenation
            return '${coin}EUR';
        }
      }

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
          final symbol = buildSymbol(coin, exchangeName);
          debugPrint('🔍 Checking $coin on $exchangeName: $symbol');

          final prediction = await mlService.getPrediction(
            coin: coin,
            symbol: symbol,
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

  /// Calculate adaptive polling interval based on timeframe
  /// - 5M → check every 5 minutes
  /// - 15M → check every 15 minutes
  /// - 1H+ → check every 30 minutes
  static Duration _getPollingInterval(String timeframe) {
    switch (timeframe) {
      case '5m':
        return const Duration(minutes: 5);
      case '15m':
        return const Duration(minutes: 15);
      case '1h':
      case '4h':
      case '1d':
      default:
        return const Duration(minutes: 30);
    }
  }

  /// Initialize background monitoring
  static Future<void> initialize() async {
    // Workmanager only works on Android
    if (Platform.isAndroid) {
      await Workmanager().initialize(
        callbackDispatcher,
        isInDebugMode: false, // Set to true for debugging
      );
      debugPrint('✅ Background AI Monitor initialized (Android)');
    } else {
      debugPrint('⚠️  Background monitoring not available on iOS - use foreground only');
    }
  }

  /// Start monitoring with adaptive frequency based on timeframe
  static Future<void> startMonitoring({
    required String exchangeName,
  }) async {
    // Read timeframe from SharedPreferences to calculate adaptive frequency
    final prefs = await SharedPreferences.getInstance();
    final timeframe = prefs.getString('alert_timeframe') ?? '4h';
    final frequency = _getPollingInterval(timeframe);

    // Background monitoring only works on Android
    if (Platform.isAndroid) {
      await Workmanager().registerPeriodicTask(
        _taskName,
        _taskName,
        frequency: frequency,
        initialDelay: const Duration(minutes: 1), // First check after 1 minute
        constraints: Constraints(
          networkType: NetworkType.connected, // Requires internet for price data
          requiresBatteryNotLow: true, // Don't drain battery
        ),
      );
      debugPrint('🚀 Background monitoring started: $timeframe → check every ${frequency.inMinutes} minutes');
    } else {
      // iOS: Just save the enabled state, notifications work in foreground
      debugPrint('⚠️  iOS: Background monitoring limited - alerts work when app is open');
    }

    // Save enabled state and exchange name
    await prefs.setBool('ai_alerts_enabled', true);
    await prefs.setString('ai_alerts_exchange', exchangeName);
    debugPrint('📝 AI Alerts exchange set to: $exchangeName');
  }

  /// Stop monitoring
  static Future<void> stopMonitoring() async {
    // Only cancel on Android
    if (Platform.isAndroid) {
      await Workmanager().cancelByUniqueName(_taskName);
      debugPrint('⏹️  Background monitoring stopped');
    }

    // Save disabled state
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('ai_alerts_enabled', false);
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

  /// Update alert timeframe and restart monitoring with new interval
  static Future<void> setAlertTimeframe(String timeframe) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('alert_timeframe', timeframe);

    // If monitoring is active, restart with new adaptive interval
    final isActive = prefs.getBool('ai_alerts_enabled') ?? false;
    if (isActive) {
      final exchangeName = prefs.getString('ai_alerts_exchange') ?? 'binance';
      await stopMonitoring();
      await startMonitoring(exchangeName: exchangeName);
      debugPrint('🔄 Restarted monitoring with new timeframe: $timeframe → ${_getPollingInterval(timeframe).inMinutes} min');
    } else {
      debugPrint('📝 Alert timeframe updated: $timeframe');
    }
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

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

/// ML Accuracy Monitor
///
/// Tracks predictions vs actual price movements to measure model accuracy
/// Usage:
/// ```dart
/// final monitor = MLAccuracyMonitor();
///
/// // Record prediction
/// monitor.recordPrediction(
///   coin: 'BTC',
///   timeframe: '5m',
///   prediction: 'BUY',
///   confidence: 0.75,
///   currentPrice: 95000.0,
/// );
///
/// // Check accuracy (after timeframe passed)
/// final accuracy = await monitor.calculateAccuracy(coin: 'BTC', timeframe: '5m');
/// print('BTC 5m accuracy: ${accuracy.toStringAsFixed(1)}%');
/// ```
class MLAccuracyMonitor {
  static final MLAccuracyMonitor _instance = MLAccuracyMonitor._internal();
  factory MLAccuracyMonitor() => _instance;
  MLAccuracyMonitor._internal();

  // In-memory cache
  final List<PredictionRecord> _predictions = [];
  bool _isLoaded = false;

  /// Load historical predictions from storage
  Future<void> load() async {
    if (_isLoaded) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString('ml_accuracy_predictions');
      if (json != null) {
        final List<dynamic> data = jsonDecode(json);
        _predictions.clear();
        _predictions.addAll(data.map((e) => PredictionRecord.fromJson(e)));
        debugPrint('📊 ML Monitor: Loaded ${_predictions.length} historical predictions');
      }
      _isLoaded = true;
    } catch (e) {
      debugPrint('⚠️ ML Monitor: Failed to load predictions: $e');
      _isLoaded = true;
    }
  }

  /// Save predictions to storage
  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Keep only last 1000 predictions (memory limit)
      final toSave = _predictions.length > 1000
          ? _predictions.sublist(_predictions.length - 1000)
          : _predictions;
      final json = jsonEncode(toSave.map((e) => e.toJson()).toList());
      await prefs.setString('ml_accuracy_predictions', json);
    } catch (e) {
      debugPrint('⚠️ ML Monitor: Failed to save predictions: $e');
    }
  }

  /// Record a new prediction
  Future<void> recordPrediction({
    required String coin,
    required String timeframe,
    required String prediction,
    required double confidence,
    required double currentPrice,
    Map<String, double>? technicals,
  }) async {
    await load();

    final record = PredictionRecord(
      timestamp: DateTime.now(),
      coin: coin,
      timeframe: timeframe,
      prediction: prediction,
      confidence: confidence,
      priceAtPrediction: currentPrice,
      technicals: technicals ?? {},
    );

    _predictions.add(record);

    debugPrint('📝 ML Monitor: Recorded $coin @$timeframe -> $prediction (${(confidence * 100).toStringAsFixed(1)}%) @ \$${currentPrice.toStringAsFixed(2)}');

    await _save();
  }

  /// Update actual price movement after timeframe elapsed
  Future<void> updateActualMovement({
    required String coin,
    required String timeframe,
    required double finalPrice,
  }) async {
    await load();

    // Find recent unverified predictions for this coin/timeframe
    final now = DateTime.now();
    final timeframeMinutes = _parseTimeframeMinutes(timeframe);

    for (var record in _predictions.reversed) {
      if (record.coin == coin &&
          record.timeframe == timeframe &&
          record.actualPriceChange == null) {

        final elapsed = now.difference(record.timestamp).inMinutes;

        // Only update if enough time has passed (e.g., 1x timeframe)
        if (elapsed >= timeframeMinutes) {
          record.actualPriceChange = ((finalPrice - record.priceAtPrediction) / record.priceAtPrediction) * 100;
          record.verifiedAt = now;

          // Check if prediction was correct
          final isCorrect = _isPredictionCorrect(record.prediction, record.actualPriceChange!);
          record.wasCorrect = isCorrect;

          debugPrint('✅ ML Monitor: Verified $coin @$timeframe -> ${record.prediction} was ${isCorrect ? "CORRECT ✅" : "WRONG ❌"} (predicted: ${record.prediction}, actual: ${record.actualPriceChange!.toStringAsFixed(2)}%)');

          await _save();
          break; // Only update the most recent unverified prediction
        }
      }
    }
  }

  /// Calculate accuracy for a specific coin/timeframe
  Future<double> calculateAccuracy({
    String? coin,
    String? timeframe,
    Duration? lookback,
  }) async {
    await load();

    final cutoff = lookback != null
        ? DateTime.now().subtract(lookback)
        : DateTime.now().subtract(const Duration(days: 7)); // Default: last 7 days

    final relevant = _predictions.where((p) {
      if (p.wasCorrect == null) return false; // Skip unverified
      if (p.timestamp.isBefore(cutoff)) return false; // Skip old
      if (coin != null && p.coin != coin) return false;
      if (timeframe != null && p.timeframe != timeframe) return false;
      return true;
    }).toList();

    if (relevant.isEmpty) return 0.0;

    final correct = relevant.where((p) => p.wasCorrect == true).length;
    return (correct / relevant.length) * 100;
  }

  /// Get accuracy summary for all coins/timeframes
  Future<Map<String, dynamic>> getAccuracySummary() async {
    await load();

    final summary = <String, dynamic>{};

    // Group by coin
    final coins = _predictions.map((p) => p.coin).toSet();
    for (var coin in coins) {
      final timeframes = _predictions
          .where((p) => p.coin == coin)
          .map((p) => p.timeframe)
          .toSet();

      summary[coin] = {};
      for (var tf in timeframes) {
        final accuracy = await calculateAccuracy(coin: coin, timeframe: tf);
        final count = _predictions
            .where((p) => p.coin == coin && p.timeframe == tf && p.wasCorrect != null)
            .length;

        summary[coin][tf] = {
          'accuracy': accuracy,
          'predictions': count,
        };
      }
    }

    return summary;
  }

  /// Get detailed statistics
  Future<AccuracyStats> getStats({String? coin, String? timeframe}) async {
    await load();

    final relevant = _predictions.where((p) {
      if (coin != null && p.coin != coin) return false;
      if (timeframe != null && p.timeframe != timeframe) return false;
      return true;
    }).toList();

    final verified = relevant.where((p) => p.wasCorrect != null).toList();
    final correct = verified.where((p) => p.wasCorrect == true).length;

    double avgConfidence = 0.0;
    if (relevant.isNotEmpty) {
      avgConfidence = relevant.map((p) => p.confidence).reduce((a, b) => a + b) / relevant.length;
    }

    double avgPriceChange = 0.0;
    if (verified.isNotEmpty) {
      avgPriceChange = verified
          .map((p) => p.actualPriceChange!)
          .reduce((a, b) => a + b) / verified.length;
    }

    return AccuracyStats(
      totalPredictions: relevant.length,
      verifiedPredictions: verified.length,
      correctPredictions: correct,
      accuracy: verified.isEmpty ? 0.0 : (correct / verified.length) * 100,
      avgConfidence: avgConfidence,
      avgPriceChange: avgPriceChange,
      buyCount: relevant.where((p) => p.prediction == 'BUY').length,
      sellCount: relevant.where((p) => p.prediction == 'SELL').length,
      holdCount: relevant.where((p) => p.prediction == 'HOLD').length,
    );
  }

  /// Clear old predictions (older than 30 days)
  Future<void> clearOldPredictions() async {
    await load();
    final cutoff = DateTime.now().subtract(const Duration(days: 30));
    _predictions.removeWhere((p) => p.timestamp.isBefore(cutoff));
    await _save();
    debugPrint('🧹 ML Monitor: Cleared predictions older than 30 days');
  }

  /// Parse timeframe string to minutes
  int _parseTimeframeMinutes(String timeframe) {
    final lower = timeframe.toLowerCase();
    if (lower.contains('5m')) return 5;
    if (lower.contains('15m')) return 15;
    if (lower.contains('1h')) return 60;
    if (lower.contains('4h')) return 240;
    if (lower.contains('1d')) return 1440;
    if (lower.contains('7d')) return 10080;
    return 60; // Default 1h
  }

  /// Check if prediction was correct
  bool _isPredictionCorrect(String prediction, double actualChange) {
    const threshold = 0.1; // 0.1% movement threshold

    switch (prediction.toUpperCase()) {
      case 'BUY':
      case 'STRONG_BUY':
        return actualChange > threshold; // Price went up
      case 'SELL':
      case 'STRONG_SELL':
        return actualChange < -threshold; // Price went down
      case 'HOLD':
        return actualChange.abs() < threshold; // Price stayed flat
      default:
        return false;
    }
  }
}

/// Prediction record
class PredictionRecord {
  final DateTime timestamp;
  final String coin;
  final String timeframe;
  final String prediction;
  final double confidence;
  final double priceAtPrediction;
  final Map<String, double> technicals;

  double? actualPriceChange;
  DateTime? verifiedAt;
  bool? wasCorrect;

  PredictionRecord({
    required this.timestamp,
    required this.coin,
    required this.timeframe,
    required this.prediction,
    required this.confidence,
    required this.priceAtPrediction,
    required this.technicals,
    this.actualPriceChange,
    this.verifiedAt,
    this.wasCorrect,
  });

  Map<String, dynamic> toJson() => {
    'timestamp': timestamp.toIso8601String(),
    'coin': coin,
    'timeframe': timeframe,
    'prediction': prediction,
    'confidence': confidence,
    'priceAtPrediction': priceAtPrediction,
    'technicals': technicals,
    'actualPriceChange': actualPriceChange,
    'verifiedAt': verifiedAt?.toIso8601String(),
    'wasCorrect': wasCorrect,
  };

  factory PredictionRecord.fromJson(Map<String, dynamic> json) => PredictionRecord(
    timestamp: DateTime.parse(json['timestamp']),
    coin: json['coin'],
    timeframe: json['timeframe'],
    prediction: json['prediction'],
    confidence: json['confidence'],
    priceAtPrediction: json['priceAtPrediction'],
    technicals: Map<String, double>.from(json['technicals'] ?? {}),
    actualPriceChange: json['actualPriceChange'],
    verifiedAt: json['verifiedAt'] != null ? DateTime.parse(json['verifiedAt']) : null,
    wasCorrect: json['wasCorrect'],
  );
}

/// Accuracy statistics
class AccuracyStats {
  final int totalPredictions;
  final int verifiedPredictions;
  final int correctPredictions;
  final double accuracy;
  final double avgConfidence;
  final double avgPriceChange;
  final int buyCount;
  final int sellCount;
  final int holdCount;

  AccuracyStats({
    required this.totalPredictions,
    required this.verifiedPredictions,
    required this.correctPredictions,
    required this.accuracy,
    required this.avgConfidence,
    required this.avgPriceChange,
    required this.buyCount,
    required this.sellCount,
    required this.holdCount,
  });

  @override
  String toString() => '''
📊 ML Accuracy Stats:
   Total Predictions: $totalPredictions
   Verified: $verifiedPredictions
   Correct: $correctPredictions
   Accuracy: ${accuracy.toStringAsFixed(1)}%
   Avg Confidence: ${(avgConfidence * 100).toStringAsFixed(1)}%
   Avg Price Change: ${avgPriceChange.toStringAsFixed(2)}%
   Distribution: BUY=$buyCount, SELL=$sellCount, HOLD=$holdCount
''';
}

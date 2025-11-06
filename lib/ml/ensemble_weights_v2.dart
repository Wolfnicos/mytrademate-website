import 'dart:math';

/// Enhanced weighting system for ML ensemble with dynamic adjustments
/// based on volatility (ATR) and recent model performance
class EnsembleWeightsV2 {
  // Performance tracking: modelKey -> List of recent predictions (correct=1, incorrect=0)
  static final Map<String, List<int>> _modelPerformance = {};
  static const int _performanceWindowSize = 50; // Track last 50 predictions

  // ATR cache: coin -> ATR value (cached for 5 minutes)
  static final Map<String, _ATRCache> _atrCache = {};
  static const Duration _atrCacheDuration = Duration(minutes: 5);

  /// Calculate Average True Range (ATR) from OHLCV candle data
  /// ATR measures volatility as the average of true ranges over a period
  ///
  /// Formula: ATR = Average of TR over last N periods
  /// where TR = max(High - Low, |High - Close_prev|, |Low - Close_prev|)
  ///
  /// [candles]: List of OHLCV data [timestamp, open, high, low, close, volume]
  /// [period]: Number of candles to calculate ATR over (default: 14 for crypto)
  ///
  /// Returns: ATR value (e.g., 0.05 = 5% volatility)
  static double calculateATR({
    required List<List<double>> candles,
    int period = 14,
  }) {
    if (candles.length < period + 1) {
      // Not enough data, return default medium volatility
      print('⚠️  Insufficient candles for ATR (need ${period + 1}, got ${candles.length})');
      return 0.02; // Default 2% volatility
    }

    final trueRanges = <double>[];

    // Calculate True Range for each candle
    for (int i = 1; i < candles.length; i++) {
      final high = candles[i][2]; // High price
      final low = candles[i][3];  // Low price
      final prevClose = candles[i - 1][4]; // Previous close

      // True Range = max of three values
      final tr = max(
        high - low,
        max(
          (high - prevClose).abs(),
          (low - prevClose).abs(),
        ),
      );

      trueRanges.add(tr);
    }

    // Calculate ATR as simple moving average of last 'period' TRs
    final recentTRs = trueRanges.length >= period
        ? trueRanges.sublist(trueRanges.length - period)
        : trueRanges;

    final atr = recentTRs.reduce((a, b) => a + b) / recentTRs.length;

    // Normalize ATR by current price to get percentage volatility
    final currentPrice = candles.last[4]; // Close price
    final atrPercent = (atr / currentPrice) * 100;

    print('📊 ATR calculated: ${atrPercent.toStringAsFixed(2)}% '
        '(${trueRanges.length} candles, last $period periods)');

    return atrPercent / 100; // Return as decimal (e.g., 0.05 = 5%)
  }

  /// Get ATR from cache or calculate if expired
  static Future<double> getATRCached({
    required String coin,
    required List<List<double>> candles,
    int period = 14,
  }) async {
    final cached = _atrCache[coin];
    final now = DateTime.now();

    if (cached != null && now.difference(cached.timestamp) < _atrCacheDuration) {
      print('✅ Using cached ATR for $coin: ${(cached.atr * 100).toStringAsFixed(2)}%');
      return cached.atr;
    }

    // Calculate fresh ATR
    final atr = calculateATR(candles: candles, period: period);
    _atrCache[coin] = _ATRCache(atr: atr, timestamp: now);

    return atr;
  }

  /// Calculate enhanced timeframe weight with dynamic adjustments
  ///
  /// **UPGRADE 1: Dynamic Weights Based on Volatility**
  /// - Increase weights for short timeframes (5m, 15m) by 20% if volatility > median
  /// - Track model accuracy over last 50 predictions and boost weights by 10% for above-average models
  ///
  /// **PHASE 3: Volume and Recency Enhancements**
  /// - Volume boost: +5% for general models on high-volume symbols (percentile > 0.5)
  /// - Recency penalty: -10% for models trained > 90 days ago
  ///
  /// [requestedTf]: User's requested timeframe (e.g., "1h")
  /// [modelTf]: Model's timeframe (e.g., "5m")
  /// [coin]: Cryptocurrency symbol (e.g., "btc")
  /// [atr]: Current ATR (volatility) for the coin
  /// [modelKey]: Model identifier (e.g., "btc_5m") for performance tracking
  /// [isGeneral]: Whether this is a general model (affects penalty)
  /// [volumePercentile]: Volume percentile (0.0-1.0) for Phase 3 volume boost
  /// [trainedDate]: Model training date (YYYY-MM-DD) for Phase 3 recency penalty
  ///
  /// Returns: Adjusted weight (will be normalized later)
  static double calculateTimeframeWeight({
    required String requestedTf,
    required String modelTf,
    required String coin,
    required double atr,
    required String modelKey,
    bool isGeneral = false,
    double volumePercentile = 0.5,
    String? trainedDate,
  }) {
    // Map timeframes to minutes for distance calculation
    const tfToMinutes = {
      '5m': 5,
      '15m': 15,
      '1h': 60,
      '4h': 240,
      '1d': 1440,
    };

    final requestedMinutes = tfToMinutes[requestedTf] ?? 60;
    final modelMinutes = tfToMinutes[modelTf] ?? 60;

    // ========================================
    // STEP 1: BASE WEIGHT (Timeframe Proximity)
    // ========================================
    double weight;

    if (requestedTf == modelTf) {
      // Exact match gets highest weight
      // REDUCED from 0.35 to 0.25 to prevent single model dominance
      weight = 0.25;
    } else {
      // Calculate distance in log space
      final distance = (requestedMinutes / modelMinutes).abs();
      final logDistance = (distance > 1.0 ? distance : 1.0 / distance);

      // Exponential decay for distant timeframes
      weight = 0.15 * (1.0 / (logDistance + 0.5));
      weight = weight.clamp(0.05, 0.35);
    }

    print('   📏 Base weight for $modelKey: ${weight.toStringAsFixed(3)} '
        '(tf match: $requestedTf vs $modelTf)');

    // ========================================
    // STEP 2: VOLATILITY BOOST (NEW!)
    // ========================================
    // High volatility? Short timeframes become more valuable
    // Median ATR for crypto: ~2.5% (empirical)
    const medianATR = 0.025;

    if (atr > medianATR && (modelTf == '5m' || modelTf == '15m')) {
      final volatilityBoost = 1.20; // 20% boost for short TFs in high volatility
      weight *= volatilityBoost;
      print('   🔥 Volatility boost: ${((volatilityBoost - 1) * 100).toStringAsFixed(0)}% '
          '(ATR: ${(atr * 100).toStringAsFixed(2)}% > ${(medianATR * 100).toStringAsFixed(2)}%)');
    }

    // ========================================
    // STEP 3: PERFORMANCE BOOST
    // ========================================
    // Models with recent accuracy > average get a 10% boost
    final recentAccuracy = getRecentModelAccuracy(modelKey);
    final avgAccuracy = getAverageAccuracy();

    if (recentAccuracy > avgAccuracy && recentAccuracy > 0.45) {
      // Only boost if accuracy is above 45% (better than random)
      final performanceBoost = 1.10; // 10% boost
      weight *= performanceBoost;
      print('   📈 Performance boost: ${((performanceBoost - 1) * 100).toStringAsFixed(0)}% '
          '(accuracy: ${(recentAccuracy * 100).toStringAsFixed(1)}% vs '
          'avg: ${(avgAccuracy * 100).toStringAsFixed(1)}%)');
    }

    // ========================================
    // STEP 4: GENERAL MODEL PENALTY
    // ========================================
    // UPGRADE 3: Reduced penalty for general models (0.6x → 0.8x)
    if (isGeneral) {
      const generalPenalty = 0.8; // Was 0.6, now 0.8 (less harsh)
      weight *= generalPenalty;
      print('   ⚖️  General model penalty: ${((1 - generalPenalty) * 100).toStringAsFixed(0)}% '
          '(final weight: ${weight.toStringAsFixed(3)})');
    }

    // ========================================
    // STEP 5: VOLUME BOOST (PHASE 3)
    // ========================================
    // General models get +5% confidence boost for high-volume symbols
    if (isGeneral && volumePercentile > 0.5) {
      const volumeBoost = 1.05; // 5% boost for high volume
      weight *= volumeBoost;
      print('   📊 Volume boost: +${((volumeBoost - 1) * 100).toStringAsFixed(0)}% '
          '(percentile: ${(volumePercentile * 100).toStringAsFixed(0)}%)');
    }

    // ========================================
    // STEP 6: RECENCY PENALTY (PHASE 3)
    // ========================================
    // Models trained > 90 days ago get -10% weight reduction
    if (trainedDate != null && trainedDate.isNotEmpty) {
      try {
        final trained = DateTime.parse(trainedDate);
        final daysSinceTrained = DateTime.now().difference(trained).inDays;

        if (daysSinceTrained > 90) {
          const recencyPenalty = 0.90; // -10% for old models
          weight *= recencyPenalty;
          print('   🕰️  Recency penalty: -${((1 - recencyPenalty) * 100).toStringAsFixed(0)}% '
              '($daysSinceTrained days old)');
        }
      } catch (e) {
        // Invalid date format, skip recency adjustment
        print('   ⚠️  Invalid trained_date format: $trainedDate');
      }
    }

    return weight;
  }

  /// Track prediction outcome for a model
  /// [modelKey]: Model identifier (e.g., "btc_5m")
  /// [correct]: Whether the prediction was correct (true) or incorrect (false)
  static void trackPrediction(String modelKey, bool correct) {
    if (!_modelPerformance.containsKey(modelKey)) {
      _modelPerformance[modelKey] = [];
    }

    _modelPerformance[modelKey]!.add(correct ? 1 : 0);

    // Keep only last N predictions (sliding window)
    if (_modelPerformance[modelKey]!.length > _performanceWindowSize) {
      _modelPerformance[modelKey]!.removeAt(0);
    }

    final accuracy = getRecentModelAccuracy(modelKey);
    print('📊 Model $modelKey performance: ${(accuracy * 100).toStringAsFixed(1)}% '
        '(${_modelPerformance[modelKey]!.length} predictions tracked)');
  }

  /// Get recent accuracy for a specific model
  /// Returns: Accuracy as decimal (e.g., 0.62 = 62%)
  static double getRecentModelAccuracy(String modelKey) {
    final performance = _modelPerformance[modelKey];
    if (performance == null || performance.isEmpty) {
      return 0.5; // Default: assume 50% if no data
    }

    final correct = performance.reduce((a, b) => a + b);
    return correct / performance.length;
  }

  /// Get average accuracy across all tracked models
  static double getAverageAccuracy() {
    if (_modelPerformance.isEmpty) return 0.5;

    final allAccuracies = _modelPerformance.keys
        .map((key) => getRecentModelAccuracy(key))
        .toList();

    return allAccuracies.reduce((a, b) => a + b) / allAccuracies.length;
  }

  /// Normalize weights to sum to 1.0
  /// [weights]: List of raw weights
  /// Returns: Normalized weights that sum to 1.0
  static List<double> normalizeWeights(List<double> weights) {
    final total = weights.reduce((a, b) => a + b);
    if (total == 0) {
      // Edge case: all weights are 0, distribute equally
      return List.filled(weights.length, 1.0 / weights.length);
    }

    final normalized = weights.map((w) => w / total).toList();
    print('✅ Weights normalized: ${normalized.map((w) => w.toStringAsFixed(3)).join(", ")}');

    return normalized;
  }

  /// Clear performance cache (useful for testing)
  static void clearPerformanceCache() {
    _modelPerformance.clear();
    _atrCache.clear();
    print('🗑️  Performance cache cleared');
  }

  /// Get performance statistics for debugging
  static Map<String, dynamic> getPerformanceStats() {
    return {
      'tracked_models': _modelPerformance.length,
      'average_accuracy': getAverageAccuracy(),
      'model_accuracies': _modelPerformance.map(
        (key, value) => MapEntry(key, getRecentModelAccuracy(key)),
      ),
      'cached_atrs': _atrCache.length,
    };
  }
}

/// Cache entry for ATR values
class _ATRCache {
  final double atr;
  final DateTime timestamp;

  _ATRCache({required this.atr, required this.timestamp});
}

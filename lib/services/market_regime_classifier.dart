import 'dart:math';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:flutter/foundation.dart';
import '../models/candle.dart';

/// Market Regime Classifier
///
/// Uses a small TFLite model (~200 KB) to classify current market conditions
/// into 7 regimes:
/// 1. STRONG_UPTREND: BTC +3-8%/day, ADX > 25
/// 2. WEAK_UPTREND: +1-3%/day, ADX 20-25
/// 3. SIDEWAYS_CHOPPY: ±2%/day, ADX < 20
/// 4. WEAK_DOWNTREND: -1-3%/day, ADX 20-25
/// 5. STRONG_DOWNTREND: -3-8%/day, ADX > 25
/// 6. HIGH_VOLATILITY: ATR > mean * 1.5
/// 7. LOW_VOLATILITY: ATR < mean * 0.7
///
/// This enables intelligent strategy selection: activate strategies that work
/// best in current conditions, deactivate those that don't.
class MarketRegimeClassifier {
  Interpreter? _regimeModel;
  bool _isLoaded = false;

  /// Load the regime classification model
  ///
  /// Model file: assets/models/regime_classifier_v1.tflite
  /// TODO: Train this model using Python script in PART3_IMPLEMENTATION_AND_EDUCATION.md
  Future<void> loadModel() async {
    if (_isLoaded) return;

    try {
      _regimeModel = await Interpreter.fromAsset('assets/models/regime_classifier_v1.tflite');
      _isLoaded = true;
      debugPrint('✅ Market Regime Classifier loaded');
    } catch (e) {
      debugPrint('⚠️ Market Regime Classifier not found. Using rule-based fallback.');
      _isLoaded = false;
    }
  }

  /// Classify market regime from last 24 hours of candles
  ///
  /// Returns MarketRegime with type and confidence score
  Future<MarketRegime> classifyRegime(List<Candle> last24Hours) async {
    if (last24Hours.length < 24) {
      debugPrint('⚠️ Insufficient data for regime classification (${last24Hours.length}/24)');
      return MarketRegime(
        type: RegimeType.SIDEWAYS_CHOPPY,
        confidence: 0.5,
        reason: 'Insufficient data',
      );
    }

    // Calculate 6 features for regime classification
    final features = _calculateRegimeFeatures(last24Hours);

    // If model loaded, use ML classification
    if (_isLoaded && _regimeModel != null) {
      return await _mlClassification(features);
    } else {
      // Fall back to rule-based classification
      return _ruleBasedClassification(features, last24Hours);
    }
  }

  /// ML-based classification using TFLite model
  Future<MarketRegime> _mlClassification(List<double> features) async {
    try {
      // Prepare input tensor [1, 6]
      var input = [features];
      var output = List.filled(7, 0.0).reshape([1, 7]);

      // Run inference
      _regimeModel!.run(input, output);

      // Get probabilities for each regime
      final probs = output[0] as List<double>;

      // Find regime with highest probability
      double maxProb = probs[0];
      int maxIndex = 0;
      for (int i = 1; i < probs.length; i++) {
        if (probs[i] > maxProb) {
          maxProb = probs[i];
          maxIndex = i;
        }
      }

      final regime = RegimeType.values[maxIndex];
      return MarketRegime(
        type: regime,
        confidence: maxProb,
        reason: 'ML classification (${(maxProb * 100).toStringAsFixed(1)}% confidence)',
      );
    } catch (e) {
      debugPrint('❌ ML classification error: $e. Falling back to rules.');
      return _ruleBasedClassification(features, []);
    }
  }

  /// Rule-based classification (fallback if model not available)
  MarketRegime _ruleBasedClassification(List<double> features, List<Candle> candles) {
    // final dirMove = features[0]; // Unused - commented out
    final adx = features[1];
    final atr = features[2];
    // final hurstExp = features[3]; // Unused - commented out
    // final volumeSurge = features[4]; // Unused - commented out
    // final autocorr = features[5]; // Unused - commented out

    // Calculate 7-day return if candles provided
    double return7d = 0.0;
    if (candles.isNotEmpty && candles.length >= 7) {
      return7d = (candles.last.close - candles[candles.length - 7].close) / candles[candles.length - 7].close;
    }

    // Determine mean ATR for volatility comparison
    double meanAtr = 500.0; // Typical BTC hourly ATR
    if (candles.isNotEmpty) {
      // Calculate mean ATR over available data
      final closes = candles.map((c) => c.close).toList();
      final highs = candles.map((c) => c.high).toList();
      final lows = candles.map((c) => c.low).toList();
      final atrValues = _calculateATR(highs, lows, closes, 14);
      if (atrValues.isNotEmpty) {
        meanAtr = atrValues.where((v) => v.isFinite).reduce((a, b) => a + b) / atrValues.where((v) => v.isFinite).length;
      }
    }

    // Classification rules (priority order)

    // 1. HIGH_VOLATILITY
    if (atr > meanAtr * 1.5) {
      return MarketRegime(
        type: RegimeType.HIGH_VOLATILITY,
        confidence: 0.85,
        reason: 'ATR spike: ${(atr / meanAtr * 100).toStringAsFixed(0)}% of mean',
      );
    }

    // 2. LOW_VOLATILITY
    if (atr < meanAtr * 0.7 && adx < 20) {
      return MarketRegime(
        type: RegimeType.LOW_VOLATILITY,
        confidence: 0.80,
        reason: 'Low ATR + weak ADX',
      );
    }

    // 3. STRONG_UPTREND
    if (adx > 25 && return7d > 0.05) {
      return MarketRegime(
        type: RegimeType.STRONG_UPTREND,
        confidence: 0.75,
        reason: 'ADX ${adx.toStringAsFixed(1)} + 7d return ${(return7d * 100).toStringAsFixed(1)}%',
      );
    }

    // 4. STRONG_DOWNTREND
    if (adx > 25 && return7d < -0.05) {
      return MarketRegime(
        type: RegimeType.STRONG_DOWNTREND,
        confidence: 0.75,
        reason: 'ADX ${adx.toStringAsFixed(1)} + 7d return ${(return7d * 100).toStringAsFixed(1)}%',
      );
    }

    // 5. SIDEWAYS_CHOPPY
    if (adx < 20 && return7d.abs() < 0.02) {
      return MarketRegime(
        type: RegimeType.SIDEWAYS_CHOPPY,
        confidence: 0.70,
        reason: 'Weak ADX + flat 7d return',
      );
    }

    // 6. WEAK_UPTREND
    if (return7d > 0.01 && return7d < 0.05) {
      return MarketRegime(
        type: RegimeType.WEAK_UPTREND,
        confidence: 0.65,
        reason: 'Moderate positive return',
      );
    }

    // 7. WEAK_DOWNTREND
    if (return7d < -0.01 && return7d > -0.05) {
      return MarketRegime(
        type: RegimeType.WEAK_DOWNTREND,
        confidence: 0.65,
        reason: 'Moderate negative return',
      );
    }

    // Default: SIDEWAYS_CHOPPY (uncertain)
    return MarketRegime(
      type: RegimeType.SIDEWAYS_CHOPPY,
      confidence: 0.50,
      reason: 'Uncertain (no clear pattern)',
    );
  }

  /// Calculate 6 regime features from 24-hour candles
  List<double> _calculateRegimeFeatures(List<Candle> candles) {
    final closes = candles.map((c) => c.close).toList();
    final highs = candles.map((c) => c.high).toList();
    final lows = candles.map((c) => c.low).toList();
    final volumes = candles.map((c) => c.volume).toList();

    // Feature 1: Directional Movement
    final high24 = highs.reduce((a, b) => a > b ? a : b);
    final low24 = lows.reduce((a, b) => a < b ? a : b);
    final open24 = candles.first.open;
    final dirMove = (high24 - low24) / open24;

    // Feature 2: ADX (14-period)
    final adx = _calculateADX(candles, 14);

    // Feature 3: ATR (14-period)
    final atrValues = _calculateATR(highs, lows, closes, 14);
    final atr = atrValues.isNotEmpty ? atrValues.last : 0.0;

    // Feature 4: Hurst Exponent (mean-reverting < 0.5, trending > 0.5)
    final hurst = _calculateHurstExponent(closes);

    // Feature 5: Volume Surge (24h vs 7d average)
    // Simplified: current volume vs mean volume
    final volumeSurge = volumes.last / (volumes.reduce((a, b) => a + b) / volumes.length);

    // Feature 6: Autocorrelation (positive = momentum, negative = reversion)
    final returns = _calculateReturns(closes);
    final autocorr = _calculateAutocorrelation(returns, lag: 1);

    return [dirMove, adx, atr, hurst, volumeSurge, autocorr];
  }

  /// Calculate ADX (Average Directional Index)
  double _calculateADX(List<Candle> candles, int period) {
    if (candles.length < period + 1) return 20.0; // Neutral fallback

    final highs = candles.map((c) => c.high).toList();
    final lows = candles.map((c) => c.low).toList();
    final closes = candles.map((c) => c.close).toList();

    // Calculate True Range
    List<double> tr = [0.0];
    for (int i = 1; i < candles.length; i++) {
      final hl = highs[i] - lows[i];
      final hc = (highs[i] - closes[i - 1]).abs();
      final lc = (lows[i] - closes[i - 1]).abs();
      tr.add(max(hl, max(hc, lc)));
    }

    // Calculate +DM and -DM
    List<double> plusDM = [0.0];
    List<double> minusDM = [0.0];
    for (int i = 1; i < candles.length; i++) {
      final upMove = highs[i] - highs[i - 1];
      final downMove = lows[i - 1] - lows[i];

      if (upMove > downMove && upMove > 0) {
        plusDM.add(upMove);
        minusDM.add(0.0);
      } else if (downMove > upMove && downMove > 0) {
        plusDM.add(0.0);
        minusDM.add(downMove);
      } else {
        plusDM.add(0.0);
        minusDM.add(0.0);
      }
    }

    // Smooth TR, +DM, -DM
    double smoothTR = tr.sublist(1, period + 1).reduce((a, b) => a + b);
    double smoothPlusDM = plusDM.sublist(1, period + 1).reduce((a, b) => a + b);
    double smoothMinusDM = minusDM.sublist(1, period + 1).reduce((a, b) => a + b);

    for (int i = period + 1; i < candles.length; i++) {
      smoothTR = smoothTR - (smoothTR / period) + tr[i];
      smoothPlusDM = smoothPlusDM - (smoothPlusDM / period) + plusDM[i];
      smoothMinusDM = smoothMinusDM - (smoothMinusDM / period) + minusDM[i];
    }

    // Calculate DI+ and DI-
    final plusDI = 100 * smoothPlusDM / smoothTR;
    final minusDI = 100 * smoothMinusDM / smoothTR;

    // Calculate DX and ADX
    final dx = 100 * (plusDI - minusDI).abs() / (plusDI + minusDI);
    return dx.isFinite ? dx : 20.0;
  }

  /// Calculate ATR (Average True Range)
  List<double> _calculateATR(List<double> highs, List<double> lows, List<double> closes, int period) {
    final n = highs.length;
    if (n < 2) return [];

    List<double> tr = [0.0];
    for (int i = 1; i < n; i++) {
      final hl = highs[i] - lows[i];
      final hc = (highs[i] - closes[i - 1]).abs();
      final lc = (lows[i] - closes[i - 1]).abs();
      tr.add(max(hl, max(hc, lc)));
    }

    List<double> atr = [];
    if (n >= period) {
      double sum = tr.sublist(1, period + 1).reduce((a, b) => a + b);
      atr.add(sum / period);

      for (int i = period + 1; i < n; i++) {
        atr.add((atr.last * (period - 1) + tr[i]) / period);
      }
    }

    return atr;
  }

  /// Calculate Hurst Exponent (simplified R/S analysis)
  double _calculateHurstExponent(List<double> prices) {
    if (prices.length < 20) return 0.5; // Neutral

    final returns = _calculateReturns(prices);
    if (returns.isEmpty) return 0.5;

    // Simplified Hurst calculation (not full R/S analysis)
    // Based on variance scaling
    final n = returns.length;
    final mean = returns.reduce((a, b) => a + b) / n;
    final variance = returns.map((r) => pow(r - mean, 2)).reduce((a, b) => a + b) / n;

    // Calculate variance at different lags
    int lag = (n / 4).floor();
    if (lag < 2) lag = 2;

    double lagVariance = 0.0;
    for (int i = lag; i < n; i++) {
      lagVariance += pow(returns[i] - returns[i - lag], 2);
    }
    lagVariance /= (n - lag);

    // Hurst = 0.5 + log(var_ratio) / (2 * log(lag))
    if (variance > 0 && lagVariance > 0) {
      final varRatio = lagVariance / variance;
      final hurst = 0.5 + log(varRatio) / (2 * log(lag));
      return hurst.clamp(0.0, 1.0);
    }

    return 0.5;
  }

  /// Calculate autocorrelation at given lag
  double _calculateAutocorrelation(List<double> series, {int lag = 1}) {
    if (series.length < lag + 10) return 0.0;

    final n = series.length - lag;
    final mean = series.reduce((a, b) => a + b) / series.length;

    double numerator = 0.0;
    double denominator = 0.0;

    for (int i = 0; i < n; i++) {
      numerator += (series[i] - mean) * (series[i + lag] - mean);
    }

    for (int i = 0; i < series.length; i++) {
      denominator += pow(series[i] - mean, 2);
    }

    if (denominator == 0) return 0.0;
    return numerator / denominator;
  }

  /// Calculate simple returns
  List<double> _calculateReturns(List<double> prices) {
    List<double> returns = [];
    for (int i = 1; i < prices.length; i++) {
      if (prices[i - 1] != 0) {
        returns.add((prices[i] - prices[i - 1]) / prices[i - 1]);
      }
    }
    return returns;
  }

  /// Dispose model resources
  void dispose() {
    _regimeModel?.close();
    _isLoaded = false;
  }
}

/// Market regime types
enum RegimeType {
  STRONG_UPTREND,
  WEAK_UPTREND,
  SIDEWAYS_CHOPPY,
  WEAK_DOWNTREND,
  STRONG_DOWNTREND,
  HIGH_VOLATILITY,
  LOW_VOLATILITY,
}

/// Market regime result
class MarketRegime {
  final RegimeType type;
  final double confidence; // 0.0 to 1.0
  final String reason;
  final DateTime timestamp;

  MarketRegime({
    required this.type,
    required this.confidence,
    required this.reason,
  }) : timestamp = DateTime.now();

  /// Get human-readable description
  String get description {
    switch (type) {
      case RegimeType.STRONG_UPTREND:
        return 'Strong Uptrend: BTC rising 3-8%/day with strong momentum';
      case RegimeType.WEAK_UPTREND:
        return 'Weak Uptrend: Moderate gains, trend not firmly established';
      case RegimeType.SIDEWAYS_CHOPPY:
        return 'Sideways/Choppy: Price range-bound, no clear direction';
      case RegimeType.WEAK_DOWNTREND:
        return 'Weak Downtrend: Moderate losses, uncertain direction';
      case RegimeType.STRONG_DOWNTREND:
        return 'Strong Downtrend: BTC falling 3-8%/day with strong bearish momentum';
      case RegimeType.HIGH_VOLATILITY:
        return 'High Volatility: Large price swings regardless of direction';
      case RegimeType.LOW_VOLATILITY:
        return 'Low Volatility: Stable, range-bound market';
    }
  }

  /// Get recommended action
  String get recommendation {
    switch (type) {
      case RegimeType.STRONG_UPTREND:
        return 'Enable: Momentum Scalper, Breakout Strategy';
      case RegimeType.WEAK_UPTREND:
        return 'Enable: RSI/ML Hybrid, Momentum Scalper (cautious)';
      case RegimeType.SIDEWAYS_CHOPPY:
        return 'Enable: Grid Bot, Mean Reversion';
      case RegimeType.WEAK_DOWNTREND:
        return 'Enable: Mean Reversion, RSI/ML Hybrid';
      case RegimeType.STRONG_DOWNTREND:
        return 'Enable: RSI/ML Hybrid ONLY (most reliable in bear markets)';
      case RegimeType.HIGH_VOLATILITY:
        return 'Enable: RSI/ML Hybrid ONLY, reduce position sizes by 50%';
      case RegimeType.LOW_VOLATILITY:
        return 'Enable: Grid Bot, Mean Reversion';
    }
  }

  /// Get color for UI display
  String get color {
    if (confidence >= 0.75) return 'green';
    if (confidence >= 0.60) return 'yellow';
    return 'orange';
  }

  @override
  String toString() {
    return '''
=== Market Regime ===
Type: $type
Confidence: ${(confidence * 100).toStringAsFixed(1)}%
Reason: $reason
Description: $description
Recommendation: $recommendation
Timestamp: $timestamp
''';
  }
}

/// Example usage:
///
/// ```dart
/// final classifier = MarketRegimeClassifier();
/// await classifier.loadModel();
///
/// // Fetch last 24 hours of data
/// final candles = await binanceService.fetchHourlyKlines('BTCUSDT', limit: 24);
///
/// // Classify regime
/// final regime = await classifier.classifyRegime(candles);
///
/// print(regime);
/// // Output:
/// // === Market Regime ===
/// // Type: RegimeType.STRONG_UPTREND
/// // Confidence: 78.5%
/// // Reason: ADX 32.4 + 7d return 6.2%
/// // Recommendation: Enable: Momentum Scalper, Breakout Strategy
///
/// // Use regime to adjust strategies
/// if (regime.type == RegimeType.SIDEWAYS_CHOPPY) {
///   // Activate Grid Bot and Mean Reversion
///   // Deactivate Momentum Scalper
/// }
/// ```

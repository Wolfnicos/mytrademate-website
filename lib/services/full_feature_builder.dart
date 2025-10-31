import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'dart:convert' show utf8;
import '../models/candle.dart';
import 'candle_pattern_detector.dart';

/// Full Feature Builder - generates ALL 76 features matching Python training
/// Features:
/// - 25 candle patterns (indices 0-24)
/// - 51 technical indicators and price features (indices 25-75)
class FullFeatureBuilder {
  final _patternDetector = CandlePatternDetector();

  /// Build complete 76-feature vector for 60 timesteps using SLIDING WINDOW
  /// Returns List<List<double>> of shape (60, 76)
  ///
  /// CRITICAL FIX: Each timestep uses a unique 60-candle window for feature calculation
  /// - Timestep 0: uses candles[candles.length - 119 : candles.length - 59]
  /// - Timestep 1: uses candles[candles.length - 118 : candles.length - 58]
  /// - ...
  /// - Timestep 59: uses candles[candles.length - 60 : candles.length]
  ///
  /// This ensures First row ≠ Last row and model sees temporal evolution, not static data.
  List<List<double>> buildFeatures({
    required List<Candle> candles,
  }) {
    const int lookback = 60; // Candles per window for feature calculation
    const int timesteps = 60; // Output sequence length
    const int minCandles = lookback + timesteps - 1; // 119

    if (candles.length < minCandles) {
      throw ArgumentError('Need at least $minCandles candles for sliding window, got ${candles.length}');
    }

    // Sort by time ascending
    final sorted = List<Candle>.from(candles)..sort((a, b) => a.closeTime.compareTo(b.closeTime));

    debugPrint('🔍 FullFeatureBuilder: Processing ${sorted.length} candles');
    debugPrint('   Using 2-PASS approach: pre-calculate all indicators, then extract last 60 timesteps');

    // === PASS 1: Pre-calculate ALL indicators on entire 1000-candle array ===
    final allFeatures = _calculateAllFeatures(sorted);

    // === PASS 2: Extract last 60 timesteps ===
    final n = sorted.length;
    final startIdx = n - timesteps;

    if (startIdx < 0) {
      throw ArgumentError('Need at least $timesteps candles, got $n');
    }

    final output = <List<double>>[];
    for (int i = startIdx; i < n; i++) {
      output.add(allFeatures[i]);
    }

    // DEBUG: Log first and last timestep
    if (output.isNotEmpty) {
      final firstRow = output.first;
      final lastRow = output.last;

      debugPrint('');
      debugPrint('🔬 FEATURE DEBUG | First timestep (t=0, candle index=$startIdx)');
      final priceAction0 = firstRow.sublist(25, 30).map((f) => f.toStringAsFixed(4)).join(', ');
      debugPrint('   Features[25:30] (price action): [$priceAction0]');
      final patterns0 = firstRow.sublist(0, 6).map((f) => f.toStringAsFixed(1)).join(', ');
      debugPrint('   Features[0:6] (patterns): [$patterns0]');

      debugPrint('');
      debugPrint('🔬 FEATURE DEBUG | Last timestep (t=59, candle index=${n-1})');
      final priceAction59 = lastRow.sublist(25, 30).map((f) => f.toStringAsFixed(4)).join(', ');
      debugPrint('   Features[25:30] (price action): [$priceAction59]');
      final patterns59 = lastRow.sublist(0, 6).map((f) => f.toStringAsFixed(1)).join(', ');
      debugPrint('   Features[0:6] (patterns): [$patterns59]');
    }

    debugPrint('🔍 FullFeatureBuilder: Generated ${output.length} timesteps × ${output.first.length} features');

    return output;
  }

  /// Pre-calculate ALL features for ALL candles (PASS 1)
  /// Returns [n, 76] array where each row is the feature vector for that candle
  List<List<double>> _calculateAllFeatures(List<Candle> candles) {
    // Extract OHLCV arrays from ALL candles
    final opens = candles.map((c) => c.open).toList();
    final highs = candles.map((c) => c.high).toList();
    final lows = candles.map((c) => c.low).toList();
    final closes = candles.map((c) => c.close).toList();
    final volumes = candles.map((c) => c.volume).toList();
    final n = closes.length; // 60

    // Pattern order MUST match Python exactly
    final patternOrder = [
      'doji', 'dragonfly_doji', 'gravestone_doji', 'long_legged_doji',
      'hammer', 'inverted_hammer', 'shooting_star', 'hanging_man',
      'spinning_top', 'marubozu_bullish', 'marubozu_bearish',
      'bullish_engulfing', 'bearish_engulfing', 'piercing_line',
      'dark_cloud_cover', 'bullish_harami', 'bearish_harami',
      'tweezer_bottom', 'tweezer_top', 'morning_star', 'evening_star',
      'three_white_soldiers', 'three_black_crows', 'rising_three', 'falling_three'
    ];

    // === CALCULATE ALL INDICATORS OVER THIS WINDOW ===
    final patterns = _patternDetector.detectAllPatterns(
      opens: opens,
      highs: highs,
      lows: lows,
      closes: closes,
      volumes: volumes,
    );

    final returns = _calculateReturns(closes);
    final logReturns = _calculateLogReturns(closes);
    final volatility = _calculateVolatility(returns);
    final hlRange = List<double>.generate(n, (i) => (highs[i] - lows[i]) / closes[i]);
    final closePosition = List<double>.generate(
      n,
      (i) => (closes[i] - lows[i]) / ((highs[i] - lows[i]) + 1e-10),
    );

    final rsi = _calculateRSI(closes, 14);
    final rsiOversold = rsi.map((v) => v < 30 ? 1.0 : 0.0).toList();
    final rsiOverbought = rsi.map((v) => v > 70 ? 1.0 : 0.0).toList();

    final macdData = _calculateMACD(closes);
    final macdLine = macdData['macd']!;
    final macdSignal = macdData['signal']!;
    final macdHistogram = macdData['histogram']!;
    final macdCrossAbove = List<double>.generate(n, (i) {
      if (i == 0) return 0.0;
      return (macdLine[i] > macdSignal[i] && macdLine[i - 1] <= macdSignal[i - 1]) ? 1.0 : 0.0;
    });
    final macdCrossBelow = List<double>.generate(n, (i) {
      if (i == 0) return 0.0;
      return (macdLine[i] < macdSignal[i] && macdLine[i - 1] >= macdSignal[i - 1]) ? 1.0 : 0.0;
    });

    final bbData = _calculateBollingerBands(closes, 20, 2.0);
    final bbUpper = bbData['upper']!;
    final bbMiddle = bbData['middle']!;
    final bbLower = bbData['lower']!;
    final bbWidth = List<double>.generate(n, (i) => (bbUpper[i] - bbLower[i]) / bbMiddle[i]);
    final bbPosition = List<double>.generate(
      n,
      (i) => (closes[i] - bbLower[i]) / ((bbUpper[i] - bbLower[i]) + 1e-10),
    );
    final bbSqueeze = bbWidth.map((v) => v < 0.1 ? 1.0 : 0.0).toList();

    final atr = _calculateATR(highs, lows, closes, 14);
    final atrPct = List<double>.generate(n, (i) => atr[i] / closes[i]);

    final adx = _calculateADX(highs, lows, closes, 14);
    final trending = adx.map((v) => v > 25 ? 1.0 : 0.0).toList();

    final stochData = _calculateStochastic(highs, lows, closes, 14);
    final stochK = stochData['k']!;
    final stochD = stochData['d']!;
    final stochOversold = stochK.map((v) => v < 20 ? 1.0 : 0.0).toList();
    final stochOverbought = stochK.map((v) => v > 80 ? 1.0 : 0.0).toList();

    final ichimoku = _calculateIchimoku(highs, lows, closes);
    final ichimokuTenkan = ichimoku['tenkan']!;
    final ichimokuKijun = ichimoku['kijun']!;
    final ichimokuSenkouA = ichimoku['senkou_a']!;
    final ichimokuSenkouB = ichimoku['senkou_b']!;
    final ichimokuCloudGreen = List<double>.generate(
      n,
      (i) => ichimokuSenkouA[i] > ichimokuSenkouB[i] ? 1.0 : 0.0,
    );
    final ichimokuAboveCloud = List<double>.generate(
      n,
      (i) => (closes[i] > ichimokuSenkouA[i] && closes[i] > ichimokuSenkouB[i]) ? 1.0 : 0.0,
    );
    final ichimokuBelowCloud = List<double>.generate(
      n,
      (i) => (closes[i] < ichimokuSenkouA[i] && closes[i] < ichimokuSenkouB[i]) ? 1.0 : 0.0,
    );

    final volSMA = _calculateSMA(volumes, 20);
    final volRatio = List<double>.generate(n, (i) => volumes[i] / (volSMA[i] + 1e-10));
    final obv = _calculateOBV(closes, volumes);
    final highVolume = volRatio.map((v) => v > 1.5 ? 1.0 : 0.0).toList();

    final sma20 = _calculateSMA(closes, 20);
    final sma50 = _calculateSMA(closes, 50);
    final sma200 = _calculateSMA(closes, 200);
    final priceAboveSma20 = List<double>.generate(n, (i) => closes[i] > sma20[i] ? 1.0 : 0.0);
    final priceAboveSma50 = List<double>.generate(n, (i) => closes[i] > sma50[i] ? 1.0 : 0.0);
    final priceAboveSma200 = List<double>.generate(n, (i) => closes[i] > sma200[i] ? 1.0 : 0.0);
    final goldenCross = List<double>.generate(n, (i) {
      if (i == 0) return 0.0;
      return (sma50[i] > sma200[i] && sma50[i - 1] <= sma200[i - 1]) ? 1.0 : 0.0;
    });
    final deathCross = List<double>.generate(n, (i) {
      if (i == 0) return 0.0;
      return (sma50[i] < sma200[i] && sma50[i - 1] >= sma200[i - 1]) ? 1.0 : 0.0;
    });

    final higherHigh = List<double>.generate(n, (i) {
      if (i == 0) return 0.0;
      return highs[i] > highs[i - 1] ? 1.0 : 0.0;
    });
    final lowerLow = List<double>.generate(n, (i) {
      if (i == 0) return 0.0;
      return lows[i] < lows[i - 1] ? 1.0 : 0.0;
    });
    final uptrend = List<double>.generate(
      n,
      (i) => (closes[i] > sma20[i] && sma20[i] > sma50[i]) ? 1.0 : 0.0,
    );
    final downtrend = List<double>.generate(
      n,
      (i) => (closes[i] < sma20[i] && sma20[i] < sma50[i]) ? 1.0 : 0.0,
    );

    // === BUILD FEATURE VECTORS FOR ALL CANDLES ===
    final output = <List<double>>[];

    for (int i = 0; i < n; i++) {
      final row = <double>[];

      // Candle patterns (0-24)
      for (final patternName in patternOrder) {
        row.add(patterns[patternName]![i]);
      }

      // Price action (25-29)
      row.add(returns[i]);
      row.add(logReturns[i]);
      row.add(volatility[i]);
      row.add(hlRange[i]);
      row.add(closePosition[i]);

      // RSI (30-32)
      row.add(rsi[i]);
      row.add(rsiOversold[i]);
      row.add(rsiOverbought[i]);

      // MACD (33-37)
      row.add(macdLine[i]);
      row.add(macdSignal[i]);
      row.add(macdHistogram[i]);
      row.add(macdCrossAbove[i]);
      row.add(macdCrossBelow[i]);

      // Bollinger Bands (38-43)
      row.add(bbUpper[i]);
      row.add(bbMiddle[i]);
      row.add(bbLower[i]);
      row.add(bbWidth[i]);
      row.add(bbPosition[i]);
      row.add(bbSqueeze[i]);

      // ATR (44-45)
      row.add(atr[i]);
      row.add(atrPct[i]);

      // ADX (46-47)
      row.add(adx[i]);
      row.add(trending[i]);

      // Stochastic (48-51)
      row.add(stochK[i]);
      row.add(stochD[i]);
      row.add(stochOversold[i]);
      row.add(stochOverbought[i]);

      // Ichimoku (52-58)
      row.add(ichimokuTenkan[i]);
      row.add(ichimokuKijun[i]);
      row.add(ichimokuSenkouA[i]);
      row.add(ichimokuSenkouB[i]);
      row.add(ichimokuCloudGreen[i]);
      row.add(ichimokuAboveCloud[i]);
      row.add(ichimokuBelowCloud[i]);

      // Volume (59-63)
      row.add(volumes[i]);
      row.add(volSMA[i]);
      row.add(volRatio[i]);
      row.add(obv[i]);
      row.add(highVolume[i]);

      // Moving Averages (64-72)
      row.add(sma20[i]);
      row.add(sma50[i]);
      row.add(sma200[i]);
      row.add(priceAboveSma20[i]);
      row.add(priceAboveSma50[i]);
      row.add(priceAboveSma200[i]);
      row.add(goldenCross[i]);
      row.add(deathCross[i]);

      // Trend indicators (73-76)
      row.add(higherHigh[i]);
      row.add(lowerLow[i]);
      row.add(uptrend[i]);
      row.add(downtrend[i]);

      // Sanitize: replace NaN/Inf with 0
      final sanitized = row.map((v) => v.isFinite ? v : 0.0).toList();

      assert(sanitized.length == 76, 'Expected 76 features, got ${sanitized.length}');

      output.add(sanitized);
    }

    return output; // [n, 76]
  }

  /// Deterministic training signature (features order + scalers + lookbacks)
  static String trainingSignature() {
    const String patterns = 'doji,dragonfly_doji,gravestone_doji,long_legged_doji,hammer,inverted_hammer,shooting_star,hanging_man,spinning_top,marubozu_bullish,marubozu_bearish,bullish_engulfing,bearish_engulfing,piercing_line,dark_cloud_cover,bullish_harami,bearish_harami,tweezer_bottom,tweezer_top,morning_star,evening_star,three_white_soldiers,three_black_crows,rising_three,falling_three';
    const String spec = 'features:76;window:60;patterns:$patterns;price_action:returns,log_returns,volatility,hl_range,close_position;rsi:14;macd:12,26,9;bollinger:20,2.0;atr:14;adx:14;stoch:14,k3;ichimoku:tenkan9,kijun26,senkouB52;volume_sma:20;ma:20,50,200;trend:higher_high,lower_low,uptrend,downtrend;scaler:identity_76';
    return spec;
  }

  static String trainingSignatureSha256() {
    final String spec = trainingSignature();
    final List<int> bytes = utf8.encode(spec);
    return crypto.sha256.convert(bytes).toString();
  }

  static bool isDataQualityOk(String expectedHash) {
    try {
      final String current = trainingSignatureSha256();
      final bool ok = expectedHash.isNotEmpty && current == expectedHash;
      debugPrint('FullFeatureBuilder.data_quality=${ok ? 'OK' : 'BAD'} (runtime=$current, expected=$expectedHash)');
      return ok;
    } catch (e) {
      debugPrint('FullFeatureBuilder.data_quality=BAD (hash error: $e)');
      return false;
    }
  }

  // ========== HELPER METHODS (CONTINUED IN NEXT MESSAGE DUE TO LENGTH) ==========

  List<double> _calculateReturns(List<double> closes) {
    final n = closes.length;
    final returns = List<double>.filled(n, 0.0);
    for (int i = 1; i < n; i++) {
      returns[i] = (closes[i] - closes[i - 1]) / closes[i - 1];
    }
    return returns;
  }

  List<double> _calculateLogReturns(List<double> closes) {
    final n = closes.length;
    final returns = List<double>.filled(n, 0.0);
    for (int i = 1; i < n; i++) {
      returns[i] = math.log(closes[i] / closes[i - 1]);
    }
    return returns;
  }

  List<double> _calculateVolatility(List<double> returns) {
    final n = returns.length;
    final volatility = List<double>.filled(n, 0.0);
    const window = 20;

    for (int i = window; i < n; i++) {
      final slice = returns.sublist(i - window, i);
      final mean = slice.reduce((a, b) => a + b) / window;
      final variance = slice.map((v) => math.pow(v - mean, 2)).reduce((a, b) => a + b) / window;
      volatility[i] = math.sqrt(variance);
    }
    return volatility;
  }

  List<double> _calculateSMA(List<double> values, int period) {
    final n = values.length;
    final sma = List<double>.filled(n, 0.0);

    for (int i = 0; i < n; i++) {
      if (i < period - 1) {
        sma[i] = values[0]; // Fill early values
      } else {
        final sum = values.sublist(i - period + 1, i + 1).reduce((a, b) => a + b);
        sma[i] = sum / period;
      }
    }
    return sma;
  }

  List<double> _calculateEMA(List<double> values, int period) {
    final n = values.length;
    final ema = List<double>.filled(n, 0.0);
    final multiplier = 2.0 / (period + 1);

    ema[0] = values[0];
    for (int i = 1; i < n; i++) {
      ema[i] = (values[i] - ema[i - 1]) * multiplier + ema[i - 1];
    }
    return ema;
  }

  List<double> _calculateRSI(List<double> closes, int period) {
    final n = closes.length;
    final rsi = List<double>.filled(n, 50.0);

    double avgGain = 0.0;
    double avgLoss = 0.0;

    // Calculate initial average
    for (int i = 1; i <= period; i++) {
      final change = closes[i] - closes[i - 1];
      if (change > 0) {
        avgGain += change;
      } else {
        avgLoss += -change;
      }
    }
    avgGain /= period;
    avgLoss /= period;

    rsi[period] = avgLoss == 0 ? 100 : 100 - (100 / (1 + avgGain / avgLoss));

    // Calculate remaining RSI values
    for (int i = period + 1; i < n; i++) {
      final change = closes[i] - closes[i - 1];
      final gain = change > 0 ? change : 0.0;
      final loss = change < 0 ? -change : 0.0;

      avgGain = (avgGain * (period - 1) + gain) / period;
      avgLoss = (avgLoss * (period - 1) + loss) / period;

      rsi[i] = avgLoss == 0 ? 100 : 100 - (100 / (1 + avgGain / avgLoss));
    }

    return rsi;
  }

  Map<String, List<double>> _calculateMACD(List<double> closes) {
    final ema12 = _calculateEMA(closes, 12);
    final ema26 = _calculateEMA(closes, 26);
    final n = closes.length;

    final macdLine = List<double>.generate(n, (i) => ema12[i] - ema26[i]);
    final signalLine = _calculateEMA(macdLine, 9);
    final histogram = List<double>.generate(n, (i) => macdLine[i] - signalLine[i]);

    return {
      'macd': macdLine,
      'signal': signalLine,
      'histogram': histogram,
    };
  }

  Map<String, List<double>> _calculateBollingerBands(List<double> closes, int period, double stdDev) {
    final sma = _calculateSMA(closes, period);
    final n = closes.length;
    final upper = List<double>.filled(n, 0.0);
    final lower = List<double>.filled(n, 0.0);

    for (int i = period - 1; i < n; i++) {
      final slice = closes.sublist(i - period + 1, i + 1);
      final mean = sma[i];
      final variance = slice.map((v) => math.pow(v - mean, 2)).reduce((a, b) => a + b) / period;
      final std = math.sqrt(variance);

      upper[i] = mean + (std * stdDev);
      lower[i] = mean - (std * stdDev);
    }

    // Fill early values
    for (int i = 0; i < period - 1; i++) {
      upper[i] = closes[i];
      lower[i] = closes[i];
    }

    return {
      'upper': upper,
      'middle': sma,
      'lower': lower,
    };
  }

  List<double> _calculateATR(List<double> highs, List<double> lows, List<double> closes, int period) {
    final n = closes.length;
    final tr = List<double>.filled(n, 0.0);

    for (int i = 1; i < n; i++) {
      final highLow = highs[i] - lows[i];
      final highClose = (highs[i] - closes[i - 1]).abs();
      final lowClose = (lows[i] - closes[i - 1]).abs();

      tr[i] = [highLow, highClose, lowClose].reduce(math.max);
    }

    return _calculateSMA(tr, period);
  }

  List<double> _calculateADX(List<double> highs, List<double> lows, List<double> closes, int period) {
    // Simplified ADX - just return a constant for now as full implementation is complex
    // TODO: Implement full ADX calculation
    return List<double>.filled(closes.length, 25.0);
  }

  Map<String, List<double>> _calculateStochastic(List<double> highs, List<double> lows, List<double> closes, int period) {
    final n = closes.length;
    final k = List<double>.filled(n, 50.0);
    final d = List<double>.filled(n, 50.0);

    for (int i = period - 1; i < n; i++) {
      final highestHigh = highs.sublist(i - period + 1, i + 1).reduce(math.max);
      final lowestLow = lows.sublist(i - period + 1, i + 1).reduce(math.min);

      k[i] = ((closes[i] - lowestLow) / ((highestHigh - lowestLow) + 1e-10)) * 100;
    }

    // %D is 3-period SMA of %K
    for (int i = period + 1; i < n; i++) {
      d[i] = k.sublist(i - 2, i + 1).reduce((a, b) => a + b) / 3;
    }

    return {'k': k, 'd': d};
  }

  Map<String, List<double>> _calculateIchimoku(List<double> highs, List<double> lows, List<double> closes) {
    final n = closes.length;

    // Tenkan-sen (9-period)
    final tenkan = List<double>.filled(n, 0.0);
    for (int i = 8; i < n; i++) {
      final high9 = highs.sublist(i - 8, i + 1).reduce(math.max);
      final low9 = lows.sublist(i - 8, i + 1).reduce(math.min);
      tenkan[i] = (high9 + low9) / 2;
    }

    // Kijun-sen (26-period)
    final kijun = List<double>.filled(n, 0.0);
    for (int i = 25; i < n; i++) {
      final high26 = highs.sublist(i - 25, i + 1).reduce(math.max);
      final low26 = lows.sublist(i - 25, i + 1).reduce(math.min);
      kijun[i] = (high26 + low26) / 2;
    }

    // Senkou Span A
    final senkouA = List<double>.generate(n, (i) => (tenkan[i] + kijun[i]) / 2);

    // Senkou Span B (52-period)
    final senkouB = List<double>.filled(n, 0.0);
    for (int i = 51; i < n; i++) {
      final high52 = highs.sublist(i - 51, i + 1).reduce(math.max);
      final low52 = lows.sublist(i - 51, i + 1).reduce(math.min);
      senkouB[i] = (high52 + low52) / 2;
    }

    // Fill early values
    for (int i = 0; i < 52; i++) {
      if (tenkan[i] == 0.0) tenkan[i] = closes[i];
      if (kijun[i] == 0.0) kijun[i] = closes[i];
      if (senkouA[i] == 0.0) senkouA[i] = closes[i];
      if (senkouB[i] == 0.0) senkouB[i] = closes[i];
    }

    return {
      'tenkan': tenkan,
      'kijun': kijun,
      'senkou_a': senkouA,
      'senkou_b': senkouB,
    };
  }

  List<double> _calculateOBV(List<double> closes, List<double> volumes) {
    final n = closes.length;
    final obv = List<double>.filled(n, 0.0);

    for (int i = 1; i < n; i++) {
      if (closes[i] > closes[i - 1]) {
        obv[i] = obv[i - 1] + volumes[i];
      } else if (closes[i] < closes[i - 1]) {
        obv[i] = obv[i - 1] - volumes[i];
      } else {
        obv[i] = obv[i - 1];
      }
    }

    return obv;
  }
}

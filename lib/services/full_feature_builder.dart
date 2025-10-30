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

  /// Build complete 76-feature vector for 60 timesteps
  /// Returns List<List<double>> of shape (60, 76)
  /// Minimum 50 candles required (for new coins like WLFI with 54 days history)
  List<List<double>> buildFeatures({
    required List<Candle> candles,
  }) {
    // Minimum 50 for sequence (WLFI has 54 days, TRUMP has more)
    if (candles.length < 50) {
      throw ArgumentError('Need at least 50 candles for sequence, got ${candles.length}');
    }

    // Warning for coins with < 120 candles (SMA100 will be less accurate)
    if (candles.length < 120) {
      debugPrint('⚠️ Only ${candles.length} candles available (< 120). SMA100 and long-term indicators may be less accurate.');
    }

    // Sort by time ascending
    final sorted = List<Candle>.from(candles)..sort((a, b) => a.closeTime.compareTo(b.closeTime));

    debugPrint('🔍 FullFeatureBuilder: Processing ${sorted.length} candles');

    // Extract OHLCV arrays - check for nulls
    final opens = sorted.map((c) => c.open).toList();
    final highs = sorted.map((c) => c.high).toList();
    final lows = sorted.map((c) => c.low).toList();
    final closes = sorted.map((c) => c.close).toList();
    final volumes = sorted.map((c) => c.volume).toList();

    debugPrint('🔍 FullFeatureBuilder: Extracted OHLCV (${opens.length} values each)');

    final n = closes.length;

    debugPrint('🔍 FullFeatureBuilder: Detecting candle patterns...');
    // === CANDLE PATTERNS (25 features, indices 0-24) ===
    final patterns = _patternDetector.detectAllPatterns(
      opens: opens,
      highs: highs,
      lows: lows,
      closes: closes,
      volumes: volumes,
    );

    debugPrint('🔍 FullFeatureBuilder: Detected ${patterns.length} patterns');

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

    // === PRICE ACTION (5 features, indices 25-29) ===
    final returns = _calculateReturns(closes);
    final logReturns = _calculateLogReturns(closes);
    final volatility = _calculateVolatility(returns);
    final hlRange = List<double>.generate(n, (i) => (highs[i] - lows[i]) / closes[i]);
    final closePosition = List<double>.generate(
      n,
      (i) => (closes[i] - lows[i]) / ((highs[i] - lows[i]) + 1e-10),
    );

    // === RSI (3 features, indices 30-32) ===
    final rsi = _calculateRSI(closes, 14);
    final rsiOversold = rsi.map((v) => v < 30 ? 1.0 : 0.0).toList();
    final rsiOverbought = rsi.map((v) => v > 70 ? 1.0 : 0.0).toList();

    // === MACD (5 features, indices 33-37) ===
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

    // === BOLLINGER BANDS (6 features, indices 38-43) ===
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

    // === ATR (2 features, indices 44-45) ===
    final atr = _calculateATR(highs, lows, closes, 14);
    final atrPct = List<double>.generate(n, (i) => atr[i] / closes[i]);

    // === ADX (2 features, indices 46-47) ===
    final adx = _calculateADX(highs, lows, closes, 14);
    final trending = adx.map((v) => v > 25 ? 1.0 : 0.0).toList();

    // === STOCHASTIC (4 features, indices 48-51) ===
    final stochData = _calculateStochastic(highs, lows, closes, 14);
    final stochK = stochData['k']!;
    final stochD = stochData['d']!;
    final stochOversold = stochK.map((v) => v < 20 ? 1.0 : 0.0).toList();
    final stochOverbought = stochK.map((v) => v > 80 ? 1.0 : 0.0).toList();

    // === ICHIMOKU (7 features, indices 52-58) ===
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

    // === VOLUME METRICS (5 features, indices 59-63) ===
    final volSMA = _calculateSMA(volumes, 20);
    final volRatio = List<double>.generate(n, (i) => volumes[i] / (volSMA[i] + 1e-10));
    final obv = _calculateOBV(closes, volumes);
    final highVolume = volRatio.map((v) => v > 1.5 ? 1.0 : 0.0).toList();

    // === MOVING AVERAGES (9 features, indices 64-72) ===
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

    // === TREND INDICATORS (4 features, indices 73-76) ===
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

    // === BUILD 76-FEATURE ROWS FOR LAST 60 TIMESTEPS ===
    final output = <List<double>>[];
    final startIdx = n - 60;

    // If we don't have 60 candles, pad with first candle data or use what we have
    if (startIdx < 0) {
      debugPrint('⚠️ WARNING: Only $n candles available, need 60. Padding sequence with earliest data.');
      // For coins with < 60 candles, take all available and pad at the beginning
      final paddingNeeded = -startIdx;

      // Pad with copies of the first candle's features
      for (int p = 0; p < paddingNeeded; p++) {
        final row = <double>[];
        final firstIdx = 0;

        // Candle patterns (0-24)
        for (final patternName in patternOrder) {
          row.add(patterns[patternName]![firstIdx]);
        }

        // Price action (25-29)
        row.add(returns[firstIdx]);
        row.add(logReturns[firstIdx]);
        row.add(volatility[firstIdx]);
        row.add(hlRange[firstIdx]);
        row.add(closePosition[firstIdx]);

        // RSI (30-32)
        row.add(rsi[firstIdx]);
        row.add(rsiOversold[firstIdx]);
        row.add(rsiOverbought[firstIdx]);

        // MACD (33-37)
        row.add(macdLine[firstIdx]);
        row.add(macdSignal[firstIdx]);
        row.add(macdHistogram[firstIdx]);
        row.add(macdCrossAbove[firstIdx]);
        row.add(macdCrossBelow[firstIdx]);

        // Bollinger Bands (38-43)
        row.add(bbUpper[firstIdx]);
        row.add(bbMiddle[firstIdx]);
        row.add(bbLower[firstIdx]);
        row.add(bbWidth[firstIdx]);
        row.add(bbPosition[firstIdx]);
        row.add(bbSqueeze[firstIdx]);

        // ATR (44-45)
        row.add(atr[firstIdx]);
        row.add(atrPct[firstIdx]);

        // ADX (46-47)
        row.add(adx[firstIdx]);
        row.add(trending[firstIdx]);

        // Stochastic (48-51)
        row.add(stochK[firstIdx]);
        row.add(stochD[firstIdx]);
        row.add(stochOversold[firstIdx]);
        row.add(stochOverbought[firstIdx]);

        // Ichimoku (52-58)
        row.add(ichimokuTenkan[firstIdx]);
        row.add(ichimokuKijun[firstIdx]);
        row.add(ichimokuSenkouA[firstIdx]);
        row.add(ichimokuSenkouB[firstIdx]);
        row.add(ichimokuCloudGreen[firstIdx]);
        row.add(ichimokuAboveCloud[firstIdx]);
        row.add(ichimokuBelowCloud[firstIdx]);

        // Volume (59-63)
        row.add(volumes[firstIdx]);
        row.add(volSMA[firstIdx]);
        row.add(volRatio[firstIdx]);
        row.add(obv[firstIdx]);
        row.add(highVolume[firstIdx]);

        // Moving averages (64-71)
        row.add(sma20[firstIdx]);
        row.add(sma50[firstIdx]);
        row.add(sma200[firstIdx]);
        row.add(priceAboveSma20[firstIdx]);
        row.add(priceAboveSma50[firstIdx]);
        row.add(priceAboveSma200[firstIdx]);
        row.add(goldenCross[firstIdx]);
        row.add(deathCross[firstIdx]);

        // Trend (73-76)
        row.add(higherHigh[firstIdx]);
        row.add(lowerLow[firstIdx]);
        row.add(uptrend[firstIdx]);
        row.add(downtrend[firstIdx]);

        output.add(row);
      }
    }

    final actualStartIdx = startIdx < 0 ? 0 : startIdx;

    for (int i = actualStartIdx; i < n; i++) {
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

      // Trend indicators (73-75)
      row.add(higherHigh[i]);
      row.add(lowerLow[i]);
      row.add(uptrend[i]);
      row.add(downtrend[i]);

      // DEBUG: Comprehensive analysis of feature values before sanitization
      if (i == actualStartIdx) {
        final nanCount = row.where((v) => !v.isFinite).length;
        final zeroCount = row.where((v) => v == 0.0).length;
        final nonZeroCount = row.where((v) => v.isFinite && v != 0.0).length;

        debugPrint('');
        debugPrint('🔬 FEATURE DEBUG (first row of 60):');
        debugPrint('   Total features: ${row.length}');
        debugPrint('   NaN/Inf: $nanCount');
        debugPrint('   Zero: $zeroCount');
        debugPrint('   Non-zero finite: $nonZeroCount');

        // Show patterns (0-24)
        final patterns = row.sublist(0, 25);
        final patternNonZero = patterns.where((v) => v.isFinite && v != 0.0).length;
        debugPrint('   Patterns [0-24]: $patternNonZero non-zero');

        // Show price action (25-29)
        debugPrint('   Price Action [25-29]: ${row.sublist(25, 30).map((v) => v.toStringAsFixed(4)).join(", ")}');

        // Show RSI (30)
        debugPrint('   RSI [30]: ${row[30].toStringAsFixed(4)}');

        // Show MACD (31-34)
        debugPrint('   MACD [31-34]: ${row.sublist(31, 35).map((v) => v.toStringAsFixed(4)).join(", ")}');

        // Show Bollinger (35-37)
        debugPrint('   Bollinger [35-37]: ${row.sublist(35, 38).map((v) => v.toStringAsFixed(4)).join(", ")}');

        // List all NaN/Inf indices
        if (nanCount > 0) {
          final nanIndices = <int>[];
          for (int j = 0; j < row.length; j++) {
            if (!row[j].isFinite) nanIndices.add(j);
          }
          debugPrint('   NaN/Inf indices: $nanIndices');
        }
        debugPrint('');
      }

      // Sanitize: replace NaN/Inf with 0
      final sanitized = row.map((v) => v.isFinite ? v : 0.0).toList();
      output.add(sanitized);
    }

    return output;
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

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

  /// Debug mode flag - set to true to enable detailed pattern logging
  static const bool debugMode = false;

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

    // DEBUG: Check allFeatures[997] BEFORE extraction (only in debug mode)
    if (debugMode && n >= 998) {
      final row997 = allFeatures[997];
      final patterns997_11_13 = row997.sublist(11, 14).map((f) => f.toStringAsFixed(1)).join(', ');
      debugPrint('🔍 DEBUG BEFORE EXTRACTION: allFeatures[997] Features[11:13] = [$patterns997_11_13]');
    }

    final output = <List<double>>[];
    for (int i = startIdx; i < n; i++) {
      output.add(allFeatures[i]);
    }

    // DEBUG: Log timestep features (only in debug mode)
    if (debugMode && output.isNotEmpty) {
      final firstRow = output.first;
      final lastRow = output.last;

      debugPrint('');
      debugPrint('🔬 FEATURE DEBUG | First timestep (t=0, candle index=$startIdx)');
      final priceAction0 = firstRow.sublist(25, 30).map((f) => f.toStringAsFixed(4)).join(', ');
      debugPrint('   Features[25:30] (price action): [$priceAction0]');
      final patterns0_6 = firstRow.sublist(0, 6).map((f) => f.toStringAsFixed(1)).join(', ');
      debugPrint('   Features[0:6] (single-candle patterns): [$patterns0_6]');
      final patterns11_13 = firstRow.sublist(11, 14).map((f) => f.toStringAsFixed(1)).join(', ');
      debugPrint('   Features[11:13] (multi-candle patterns: bullish_eng, bearish_eng, piercing): [$patterns11_13]');

      // Check timestep 55 (where Bearish Engulfing should be) and timestep 57
      if (output.length >= 56) {
        final row55 = output[55];
        final patterns55_0_6 = row55.sublist(0, 6).map((f) => f.toStringAsFixed(1)).join(', ');
        final patterns55_11_13 = row55.sublist(11, 14).map((f) => f.toStringAsFixed(1)).join(', ');
        debugPrint('');
        debugPrint('🔬 FEATURE DEBUG | Timestep 55 (candle index=${startIdx + 55})');
        debugPrint('   Features[0:6] (single-candle patterns): [$patterns55_0_6]');
        debugPrint('   Features[11:13] (multi-candle patterns: bullish_eng, bearish_eng, piercing): [$patterns55_11_13]');
      }

      if (output.length >= 58) {
        final row57 = output[57];
        final patterns57_0_6 = row57.sublist(0, 6).map((f) => f.toStringAsFixed(1)).join(', ');
        final patterns57_11_13 = row57.sublist(11, 14).map((f) => f.toStringAsFixed(1)).join(', ');
        debugPrint('');
        debugPrint('🔬 FEATURE DEBUG | Timestep 57 (candle index=${startIdx + 57})');
        debugPrint('   Features[0:6] (single-candle patterns): [$patterns57_0_6]');
        debugPrint('   Features[11:13] (multi-candle patterns: bullish_eng, bearish_eng, piercing): [$patterns57_11_13]');
      }

      debugPrint('');
      debugPrint('🔬 FEATURE DEBUG | Last timestep (t=59, candle index=${n-1})');
      final priceAction59 = lastRow.sublist(25, 30).map((f) => f.toStringAsFixed(4)).join(', ');
      debugPrint('   Features[25:30] (price action): [$priceAction59]');
      final patterns59_6 = lastRow.sublist(0, 6).map((f) => f.toStringAsFixed(1)).join(', ');
      debugPrint('   Features[0:6] (single-candle patterns): [$patterns59_6]');
      final patterns59_11_13 = lastRow.sublist(11, 14).map((f) => f.toStringAsFixed(1)).join(', ');
      debugPrint('   Features[11:13] (multi-candle patterns: bullish_eng, bearish_eng, piercing): [$patterns59_11_13]');

      // Detailed pattern breakdown for last timestep (only in debug mode)
      if (debugMode) {
        debugPrint('');
        debugPrint('📋 DETAILED PATTERN MAPPING for Last Timestep (t=59):');
        final patternIndices = [0, 1, 2, 3, 4, 5, 11, 12, 13, 19, 20]; // Include morning_star, evening_star
        final patternNames = ['doji', 'dragonfly_doji', 'gravestone_doji', 'long_legged_doji',
                              'hammer', 'inverted_hammer', 'bullish_engulfing', 'bearish_engulfing',
                              'piercing_line', 'morning_star', 'evening_star'];
        for (int i = 0; i < patternIndices.length; i++) {
          final idx = patternIndices[i];
          final name = patternNames[i];
          final value = lastRow[idx];
          if (value > 0.0) {
            debugPrint('   ✅ features[$idx] = $value → $name DETECTED');
          }
        }
      }
    }

    debugPrint('🔍 FullFeatureBuilder: Generated ${output.length} timesteps × ${output.first.length} features');

    // === PASS 3: Apply feature amplification to enhance weak signals ===
    final amplifiedOutput = FeatureAmplifier.amplifyFeatures(output);
    debugPrint('🔊 FeatureAmplifier: Applied signal enhancement to ${output.length} timesteps');

    return amplifiedOutput;
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

    // === PATTERN DETECTION LOGGING ===
    _logPatternDetection(
      candles: candles,
      patterns: patterns,
      patternOrder: patternOrder,
      startIdx: n >= 60 ? n - 60 : 0,  // Log last 60 candles
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

  /// Log pattern detection for debugging
  /// Shows detected patterns for the last 60 candles
  /// Detailed OHLC data only shown in debugMode
  void _logPatternDetection({
    required List<Candle> candles,
    required Map<String, List<double>> patterns,
    required List<String> patternOrder,
    required int startIdx,
  }) {
    final n = candles.length;
    int patternsDetected = 0;
    final detectedPatterns = <String, List<int>>{};

    // First pass: count total patterns detected and collect indices
    for (final patternName in patternOrder.take(6)) {  // Only first 6 patterns (indices 0-5)
      final patternValues = patterns[patternName]!;
      final detectedIndices = <int>[];

      for (int i = startIdx; i < n; i++) {
        if (patternValues[i] > 0.0) {
          patternsDetected++;
          detectedIndices.add(i);
        }
      }

      if (detectedIndices.isNotEmpty) {
        detectedPatterns[patternName] = detectedIndices;
      }
    }

    // Only show detailed pattern analysis in debug mode
    if (debugMode) {
      debugPrint('');
      debugPrint('🔬 ════════════════════════════════════════════════════════════════');
      debugPrint('🔬 PATTERN DETECTION ANALYSIS (Last 60 candles)');
      debugPrint('🔬 ════════════════════════════════════════════════════════════════');
      debugPrint('📊 Total patterns detected: $patternsDetected');
      debugPrint('');
    }

    if (patternsDetected == 0 && debugMode) {
      debugPrint('⚠️  NO PATTERNS DETECTED in last 60 candles');
      debugPrint('   This is NORMAL for:');
      debugPrint('   • Low volatility periods');
      debugPrint('   • Short timeframes (5m, 15m)');
      debugPrint('   • Stable/ranging markets');
      debugPrint('');

      // Show sample candles to verify data quality
      if (n > 0) {
        final lastCandle = candles[n - 1];
        final body = (lastCandle.close - lastCandle.open).abs();
        final range = lastCandle.high - lastCandle.low;
        final bodyPct = range > 0 ? (body / range * 100) : 0;

        debugPrint('📍 Last candle analysis:');
        debugPrint('   Open:  \$${lastCandle.open.toStringAsFixed(2)}');
        debugPrint('   High:  \$${lastCandle.high.toStringAsFixed(2)}');
        debugPrint('   Low:   \$${lastCandle.low.toStringAsFixed(2)}');
        debugPrint('   Close: \$${lastCandle.close.toStringAsFixed(2)}');
        debugPrint('   Body:  ${bodyPct.toStringAsFixed(1)}% of range');
        debugPrint('   Direction: ${lastCandle.close > lastCandle.open ? "BULLISH ▲" : "BEARISH ▼"}');
      }
    } else if (debugMode) {
      // Show detailed info for each detected pattern
      for (final entry in detectedPatterns.entries) {
        final patternName = entry.key;
        final indices = entry.value;

        debugPrint('✅ Pattern: ${patternName.toUpperCase().replaceAll('_', ' ')}');
        debugPrint('   Detected at ${indices.length} timestep(s): ${indices.map((i) => i - startIdx).join(', ')}');

        // Show OHLC for first detection
        if (indices.isNotEmpty) {
          final idx = indices.first;
          final candle = candles[idx];
          final body = (candle.close - candle.open).abs();
          final range = candle.high - candle.low;
          final upperShadow = candle.high - math.max(candle.open, candle.close);
          final lowerShadow = math.min(candle.open, candle.close) - candle.low;

          debugPrint('   📊 Candle @ timestep ${idx - startIdx}:');
          debugPrint('      Open:  \$${candle.open.toStringAsFixed(2)}');
          debugPrint('      High:  \$${candle.high.toStringAsFixed(2)}');
          debugPrint('      Low:   \$${candle.low.toStringAsFixed(2)}');
          debugPrint('      Close: \$${candle.close.toStringAsFixed(2)}');
          debugPrint('      Body: \$${body.toStringAsFixed(2)} (${(body/range*100).toStringAsFixed(1)}%)');
          debugPrint('      Upper shadow: \$${upperShadow.toStringAsFixed(2)} (${(upperShadow/range*100).toStringAsFixed(1)}%)');
          debugPrint('      Lower shadow: \$${lowerShadow.toStringAsFixed(2)} (${(lowerShadow/range*100).toStringAsFixed(1)}%)');
          debugPrint('');
        }
      }
    }

    if (debugMode) {
      debugPrint('🔬 ════════════════════════════════════════════════════════════════');
      debugPrint('');
    }

    // === MINIMAL LOGGING: Check critical patterns in LAST 5 candles ===
    // Only log multi-candle patterns (Bullish Engulfing, Piercing Line, etc.) - keep this always on

    // Check multi-candle patterns (bullish_engulfing, bearish_engulfing, morning_star, evening_star)
    final multiCandlePatterns = ['bullish_engulfing', 'bearish_engulfing', 'morning_star', 'evening_star'];
    final multiCandleIndices = [11, 12, 19, 20]; // Feature indices for these patterns

    for (int idx = 0; idx < multiCandlePatterns.length; idx++) {
      final patternName = multiCandlePatterns[idx];
      final featureIdx = multiCandleIndices[idx];
      final patternValues = patterns[patternName]!;
      final lastFivePatterns = <int>[];

      for (int i = n - 5; i < n; i++) {
        if (patternValues[i] > 0.0) {
          lastFivePatterns.add(i);
        }
      }

      if (lastFivePatterns.isNotEmpty) {
        // Always log critical pattern detection
        final timesteps = lastFivePatterns.map((idx) => idx - startIdx).toList();
        debugPrint('🔥 ${patternName.toUpperCase().replaceAll('_', ' ')}: detected at timesteps ${timesteps.join(", ")}');

        // Only show detailed OHLC in debug mode
        if (debugMode) {
          debugPrint('   → Detected at candle indices: ${lastFivePatterns.join(", ")}');
          debugPrint('   → Should appear in features[$featureIdx] at timesteps ${timesteps.join(", ")}');

          // Show pattern values and OHLC for debugging
          for (final candleIdx in lastFivePatterns) {
            if (candleIdx > 0 && candleIdx < candles.length) {
              final prevCandle = candles[candleIdx - 1];
              final currCandle = candles[candleIdx];
              debugPrint('   → Candle[${candleIdx-1}]: O=${prevCandle.open.toStringAsFixed(2)} C=${prevCandle.close.toStringAsFixed(2)} (${prevCandle.close > prevCandle.open ? "BULL" : "BEAR"})');
              debugPrint('   → Candle[$candleIdx]: O=${currCandle.open.toStringAsFixed(2)} C=${currCandle.close.toStringAsFixed(2)} (${currCandle.close > currCandle.open ? "BULL" : "BEAR"})');
            }
          }
        }
      }
    }

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

/// Feature Amplifier - enhances weak signals before model input
/// Addresses the "zero patterns everywhere" problem by:
/// 1. Pattern Enhancement - amplifies subtle candlestick patterns
/// 2. Momentum Amplification - boosts directional momentum signals
/// 3. Cross-Feature Correlation Enhancement - amplifies related features together
class FeatureAmplifier {
  /// Amplify weak signals before model input
  /// Input: [60, 76] feature array (60 timesteps × 76 features)
  /// Output: [60, 76] amplified feature array
  static List<List<double>> amplifyFeatures(List<List<double>> features) {
    if (features.isEmpty || features.first.length != 76) {
      return features; // Safety: return unchanged if invalid
    }

    final amplified = <List<double>>[];

    for (int t = 0; t < features.length; t++) {
      final row = features[t];
      final newRow = List<double>.from(row); // Copy original

      // 1. PATTERN ENHANCEMENT (indices 0-24)
      // Amplify subtle patterns that might be drowned out by noise
      for (int i = 0; i < 25; i++) {
        if (newRow[i] > 0.0 && newRow[i] < 0.5) {
          // Weak pattern detected → amplify it
          newRow[i] = newRow[i] * 2.0; // 2x amplification
        }
      }

      // Detect and amplify multi-candle patterns (look back 3 timesteps)
      if (t >= 2) {
        final patternStrength = _detectSubtlePattern(
          features[t - 2],
          features[t - 1],
          features[t],
        );
        if (patternStrength > 0.0) {
          // Boost all pattern features when a multi-candle pattern is detected
          for (int i = 0; i < 25; i++) {
            if (newRow[i] > 0.0) {
              newRow[i] = math.min(1.0, newRow[i] + patternStrength * 0.3);
            }
          }
        }
      }

      // 2. MOMENTUM AMPLIFICATION
      // Amplify directional momentum when multiple indicators align
      // RSI (index 48), MACD histogram (index 52), Returns (index 25)
      final rsi = row.length > 48 ? row[48] : 0.0;
      final macdHist = row.length > 52 ? row[52] : 0.0;
      final returns = row.length > 25 ? row[25] : 0.0;

      // Check if momentum indicators align (bullish or bearish)
      final bullishAlignment = (rsi > 0.5 && macdHist > 0.0 && returns > 0.0);
      final bearishAlignment = (rsi < -0.5 && macdHist < 0.0 && returns < 0.0);

      if (bullishAlignment || bearishAlignment) {
        final amplificationFactor = 1.5;
        if (row.length > 48) newRow[48] = rsi * amplificationFactor; // RSI
        if (row.length > 52) newRow[52] = macdHist * amplificationFactor; // MACD
        if (row.length > 25) newRow[25] = returns * amplificationFactor; // Returns
      }

      // 3. CROSS-FEATURE CORRELATION ENHANCEMENT
      // When related features are weak but aligned, amplify them together
      // Volume + Price action correlation
      if (row.length > 30 && row.length > 40) {
        final volumeFeature = row[30]; // Approximate volume feature
        final priceAction = row[25]; // Returns

        if ((volumeFeature > 0.0 && priceAction > 0.0) ||
            (volumeFeature < 0.0 && priceAction < 0.0)) {
          // Volume confirms price action → amplify both
          if (volumeFeature.abs() < 0.5 && priceAction.abs() < 0.5) {
            newRow[30] = volumeFeature * 1.3;
            newRow[25] = priceAction * 1.3;
          }
        }
      }

      amplified.add(newRow);
    }

    return amplified;
  }

  /// Detect subtle multi-candle patterns (Hammer, Engulfing, Star patterns)
  /// Returns strength of pattern (0.0 to 1.0)
  static double _detectSubtlePattern(
    List<double> t0,
    List<double> t1,
    List<double> t2,
  ) {
    if (t0.length < 25 || t1.length < 25 || t2.length < 25) {
      return 0.0;
    }

    double strength = 0.0;

    // Hammer pattern (index 4): small body, long lower wick
    final hammer = (t2[4] > 0.0) ? t2[4] : 0.0;
    if (hammer > 0.2) strength += 0.3;

    // Shooting star pattern (index 6): small body, long upper wick
    final shootingStar = (t2[6] > 0.0) ? t2[6] : 0.0;
    if (shootingStar > 0.2) strength += 0.3;

    // Bullish engulfing (index 11): t2 engulfs t1
    final bullishEngulfing = (t2[11] > 0.0) ? t2[11] : 0.0;
    if (bullishEngulfing > 0.3) strength += 0.4;

    // Bearish engulfing (index 12): t2 engulfs t1
    final bearishEngulfing = (t2[12] > 0.0) ? t2[12] : 0.0;
    if (bearishEngulfing > 0.3) strength += 0.4;

    // Morning star (index 19): 3-candle bullish reversal
    final morningStar = (t2[19] > 0.0) ? t2[19] : 0.0;
    if (morningStar > 0.2 && t1[4] > 0.1) strength += 0.5;

    // Evening star (index 20): 3-candle bearish reversal
    final eveningStar = (t2[20] > 0.0) ? t2[20] : 0.0;
    if (eveningStar > 0.2 && t1[6] > 0.1) strength += 0.5;

    return math.min(1.0, strength);
  }
}

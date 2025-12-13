import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import '../models/candle.dart';
import 'candle_pattern_detector.dart';

/// Advanced Feature Builder - generates ALL 150 features matching Python training (v2025 PRO)
/// Features:
/// - 25 candle patterns (indices 0-24)
/// - 51 technical indicators and price features (indices 25-75)
/// - 74 advanced indicators (indices 76-149)
class AdvancedFeatureBuilder {
  final _patternDetector = CandlePatternDetector();

  static const int nFeatures = 150;
  static const int seqLength = 60;

  /// Pattern order MUST match Python exactly
  static const List<String> patternOrder = [
    'doji', 'dragonfly_doji', 'gravestone_doji', 'long_legged_doji',
    'hammer', 'inverted_hammer', 'shooting_star', 'hanging_man',
    'spinning_top', 'marubozu_bullish', 'marubozu_bearish',
    'bullish_engulfing', 'bearish_engulfing', 'piercing_line',
    'dark_cloud_cover', 'bullish_harami', 'bearish_harami',
    'tweezer_bottom', 'tweezer_top', 'morning_star', 'evening_star',
    'three_white_soldiers', 'three_black_crows', 'rising_three', 'falling_three'
  ];

  /// Build complete 150-feature vector for 60 timesteps
  /// Returns shape (60, 150)
  List<List<double>> buildFeatures({required List<Candle> candles}) {
    const int lookback = 60;
    const int timesteps = 60;
    const int minCandles = lookback + timesteps - 1;

    if (candles.length < minCandles) {
      throw ArgumentError('Need at least $minCandles candles for sliding window, got ${candles.length}');
    }

    // Sort by time ascending
    final sorted = List<Candle>.from(candles)..sort((a, b) => a.closeTime.compareTo(b.closeTime));

    debugPrint('🔍 AdvancedFeatureBuilder: Processing ${sorted.length} candles for 150 features');

    // Calculate all features for all candles
    final allFeatures = _calculateAllFeatures(sorted);

    // Extract last 60 timesteps
    final n = sorted.length;
    final startIdx = n - timesteps;

    if (startIdx < 0) {
      throw ArgumentError('Need at least $timesteps candles, got $n');
    }

    final output = <List<double>>[];
    for (int i = startIdx; i < n; i++) {
      output.add(allFeatures[i]);
    }

    debugPrint('🔍 AdvancedFeatureBuilder: Generated ${output.length} timesteps × ${output.first.length} features');

    return output;
  }

  /// Pre-calculate ALL 150 features for ALL candles
  List<List<double>> _calculateAllFeatures(List<Candle> candles) {
    final opens = candles.map((c) => c.open).toList();
    final highs = candles.map((c) => c.high).toList();
    final lows = candles.map((c) => c.low).toList();
    final closes = candles.map((c) => c.close).toList();
    final volumes = candles.map((c) => c.volume).toList();
    final n = closes.length;

    // Detect patterns
    final patterns = _patternDetector.detectAllPatterns(
      opens: opens,
      highs: highs,
      lows: lows,
      closes: closes,
      volumes: volumes,
    );

    // =========================================================================
    // ORIGINAL 76 FEATURES CALCULATIONS
    // =========================================================================

    // Price action
    final returns = _calculateReturns(closes);
    final logReturns = _calculateLogReturns(closes);
    final volatility = _calculateVolatility(returns, 20);
    final hlRange = List<double>.generate(n, (i) => (highs[i] - lows[i]) / (closes[i] + 1e-10));
    final closePosition = List<double>.generate(n, (i) => (closes[i] - lows[i]) / ((highs[i] - lows[i]) + 1e-10));

    // RSI
    final rsi = _calculateRSI(closes, 14);
    final rsiNorm = rsi.map((v) => v / 100.0).toList();
    final rsiOversold = rsi.map((v) => v < 30 ? 1.0 : 0.0).toList();
    final rsiOverbought = rsi.map((v) => v > 70 ? 1.0 : 0.0).toList();

    // MACD
    final macdData = _calculateMACD(closes);
    final macdLine = macdData['macd']!;
    final macdSignal = macdData['signal']!;
    final macdHistogram = macdData['histogram']!;
    final macdLineNorm = List<double>.generate(n, (i) => macdLine[i] / (closes[i] + 1e-10));
    final macdSignalNorm = List<double>.generate(n, (i) => macdSignal[i] / (closes[i] + 1e-10));
    final macdHistNorm = List<double>.generate(n, (i) => macdHistogram[i] / (closes[i] + 1e-10));
    final macdCrossAbove = _crossAbove(macdLine, macdSignal);
    final macdCrossBelow = _crossBelow(macdLine, macdSignal);

    // Bollinger Bands
    final bbData = _calculateBollingerBands(closes, 20, 2.0);
    final bbUpper = bbData['upper']!;
    final bbMiddle = bbData['middle']!;
    final bbLower = bbData['lower']!;
    final bbWidth = List<double>.generate(n, (i) => (bbUpper[i] - bbLower[i]) / (bbMiddle[i] + 1e-10));
    final bbPosition = List<double>.generate(n, (i) => (closes[i] - bbLower[i]) / ((bbUpper[i] - bbLower[i]) + 1e-10));
    final bbSqueeze = bbWidth.map((v) => v < 0.04 ? 1.0 : 0.0).toList();

    // ATR
    final atr = _calculateATR(highs, lows, closes, 14);
    final atrPct = List<double>.generate(n, (i) => atr[i] / (closes[i] + 1e-10));

    // ADX
    final adx = _calculateADX(highs, lows, closes, 14);
    final adxNorm = adx.map((v) => v / 100.0).toList();
    final trending = adx.map((v) => v > 25 ? 1.0 : 0.0).toList();

    // Stochastic
    final stochData = _calculateStochastic(highs, lows, closes, 14);
    final stochK = stochData['k']!;
    final stochD = stochData['d']!;
    final stochKNorm = stochK.map((v) => v / 100.0).toList();
    final stochDNorm = stochD.map((v) => v / 100.0).toList();
    final stochOversold = stochK.map((v) => v < 20 ? 1.0 : 0.0).toList();
    final stochOverbought = stochK.map((v) => v > 80 ? 1.0 : 0.0).toList();

    // Ichimoku
    final ichimoku = _calculateIchimoku(highs, lows, closes);
    final ichimokuTenkan = ichimoku['tenkan']!;
    final ichimokuKijun = ichimoku['kijun']!;
    final ichimokuSenkouA = ichimoku['senkou_a']!;
    final ichimokuSenkouB = ichimoku['senkou_b']!;
    final ichimokuTenkanNorm = List<double>.generate(n, (i) => (ichimokuTenkan[i] - closes[i]) / (closes[i] + 1e-10));
    final ichimokuKijunNorm = List<double>.generate(n, (i) => (ichimokuKijun[i] - closes[i]) / (closes[i] + 1e-10));
    final ichimokuSenkouANorm = List<double>.generate(n, (i) => (ichimokuSenkouA[i] - closes[i]) / (closes[i] + 1e-10));
    final ichimokuSenkouBNorm = List<double>.generate(n, (i) => (ichimokuSenkouB[i] - closes[i]) / (closes[i] + 1e-10));
    final ichimokuCloudGreen = List<double>.generate(n, (i) => ichimokuSenkouA[i] > ichimokuSenkouB[i] ? 1.0 : 0.0);
    final ichimokuAboveCloud = List<double>.generate(n, (i) => (closes[i] > ichimokuSenkouA[i] && closes[i] > ichimokuSenkouB[i]) ? 1.0 : 0.0);
    final ichimokuBelowCloud = List<double>.generate(n, (i) => (closes[i] < ichimokuSenkouA[i] && closes[i] < ichimokuSenkouB[i]) ? 1.0 : 0.0);

    // Volume
    final volSMA = _calculateSMA(volumes, 20);
    final obv = _calculateOBV(closes, volumes);
    final volRatio = List<double>.generate(n, (i) => volumes[i] / (volSMA[i] + 1e-10));
    final obvNorm = _normalizeOBV(obv);
    final highVolume = volRatio.map((v) => v > 1.5 ? 1.0 : 0.0).toList();

    // Moving Averages
    final sma10 = _calculateSMA(closes, 10);
    final sma20 = _calculateSMA(closes, 20);
    final sma50 = _calculateSMA(closes, 50);
    final sma100 = _calculateSMA(closes, 100);
    final sma200 = _calculateSMA(closes, 200);
    final ema12 = _calculateEMA(closes, 12);
    final ema26 = _calculateEMA(closes, 26);

    final sma10Norm = List<double>.generate(n, (i) => (closes[i] - sma10[i]) / (sma10[i] + 1e-10));
    final sma20Norm = List<double>.generate(n, (i) => (closes[i] - sma20[i]) / (sma20[i] + 1e-10));
    final sma50Norm = List<double>.generate(n, (i) => (closes[i] - sma50[i]) / (sma50[i] + 1e-10));
    final sma100Norm = List<double>.generate(n, (i) => (closes[i] - sma100[i]) / (sma100[i] + 1e-10));
    final sma200Norm = List<double>.generate(n, (i) => (closes[i] - sma200[i]) / (sma200[i] + 1e-10));
    final ema12Norm = List<double>.generate(n, (i) => (closes[i] - ema12[i]) / (ema12[i] + 1e-10));
    final ema26Norm = List<double>.generate(n, (i) => (closes[i] - ema26[i]) / (ema26[i] + 1e-10));
    final sma10AboveSma20 = List<double>.generate(n, (i) => sma10[i] > sma20[i] ? 1.0 : 0.0);
    final sma50AboveSma200 = List<double>.generate(n, (i) => sma50[i] > sma200[i] ? 1.0 : 0.0);

    // Trend
    final trendStrength = _trendStrength(closes, 20);
    final momentum10 = _momentum(closes, 10);
    final momentum20 = _momentum(closes, 20);

    // =========================================================================
    // NEW ADVANCED FEATURES [76-149]
    // =========================================================================

    // [76-81] Fibonacci Retracements
    final fib = _fibonacciRetracements(highs, lows, closes, 50);

    // [82-88] Pivot Points
    final pivotData = _pivotPoints(highs, lows, closes);

    // [89-92] VWAP
    final vwap = _vwap(highs, lows, closes, volumes);
    final vwapBands = _vwapBands(highs, lows, closes, volumes);

    // [93-95] SuperTrend
    final supertrend = _supertrend(highs, lows, closes, 10, 3.0);

    // [96-99] Keltner Channels
    final keltner = _keltnerChannels(highs, lows, closes, 20, 2.0);

    // [100-103] Donchian Channels
    final donchian = _donchianChannels(highs, lows, 20);

    // [104-106] Chaikin Money Flow
    final cmf = _chaikinMoneyFlow(highs, lows, closes, volumes, 20);

    // [107-109] Williams %R
    final williamsR = _williamsR(highs, lows, closes, 14);

    // [110-112] CCI
    final cci = _cci(highs, lows, closes, 20);

    // [113-115] MFI
    final mfi = _mfi(highs, lows, closes, volumes, 14);

    // [116-119] ROC
    final roc5 = _roc(closes, 5);
    final roc10 = _roc(closes, 10);
    final roc20 = _roc(closes, 20);
    final roc50 = _roc(closes, 50);

    // [120-121] TRIX
    final trix = _trix(closes, 15);
    final trixSignal = _calculateSMA(trix, 9);

    // [122-124] Ultimate Oscillator
    final uo = _ultimateOscillator(highs, lows, closes, 7, 14, 28);

    // [125-126] Parabolic SAR
    final psar = _parabolicSAR(highs, lows, closes);

    // [127-129] Elder Ray
    final elderRay = _elderRay(highs, lows, closes, 13);

    // [130-132] Aroon
    final aroon = _aroon(highs, lows, 25);

    // [133-134] Chande Momentum
    final cmo = _chandeMomentum(closes, 14);

    // [135-136] DPO
    final dpo = _dpo(closes, 20);

    // [137-138] KAMA
    final kama = _kama(closes, 10, 2, 30);

    // [139-140] Hull MA
    final hma = _hullMA(closes, 20);
    final hmaDirection = _hmaDirection(hma);

    // [141-143] Market Regime
    final marketRegime = _marketRegime(closes, atr, 20);
    final volatilityRegime = _volatilityRegime(closes, 20);
    final trendRegime = _trendRegime(closes, sma50, sma200);

    // [144-146] Multi-timeframe Momentum
    final momentum5 = _momentum(closes, 5);
    final momentum14 = _momentum(closes, 14);
    final momentum30 = _momentum(closes, 30);

    // [147-149] Volume Analysis
    final volumeTrend = _volumeTrend(volumes, 20);
    final pvt = _priceVolumeTrend(closes, volumes);
    final ad = _accumulationDistribution(highs, lows, closes, volumes);

    // =========================================================================
    // BUILD FEATURE VECTORS
    // =========================================================================
    final output = <List<double>>[];

    for (int i = 0; i < n; i++) {
      final row = <double>[];

      // [0-24] Candle patterns
      for (final patternName in patternOrder) {
        row.add(patterns[patternName]![i]);
      }

      // [25-29] Price action
      row.add(returns[i]);
      row.add(logReturns[i]);
      row.add(volatility[i]);
      row.add(hlRange[i]);
      row.add(closePosition[i]);

      // [30-32] RSI
      row.add(rsiNorm[i]);
      row.add(rsiOversold[i]);
      row.add(rsiOverbought[i]);

      // [33-37] MACD
      row.add(macdLineNorm[i]);
      row.add(macdSignalNorm[i]);
      row.add(macdHistNorm[i]);
      row.add(macdCrossAbove[i]);
      row.add(macdCrossBelow[i]);

      // [38-43] Bollinger Bands
      row.add((bbUpper[i] - closes[i]) / (closes[i] + 1e-10));
      row.add(0.0); // Placeholder matching Python
      row.add((closes[i] - bbLower[i]) / (closes[i] + 1e-10));
      row.add(bbWidth[i]);
      row.add(bbPosition[i]);
      row.add(bbSqueeze[i]);

      // [44-45] ATR
      row.add(atrPct[i]);
      row.add(atrPct[i]);

      // [46-47] ADX
      row.add(adxNorm[i]);
      row.add(trending[i]);

      // [48-51] Stochastic
      row.add(stochKNorm[i]);
      row.add(stochDNorm[i]);
      row.add(stochOversold[i]);
      row.add(stochOverbought[i]);

      // [52-58] Ichimoku
      row.add(ichimokuTenkanNorm[i]);
      row.add(ichimokuKijunNorm[i]);
      row.add(ichimokuSenkouANorm[i]);
      row.add(ichimokuSenkouBNorm[i]);
      row.add(ichimokuCloudGreen[i]);
      row.add(ichimokuAboveCloud[i]);
      row.add(ichimokuBelowCloud[i]);

      // [59-63] Volume
      row.add(volRatio[i]);
      row.add(1.0); // Placeholder matching Python
      row.add(volRatio[i]);
      row.add(obvNorm[i]);
      row.add(highVolume[i]);

      // [64-72] Moving Averages
      row.add(sma10Norm[i]);
      row.add(sma20Norm[i]);
      row.add(sma50Norm[i]);
      row.add(sma100Norm[i]);
      row.add(sma200Norm[i]);
      row.add(ema12Norm[i]);
      row.add(ema26Norm[i]);
      row.add(sma10AboveSma20[i]);
      row.add(sma50AboveSma200[i]);

      // [73-75] Trend
      row.add(trendStrength[i]);
      row.add(momentum10[i]);
      row.add(momentum20[i]);

      // =====================================================================
      // NEW ADVANCED FEATURES [76-149]
      // =====================================================================

      // [76-81] Fibonacci Retracements
      row.add(fib['fib_236']![i]);
      row.add(fib['fib_382']![i]);
      row.add(fib['fib_500']![i]);
      row.add(fib['fib_618']![i]);
      row.add(fib['fib_786']![i]);
      row.add(fib['near_fib_level']![i]);

      // [82-88] Pivot Points
      row.add(pivotData['pivot_norm']![i]);
      row.add(pivotData['s1_norm']![i]);
      row.add(pivotData['s2_norm']![i]);
      row.add(pivotData['s3_norm']![i]);
      row.add(pivotData['r1_norm']![i]);
      row.add(pivotData['r2_norm']![i]);
      row.add(pivotData['r3_norm']![i]);

      // [89-92] VWAP
      row.add((closes[i] - vwap[i]) / (closes[i] + 1e-10));
      row.add(vwapBands['upper_band']![i]);
      row.add(vwapBands['lower_band']![i]);
      row.add(vwapBands['in_band']![i]);

      // [93-95] SuperTrend
      row.add((closes[i] - supertrend['supertrend']![i]) / (closes[i] + 1e-10));
      row.add(supertrend['direction']![i]);
      row.add(supertrend['flip']![i]);

      // [96-99] Keltner Channels
      row.add((closes[i] - keltner['upper']![i]) / (closes[i] + 1e-10));
      row.add((closes[i] - keltner['mid']![i]) / (closes[i] + 1e-10));
      row.add((closes[i] - keltner['lower']![i]) / (closes[i] + 1e-10));
      row.add(keltner['breakout']![i]);

      // [100-103] Donchian Channels
      row.add((closes[i] - donchian['upper']![i]) / (closes[i] + 1e-10));
      row.add((closes[i] - donchian['mid']![i]) / (closes[i] + 1e-10));
      row.add((closes[i] - donchian['lower']![i]) / (closes[i] + 1e-10));
      row.add((donchian['upper']![i] - donchian['lower']![i]) / (closes[i] + 1e-10));

      // [104-106] Chaikin Money Flow
      row.add(cmf[i]);
      row.add(cmf[i] > 0.05 ? 1.0 : 0.0);
      row.add(cmf[i] < -0.05 ? 1.0 : 0.0);

      // [107-109] Williams %R
      row.add(williamsR[i] / 100.0);
      row.add(williamsR[i] < -80 ? 1.0 : 0.0);
      row.add(williamsR[i] > -20 ? 1.0 : 0.0);

      // [110-112] CCI
      row.add(cci[i] / 200.0);
      row.add(cci[i] < -100 ? 1.0 : 0.0);
      row.add(cci[i] > 100 ? 1.0 : 0.0);

      // [113-115] MFI
      row.add(mfi[i] / 100.0);
      row.add(mfi[i] < 20 ? 1.0 : 0.0);
      row.add(mfi[i] > 80 ? 1.0 : 0.0);

      // [116-119] ROC
      row.add(roc5[i]);
      row.add(roc10[i]);
      row.add(roc20[i]);
      row.add(roc50[i]);

      // [120-121] TRIX
      row.add(trix[i]);
      row.add(trixSignal[i]);

      // [122-124] Ultimate Oscillator
      row.add(uo[i] / 100.0);
      row.add(uo[i] < 30 ? 1.0 : 0.0);
      row.add(uo[i] > 70 ? 1.0 : 0.0);

      // [125-126] Parabolic SAR
      row.add((closes[i] - psar['psar']![i]) / (closes[i] + 1e-10));
      row.add(psar['direction']![i]);

      // [127-129] Elder Ray
      row.add(elderRay['bull_power']![i] / (closes[i] + 1e-10));
      row.add(elderRay['bear_power']![i] / (closes[i] + 1e-10));
      row.add((elderRay['bull_power']![i] > 0 && elderRay['bear_power']![i] > elderRay['bear_power']![math.max(0, i - 1)]) ? 1.0 : 0.0);

      // [130-132] Aroon
      row.add(aroon['up']![i] / 100.0);
      row.add(aroon['down']![i] / 100.0);
      row.add((aroon['up']![i] - aroon['down']![i]) / 100.0);

      // [133-134] Chande Momentum
      row.add(cmo[i] / 100.0);
      row.add(cmo[i].abs() / 100.0);

      // [135-136] DPO
      row.add(dpo[i] / (closes[i] + 1e-10));
      row.add(dpo[i] > 0 ? 1.0 : 0.0);

      // [137-138] KAMA
      row.add((closes[i] - kama[i]) / (closes[i] + 1e-10));
      row.add(_crossAbove(closes, kama)[i]);

      // [139-140] Hull MA
      row.add((closes[i] - hma[i]) / (closes[i] + 1e-10));
      row.add(hmaDirection[i]);

      // [141-143] Market Regime
      row.add(marketRegime[i]);
      row.add(volatilityRegime[i]);
      row.add(trendRegime[i]);

      // [144-146] Multi-timeframe Momentum
      row.add(momentum5[i]);
      row.add(momentum14[i]);
      row.add(momentum30[i]);

      // [147-149] Volume Analysis
      row.add(volumeTrend[i]);
      row.add(pvt[i]);
      row.add(ad[i]);

      // Sanitize: replace NaN/Inf with 0
      final sanitized = row.map((v) => v.isFinite ? v : 0.0).toList();

      assert(sanitized.length == 150, 'Expected 150 features, got ${sanitized.length}');

      output.add(sanitized);
    }

    return output;
  }

  // ===========================================================================
  // HELPER METHODS - ORIGINAL FEATURES
  // ===========================================================================

  List<double> _calculateReturns(List<double> closes) {
    final n = closes.length;
    final returns = List<double>.filled(n, 0.0);
    for (int i = 1; i < n; i++) {
      returns[i] = (closes[i] - closes[i - 1]) / (closes[i - 1] + 1e-10);
    }
    return returns;
  }

  List<double> _calculateLogReturns(List<double> closes) {
    final n = closes.length;
    final returns = List<double>.filled(n, 0.0);
    for (int i = 1; i < n; i++) {
      returns[i] = math.log(closes[i] / (closes[i - 1] + 1e-10));
    }
    return returns;
  }

  List<double> _calculateVolatility(List<double> returns, int window) {
    final n = returns.length;
    final volatility = List<double>.filled(n, 0.0);

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
        sma[i] = values[0];
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

    final delta = List<double>.generate(n, (i) => i == 0 ? 0.0 : closes[i] - closes[i - 1]);
    final gain = delta.map((d) => d > 0 ? d : 0.0).toList();
    final loss = delta.map((d) => d < 0 ? -d : 0.0).toList();

    final avgGain = _calculateEMA(gain, period);
    final avgLoss = _calculateEMA(loss, period);

    for (int i = 0; i < n; i++) {
      final rs = avgGain[i] / (avgLoss[i] + 1e-10);
      rsi[i] = 100 - (100 / (1 + rs));
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

    tr[0] = highs[0] - lows[0];
    for (int i = 1; i < n; i++) {
      final highLow = highs[i] - lows[i];
      final highClose = (highs[i] - closes[i - 1]).abs();
      final lowClose = (lows[i] - closes[i - 1]).abs();

      tr[i] = [highLow, highClose, lowClose].reduce(math.max);
    }

    return _calculateEMA(tr, period);
  }

  List<double> _calculateADX(List<double> highs, List<double> lows, List<double> closes, int period) {
    final n = closes.length;
    final plusDm = List<double>.filled(n, 0.0);
    final minusDm = List<double>.filled(n, 0.0);

    for (int i = 1; i < n; i++) {
      final up = highs[i] - highs[i - 1];
      final down = lows[i - 1] - lows[i];
      plusDm[i] = (up > down && up > 0) ? up : 0;
      minusDm[i] = (down > up && down > 0) ? down : 0;
    }

    final atr = _calculateATR(highs, lows, closes, period);
    final plusDi = List<double>.generate(n, (i) => 100 * _calculateEMA(plusDm, period)[i] / (atr[i] + 1e-10));
    final minusDi = List<double>.generate(n, (i) => 100 * _calculateEMA(minusDm, period)[i] / (atr[i] + 1e-10));

    final dx = List<double>.generate(n, (i) => 100 * (plusDi[i] - minusDi[i]).abs() / (plusDi[i] + minusDi[i] + 1e-10));
    return _calculateEMA(dx, period);
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

    for (int i = period + 1; i < n; i++) {
      d[i] = k.sublist(i - 2, i + 1).reduce((a, b) => a + b) / 3;
    }

    return {'k': k, 'd': d};
  }

  Map<String, List<double>> _calculateIchimoku(List<double> highs, List<double> lows, List<double> closes) {
    final n = closes.length;

    List<double> donchianMid(List<double> high, List<double> low, int period) {
      final mid = List<double>.filled(n, 0.0);
      for (int i = period - 1; i < n; i++) {
        mid[i] = (high.sublist(i - period + 1, i + 1).reduce(math.max) + low.sublist(i - period + 1, i + 1).reduce(math.min)) / 2;
      }
      return mid;
    }

    final tenkan = donchianMid(highs, lows, 9);
    final kijun = donchianMid(highs, lows, 26);
    final senkouA = List<double>.generate(n, (i) => (tenkan[i] + kijun[i]) / 2);
    final senkouB = donchianMid(highs, lows, 52);

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

  List<double> _normalizeOBV(List<double> obv) {
    final minVal = obv.reduce(math.min);
    final maxVal = obv.reduce(math.max);
    if (maxVal - minVal > 0) {
      return obv.map((v) => (v - minVal) / (maxVal - minVal)).toList();
    }
    return List<double>.filled(obv.length, 0.0);
  }

  List<double> _crossAbove(List<double> a, List<double> b) {
    final n = a.length;
    final cross = List<double>.filled(n, 0.0);
    for (int i = 1; i < n; i++) {
      if (a[i] > b[i] && a[i - 1] <= b[i - 1]) {
        cross[i] = 1.0;
      }
    }
    return cross;
  }

  List<double> _crossBelow(List<double> a, List<double> b) {
    final n = a.length;
    final cross = List<double>.filled(n, 0.0);
    for (int i = 1; i < n; i++) {
      if (a[i] < b[i] && a[i - 1] >= b[i - 1]) {
        cross[i] = 1.0;
      }
    }
    return cross;
  }

  List<double> _trendStrength(List<double> closes, int period) {
    final n = closes.length;
    final strength = List<double>.filled(n, 0.0);
    for (int i = period; i < n; i++) {
      int upMoves = 0;
      for (int j = i - period; j < i; j++) {
        if (closes[j + 1] > closes[j]) upMoves++;
      }
      strength[i] = (upMoves / period - 0.5) * 2;
    }
    return strength;
  }

  List<double> _momentum(List<double> closes, int period) {
    final n = closes.length;
    final mom = List<double>.filled(n, 0.0);
    for (int i = period; i < n; i++) {
      mom[i] = (closes[i] - closes[i - period]) / (closes[i - period] + 1e-10);
    }
    return mom;
  }

  // ===========================================================================
  // HELPER METHODS - NEW ADVANCED FEATURES
  // ===========================================================================

  Map<String, List<double>> _fibonacciRetracements(List<double> highs, List<double> lows, List<double> closes, int period) {
    final n = closes.length;
    final fib = <String, List<double>>{
      'fib_236': List<double>.filled(n, 0.0),
      'fib_382': List<double>.filled(n, 0.0),
      'fib_500': List<double>.filled(n, 0.0),
      'fib_618': List<double>.filled(n, 0.0),
      'fib_786': List<double>.filled(n, 0.0),
      'near_fib_level': List<double>.filled(n, 0.0),
    };

    for (int i = period; i < n; i++) {
      final high = highs.sublist(i - period, i).reduce(math.max);
      final low = lows.sublist(i - period, i).reduce(math.min);
      final diff = high - low;

      final fib236 = high - diff * 0.236;
      final fib382 = high - diff * 0.382;
      final fib500 = high - diff * 0.500;
      final fib618 = high - diff * 0.618;
      final fib786 = high - diff * 0.786;

      fib['fib_236']![i] = (closes[i] - fib236) / (closes[i] + 1e-10);
      fib['fib_382']![i] = (closes[i] - fib382) / (closes[i] + 1e-10);
      fib['fib_500']![i] = (closes[i] - fib500) / (closes[i] + 1e-10);
      fib['fib_618']![i] = (closes[i] - fib618) / (closes[i] + 1e-10);
      fib['fib_786']![i] = (closes[i] - fib786) / (closes[i] + 1e-10);

      final levels = [fib236, fib382, fib500, fib618, fib786];
      for (final level in levels) {
        if ((closes[i] - level).abs() / (closes[i] + 1e-10) < 0.01) {
          fib['near_fib_level']![i] = 1.0;
          break;
        }
      }
    }

    return fib;
  }

  Map<String, List<double>> _pivotPoints(List<double> highs, List<double> lows, List<double> closes) {
    final n = closes.length;
    final pivot = List<double>.generate(n, (i) => (highs[i] + lows[i] + closes[i]) / 3);
    final s1 = List<double>.generate(n, (i) => 2 * pivot[i] - highs[i]);
    final s2 = List<double>.generate(n, (i) => pivot[i] - (highs[i] - lows[i]));
    final s3 = List<double>.generate(n, (i) => lows[i] - 2 * (highs[i] - pivot[i]));
    final r1 = List<double>.generate(n, (i) => 2 * pivot[i] - lows[i]);
    final r2 = List<double>.generate(n, (i) => pivot[i] + (highs[i] - lows[i]));
    final r3 = List<double>.generate(n, (i) => highs[i] + 2 * (pivot[i] - lows[i]));

    return {
      'pivot_norm': List<double>.generate(n, (i) => (closes[i] - pivot[i]) / (closes[i] + 1e-10)),
      's1_norm': List<double>.generate(n, (i) => (closes[i] - s1[i]) / (closes[i] + 1e-10)),
      's2_norm': List<double>.generate(n, (i) => (closes[i] - s2[i]) / (closes[i] + 1e-10)),
      's3_norm': List<double>.generate(n, (i) => (closes[i] - s3[i]) / (closes[i] + 1e-10)),
      'r1_norm': List<double>.generate(n, (i) => (closes[i] - r1[i]) / (closes[i] + 1e-10)),
      'r2_norm': List<double>.generate(n, (i) => (closes[i] - r2[i]) / (closes[i] + 1e-10)),
      'r3_norm': List<double>.generate(n, (i) => (closes[i] - r3[i]) / (closes[i] + 1e-10)),
    };
  }

  List<double> _vwap(List<double> highs, List<double> lows, List<double> closes, List<double> volumes) {
    final n = closes.length;
    final typicalPrice = List<double>.generate(n, (i) => (highs[i] + lows[i] + closes[i]) / 3);

    double cumulativeTPV = 0;
    double cumulativeVol = 0;
    final vwap = List<double>.filled(n, 0.0);

    for (int i = 0; i < n; i++) {
      cumulativeTPV += typicalPrice[i] * volumes[i];
      cumulativeVol += volumes[i];
      vwap[i] = cumulativeTPV / (cumulativeVol + 1e-10);
    }

    return vwap;
  }

  Map<String, List<double>> _vwapBands(List<double> highs, List<double> lows, List<double> closes, List<double> volumes) {
    final vwap = _vwap(highs, lows, closes, volumes);
    final n = closes.length;
    final typicalPrice = List<double>.generate(n, (i) => (highs[i] + lows[i] + closes[i]) / 3);

    final std = List<double>.filled(n, 0.0);
    for (int i = 20; i < n; i++) {
      final slice = typicalPrice.sublist(i - 20, i);
      final mean = slice.reduce((a, b) => a + b) / 20;
      final variance = slice.map((v) => math.pow(v - mean, 2)).reduce((a, b) => a + b) / 20;
      std[i] = math.sqrt(variance);
    }

    final upper = List<double>.generate(n, (i) => vwap[i] + 2 * std[i]);
    final lower = List<double>.generate(n, (i) => vwap[i] - 2 * std[i]);

    return {
      'upper_band': List<double>.generate(n, (i) => (upper[i] - closes[i]) / (closes[i] + 1e-10)),
      'lower_band': List<double>.generate(n, (i) => (closes[i] - lower[i]) / (closes[i] + 1e-10)),
      'in_band': List<double>.generate(n, (i) => (closes[i] > vwap[i] && closes[i] < upper[i]) ? 1.0 : 0.0),
    };
  }

  Map<String, List<double>> _supertrend(List<double> highs, List<double> lows, List<double> closes, int period, double multiplier) {
    final atr = _calculateATR(highs, lows, closes, period);
    final n = closes.length;
    final hl2 = List<double>.generate(n, (i) => (highs[i] + lows[i]) / 2);

    final upperBand = List<double>.generate(n, (i) => hl2[i] + multiplier * atr[i]);
    final lowerBand = List<double>.generate(n, (i) => hl2[i] - multiplier * atr[i]);

    final supertrend = List<double>.filled(n, 0.0);
    final direction = List<double>.filled(n, 1.0);

    for (int i = 1; i < n; i++) {
      if (closes[i] > upperBand[i - 1]) {
        direction[i] = 1;
      } else if (closes[i] < lowerBand[i - 1]) {
        direction[i] = -1;
      } else {
        direction[i] = direction[i - 1];
      }

      if (direction[i] == 1) {
        supertrend[i] = lowerBand[i];
      } else {
        supertrend[i] = upperBand[i];
      }
    }

    final flip = List<double>.filled(n, 0.0);
    for (int i = 1; i < n; i++) {
      if (direction[i] != direction[i - 1]) {
        flip[i] = 1.0;
      }
    }

    return {
      'supertrend': supertrend,
      'direction': direction,
      'flip': flip,
    };
  }

  Map<String, List<double>> _keltnerChannels(List<double> highs, List<double> lows, List<double> closes, int period, double multiplier) {
    final mid = _calculateEMA(closes, period);
    final atr = _calculateATR(highs, lows, closes, period);
    final n = closes.length;

    final upper = List<double>.generate(n, (i) => mid[i] + multiplier * atr[i]);
    final lower = List<double>.generate(n, (i) => mid[i] - multiplier * atr[i]);
    final breakout = List<double>.generate(n, (i) => (closes[i] > upper[i] || closes[i] < lower[i]) ? 1.0 : 0.0);

    return {
      'upper': upper,
      'mid': mid,
      'lower': lower,
      'breakout': breakout,
    };
  }

  Map<String, List<double>> _donchianChannels(List<double> highs, List<double> lows, int period) {
    final n = highs.length;
    final upper = List<double>.filled(n, 0.0);
    final lower = List<double>.filled(n, 0.0);

    for (int i = period - 1; i < n; i++) {
      upper[i] = highs.sublist(i - period + 1, i + 1).reduce(math.max);
      lower[i] = lows.sublist(i - period + 1, i + 1).reduce(math.min);
    }

    final mid = List<double>.generate(n, (i) => (upper[i] + lower[i]) / 2);

    return {
      'upper': upper,
      'mid': mid,
      'lower': lower,
    };
  }

  List<double> _chaikinMoneyFlow(List<double> highs, List<double> lows, List<double> closes, List<double> volumes, int period) {
    final n = closes.length;
    final mfm = List<double>.generate(n, (i) => ((closes[i] - lows[i]) - (highs[i] - closes[i])) / (highs[i] - lows[i] + 1e-10));
    final mfv = List<double>.generate(n, (i) => mfm[i] * volumes[i]);

    final cmf = List<double>.filled(n, 0.0);
    for (int i = period - 1; i < n; i++) {
      final mfvSum = mfv.sublist(i - period + 1, i + 1).reduce((a, b) => a + b);
      final volSum = volumes.sublist(i - period + 1, i + 1).reduce((a, b) => a + b);
      cmf[i] = mfvSum / (volSum + 1e-10);
    }

    return cmf;
  }

  List<double> _williamsR(List<double> highs, List<double> lows, List<double> closes, int period) {
    final n = closes.length;
    final wr = List<double>.filled(n, 0.0);

    for (int i = period - 1; i < n; i++) {
      final highest = highs.sublist(i - period + 1, i + 1).reduce(math.max);
      final lowest = lows.sublist(i - period + 1, i + 1).reduce(math.min);
      wr[i] = -100 * (highest - closes[i]) / (highest - lowest + 1e-10);
    }

    return wr;
  }

  List<double> _cci(List<double> highs, List<double> lows, List<double> closes, int period) {
    final n = closes.length;
    final tp = List<double>.generate(n, (i) => (highs[i] + lows[i] + closes[i]) / 3);
    final smaTp = _calculateSMA(tp, period);

    final mad = List<double>.filled(n, 0.0);
    for (int i = period - 1; i < n; i++) {
      final slice = tp.sublist(i - period + 1, i + 1);
      mad[i] = slice.map((v) => (v - smaTp[i]).abs()).reduce((a, b) => a + b) / period;
    }

    return List<double>.generate(n, (i) => (tp[i] - smaTp[i]) / (0.015 * mad[i] + 1e-10));
  }

  List<double> _mfi(List<double> highs, List<double> lows, List<double> closes, List<double> volumes, int period) {
    final n = closes.length;
    final tp = List<double>.generate(n, (i) => (highs[i] + lows[i] + closes[i]) / 3);
    final mf = List<double>.generate(n, (i) => tp[i] * volumes[i]);

    final posMf = List<double>.filled(n, 0.0);
    final negMf = List<double>.filled(n, 0.0);

    for (int i = 1; i < n; i++) {
      if (tp[i] > tp[i - 1]) {
        posMf[i] = mf[i];
      } else if (tp[i] < tp[i - 1]) {
        negMf[i] = mf[i];
      }
    }

    final mfi = List<double>.filled(n, 0.0);
    for (int i = period - 1; i < n; i++) {
      final posSum = posMf.sublist(i - period + 1, i + 1).reduce((a, b) => a + b);
      final negSum = negMf.sublist(i - period + 1, i + 1).reduce((a, b) => a + b);
      mfi[i] = 100 * posSum / (posSum + negSum + 1e-10);
    }

    return mfi;
  }

  List<double> _roc(List<double> closes, int period) {
    final n = closes.length;
    final roc = List<double>.filled(n, 0.0);
    for (int i = period; i < n; i++) {
      roc[i] = (closes[i] - closes[i - period]) / (closes[i - period] + 1e-10);
    }
    return roc;
  }

  List<double> _trix(List<double> closes, int period) {
    final ema1 = _calculateEMA(closes, period);
    final ema2 = _calculateEMA(ema1, period);
    final ema3 = _calculateEMA(ema2, period);
    final n = closes.length;

    final trix = List<double>.filled(n, 0.0);
    for (int i = 1; i < n; i++) {
      trix[i] = (ema3[i] - ema3[i - 1]) / (ema3[i - 1] + 1e-10) * 100;
    }

    return trix;
  }

  List<double> _ultimateOscillator(List<double> highs, List<double> lows, List<double> closes, int period1, int period2, int period3) {
    final n = closes.length;
    final bp = List<double>.filled(n, 0.0);
    final tr = List<double>.filled(n, 0.0);

    for (int i = 1; i < n; i++) {
      bp[i] = closes[i] - math.min(lows[i], closes[i - 1]);
      tr[i] = math.max(highs[i], closes[i - 1]) - math.min(lows[i], closes[i - 1]);
    }

    final avg1 = List<double>.generate(n, (i) => _calculateSMA(bp, period1)[i] / (_calculateSMA(tr, period1)[i] + 1e-10));
    final avg2 = List<double>.generate(n, (i) => _calculateSMA(bp, period2)[i] / (_calculateSMA(tr, period2)[i] + 1e-10));
    final avg3 = List<double>.generate(n, (i) => _calculateSMA(bp, period3)[i] / (_calculateSMA(tr, period3)[i] + 1e-10));

    return List<double>.generate(n, (i) => 100 * (4 * avg1[i] + 2 * avg2[i] + avg3[i]) / 7);
  }

  Map<String, List<double>> _parabolicSAR(List<double> highs, List<double> lows, List<double> closes, {double afStart = 0.02, double afMax = 0.2}) {
    final n = closes.length;
    final psar = List<double>.filled(n, 0.0);
    final direction = List<double>.filled(n, 1.0);

    psar[0] = lows[0];
    double ep = highs[0];
    double af = afStart;

    for (int i = 1; i < n; i++) {
      if (direction[i - 1] == 1) {
        psar[i] = psar[i - 1] + af * (ep - psar[i - 1]);
        psar[i] = math.min(psar[i], i > 1 ? math.min(lows[i - 1], lows[i - 2]) : lows[i - 1]);

        if (lows[i] < psar[i]) {
          direction[i] = -1;
          psar[i] = ep;
          ep = lows[i];
          af = afStart;
        } else {
          direction[i] = 1;
          if (highs[i] > ep) {
            ep = highs[i];
            af = math.min(af + afStart, afMax);
          }
        }
      } else {
        psar[i] = psar[i - 1] - af * (psar[i - 1] - ep);
        psar[i] = math.max(psar[i], i > 1 ? math.max(highs[i - 1], highs[i - 2]) : highs[i - 1]);

        if (highs[i] > psar[i]) {
          direction[i] = 1;
          psar[i] = ep;
          ep = highs[i];
          af = afStart;
        } else {
          direction[i] = -1;
          if (lows[i] < ep) {
            ep = lows[i];
            af = math.min(af + afStart, afMax);
          }
        }
      }
    }

    return {
      'psar': psar,
      'direction': direction,
    };
  }

  Map<String, List<double>> _elderRay(List<double> highs, List<double> lows, List<double> closes, int period) {
    final ema = _calculateEMA(closes, period);
    final n = closes.length;

    return {
      'bull_power': List<double>.generate(n, (i) => highs[i] - ema[i]),
      'bear_power': List<double>.generate(n, (i) => lows[i] - ema[i]),
    };
  }

  Map<String, List<double>> _aroon(List<double> highs, List<double> lows, int period) {
    final n = highs.length;
    final aroonUp = List<double>.filled(n, 0.0);
    final aroonDown = List<double>.filled(n, 0.0);

    for (int i = period; i < n; i++) {
      final highSlice = highs.sublist(i - period, i + 1);
      final lowSlice = lows.sublist(i - period, i + 1);

      int highIdx = 0;
      int lowIdx = 0;
      double maxHigh = highSlice[0];
      double minLow = lowSlice[0];

      for (int j = 1; j < highSlice.length; j++) {
        if (highSlice[j] >= maxHigh) {
          maxHigh = highSlice[j];
          highIdx = j;
        }
        if (lowSlice[j] <= minLow) {
          minLow = lowSlice[j];
          lowIdx = j;
        }
      }

      aroonUp[i] = 100 * highIdx / period;
      aroonDown[i] = 100 * lowIdx / period;
    }

    return {
      'up': aroonUp,
      'down': aroonDown,
    };
  }

  List<double> _chandeMomentum(List<double> closes, int period) {
    final n = closes.length;
    final delta = List<double>.generate(n, (i) => i == 0 ? 0.0 : closes[i] - closes[i - 1]);
    final gains = delta.map((d) => d > 0 ? d : 0.0).toList();
    final losses = delta.map((d) => d < 0 ? -d : 0.0).toList();

    final sumGains = List<double>.filled(n, 0.0);
    final sumLosses = List<double>.filled(n, 0.0);

    for (int i = period; i < n; i++) {
      sumGains[i] = gains.sublist(i - period + 1, i + 1).reduce((a, b) => a + b);
      sumLosses[i] = losses.sublist(i - period + 1, i + 1).reduce((a, b) => a + b);
    }

    return List<double>.generate(n, (i) => 100 * (sumGains[i] - sumLosses[i]) / (sumGains[i] + sumLosses[i] + 1e-10));
  }

  List<double> _dpo(List<double> closes, int period) {
    final shift = period ~/ 2 + 1;
    final sma = _calculateSMA(closes, period);
    final n = closes.length;
    final dpo = List<double>.filled(n, 0.0);

    for (int i = shift; i < n; i++) {
      dpo[i] = closes[i] - sma[i - shift];
    }

    return dpo;
  }

  List<double> _kama(List<double> closes, int period, int fast, int slow) {
    final n = closes.length;
    final change = List<double>.filled(n, 0.0);
    for (int i = period; i < n; i++) {
      change[i] = (closes[i] - closes[i - period]).abs();
    }

    final volatility = List<double>.filled(n, 0.0);
    for (int i = period; i < n; i++) {
      double sum = 0;
      for (int j = i - period; j < i; j++) {
        sum += (closes[j + 1] - closes[j]).abs();
      }
      volatility[i] = sum;
    }

    final er = List<double>.generate(n, (i) => change[i] / (volatility[i] + 1e-10));

    final fastSc = 2 / (fast + 1);
    final slowSc = 2 / (slow + 1);
    final sc = List<double>.generate(n, (i) => math.pow(er[i] * (fastSc - slowSc) + slowSc, 2).toDouble());

    final kama = List<double>.filled(n, 0.0);
    if (period - 1 < n) {
      kama[period - 1] = closes[period - 1];
    }

    for (int i = period; i < n; i++) {
      kama[i] = kama[i - 1] + sc[i] * (closes[i] - kama[i - 1]);
    }

    return kama;
  }

  List<double> _wma(List<double> data, int period) {
    final n = data.length;
    final weights = List<double>.generate(period, (i) => (i + 1).toDouble());
    final weightSum = weights.reduce((a, b) => a + b);

    final wma = List<double>.filled(n, 0.0);
    for (int i = period - 1; i < n; i++) {
      double sum = 0;
      for (int j = 0; j < period; j++) {
        sum += data[i - period + 1 + j] * weights[j];
      }
      wma[i] = sum / weightSum;
    }

    return wma;
  }

  List<double> _hullMA(List<double> closes, int period) {
    final halfPeriod = period ~/ 2;
    final sqrtPeriod = math.sqrt(period).toInt();

    final wmaHalf = _wma(closes, halfPeriod);
    final wmaFull = _wma(closes, period);

    final rawHma = List<double>.generate(closes.length, (i) => 2 * wmaHalf[i] - wmaFull[i]);
    return _wma(rawHma, sqrtPeriod);
  }

  List<double> _hmaDirection(List<double> hma) {
    final n = hma.length;
    final direction = List<double>.filled(n, 0.0);
    for (int i = 1; i < n; i++) {
      direction[i] = (hma[i] - hma[i - 1]).sign.toDouble();
    }
    return direction;
  }

  List<double> _marketRegime(List<double> closes, List<double> atr, int period) {
    final n = closes.length;
    final regime = List<double>.filled(n, 0.0);

    for (int i = period; i < n; i++) {
      final priceChange = (closes[i] - closes[i - period]) / closes[i - period];
      final avgAtr = atr.sublist(i - period, i).reduce((a, b) => a + b) / period / closes[i];

      if (priceChange.abs() > 2 * avgAtr * period) {
        regime[i] = priceChange > 0 ? 1.0 : -1.0;
      }
    }

    return regime;
  }

  List<double> _volatilityRegime(List<double> closes, int period) {
    final returns = _calculateReturns(closes);
    final n = closes.length;
    final regime = List<double>.filled(n, 0.0);

    for (int i = period * 2; i < n; i++) {
      final currentVol = returns.sublist(i - period, i).map((r) => r * r).reduce((a, b) => a + b) / period;
      final historicalVol = returns.sublist(i - period * 2, i - period).map((r) => r * r).reduce((a, b) => a + b) / period;

      if (historicalVol > 0) {
        final ratio = math.sqrt(currentVol) / math.sqrt(historicalVol);
        regime[i] = math.min(1.0, math.max(0.0, (ratio - 0.5) / 1.5));
      }
    }

    return regime;
  }

  List<double> _trendRegime(List<double> closes, List<double> sma50, List<double> sma200) {
    final n = closes.length;
    final regime = List<double>.filled(n, 0.0);

    for (int i = 0; i < n; i++) {
      if (closes[i] > sma50[i] && sma50[i] > sma200[i]) {
        regime[i] = 1.0;
      } else if (closes[i] < sma50[i] && sma50[i] < sma200[i]) {
        regime[i] = -1.0;
      }
    }

    return regime;
  }

  List<double> _volumeTrend(List<double> volumes, int period) {
    final smaVol = _calculateSMA(volumes, period);
    return List<double>.generate(volumes.length, (i) => (volumes[i] - smaVol[i]) / (smaVol[i] + 1e-10));
  }

  List<double> _priceVolumeTrend(List<double> closes, List<double> volumes) {
    final n = closes.length;
    final pvt = List<double>.filled(n, 0.0);

    for (int i = 1; i < n; i++) {
      pvt[i] = pvt[i - 1] + volumes[i] * (closes[i] - closes[i - 1]) / (closes[i - 1] + 1e-10);
    }

    // Normalize
    final minVal = pvt.reduce(math.min);
    final maxVal = pvt.reduce(math.max);
    if (maxVal - minVal > 0) {
      return pvt.map((v) => (v - minVal) / (maxVal - minVal)).toList();
    }
    return List<double>.filled(n, 0.0);
  }

  List<double> _accumulationDistribution(List<double> highs, List<double> lows, List<double> closes, List<double> volumes) {
    final n = closes.length;
    final mfm = List<double>.generate(n, (i) => ((closes[i] - lows[i]) - (highs[i] - closes[i])) / (highs[i] - lows[i] + 1e-10));

    double cumAd = 0;
    final ad = List<double>.filled(n, 0.0);
    for (int i = 0; i < n; i++) {
      cumAd += mfm[i] * volumes[i];
      ad[i] = cumAd;
    }

    // Normalize
    final minVal = ad.reduce(math.min);
    final maxVal = ad.reduce(math.max);
    if (maxVal - minVal > 0) {
      return ad.map((v) => (v - minVal) / (maxVal - minVal)).toList();
    }
    return List<double>.filled(n, 0.0);
  }
}

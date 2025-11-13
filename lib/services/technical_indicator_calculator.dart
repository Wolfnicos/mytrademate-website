import 'dart:math';
import '../models/candle.dart';

/// Calculates exactly 34 technical indicators for cryptocurrency trading
/// Order matches the Python training script for model compatibility
class TechnicalIndicatorCalculator {
  /// Calculate all 34 features for a window of 60 candles
  /// Returns List<List<double>> where outer list is timesteps, inner is features
  List<List<double>> calculateFeatures(List<Candle> candles) {
    if (candles.length != 60) {
      throw ArgumentError('Expected 60 candles, got ${candles.length}');
    }

    final List<List<double>> features = [];

    // Extract price arrays
    final closes = candles.map((c) => c.close).toList();
    final highs = candles.map((c) => c.high).toList();
    final lows = candles.map((c) => c.low).toList();
    // final opens = candles.map((c) => c.open).toList(); // Unused - commented out
    final volumes = candles.map((c) => c.volume).toList();

    // Calculate all indicators once
    final rsi14 = _calculateRSI(closes, 14);
    final macd = _calculateMACD(closes);
    final bbands = _calculateBollingerBands(closes, 20, 2.0);
    final stoch = _calculateStochastic(highs, lows, closes, 14, 3);
    final atr14 = _calculateATR(highs, lows, closes, 14);
    final adx14 = _calculateADX(highs, lows, closes, 14);
    final cci20 = _calculateCCI(highs, lows, closes, 20);
    final willr14 = _calculateWilliamsR(highs, lows, closes, 14);
    final mfi14 = _calculateMFI(highs, lows, closes, volumes, 14);
    final obv = _calculateOBV(closes, volumes);

    // For each timestep, construct the 34 feature vector
    for (int i = 0; i < candles.length; i++) {
      final featureVector = <double>[
        // 1-4: Returns
        _safeGet(_calculateReturns(closes), i),
        _safeGet(_calculateLogReturns(closes), i),
        rsi14[i],
        _safeGet(_calculateRSISlope(rsi14, 5), i),

        // 5-8: MACD
        macd['macd']![i],
        macd['signal']![i],
        macd['histogram']![i],
        _safeGet(_calculateMACDSlopeSignal(macd['signal']!, 3), i),

        // 9-12: Bollinger Bands
        bbands['upper']![i],
        bbands['middle']![i],
        bbands['lower']![i],
        bbands['bandwidth']![i],

        // 13-16: Stochastic
        stoch['k']![i],
        stoch['d']![i],
        _safeGet(_calculateStochasticKSlope(stoch['k']!, 3), i),
        _safeGet(_calculateStochasticDSlope(stoch['d']!, 3), i),

        // 17-20: ATR
        atr14[i],
        _safeGet(_calculateATRSlope(atr14, 5), i),
        _safeGet(_calculateATRPercent(atr14, closes), i),
        _safeGet(_calculateVolatilityRatio(highs, lows, atr14), i),

        // 21-24: ADX
        adx14['adx']![i],
        adx14['plusDI']![i],
        adx14['minusDI']![i],
        _safeGet(_calculateADXSlope(adx14['adx']!, 5), i),

        // 25-28: Other indicators
        cci20[i],
        willr14[i],
        mfi14[i],
        _safeGet(_calculateOBVSlope(obv, 5), i),

        // 29-32: Volume indicators
        _safeGet(_calculateVolumeMA(volumes, 20), i),
        _safeGet(_calculateVolumeRatio(volumes, 20), i),
        _safeGet(_calculateVWAP(highs, lows, closes, volumes, 20), i),
        _safeGet(_calculateForceIndex(closes, volumes, 13), i),

        // 33-34: Price position indicators
        _safeGet(_calculatePricePosition(closes, highs, lows, 20), i),
        _safeGet(_calculateTrendStrength(closes, 20), i),
      ];

      features.add(featureVector);
    }

    return features;
  }

  // ==================== HELPER FUNCTIONS ====================

  double _safeGet(List<double> list, int index) {
    if (index < 0 || index >= list.length) return 0.0;
    final value = list[index];
    return value.isNaN || value.isInfinite ? 0.0 : value;
  }

  // ==================== BASIC INDICATORS ====================

  List<double> _calculateReturns(List<double> closes) {
    final returns = <double>[0.0];
    for (int i = 1; i < closes.length; i++) {
      final ret = (closes[i] - closes[i - 1]) / closes[i - 1];
      returns.add(ret.isFinite ? ret : 0.0);
    }
    return returns;
  }

  List<double> _calculateLogReturns(List<double> closes) {
    final returns = <double>[0.0];
    for (int i = 1; i < closes.length; i++) {
      final ret = log(closes[i] / closes[i - 1]);
      returns.add(ret.isFinite ? ret : 0.0);
    }
    return returns;
  }

  // ==================== RSI ====================

  List<double> _calculateRSI(List<double> closes, int period) {
    final rsi = List<double>.filled(closes.length, 50.0);
    if (closes.length < period + 1) return rsi;

    final gains = <double>[];
    final losses = <double>[];

    for (int i = 1; i < closes.length; i++) {
      final change = closes[i] - closes[i - 1];
      gains.add(change > 0 ? change : 0.0);
      losses.add(change < 0 ? -change : 0.0);
    }

    double avgGain = gains.take(period).reduce((a, b) => a + b) / period;
    double avgLoss = losses.take(period).reduce((a, b) => a + b) / period;

    for (int i = period; i < closes.length; i++) {
      if (avgLoss == 0) {
        rsi[i] = 100.0;
      } else {
        final rs = avgGain / avgLoss;
        rsi[i] = 100 - (100 / (1 + rs));
      }

      if (i < closes.length - 1) {
        avgGain = (avgGain * (period - 1) + gains[i]) / period;
        avgLoss = (avgLoss * (period - 1) + losses[i]) / period;
      }
    }

    return rsi;
  }

  List<double> _calculateRSISlope(List<double> rsi, int period) {
    final slope = List<double>.filled(rsi.length, 0.0);
    for (int i = period; i < rsi.length; i++) {
      slope[i] = (rsi[i] - rsi[i - period]) / period;
    }
    return slope;
  }

  // ==================== MACD ====================

  Map<String, List<double>> _calculateMACD(List<double> closes, {int fast = 12, int slow = 26, int signal = 9}) {
    final emaFast = _calculateEMA(closes, fast);
    final emaSlow = _calculateEMA(closes, slow);
    final macdLine = List<double>.generate(closes.length, (i) => emaFast[i] - emaSlow[i]);
    final signalLine = _calculateEMA(macdLine, signal);
    final histogram = List<double>.generate(closes.length, (i) => macdLine[i] - signalLine[i]);

    return {
      'macd': macdLine,
      'signal': signalLine,
      'histogram': histogram,
    };
  }

  List<double> _calculateEMA(List<double> values, int period) {
    final ema = List<double>.filled(values.length, 0.0);
    if (values.isEmpty) return ema;

    final multiplier = 2.0 / (period + 1);
    ema[0] = values[0];

    for (int i = 1; i < values.length; i++) {
      ema[i] = (values[i] - ema[i - 1]) * multiplier + ema[i - 1];
    }

    return ema;
  }

  List<double> _calculateMACDSlopeSignal(List<double> signal, int period) {
    final slope = List<double>.filled(signal.length, 0.0);
    for (int i = period; i < signal.length; i++) {
      slope[i] = (signal[i] - signal[i - period]) / period;
    }
    return slope;
  }

  // ==================== BOLLINGER BANDS ====================

  Map<String, List<double>> _calculateBollingerBands(List<double> closes, int period, double stdDev) {
    final middle = _calculateSMA(closes, period);
    final upper = List<double>.filled(closes.length, 0.0);
    final lower = List<double>.filled(closes.length, 0.0);
    final bandwidth = List<double>.filled(closes.length, 0.0);

    for (int i = period - 1; i < closes.length; i++) {
      final slice = closes.sublist(i - period + 1, i + 1);
      final std = _calculateStdDev(slice);
      upper[i] = middle[i] + stdDev * std;
      lower[i] = middle[i] - stdDev * std;
      bandwidth[i] = (upper[i] - lower[i]) / middle[i];
    }

    return {
      'upper': upper,
      'middle': middle,
      'lower': lower,
      'bandwidth': bandwidth,
    };
  }

  List<double> _calculateSMA(List<double> values, int period) {
    final sma = List<double>.filled(values.length, 0.0);
    for (int i = period - 1; i < values.length; i++) {
      final sum = values.sublist(i - period + 1, i + 1).reduce((a, b) => a + b);
      sma[i] = sum / period;
    }
    return sma;
  }

  double _calculateStdDev(List<double> values) {
    if (values.isEmpty) return 0.0;
    final mean = values.reduce((a, b) => a + b) / values.length;
    final variance = values.map((x) => pow(x - mean, 2)).reduce((a, b) => a + b) / values.length;
    return sqrt(variance);
  }

  // ==================== STOCHASTIC ====================

  Map<String, List<double>> _calculateStochastic(List<double> highs, List<double> lows, List<double> closes, int period, int smoothK) {
    final k = List<double>.filled(closes.length, 50.0);

    for (int i = period - 1; i < closes.length; i++) {
      final highestHigh = highs.sublist(i - period + 1, i + 1).reduce(max);
      final lowestLow = lows.sublist(i - period + 1, i + 1).reduce(min);
      if (highestHigh - lowestLow != 0) {
        k[i] = ((closes[i] - lowestLow) / (highestHigh - lowestLow)) * 100;
      }
    }

    final d = _calculateSMA(k, smoothK);

    return {'k': k, 'd': d};
  }

  List<double> _calculateStochasticKSlope(List<double> k, int period) {
    final slope = List<double>.filled(k.length, 0.0);
    for (int i = period; i < k.length; i++) {
      slope[i] = (k[i] - k[i - period]) / period;
    }
    return slope;
  }

  List<double> _calculateStochasticDSlope(List<double> d, int period) {
    final slope = List<double>.filled(d.length, 0.0);
    for (int i = period; i < d.length; i++) {
      slope[i] = (d[i] - d[i - period]) / period;
    }
    return slope;
  }

  // ==================== ATR ====================

  List<double> _calculateATR(List<double> highs, List<double> lows, List<double> closes, int period) {
    final tr = List<double>.filled(closes.length, 0.0);
    tr[0] = highs[0] - lows[0];

    for (int i = 1; i < closes.length; i++) {
      final hl = highs[i] - lows[i];
      final hc = (highs[i] - closes[i - 1]).abs();
      final lc = (lows[i] - closes[i - 1]).abs();
      tr[i] = max(hl, max(hc, lc));
    }

    return _calculateEMA(tr, period);
  }

  List<double> _calculateATRSlope(List<double> atr, int period) {
    final slope = List<double>.filled(atr.length, 0.0);
    for (int i = period; i < atr.length; i++) {
      slope[i] = (atr[i] - atr[i - period]) / period;
    }
    return slope;
  }

  List<double> _calculateATRPercent(List<double> atr, List<double> closes) {
    final percent = List<double>.filled(atr.length, 0.0);
    for (int i = 0; i < atr.length; i++) {
      if (closes[i] != 0) {
        percent[i] = (atr[i] / closes[i]) * 100;
      }
    }
    return percent;
  }

  List<double> _calculateVolatilityRatio(List<double> highs, List<double> lows, List<double> atr) {
    final ratio = List<double>.filled(highs.length, 0.0);
    for (int i = 0; i < highs.length; i++) {
      final range = highs[i] - lows[i];
      if (atr[i] != 0) {
        ratio[i] = range / atr[i];
      }
    }
    return ratio;
  }

  // ==================== ADX ====================

  Map<String, List<double>> _calculateADX(List<double> highs, List<double> lows, List<double> closes, int period) {
    final plusDM = List<double>.filled(closes.length, 0.0);
    final minusDM = List<double>.filled(closes.length, 0.0);

    for (int i = 1; i < closes.length; i++) {
      final highDiff = highs[i] - highs[i - 1];
      final lowDiff = lows[i - 1] - lows[i];

      if (highDiff > lowDiff && highDiff > 0) {
        plusDM[i] = highDiff;
      }
      if (lowDiff > highDiff && lowDiff > 0) {
        minusDM[i] = lowDiff;
      }
    }

    final atr = _calculateATR(highs, lows, closes, period);
    final plusDI = List<double>.filled(closes.length, 0.0);
    final minusDI = List<double>.filled(closes.length, 0.0);
    final dx = List<double>.filled(closes.length, 0.0);

    for (int i = period; i < closes.length; i++) {
      if (atr[i] != 0) {
        plusDI[i] = (plusDM[i] / atr[i]) * 100;
        minusDI[i] = (minusDM[i] / atr[i]) * 100;

        final diSum = plusDI[i] + minusDI[i];
        if (diSum != 0) {
          dx[i] = ((plusDI[i] - minusDI[i]).abs() / diSum) * 100;
        }
      }
    }

    final adx = _calculateSMA(dx, period);

    return {
      'adx': adx,
      'plusDI': plusDI,
      'minusDI': minusDI,
    };
  }

  List<double> _calculateADXSlope(List<double> adx, int period) {
    final slope = List<double>.filled(adx.length, 0.0);
    for (int i = period; i < adx.length; i++) {
      slope[i] = (adx[i] - adx[i - period]) / period;
    }
    return slope;
  }

  // ==================== CCI ====================

  List<double> _calculateCCI(List<double> highs, List<double> lows, List<double> closes, int period) {
    final cci = List<double>.filled(closes.length, 0.0);
    final tp = List<double>.generate(closes.length, (i) => (highs[i] + lows[i] + closes[i]) / 3);
    final sma = _calculateSMA(tp, period);

    for (int i = period - 1; i < closes.length; i++) {
      final slice = tp.sublist(i - period + 1, i + 1);
      final meanDev = slice.map((x) => (x - sma[i]).abs()).reduce((a, b) => a + b) / period;
      if (meanDev != 0) {
        cci[i] = (tp[i] - sma[i]) / (0.015 * meanDev);
      }
    }

    return cci;
  }

  // ==================== WILLIAMS %R ====================

  List<double> _calculateWilliamsR(List<double> highs, List<double> lows, List<double> closes, int period) {
    final willr = List<double>.filled(closes.length, -50.0);

    for (int i = period - 1; i < closes.length; i++) {
      final highestHigh = highs.sublist(i - period + 1, i + 1).reduce(max);
      final lowestLow = lows.sublist(i - period + 1, i + 1).reduce(min);
      if (highestHigh - lowestLow != 0) {
        willr[i] = ((highestHigh - closes[i]) / (highestHigh - lowestLow)) * -100;
      }
    }

    return willr;
  }

  // ==================== MFI ====================

  List<double> _calculateMFI(List<double> highs, List<double> lows, List<double> closes, List<double> volumes, int period) {
    final mfi = List<double>.filled(closes.length, 50.0);
    final tp = List<double>.generate(closes.length, (i) => (highs[i] + lows[i] + closes[i]) / 3);
    final mf = List<double>.generate(closes.length, (i) => tp[i] * volumes[i]);

    for (int i = period; i < closes.length; i++) {
      double posFlow = 0.0;
      double negFlow = 0.0;

      for (int j = i - period + 1; j <= i; j++) {
        if (tp[j] > tp[j - 1]) {
          posFlow += mf[j];
        } else if (tp[j] < tp[j - 1]) {
          negFlow += mf[j];
        }
      }

      if (negFlow != 0) {
        final mfRatio = posFlow / negFlow;
        mfi[i] = 100 - (100 / (1 + mfRatio));
      }
    }

    return mfi;
  }

  // ==================== OBV ====================

  List<double> _calculateOBV(List<double> closes, List<double> volumes) {
    final obv = List<double>.filled(closes.length, 0.0);
    obv[0] = volumes[0];

    for (int i = 1; i < closes.length; i++) {
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

  List<double> _calculateOBVSlope(List<double> obv, int period) {
    final slope = List<double>.filled(obv.length, 0.0);
    for (int i = period; i < obv.length; i++) {
      slope[i] = (obv[i] - obv[i - period]) / period;
    }
    return slope;
  }

  // ==================== VOLUME INDICATORS ====================

  List<double> _calculateVolumeMA(List<double> volumes, int period) {
    return _calculateSMA(volumes, period);
  }

  List<double> _calculateVolumeRatio(List<double> volumes, int period) {
    final ratio = List<double>.filled(volumes.length, 1.0);
    final sma = _calculateSMA(volumes, period);

    for (int i = period - 1; i < volumes.length; i++) {
      if (sma[i] != 0) {
        ratio[i] = volumes[i] / sma[i];
      }
    }

    return ratio;
  }

  List<double> _calculateVWAP(List<double> highs, List<double> lows, List<double> closes, List<double> volumes, int period) {
    final vwap = List<double>.filled(closes.length, 0.0);

    for (int i = period - 1; i < closes.length; i++) {
      double cumTPV = 0.0;
      double cumVol = 0.0;

      for (int j = i - period + 1; j <= i; j++) {
        final tp = (highs[j] + lows[j] + closes[j]) / 3;
        cumTPV += tp * volumes[j];
        cumVol += volumes[j];
      }

      if (cumVol != 0) {
        vwap[i] = cumTPV / cumVol;
      }
    }

    return vwap;
  }

  List<double> _calculateForceIndex(List<double> closes, List<double> volumes, int period) {
    final fi = List<double>.filled(closes.length, 0.0);

    for (int i = 1; i < closes.length; i++) {
      fi[i] = (closes[i] - closes[i - 1]) * volumes[i];
    }

    return _calculateEMA(fi, period);
  }

  // ==================== PRICE POSITION ====================

  List<double> _calculatePricePosition(List<double> closes, List<double> highs, List<double> lows, int period) {
    final position = List<double>.filled(closes.length, 0.5);

    for (int i = period - 1; i < closes.length; i++) {
      final highestHigh = highs.sublist(i - period + 1, i + 1).reduce(max);
      final lowestLow = lows.sublist(i - period + 1, i + 1).reduce(min);
      if (highestHigh - lowestLow != 0) {
        position[i] = (closes[i] - lowestLow) / (highestHigh - lowestLow);
      }
    }

    return position;
  }

  List<double> _calculateTrendStrength(List<double> closes, int period) {
    final strength = List<double>.filled(closes.length, 0.0);

    for (int i = period; i < closes.length; i++) {
      final returns = <double>[];
      for (int j = i - period + 1; j <= i; j++) {
        returns.add(closes[j] - closes[j - 1]);
      }

      final sumReturns = returns.reduce((a, b) => a + b).abs();
      final sumAbsReturns = returns.map((r) => r.abs()).reduce((a, b) => a + b);

      if (sumAbsReturns != 0) {
        strength[i] = sumReturns / sumAbsReturns;
      }
    }

    return strength;
  }
}

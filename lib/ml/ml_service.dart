import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

// Three-class trading signal emitted by the ML model
enum TradingSignal { SELL, HOLD, BUY }

class _Thresh {
  final double buy;
  final double sell;
  final double confidence;
  const _Thresh({required this.buy, required this.sell, required this.confidence});
}

class MLService {
  late Interpreter _interpreter;
  bool isInitialized = false;

  // Exact values provided from Python training/export
  final double optimalTemperature = 2.0;
  final double thresholdBuy = 0.55;
  final double thresholdSell = 0.55;
  final double thresholdConfidence = 0.38;

  // Per-coin overrides (by base), to tune behavior symbol-wise
  // These can be further adjusted based on observed behavior
  final Map<String, Map<String, double>> _symbolThresholds = <String, Map<String, double>>{
    'BTC': {'buy': 0.45, 'sell': 0.58, 'conf': 0.36},
    'SOL': {'buy': 0.43, 'sell': 0.58, 'conf': 0.36},
    'WLFI': {'buy': 0.40, 'sell': 0.60, 'conf': 0.36},
    'TRUMP': {'buy': 0.42, 'sell': 0.60, 'conf': 0.36},
    // Keep defaults for ETH/BNB unless specified
    'ETH': {'buy': 0.55, 'sell': 0.55, 'conf': 0.38},
    'BNB': {'buy': 0.55, 'sell': 0.55, 'conf': 0.38},
  };

  // Per-quote deltas to slightly relax/tighten thresholds depending on quote currency.
  final Map<String, Map<String, double>> _quoteDeltas = const <String, Map<String, double>>{
    'EUR': {'buy': -0.05, 'sell': 0.0, 'conf': -0.02},
    'USD': {'buy': -0.02, 'sell': 0.0, 'conf': -0.01},
    'USDC': {'buy': 0.0, 'sell': 0.0, 'conf': 0.0},
    'USDT': {'buy': 0.0, 'sell': 0.0, 'conf': 0.0},
  };

  // StandardScaler mean/scale for 34 features
  final List<double> scalerMean = const [
    -6.261972257839915e-06, 0.006796661934405448, 50.08088475231509, 0.03008563712782742,
    9823.82488550076, 9818.594870037758, 79.31022523260559, 0.48493856520015854,
    9828.846171224734, 60695.67524339066, 2.4562926747518962e-05, 0.0033280663853553624,
    50.193428876843825, 0.002250047140233959, 9826.481048094374, 9824.661734620438,
    37.98391588509552, 0.49944719110499197, 9828.88318198886, 15922.288971761802,
    -2.690691703945675e-05, 0.01385255107577443, 50.13062467042356, 0.24329538429736575,
    9817.108975947596, 9809.759727246177, 165.4843219833477, 0.4508834511963619,
    9827.9506963306, 242769.9987848025, 0.2499947848217452, 0.2500052151782548,
    0.2500052151782548, 0.2499947848217452
  ];
  final List<double> scalerScale = const [
    0.008217990847552597, 0.004627414390821184, 11.966813622092445, 40.2202206308292,
    17400.13197711625, 17383.03299263452, 158.13079647130243, 0.49977310169893113,
    17413.841149449152, 134554.3121297035, 0.004330410612503934, 0.002564468704936143,
    11.27186920505309, 19.74756328885756, 17408.08955489309, 17403.01118349171,
    79.3565735210178, 0.49999969440223224, 17413.779687643335, 39095.87782191155,
    0.016085978908539657, 0.008152392886587038, 12.674613725189518, 78.69180506920333,
    17375.739395600376, 17340.255001151058, 317.8574209833367, 0.4975817165387207,
    17411.614087598955, 483380.00937141705, 0.4330096908657756, 0.4330157128349147,
    0.4330157128349147, 0.4330096908657756
  ];

  // Model window and features
  final int windowSize = 60;
  int numFeatures = 34; // Updated from model input tensor if available

  MLService();

  Future<void> loadModel() async {
    try {
      _interpreter = await Interpreter.fromAsset('assets/models/legacy/mytrademate_v8_tcn_mtf_float32.tflite');
      isInitialized = true;
      // Try to infer feature count from input tensor shape [1, window, features]
      try {
        final List<int> inputShape = _interpreter.getInputTensor(0).shape;
        if (inputShape.length >= 3) {
          numFeatures = inputShape[2];
        }
        debugPrint('✅ MLService: TFLite model loaded. Input shape=$inputShape, numFeatures=$numFeatures');
      } catch (_) {
        debugPrint('⚠️ MLService: Could not read input tensor shape; using numFeatures=$numFeatures');
      }
    } catch (e) {
      isInitialized = false;
      debugPrint('❌ MLService: Failed to load model → $e');
    }
  }

  Map<String, dynamic> getSignal(List<List<double>> rawInput, {String? symbol}) {
    if (!isInitialized) {
      throw Exception('MLService not initialized. Call loadModel() first.');
    }
    if (rawInput.length != windowSize) {
      throw Exception('Expected $windowSize timesteps, got ${rawInput.length}.');
    }

    final List<double> rawProbs = _getRawProbabilities(rawInput);
    final List<double> calibrated = _applyTemperature(rawProbs, optimalTemperature);
    final TradingSignal signal = _applyPolicy(calibrated, symbol: symbol);
    if (symbol != null) {
      final _Thresh tt = _getThresholds(symbol);
      debugPrint('ℹ️ ML thresholds for $symbol → buy=${tt.buy.toStringAsFixed(3)}, sell=${tt.sell.toStringAsFixed(3)}, conf=${tt.confidence.toStringAsFixed(3)}');
    }

    return {
      'signal': signal,
      'probabilities': calibrated,
    };
  }

  List<double> _getRawProbabilities(List<List<double>> rawInput) {
    // Use StandardScaler only if provided and matching current feature count
    final bool useScaling = scalerMean.isNotEmpty &&
        scalerScale.isNotEmpty &&
        scalerMean.length == scalerScale.length &&
        scalerMean.length == numFeatures;

    final List<List<double>> scaledInput = List<List<double>>.generate(windowSize, (int i) {
      final List<double> row = rawInput[i];
      if (!useScaling) {
        if (row.length != numFeatures) {
          throw Exception('Each row must have $numFeatures features.');
        }
        return List<double>.from(row);
      }
      // Scaling path
      if (row.length != numFeatures) {
        throw Exception('Each row must have $numFeatures features for scaling.');
      }
      return List<double>.generate(numFeatures, (int j) => (row[j] - scalerMean[j]) / scalerScale[j]);
    }, growable: false);

    // Prepare tensors: shape [1, windowSize, numFeatures]
    final List<List<List<double>>> inputTensor = <List<List<double>>>[scaledInput];
    final List<List<double>> outputTensor = <List<double>>[List<double>.filled(3, 0.0)];

    try {
      debugPrint('▶️ MLService.run: first row(3)=${scaledInput.isNotEmpty ? scaledInput.first.take(3).toList().toString() : '[]'}');
      _interpreter.run(inputTensor, outputTensor);
      debugPrint('◀️ MLService.run: raw out=${outputTensor[0]}');
      return outputTensor[0];
    } catch (e) {
      debugPrint('❌ MLService: Inference error → $e');
      return const [0.333, 0.333, 0.333];
    }
  }

  List<double> _applyTemperature(List<double> probs, double temp) {
    debugPrint('ℹ️ Temperature in=$probs, T=$temp');
    final List<double> scaled = probs.map((double p) => pow(p, 1.0 / temp).toDouble()).toList(growable: false);
    final double sum = scaled.fold(0.0, (double a, double b) => a + b);
    if (sum < 1e-9) return const [0.333, 0.333, 0.333];
    final out = scaled.map((double p) => p / sum).toList(growable: false);
    debugPrint('ℹ️ Temperature out=$out');
    return out;
  }

  TradingSignal _applyPolicy(List<double> calibrated, {String? symbol}) {
    final double probSell = calibrated[0];
    final double probHold = calibrated[1];
    final double probBuy = calibrated[2];

    // Simple logic: return the class with highest probability
    // No complex thresholds - just show what the model actually predicts
    if (probSell > probHold && probSell > probBuy) {
      return TradingSignal.SELL;
    } else if (probBuy > probHold && probBuy > probSell) {
      return TradingSignal.BUY;
    } else {
      return TradingSignal.HOLD;
    }
  }

  _Thresh _getThresholds(String? symbol) {
    if (symbol == null || symbol.isEmpty) {
      return _Thresh(buy: thresholdBuy, sell: thresholdSell, confidence: thresholdConfidence);
    }
    final String base = _extractBase(symbol);
    final String quote = _extractQuote(symbol);
    final Map<String, double>? sm = _symbolThresholds[base];
    final Map<String, double>? qd = _quoteDeltas[quote];
    double b = (sm?['buy'] ?? thresholdBuy) + (qd?['buy'] ?? 0.0);
    double s = (sm?['sell'] ?? thresholdSell) + (qd?['sell'] ?? 0.0);
    double c = (sm?['conf'] ?? thresholdConfidence) + (qd?['conf'] ?? 0.0);
    // Keep thresholds in sane bounds
    b = b.clamp(0.35, 0.80);
    s = s.clamp(0.40, 0.85);
    c = c.clamp(0.30, 0.60);
    return _Thresh(buy: b, sell: s, confidence: c);
  }

  String _extractBase(String sym) {
    final up = sym.toUpperCase();
    for (final q in const ['USDT', 'USDC', 'USD', 'EUR']) {
      if (up.endsWith(q)) {
        return up.substring(0, up.length - q.length);
      }
    }
    return up;
  }

  String _extractQuote(String sym) {
    final up = sym.toUpperCase();
    for (final q in const ['USDT', 'USDC', 'USD', 'EUR']) {
      if (up.endsWith(q)) return q;
    }
    return 'USDT';
  }

  void dispose() {
    try {
      _interpreter.close();
    } catch (_) {}
  }
}

// Global singleton for convenient access from UI layers
final MLService globalMlService = MLService();



import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'dart:convert';
import 'dart:math' show exp, log;
import 'package:mytrademate/services/binance_service.dart';
import 'package:mytrademate/services/base_exchange_service.dart';
import 'package:mytrademate/services/advanced_feature_builder.dart';
import 'package:mytrademate/ml/crypto_ml_service.dart';

/// Service pentru predicții ML crypto - MODELE V2 (150 features)
/// Funcționează IN PARALEL cu CryptoMLService (76 features)
///
/// Modele: btc_4h_v2, btc_1d_v2, eth_4h_v2, eth_1d_v2, sol_4h_v2, sol_1d_v2, bnb_4h_v2, bnb_1d_v2
/// Arhitectură: Deep Conv1D cu Dilated Convolutions (iOS TFLite compatible)
/// Features: 150 (76 originale + 74 avansate)
class CryptoMLV2Service {
  static final CryptoMLV2Service _instance = CryptoMLV2Service._internal();
  factory CryptoMLV2Service() => _instance;
  static CryptoMLV2Service get instance => _instance;
  CryptoMLV2Service._internal();

  // Cache pentru interpretere v2
  final Map<String, Interpreter> _interpreters = {};

  // Cache pentru scalere v2 (mean, scale din antrenament)
  final Map<String, Map<String, dynamic>> _scalers = {};

  // Feature builder pentru 150 features
  final AdvancedFeatureBuilder _featureBuilder = AdvancedFeatureBuilder();

  // Binance service pentru date
  final BinanceService _binanceService = BinanceService();

  // Modelele v2 disponibile - COMPLETE pentru toate monedele
  static const List<String> availableV2Models = [
    'btc_1h_v2', 'btc_4h_v2', 'btc_1d_v2',
    'eth_1h_v2', 'eth_4h_v2', 'eth_1d_v2',
    'sol_1h_v2', 'sol_4h_v2', 'sol_1d_v2',
    'bnb_1h_v2', 'bnb_4h_v2', 'bnb_1d_v2',
  ];

  // Ponderile pentru weighted ensemble per timeframe
  // Primar = 50%, Secundar = 30%, Terțiar = 20%
  static const Map<String, List<Map<String, dynamic>>> ensembleWeights = {
    '1h': [
      {'timeframe': '1h', 'weight': 0.50},  // Primar - exact match
      {'timeframe': '4h', 'weight': 0.30},  // Secundar - trend context
      {'timeframe': '1d', 'weight': 0.20},  // Terțiar - macro trend
    ],
    '4h': [
      {'timeframe': '4h', 'weight': 0.50},  // Primar - exact match
      {'timeframe': '1d', 'weight': 0.30},  // Secundar - trend context
      {'timeframe': '1h', 'weight': 0.20},  // Terțiar - short-term momentum
    ],
    '1d': [
      {'timeframe': '1d', 'weight': 0.50},  // Primar - exact match
      {'timeframe': '4h', 'weight': 0.30},  // Secundar - medium-term
      {'timeframe': '1h', 'weight': 0.20},  // Terțiar - short-term
    ],
  };

  /// Inițializează serviciul (LAZY LOADING - models load on-demand)
  Future<void> initialize() async {
    debugPrint('🚀 ========================================');
    debugPrint('🚀 Initializing CryptoMLV2Service (150 features)');
    debugPrint('🚀 Models: ${availableV2Models.join(", ")}');
    debugPrint('🚀 ========================================');
    debugPrint('✅ CryptoMLV2Service ready - Models will load on-demand');
  }

  /// Încarcă un model v2 specific
  Future<bool> loadModel(String coin, String timeframe) async {
    final key = '${coin.toLowerCase()}_${timeframe}_v2';

    // Skip dacă deja încărcat
    if (_interpreters.containsKey(key)) {
      return true;
    }

    try {
      final modelPath = 'assets/ml/$key.tflite';
      final scalerPath = 'assets/ml/${key}_scaler.json';

      debugPrint('📦 Loading V2 model: $key from $modelPath');

      // 1. Verifică dacă modelul există
      try {
        await rootBundle.load(modelPath);
      } catch (e) {
        debugPrint('   ❌ V2 model NOT found: $modelPath');
        return false;
      }

      // 2. Încarcă interpretorul
      Interpreter? interpreter;
      try {
        final options = InterpreterOptions()..threads = 2;
        interpreter = await Interpreter.fromAsset(modelPath, options: options);
        debugPrint('   ✅ V2 model loaded successfully');
      } catch (e) {
        debugPrint('   ❌ Failed to load V2 interpreter: $e');
        return false;
      }

      _interpreters[key] = interpreter;

      // 3. Încarcă scalerul
      try {
        final scalerString = await rootBundle.loadString(scalerPath);
        final scalerData = json.decode(scalerString) as Map<String, dynamic>;
        _scalers[key] = {
          'mean': (scalerData['mean'] as List).cast<double>(),
          'scale': (scalerData['scale'] as List).cast<double>(),
          'n_features': scalerData['n_features'] ?? 150,
        };
        debugPrint('   📊 Loaded V2 scaler: ${_scalers[key]!['n_features']} features');
      } catch (e) {
        debugPrint('   ⚠️  Failed to load V2 scaler, using identity: $e');
        _scalers[key] = {
          'mean': List<double>.filled(150, 0.0),
          'scale': List<double>.filled(150, 1.0),
          'n_features': 150,
        };
      }

      return true;
    } catch (e) {
      debugPrint('   ❌ Error loading V2 model $key: $e');
      return false;
    }
  }

  /// Ensure a specific V2 model is loaded (lazy loading)
  Future<bool> _ensureModelLoaded(String coin, String timeframe) async {
    final key = '${coin.toLowerCase()}_${timeframe}_v2';

    if (_interpreters.containsKey(key)) {
      return true;
    }

    return await loadModel(coin, timeframe);
  }

  /// Obține predicția V2 pentru o monedă
  Future<CryptoPrediction?> getPredictionV2({
    required String coin,
    required String symbol,
    required String timeframe,
    bool silent = false,
    BaseExchangeService? exchangeService,
  }) async {
    // Normalizează coin-ul
    final normalizedCoin = coin.toLowerCase().replaceAll(RegExp(r'(usd|eur|usdt|usdc)$'), '');

    // Verifică dacă avem model V2 pentru acest timeframe
    if (!['1h', '4h', '1d'].contains(timeframe)) {
      if (!silent) {
        debugPrint('⚠️  V2 models only available for 1h, 4h and 1d timeframes');
      }
      return null;
    }

    // Încarcă modelul dacă nu e încărcat
    final loaded = await _ensureModelLoaded(normalizedCoin, timeframe);
    if (!loaded) {
      if (!silent) {
        debugPrint('⚠️  V2 model not available for $normalizedCoin@$timeframe');
      }
      return null;
    }

    final key = '${normalizedCoin}_${timeframe}_v2';

    try {
      if (!silent) {
        debugPrint('🎯 V2 PREDICTION for ${coin.toUpperCase()} @ $timeframe (150 features)');
      }

      // 1. Fetch candles (need at least 119 for sliding window)
      // Always use Binance for V2 predictions - most reliable data source
      // This avoids symbol format issues with other exchanges (Coinbase uses BTC-USD, etc)
      final binanceSymbol = '${normalizedCoin.toUpperCase()}USDT';
      final candles = await _binanceService.fetchKlines(binanceSymbol, timeframe, limit: 200);

      if (candles.length < 119) {
        debugPrint('   ❌ Not enough candles: ${candles.length} < 119');
        return null;
      }

      // 2. Build 150 features
      final features = _featureBuilder.buildFeatures(candles: candles);

      if (features.isEmpty || features.first.length != 150) {
        debugPrint('   ❌ Invalid features: ${features.length}x${features.isEmpty ? 0 : features.first.length}');
        return null;
      }

      // 3. Run prediction
      return await _getPredictionWithV2Model(key, features, silent: silent);
    } catch (e) {
      debugPrint('   ❌ V2 prediction error: $e');
      return null;
    }
  }

  /// Execută predicția cu un model V2 specific
  Future<CryptoPrediction> _getPredictionWithV2Model(
    String modelKey,
    List<List<double>> features,
    {bool silent = false}
  ) async {
    final interpreter = _interpreters[modelKey]!;
    final scaler = _scalers[modelKey]!;

    // Validare
    if (features.length != 60) {
      throw Exception('Need exactly 60 timesteps, got ${features.length}');
    }
    if (features[0].length != 150) {
      throw Exception('Need exactly 150 features, got ${features[0].length}');
    }

    // Normalizare cu scalerul din antrenament
    final normalizedData = _normalizeData(features, scaler);

    // Input: [1, 60, 150]
    final List<List<List<double>>> input = [normalizedData];

    // Output: [1, 3] (SELL, HOLD, BUY)
    final List<List<double>> output = List<List<double>>.generate(
      1,
      (_) => List<double>.filled(3, 0.0),
    );

    interpreter.run(input, output);

    if (!silent) {
      debugPrint('🔬 V2 OUTPUT ($modelKey): [${output[0].map((v) => v.toStringAsFixed(4)).join(", ")}]');
    }

    // Apply temperature scaling pentru predicții mai calibrate
    var probabilities = output[0];
    final maxProb = probabilities.reduce((a, b) => a > b ? a : b);

    // Aplicăm temperature scaling dacă e prea confident
    if (maxProb > 0.92) {
      probabilities = _applyTemperatureScaling(probabilities, 1.5);
      if (!silent) {
        debugPrint('   🌡️  Applied temperature scaling (T=1.5)');
      }
    }

    final maxIndex = _argmax(probabilities);
    final action = ['SELL', 'HOLD', 'BUY'][maxIndex];
    final confidence = probabilities[maxIndex].clamp(0.30, 0.95);

    final probMap = {
      'SELL': probabilities[0],
      'HOLD': probabilities[1],
      'BUY': probabilities[2],
    };

    // Calculate signal strength
    final sorted = probabilities.toList()..sort();
    final signalStrength = (sorted.last - sorted[sorted.length - 2]).clamp(0.0, 1.0);

    return CryptoPrediction(
      action: action,
      confidence: confidence,
      probabilities: probMap,
      signalStrength: signalStrength,
      modelAccuracy: 0.58, // Aproximativ din antrenament
      timestamp: DateTime.now(),
      isEnsemble: false,
      decisionReason: 'Deep learning analysis across 150+ technical indicators',
    );
  }

  /// Normalizează datele folosind scalerul salvat din antrenament
  /// Formula: (x - mean) / scale
  List<List<double>> _normalizeData(
    List<List<double>> data,
    Map<String, dynamic> scaler,
  ) {
    final mean = (scaler['mean'] as List).cast<double>();
    final scale = (scaler['scale'] as List).cast<double>();

    final normalized = <List<double>>[];

    for (int t = 0; t < data.length; t++) {
      final row = <double>[];
      for (int f = 0; f < data[0].length; f++) {
        if (f < mean.length && f < scale.length) {
          final value = scale[f] > 1e-8
              ? (data[t][f] - mean[f]) / scale[f]
              : 0.0;
          row.add(value.clamp(-10.0, 10.0)); // Clamp extreme values
        } else {
          row.add(data[t][f]);
        }
      }
      normalized.add(row);
    }

    return normalized;
  }

  /// Apply temperature scaling
  List<double> _applyTemperatureScaling(List<double> probs, double temperature) {
    if (temperature == 1.0) return probs;

    final epsilon = 1e-10;
    final logits = probs.map((p) => log(p + epsilon)).toList();
    final scaledLogits = logits.map((l) => l / temperature).toList();

    final maxLogit = scaledLogits.reduce((a, b) => a > b ? a : b);
    final expValues = scaledLogits.map((l) => exp(l - maxLogit)).toList();
    final sumExp = expValues.reduce((a, b) => a + b);

    final scaled = expValues.map((e) => e / sumExp).toList();

    // Hard cap at 98%
    const maxAllowedProb = 0.98;
    final maxScaledProb = scaled.reduce((a, b) => a > b ? a : b);

    if (maxScaledProb > maxAllowedProb) {
      final maxIdx = scaled.indexOf(maxScaledProb);
      final excess = maxScaledProb - maxAllowedProb;
      final otherCount = scaled.length - 1;

      for (int i = 0; i < scaled.length; i++) {
        if (i == maxIdx) {
          scaled[i] = maxAllowedProb;
        } else {
          scaled[i] = scaled[i] + (excess / otherCount);
        }
      }
    }

    return scaled;
  }

  /// Argmax helper
  int _argmax(List<double> list) {
    var maxVal = list[0];
    var maxIndex = 0;
    for (var i = 1; i < list.length; i++) {
      if (list[i] > maxVal) {
        maxVal = list[i];
        maxIndex = i;
      }
    }
    return maxIndex;
  }

  /// Obține WEIGHTED ensemble V2 pentru un timeframe specific
  /// Folosește: Primar 50%, Secundar 30%, Terțiar 20%
  Future<CryptoPrediction?> getV2WeightedEnsemblePrediction({
    required String coin,
    required String symbol,
    required String targetTimeframe,
    bool silent = false,
    BaseExchangeService? exchangeService,
  }) async {
    final normalizedCoin = coin.toLowerCase().replaceAll(RegExp(r'(usd|eur|usdt|usdc)$'), '');

    // Obține ponderile pentru timeframe-ul cerut
    final weights = ensembleWeights[targetTimeframe];
    if (weights == null) {
      if (!silent) {
        debugPrint('⚠️  No ensemble weights for $targetTimeframe, using single model');
      }
      return await getPredictionV2(
        coin: coin,
        symbol: symbol,
        timeframe: targetTimeframe,
        silent: silent,
        exchangeService: exchangeService,
      );
    }

    final predictions = <String, CryptoPrediction>{};
    final availableWeights = <String, double>{};

    if (!silent) {
      debugPrint('🎯 V2 WEIGHTED ENSEMBLE for ${coin.toUpperCase()} @ $targetTimeframe');
    }

    // Colectează predicții pentru fiecare timeframe din ensemble
    for (final config in weights) {
      final tf = config['timeframe'] as String;
      final weight = config['weight'] as double;

      final pred = await getPredictionV2(
        coin: normalizedCoin,
        symbol: symbol,
        timeframe: tf,
        silent: true, // Silent pentru sub-predicții
        exchangeService: exchangeService,
      );

      if (pred != null) {
        predictions[tf] = pred;
        availableWeights[tf] = weight;
        if (!silent) {
          debugPrint('   ✓ ${normalizedCoin}_${tf}_v2: ${pred.action} (${(pred.confidence * 100).toStringAsFixed(1)}%) - weight: ${(weight * 100).toInt()}%');
        }
      } else {
        if (!silent) {
          debugPrint('   ✗ ${normalizedCoin}_${tf}_v2: NOT AVAILABLE');
        }
      }
    }

    if (predictions.isEmpty) {
      return null;
    }

    // Dacă avem doar 1 model, returnează-l direct
    if (predictions.length == 1) {
      final singlePred = predictions.values.first;
      return CryptoPrediction(
        action: singlePred.action,
        confidence: singlePred.confidence,
        probabilities: singlePred.probabilities,
        signalStrength: singlePred.signalStrength,
        modelAccuracy: singlePred.modelAccuracy,
        timestamp: DateTime.now(),
        isEnsemble: false,
        decisionReason: 'AI analysis based on technical indicators and patterns',
      );
    }

    // Normalizează ponderile pentru modelele disponibile
    final totalWeight = availableWeights.values.reduce((a, b) => a + b);
    final normalizedWeights = <String, double>{};
    for (final entry in availableWeights.entries) {
      normalizedWeights[entry.key] = entry.value / totalWeight;
    }

    if (!silent) {
      debugPrint('   📊 Normalized weights: ${normalizedWeights.entries.map((e) => '${e.key}=${(e.value * 100).toInt()}%').join(', ')}');
    }

    // Calculează probabilitățile ponderate
    final weightedProb = {'SELL': 0.0, 'HOLD': 0.0, 'BUY': 0.0};
    var weightedConfidence = 0.0;
    var weightedSignalStrength = 0.0;

    for (final entry in predictions.entries) {
      final tf = entry.key;
      final pred = entry.value;
      final weight = normalizedWeights[tf]!;

      weightedProb['SELL'] = weightedProb['SELL']! + pred.probabilities['SELL']! * weight;
      weightedProb['HOLD'] = weightedProb['HOLD']! + pred.probabilities['HOLD']! * weight;
      weightedProb['BUY'] = weightedProb['BUY']! + pred.probabilities['BUY']! * weight;

      weightedConfidence += pred.confidence * weight;
      weightedSignalStrength += pred.signalStrength * weight;
    }

    // Determină acțiunea finală
    var finalAction = 'HOLD';
    var maxProb = 0.0;
    weightedProb.forEach((action, prob) {
      if (prob > maxProb) {
        maxProb = prob;
        finalAction = action;
      }
    });

    // Verifică consensus-ul (dacă toate modelele zic la fel, boost confidence)
    final actions = predictions.values.map((p) => p.action).toSet();
    final hasConsensus = actions.length == 1;

    if (hasConsensus) {
      weightedConfidence = (weightedConfidence * 1.1).clamp(0.30, 0.95); // +10% pentru consensus
      if (!silent) {
        debugPrint('   🤝 CONSENSUS: All ${predictions.length} models agree on $finalAction (+10% confidence boost)');
      }
    }

    if (!silent) {
      final usedModels = predictions.keys.map((tf) => '${normalizedCoin}_${tf}_v2').join('+');
      debugPrint('✅ V2 WEIGHTED ENSEMBLE RESULT: $finalAction (${(weightedConfidence * 100).toStringAsFixed(1)}%) from ${predictions.length} models ($usedModels)');
    }

    return CryptoPrediction(
      action: finalAction,
      confidence: weightedConfidence.clamp(0.30, 0.95),
      probabilities: weightedProb,
      signalStrength: weightedSignalStrength,
      modelAccuracy: 0.58,
      timestamp: DateTime.now(),
      isEnsemble: true,
      decisionReason: 'Multi-timeframe AI ensemble combining ${predictions.length} models for optimal accuracy',
    );
  }

  /// Obține ensemble V2 simplu (legacy) pentru toate timeframe-urile disponibile
  Future<CryptoPrediction?> getV2EnsemblePrediction({
    required String coin,
    required String symbol,
    bool silent = false,
    BaseExchangeService? exchangeService,
  }) async {
    // Folosește weighted ensemble cu 4h ca target default
    return await getV2WeightedEnsemblePrediction(
      coin: coin,
      symbol: symbol,
      targetTimeframe: '4h',
      silent: silent,
      exchangeService: exchangeService,
    );
  }

  /// Verifică dacă un model V2 este încărcat
  bool isModelLoaded(String coin, String timeframe) {
    final key = '${coin.toLowerCase()}_${timeframe}_v2';
    return _interpreters.containsKey(key);
  }

  /// Numărul de modele V2 încărcate
  int get loadedModelsCount => _interpreters.length;

  /// Lista de modele V2 încărcate
  List<String> get loadedModels => _interpreters.keys.toList();

  /// Cleanup
  void dispose() {
    for (final interpreter in _interpreters.values) {
      interpreter.close();
    }
    _interpreters.clear();
    _scalers.clear();
  }
}

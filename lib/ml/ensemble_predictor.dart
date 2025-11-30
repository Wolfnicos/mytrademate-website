import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'crypto_ml_service.dart';

/// Ensemble Predictor for MyTradeMate
///
/// Uses per-coin specialized AI models trained on each cryptocurrency
/// - Per-coin models: Specialized 27MB models trained individually for BTC, ETH, BNB, SOL, WLFI, TRUMP
///
/// Input: 60 timesteps × 76 features (25 candle patterns + 51 technical indicators)
/// Output: 5-class probabilities [STRONG_SELL, SELL, HOLD, BUY, STRONG_BUY]
///
/// Example:
/// ```dart
/// final predictor = EnsemblePredictor();
/// await predictor.loadModels();
///
/// final prediction = await predictor.predict(featureMatrix, symbol: 'BTC/USDT');
/// print(prediction.label); // "BUY"
/// print(prediction.confidence); // 0.78
/// ```
class EnsemblePredictor {
  // Per-coin model interpreters (specialized for each cryptocurrency, 27MB each)
  final Map<String, Interpreter?> _perCoinModels = {
    'BTC': null,
    'ETH': null,
    'BNB': null,
    'SOL': null,
    'WLFI': null,
    'TRUMP': null,
  };

  // Legacy fallback models (deprecated, kept for backward compatibility)
  // Interpreter? _transformerModel; // Unused - commented out
  // Interpreter? _lstmModel; // Unused - commented out
  Interpreter? _legacyTcnModel;

  // Model weights
  // Per-coin models: 100% (specialized knowledge for each coin)
  // static const double _perCoinWeight = 1.0; // Unused - commented out

  // Model load status
  bool _isLoaded = false;
  final Map<String, bool> _modelStatus = {
    'transformer': false,
    'lstm': false,
    'randomForest': false,
  };

  // Performance metrics
  final Map<String, double> _modelLatency = {};
  final Map<String, int> _modelErrors = {};
  bool _useLegacyFallback = false;

  // Class labels (5 classes to match training)
  static const List<String> _classLabels = [
    'STRONG_SELL', // 0
    'SELL', // 1
    'HOLD', // 2
    'BUY', // 3
    'STRONG_BUY', // 4
  ];

  /// Load all ensemble models
  ///
  /// Loads per-coin specialized models.
  /// Falls back gracefully if some models are missing.
  Future<void> loadModels() async {
    // Skip ML initialization on Windows (TFLite not supported without manual setup)
    if (Platform.isWindows) {
      debugPrint('⚠️ ML disabled on Windows - TensorFlow Lite not available');
      debugPrint('   Portfolio tracking, charts, and all other features will work normally');
      _isLoaded = true; // Mark as loaded to prevent errors
      return;
    }

    // RELEASE MODE LOGGING - use print() instead of debugPrint()
    // ignore: avoid_print
    print('🤖 [RELEASE LOG] Loading ensemble models...');
    debugPrint('🤖 Loading ensemble models...');

    // Legacy models commented out for potential future use
    // try {
    //   // Load Transformer
    //   await _loadTransformerModel();
    // } catch (e) {
    //   debugPrint('⚠️ Failed to load Transformer: $e');
    // }

    // try {
    //   // Load LSTM
    //   await _loadLstmModel();
    // } catch (e) {
    //   debugPrint('⚠️ Failed to load LSTM: $e');
    // }

    try {
      // Load Random Forest (optional, can use rule-based fallback)
      await _loadRandomForestModel();
    } catch (e) {
      debugPrint('⚠️ Failed to load Random Forest: $e (will use fallback)');
    }

    try {
      // Load per-coin models (BTC, ETH, BNB, SOL, WLFI, TRUMP)
      await _loadPerCoinModels();
    } catch (e) {
      debugPrint('⚠️ Failed to load per-coin models: $e');
    }

    // Check if at least one model type loaded
    final perCoinLoaded = _perCoinModels.values.any((model) => model != null);
    _isLoaded = perCoinLoaded || _modelStatus.values.any((status) => status);

    if (!_isLoaded) {
      throw Exception('❌ No models loaded! Ensure TFLite models exist in assets/models/ and assets/ml/');
    }

    // Load legacy fallback if new models fail
    if (!_isLoaded) {
      debugPrint('⚠️ New models failed, loading legacy TCN fallback...');
      try {
        await _loadLegacyTcnModel();
        _useLegacyFallback = true;
        _isLoaded = true;
      } catch (e) {
        debugPrint('❌ Legacy fallback also failed: $e');
      }
    }

    debugPrint('');
    debugPrint('✅ ========================================');
    debugPrint('✅ Ensemble models loaded summary:');
    debugPrint('✅ ========================================');
    debugPrint('   Per-Coin Models (100% weight):');
    _perCoinModels.forEach((coin, model) {
      debugPrint('      $coin: ${model != null ? "✅ LOADED (27MB specialized)" : "❌ NOT LOADED"}');
    });
    debugPrint('✅ ========================================');
    if (_useLegacyFallback) {
      debugPrint('   💡 Using Legacy TCN Fallback');
    }
    debugPrint('');
  }

  // /// Load Transformer model - UNUSED, commented out
  // Future<void> _loadTransformerModel() async {
  //   _transformerModel = await Interpreter.fromAsset('assets/models/transformer_crypto_model.tflite');
  //   _modelStatus['transformer'] = true;
  //   debugPrint('   ✅ Transformer loaded (40.77% accuracy on 76 features)');
  // }

  // /// Load LSTM model - UNUSED, commented out
  // Future<void> _loadLstmModel() async {
  //   try {
  //     // LSTM uses Flex ops - try loading directly first
  //     _lstmModel = await Interpreter.fromAsset('assets/models/lstm_crypto_model.tflite');
  //     _modelStatus['lstm'] = true;
  //     debugPrint('   ✅ LSTM loaded (trained on 76 features)');
  //   } catch (e) {
  //     // If loading fails, try with options
  //     try {
  //       debugPrint('   ⚠️ LSTM direct load failed, trying with options...');
  //       final options = InterpreterOptions()..threads = 2;
  //       _lstmModel = await Interpreter.fromAsset(
  //         'assets/models/lstm_crypto_model.tflite',
  //         options: options,
  //       );
  //       _modelStatus['lstm'] = true;
  //       debugPrint('   ✅ LSTM loaded (with options)');
  //     } catch (e2) {
  //       debugPrint('   ❌ LSTM load failed completely: $e2');
  //       rethrow;
  //     }
  //   }
  // }

  /// Load Random Forest model (if available as TFLite)
  Future<void> _loadRandomForestModel() async {
    // Note: Random Forest usually saved as .pkl (scikit-learn)
    // For mobile, we either:
    // 1. Convert to TFLite (if using TensorFlow Decision Forests)
    // 2. Use a fallback rule-based approach
    // 3. Implement lightweight RF in Dart

    // For now, use fallback (mark as not loaded)
    _modelStatus['randomForest'] = false;
    debugPrint('   ⚠️ Random Forest: Using rule-based fallback');
  }

  /// Load legacy TCN model as fallback
  Future<void> _loadLegacyTcnModel() async {
    _legacyTcnModel = await Interpreter.fromAsset('assets/models/legacy/mytrademate_v8_tcn_mtf_float32.tflite');
    debugPrint('   ✅ Legacy TCN loaded (v8)');
  }

  /// Load per-coin specialized models
  Future<void> _loadPerCoinModels() async {
    debugPrint('');
    debugPrint('🪙 ========================================');
    debugPrint('🪙 Loading per-coin specialized models');
    debugPrint('🪙 Location: assets/models/');
    debugPrint('🪙 ========================================');

    for (var entry in _perCoinModels.keys) {
      try {
        final coinLower = entry.toLowerCase();
        final modelPath = 'assets/models/${coinLower}_model.tflite';
        // ignore: avoid_print
        print('🪙 [RELEASE LOG] [$entry] Loading: $modelPath');
        debugPrint('');
        debugPrint('🪙 [$entry] Attempting to load: $modelPath');

        _perCoinModels[entry] = await Interpreter.fromAsset(modelPath);

        // ignore: avoid_print
        print('🪙 [RELEASE LOG] [$entry] ✅ SUCCESS');
        debugPrint('   ✅ $entry model loaded successfully!');
        debugPrint('   📊 Model: Per-coin specialized');
        debugPrint('   📏 Size: ~27MB');
        debugPrint('   🎯 Input: [1, 60, 76] -> Output: [1, 3] (SELL, HOLD, BUY)');
      } catch (e) {
        // ignore: avoid_print
        print('🪙 [RELEASE LOG] [$entry] ❌ FAILED: $e');
        debugPrint('');
        debugPrint('   ❌ $entry model NOT FOUND!');
        debugPrint('   ⚠️  Error: $e');
        debugPrint('   💡 Will fallback to general ensemble models');
        _perCoinModels[entry] = null;
      }
    }

    debugPrint('');
    debugPrint('🪙 ========================================');
    debugPrint('🪙 Per-coin models loading summary:');
    debugPrint('🪙 ========================================');
    _perCoinModels.forEach((coin, model) {
      debugPrint('   $coin: ${model != null ? "✅ LOADED (specialized 27MB model)" : "❌ NOT LOADED (will use ensemble fallback)"}');
    });
    debugPrint('🪙 ========================================');
    debugPrint('');
  }

  /// Predict using per-coin specialized model
  ///
  /// Args:
  ///   features: [60, 76] feature matrix (60 timesteps × 76 features)
  ///   symbol: Trading pair symbol (e.g., 'BTC/USDT', 'BTCEUR') to select per-coin model
  ///
  /// Returns:
  ///   EnsemblePrediction with per-coin model probabilities (100% weight)
  Future<EnsemblePrediction> predict(List<List<double>> features, {String? symbol, String? timeframe}) async {
    if (!_isLoaded) {
      throw Exception('Models not loaded. Call loadModels() first.');
    }

    // Validate input shape
    if (features.length != 60 || features[0].length != 76) {
      throw Exception('Invalid input shape: ${features.length}x${features[0].length}. Expected 60x76 (60 timesteps × 76 features)');
    }

    debugPrint('✅ Input shape validated: ${features.length}x${features[0].length}');

    // Extract coin symbol (BTC, ETH, etc.) from trading pair
    String? coinSymbol;
    if (symbol != null) {
      // Handle formats like 'BTC/USDT', 'BTCEUR', 'BTCUSDT'
      coinSymbol = symbol.replaceAll('/', '').replaceAll('USDT', '').replaceAll('EUR', '').toUpperCase();
      // Take first part if still has slash
      if (coinSymbol.contains('/')) {
        coinSymbol = coinSymbol.split('/')[0];
      }
      debugPrint('🪙 Using per-coin model for: $coinSymbol (from $symbol)');
    }

    // Try NEW assets/ml models first via CryptoMLService (3-class -> map to 5-class)
    final fromNewModels = await _predictNewModel(features, coinSymbol, timeframe);

    // If new models not available, fall back to per-coin specialized models
    final perCoinProbs = fromNewModels ?? await _predictPerCoin(features, coinSymbol);
    // Legacy models commented out
    // final transformerProbs = await _predictTransformer(features);
    // final lstmProbs = await _predictLstm(features);
    final rfProbs = await _predictRandomForest(features);

    // 🔍 DEBUG: Print raw model outputs
    debugPrint('🔍 RAW MODEL OUTPUTS:');
    debugPrint('   Per-Coin ($coinSymbol): [${perCoinProbs.map((p) => (p * 100).toStringAsFixed(1)).join(', ')}]');
    debugPrint('   RF: [${rfProbs.map((p) => (p * 100).toStringAsFixed(1)).join(', ')}]');

    // Use Per-Coin model directly (100% weight)
    final ensembleProbs = perCoinProbs;

    // 🔍 DEBUG: Print final result
    debugPrint('🔍 FINAL RESULT: [${ensembleProbs.map((p) => (p * 100).toStringAsFixed(1)).join(', ')}]');

    // Get final prediction
    final maxIndex = ensembleProbs.indexOf(ensembleProbs.reduce((a, b) => a > b ? a : b));
    final confidence = ensembleProbs[maxIndex];

    debugPrint('🔍 PREDICTION: ${_classLabels[maxIndex]} (${(confidence * 100).toStringAsFixed(1)}%)');

    return EnsemblePrediction(
      label: _classLabels[maxIndex],
      classIndex: maxIndex,
      confidence: confidence,
      probabilities: ensembleProbs,
      modelContributions: {
        fromNewModels != null ? 'newModels_${coinSymbol ?? "GEN"}' : 'perCoin_$coinSymbol': perCoinProbs,
        'randomForest': rfProbs,
      },
    );
  }

  /// Try prediction using the new multi-coin/timeframe models (assets/ml)
  /// Returns 5-class probabilities if successful; otherwise null to signal fallback
  Future<List<double>?> _predictNewModel(List<List<double>> features, String? coinSymbol, String? timeframe, {String? symbol}) async {
    try {
      final coin = (coinSymbol ?? 'general').toLowerCase();
      // Normalize timeframe to available ones in assets/ml
      final tf = (timeframe ?? '1h').toLowerCase();
      // Map timeframes: 1w -> 7d, 4h -> 1h, keep 15m/5m/1h/1d/7d as-is
      String tfNorm;
      if (tf == '1w' || tf == '7d') {
        tfNorm = '7d';  // Weekly uses 7-day model
      } else if (tf == '1d') {
        tfNorm = '1d';  // Daily uses 1-day model
      } else if (tf == '4h') {
        tfNorm = '1h';  // 4h uses 1h model
      } else if (tf == '15m' || tf == '5m' || tf == '1h') {
        tfNorm = tf;    // Short-term uses exact timeframe
      } else {
        tfNorm = '1h';  // Default fallback
      }

      debugPrint('🧠 Trying NEW ML model: coin=$coinSymbol tf=$tf -> tfNorm=$tfNorm');
      if (tf != tfNorm) {
        debugPrint('   ⚠️ Timeframe mapped: $tf → $tfNorm (closest available model)');
      }

      // NEW: Need symbol for multi-timeframe fetch
      if (symbol == null) {
        debugPrint('   ⚠️ Symbol not provided, cannot use new multi-timeframe architecture');
        return null;
      }

      final prediction = await CryptoMLService().getPrediction(
        coin: coin,
        symbol: symbol,
        timeframe: tfNorm,
      );

      final sell = prediction.probabilities['SELL'] ?? 0.0;
      final hold = prediction.probabilities['HOLD'] ?? 0.0;
      final buy = prediction.probabilities['BUY'] ?? 0.0;

      // Check if this is a binary model (long-term: 1d/7d) or ternary (short-term: 5m/15m/1h)
      final isBinary = (tfNorm == '1d' || tfNorm == '7d') && hold < 0.01;

      if (isBinary) {
        // Binary model (DOWN/UP) - return as-is for binary predictions
        // DOWN=probabilities[0], UP=probabilities[1]
        // For the UI to display correctly, we return the raw binary probabilities
        debugPrint('🧠 BINARY ML result (2-class): DOWN=${(sell * 100).toStringAsFixed(1)}%, UP=${(buy * 100).toStringAsFixed(1)}%');
        // Return 2-element list for binary models
        return [sell, buy];
      } else {
        // Ternary model (SELL/HOLD/BUY) - map 3-class to 5-class
        double strongSell, normalSell, normalBuy, strongBuy;
        if (sell > 0.6) {
          strongSell = sell * 0.5;
          normalSell = sell * 0.5;
        } else {
          strongSell = sell * 0.2;
          normalSell = sell * 0.8;
        }
        if (buy > 0.6) {
          strongBuy = buy * 0.5;
          normalBuy = buy * 0.5;
        } else {
          strongBuy = buy * 0.2;
          normalBuy = buy * 0.8;
        }

        final result = [strongSell, normalSell, hold, normalBuy, strongBuy];
        debugPrint('🧠 TERNARY ML result (5-class): [${result.map((p) => (p * 100).toStringAsFixed(1)).join(', ')}]');
        return result;
      }
    } catch (e) {
      debugPrint('⚠️ NEW ML prediction unavailable → $e');
      return null;
    }
  }

  // Legacy Transformer and LSTM models (commented out for potential future use)
  // /// Predict using Transformer model
  // Future<List<double>> _predictTransformer(List<List<double>> features) async {
  //   if (_transformerModel == null || !_modelStatus['transformer']!) {
  //     return [0.2, 0.2, 0.2, 0.2, 0.2]; // Neutral if model not loaded (5 classes)
  //   }

  //   final startTime = DateTime.now();
  //   try {
  //     // Reshape input: [1, 60, 76]
  //     var input = [features];

  //     // Output buffer: [1, 5] (5 classes: STRONG_SELL, SELL, HOLD, BUY, STRONG_BUY)
  //     var output = List.generate(1, (_) => List.filled(5, 0.0));

  //     // Run inference
  //     _transformerModel!.run(input, output);

  //     // Track latency
  //     final latency = DateTime.now().difference(startTime).inMilliseconds;
  //     _modelLatency['transformer'] = latency.toDouble();

  //     return List<double>.from(output[0]);
  //   } catch (e) {
  //     debugPrint('⚠️ Transformer inference failed: $e');
  //     _modelErrors['transformer'] = (_modelErrors['transformer'] ?? 0) + 1;
  //     return [0.2, 0.2, 0.2, 0.2, 0.2];
  //   }
  // }

  // /// Predict using LSTM model
  // Future<List<double>> _predictLstm(List<List<double>> features) async {
  //   if (_lstmModel == null || !_modelStatus['lstm']!) {
  //     return [0.2, 0.2, 0.2, 0.2, 0.2]; // Neutral if model not loaded (5 classes)
  //   }

  //   final startTime = DateTime.now();
  //   try {
  //     // Reshape input: [1, 60, 76]
  //     var input = [features];

  //     // Output buffer: [1, 5] (5 classes)
  //     var output = List.generate(1, (_) => List.filled(5, 0.0));

  //     // Run inference
  //     _lstmModel!.run(input, output);

  //     // Track latency
  //     final latency = DateTime.now().difference(startTime).inMilliseconds;
  //     _modelLatency['lstm'] = latency.toDouble();

  //     return List<double>.from(output[0]);
  //   } catch (e) {
  //     debugPrint('⚠️ LSTM inference failed: $e');
  //     _modelErrors['lstm'] = (_modelErrors['lstm'] ?? 0) + 1;
  //     return [0.2, 0.2, 0.2, 0.2, 0.2];
  //   }
  // }

  /// Extract coin symbol from trading pair (BTC from BTC/USDT, BTCUSDT, etc.)
  String _extractCoinSymbol(String symbol) {
    // Handle formats like 'BTC/USDT', 'BTCEUR', 'BTCUSDT'
    String coinSymbol = symbol.replaceAll('/', '').replaceAll('USDT', '').replaceAll('EUR', '').toUpperCase();
    // Take first part if still has slash
    if (coinSymbol.contains('/')) {
      coinSymbol = coinSymbol.split('/')[0];
    }
    return coinSymbol;
  }

  /// Predict using per-coin specialized model
  ///
  /// Per-coin models output 3 classes [SELL, HOLD, BUY]
  /// This method maps them to 5 classes [STRONG_SELL, SELL, HOLD, BUY, STRONG_BUY]
  Future<List<double>> _predictPerCoin(List<List<double>> features, String? coinSymbol) async {
    debugPrint('');
    debugPrint('🪙 === PER-COIN MODEL PREDICTION ===');
    debugPrint('🪙 Coin Symbol: $coinSymbol');

    // If no coin symbol or model not available, return neutral
    if (coinSymbol == null) {
      debugPrint('⚠️ Per-coin model: No coin symbol provided!');
      debugPrint('   Using neutral probabilities: [0.0, 0.0, 1.0, 0.0, 0.0] (HOLD)');
      return [0.0, 0.0, 1.0, 0.0, 0.0]; // HOLD
    }

    final coin = _extractCoinSymbol(coinSymbol);
    final model = _perCoinModels[coin];

    if (model == null) {
      debugPrint('⚠️ Per-coin model for $coin not available!');
      debugPrint('   Reason: Model not loaded');
      debugPrint('   Using neutral probabilities: [0.0, 0.0, 1.0, 0.0, 0.0] (HOLD)');
      return [0.0, 0.0, 1.0, 0.0, 0.0]; // HOLD
    }
    final startTime = DateTime.now();
    debugPrint('✅ $coin model is loaded!');
    debugPrint('📥 Input shape: [1, ${features.length}, ${features[0].length}]');

    try {
      // Reshape input: [1, 60, 76]
      var input = [features];

      // Output buffer: [1, 3] for 3-class models (SELL, HOLD, BUY)
      var output = List.generate(1, (_) => List.filled(3, 0.0));

      debugPrint('🔄 Running inference on $coin model...');

      // Run inference
      model.run(input, output);

      // Track latency
      final latency = DateTime.now().difference(startTime).inMilliseconds;
      _modelLatency['perCoin_$coin'] = latency.toDouble();

      debugPrint('⏱️  Inference time: ${latency}ms');

      // Convert 3-class [SELL, HOLD, BUY] to 5-class [STRONG_SELL, SELL, HOLD, BUY, STRONG_BUY]
      final sell = output[0][0];
      final hold = output[0][1];
      final buy = output[0][2];

      debugPrint('📊 Raw 3-class output:');
      debugPrint('   SELL: ${(sell * 100).toStringAsFixed(2)}%');
      debugPrint('   HOLD: ${(hold * 100).toStringAsFixed(2)}%');
      debugPrint('   BUY:  ${(buy * 100).toStringAsFixed(2)}%');

      // Map 3-class to 5-class:
      // - High SELL probability (>0.6) -> split between STRONG_SELL and SELL
      // - Low-medium SELL (<0.6) -> mostly SELL
      // - HOLD stays as HOLD
      // - High BUY probability (>0.6) -> split between BUY and STRONG_BUY
      // - Low-medium BUY (<0.6) -> mostly BUY
      double strongSell, normalSell, normalBuy, strongBuy;

      if (sell > 0.6) {
        strongSell = sell * 0.5;
        normalSell = sell * 0.5;
        debugPrint('🔴 High SELL probability -> splitting to STRONG_SELL + SELL');
      } else {
        strongSell = sell * 0.2;
        normalSell = sell * 0.8;
        debugPrint('🟠 Normal SELL probability -> mostly SELL');
      }

      if (buy > 0.6) {
        strongBuy = buy * 0.5;
        normalBuy = buy * 0.5;
        debugPrint('🟢 High BUY probability -> splitting to BUY + STRONG_BUY');
      } else {
        strongBuy = buy * 0.2;
        normalBuy = buy * 0.8;
        debugPrint('🟡 Normal BUY probability -> mostly BUY');
      }

      final result = [strongSell, normalSell, hold, normalBuy, strongBuy];

      debugPrint('📊 Mapped to 5-class output:');
      debugPrint('   STRONG_SELL: ${(strongSell * 100).toStringAsFixed(2)}%');
      debugPrint('   SELL:        ${(normalSell * 100).toStringAsFixed(2)}%');
      debugPrint('   HOLD:        ${(hold * 100).toStringAsFixed(2)}%');
      debugPrint('   BUY:         ${(normalBuy * 100).toStringAsFixed(2)}%');
      debugPrint('   STRONG_BUY:  ${(strongBuy * 100).toStringAsFixed(2)}%');

      return result;
    } catch (e) {
      debugPrint('❌ Per-coin ($coin) inference FAILED!');
      debugPrint('   Error: $e');
      _modelErrors['perCoin_$coin'] = (_modelErrors['perCoin_$coin'] ?? 0) + 1;
      return [0.0, 0.0, 1.0, 0.0, 0.0]; // HOLD
    }
  }

  /// Predict using Random Forest (fallback rule-based)
  ///
  /// Uses technical indicators from the 76-feature vector
  Future<List<double>> _predictRandomForest(List<List<double>> features) async {
    // Fallback: Simple rule-based prediction using 76-feature vector
    // Feature indices (from Python training):
    // 30-32: RSI (rsi, rsi_oversold, rsi_overbought)
    // 33-37: MACD (macd, macd_signal, macd_histogram, macd_cross_above, macd_cross_below)
    // 73-75: Trend (higher_high, lower_low, uptrend, downtrend)

    // Get features from MIDDLE of sequence
    final midIdx = features.length ~/ 2;
    final midTimestep = features[midIdx];

    // Extract key indicators (these are RAW values, not normalized 0-1)
    final rsi = midTimestep[30];  // RSI (0-100)
    final macd = midTimestep[33]; // MACD (can be negative)
    final uptrend = midTimestep[74]; // Uptrend indicator (0 or 1)

    // 🔍 DEBUG: Print RF inputs
    debugPrint('🔍 RF INPUTS: RSI=$rsi, MACD=$macd, Uptrend=$uptrend');

    // Simple rules using RAW values
    double strongSellProb = 0.0;
    double sellProb = 0.0;
    double holdProb = 0.2; // Base hold probability
    double buyProb = 0.0;
    double strongBuyProb = 0.0;

    // RSI logic (0-100 scale)
    if (rsi < 30) {
      strongBuyProb += 0.4; // Oversold
      buyProb += 0.2;
    } else if (rsi > 70) {
      strongSellProb += 0.4; // Overbought
      sellProb += 0.2;
    } else {
      holdProb += 0.3; // Neutral RSI -> hold
    }

    // MACD logic (positive = bullish, negative = bearish)
    if (macd > 0) {
      buyProb += 0.3;
      strongBuyProb += 0.2;
    } else {
      sellProb += 0.3;
      strongSellProb += 0.2;
    }

    // Trend logic (binary: 1 = uptrend, 0 = downtrend)
    if (uptrend > 0.5) {
      // Uptrend - favor buys
      buyProb += 0.2;
      strongBuyProb += 0.1;
    } else {
      // Downtrend - favor sells
      sellProb += 0.2;
      strongSellProb += 0.1;
    }

    // Normalize
    final total = strongSellProb + sellProb + holdProb + buyProb + strongBuyProb;
    if (total > 0) {
      strongSellProb /= total;
      sellProb /= total;
      holdProb /= total;
      buyProb /= total;
      strongBuyProb /= total;
    } else {
      // Fallback to neutral
      strongSellProb = sellProb = holdProb = buyProb = strongBuyProb = 0.2;
    }

    return [strongSellProb, sellProb, holdProb, buyProb, strongBuyProb];
  }


  /// Check if models are loaded
  bool get isLoaded => _isLoaded;

  /// Get number of loaded models
  int get loadedModelsCount => _perCoinModels.values.where((m) => m != null).length;

  /// Get model load status
  Map<String, bool> get modelStatus => _modelStatus;

  /// Get model performance metrics (latency in ms)
  Map<String, double> get modelLatency => Map.unmodifiable(_modelLatency);

  /// Get model error counts
  Map<String, int> get modelErrors => Map.unmodifiable(_modelErrors);

  /// Check if using legacy fallback
  bool get isUsingLegacyFallback => _useLegacyFallback;

  /// Get performance summary
  String get performanceSummary {
    if (_modelLatency.isEmpty) return 'No metrics yet';

    final buffer = StringBuffer('📊 Model Performance:\n');
    _modelLatency.forEach((model, latency) {
      final errors = _modelErrors[model] ?? 0;
      buffer.writeln('   $model: ${latency.toStringAsFixed(0)}ms (errors: $errors)');
    });
    return buffer.toString();
  }


  /// Dispose interpreters
  void dispose() {
    // Legacy models (commented out but kept for potential future use)
    // _transformerModel?.close();
    // _lstmModel?.close();
    _legacyTcnModel?.close();

    // Dispose per-coin models
    for (var entry in _perCoinModels.entries) {
      entry.value?.close();
    }

    debugPrint('🧹 Ensemble models disposed');
    debugPrint(performanceSummary);
  }
}

/// Ensemble prediction result
class EnsemblePrediction {
  final String label; // "STRONG_SELL", "SELL", "BUY", "STRONG_BUY"
  final int classIndex; // 0, 1, 2, 3
  final double confidence; // 0.0 to 1.0
  final List<double> probabilities; // [p(STRONG_SELL), p(SELL), p(BUY), p(STRONG_BUY)]
  final Map<String, List<double>> modelContributions; // Individual model predictions

  EnsemblePrediction({
    required this.label,
    required this.classIndex,
    required this.confidence,
    required this.probabilities,
    required this.modelContributions,
  });

  /// Convert to signal type for strategy execution
  SignalType toSignalType() {
    switch (classIndex) {
      case 0: // STRONG_SELL
      case 1: // SELL
        return SignalType.sell;
      case 2: // HOLD
        return SignalType.hold;
      case 3: // BUY
      case 4: // STRONG_BUY
        return SignalType.buy;
      default:
        return SignalType.hold;
    }
  }

  /// Check if prediction is tradeable (high confidence)
  bool get isTradeable {
    // Require at least 60% confidence for trading
    return confidence >= 0.60;
  }

  /// Check if prediction is strong (STRONG_SELL or STRONG_BUY)
  bool get isStrong {
    return classIndex == 0 || classIndex == 4;
  }

  @override
  String toString() {
    return '''
=== Ensemble Prediction ===
Label: $label
Confidence: ${(confidence * 100).toStringAsFixed(1)}%
Probabilities:
  STRONG_SELL: ${(probabilities[0] * 100).toStringAsFixed(1)}%
  SELL: ${(probabilities[1] * 100).toStringAsFixed(1)}%
  HOLD: ${(probabilities[2] * 100).toStringAsFixed(1)}%
  BUY: ${(probabilities[3] * 100).toStringAsFixed(1)}%
  STRONG_BUY: ${(probabilities[4] * 100).toStringAsFixed(1)}%
Tradeable: ${isTradeable ? "YES ✅" : "NO ❌"}
''';
  }
}

/// Signal type enum (for compatibility with existing strategies)
enum SignalType {
  buy,
  sell,
  hold,
}

/// Example usage:
///
/// ```dart
/// // Initialize predictor
/// final predictor = EnsemblePredictor();
/// await predictor.loadModels();
///
/// // Build features (from MtfFeatureBuilderV2)
/// final featureBuilder = MtfFeatureBuilderV2();
/// final features = await featureBuilder.buildFeatures(
///   symbol: 'BTCUSDT',
///   base1h: candles1h,
///   low15m: candles15m,
///   high4h: candles4h,
/// );
///
/// // Get ensemble prediction
/// final prediction = await predictor.predict(features);
///
/// print(prediction);
/// // Output:
/// // === Ensemble Prediction ===
/// // Label: BUY
/// // Confidence: 78.5%
/// // Probabilities:
/// //   STRONG_SELL: 5.2%
/// //   SELL: 8.3%
/// //   BUY: 58.0%
/// //   STRONG_BUY: 28.5%
/// // Tradeable: YES ✅
///
/// if (prediction.isTradeable) {
///   // Execute trade with adaptive position sizing
///   final signal = prediction.toSignalType();
///   final positionSize = baseSize * prediction.confidence; // Scale by confidence
///
///   await executeTrade(
///     signal: signal,
///     size: positionSize,
///     confidence: prediction.confidence,
///   );
/// }
///
/// // Dispose when done
/// predictor.dispose();
/// ```

// Global singleton for convenient access from UI layers
final EnsemblePredictor globalEnsemblePredictor = EnsemblePredictor();

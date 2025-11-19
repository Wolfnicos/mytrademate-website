import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'dart:convert';
import 'dart:math' show exp, log, sqrt;
import 'package:mytrademate/services/binance_service.dart';
import 'package:mytrademate/services/base_exchange_service.dart';
import 'package:mytrademate/services/volume_profile_service.dart';
import 'package:mytrademate/ml/ensemble_weights_v2.dart';

/// Service pentru predicții ML crypto
class CryptoMLService {
  static final CryptoMLService _instance = CryptoMLService._internal();
  factory CryptoMLService() => _instance;
  static CryptoMLService get instance => _instance;
  CryptoMLService._internal();

  // Cache pentru interpretere
  final Map<String, Interpreter> _interpreters = {};

  // Cache pentru scalere
  final Map<String, Map<String, dynamic>> _scalers = {};

  // Metadata pentru modele
  final Map<String, Map<String, dynamic>> _metadata = {};

  // PHASE 3: Binance service for volume percentile
  final BinanceService _binanceService = BinanceService();

  // PHASE 4: Volume Profile service for order book analysis
  final VolumeProfileService _volumeProfileService = VolumeProfileService();

  // PHASE 3: Model registry with trained_date
  Map<String, dynamic>? _modelRegistry;

  // PHASE 3 PILOT: Feature flag for gradual rollout
  static const Set<String> _phase3EnabledCoins = {'BTC', 'ETH', 'BNB', 'SOL', 'WLFI', 'TRUMP'};
  static const Set<String> _phase3EnabledTimeframes = {'5m', '15m', '1h', '4h'};

  // PHASE 3 PILOT: Exclusions (WLFI@1d has insufficient history)
  static bool _isPhase3Enabled(String coin, String timeframe) {
    if (coin.toUpperCase() == 'WLFI' && timeframe == '1d') {
      return false; // WLFI doesn't have enough 1d history
    }
    return _phase3EnabledCoins.contains(coin.toUpperCase()) &&
           _phase3EnabledTimeframes.contains(timeframe);
  }

  /// Get best available model for a coin+timeframe with fallback logic
  /// If exact model doesn't exist (e.g., btc_4h), falls back to closest smaller timeframe
  ///
  /// Fallback hierarchy:
  /// - 4h → 1h → 15m → 5m
  /// - 1d → 4h → 1h → 15m → 5m
  /// - 1h → 15m → 5m
  /// - 15m → 5m
  /// - 5m → (no fallback)
  ///
  /// Returns: model key (e.g., "btc_1h") or null if no model found
  String? _getBestModelKey(String coin, String requestedTf) {
    final normalizedCoin = coin.toLowerCase().replaceAll(RegExp(r'(usd|eur|usdt|usdc)$'), '');

    // Define fallback chain for each timeframe
    final Map<String, List<String>> fallbackChain = {
      '1d': ['1d', '4h', '1h', '15m', '5m'],
      '4h': ['4h', '1h', '15m', '5m'],
      '1h': ['1h', '15m', '5m'],
      '15m': ['15m', '5m'],
      '5m': ['5m'],
    };

    final chain = fallbackChain[requestedTf] ?? ['1h', '15m', '5m'];

    // Try each timeframe in the fallback chain
    for (final tf in chain) {
      final modelKey = '${normalizedCoin}_$tf';
      if (_interpreters.containsKey(modelKey)) {
        if (tf != requestedTf) {
          // ignore: avoid_print
          print('   🔄 Fallback: $normalizedCoin@$requestedTf not found, using $modelKey');
        }
        return modelKey;
      }
    }

    return null; // No model found in fallback chain
  }

  // PHASE 3 PILOT: Volume percentile cache (5 min TTL)
  static final Map<String, (double, DateTime)> _volumeCache = {};
  static const Duration _volumeCacheTTL = Duration(minutes: 5);

  /// Clear volume percentile cache (useful when switching exchanges)
  static void clearVolumeCache() {
    _volumeCache.clear();
    // ignore: avoid_print
    print('🧹 Cleared volume percentile cache');
  }

  /// Inițializează serviciul și încarcă modelele
  Future<void> initialize() async {
    // ignore: avoid_print
    print('🚀 ========================================');
    // ignore: avoid_print
    print('🚀 Initializing CryptoMLService');
    // ignore: avoid_print
    print('🚀 Loading NEW multi-timeframe models from assets/ml/');
    // ignore: avoid_print
    print('🚀 ========================================');

    // Încarcă NOILE modele multi-timeframe (6 monede × 3 timeframes = 18 modele)
    const coins = ['btc', 'eth', 'bnb', 'sol', 'trump', 'wlfi'];
    const timeframes = ['5m', '15m', '1h'];

    int successCount = 0;
    int failCount = 0;

    // ignore: avoid_print
    print('📦 Loading coin-specific models...');
    for (final coin in coins) {
      for (final timeframe in timeframes) {
        final success = await loadModel(coin, timeframe);
        if (success) {
          successCount++;
        } else {
          failCount++;
        }
      }
    }

    // ignore: avoid_print
    print('');
    // ignore: avoid_print
    print('📦 Loading GENERAL models (work on ANY crypto)...');

    // Load general_5m and general_1d (FIXED with correct features)
    int generalSuccess = 0;
    int generalFail = 0;

    for (final tf in ['5m', '1d']) {
      final loaded = await loadModel('general', tf);
      if (loaded) {
        generalSuccess++;
      } else {
        generalFail++;
      }
    }

    // PHASE 3: Load model registry with trained_date
    try {
      final registryJson = await rootBundle.loadString('assets/models/model_registry.json');
      _modelRegistry = json.decode(registryJson) as Map<String, dynamic>;
      // ignore: avoid_print
      print('✅ Model registry loaded (Phase 3)');
    } catch (e) {
      // ignore: avoid_print
      print('⚠️  Failed to load model registry: $e');
    }

    // ignore: avoid_print
    print('');
    // ignore: avoid_print
    print('✅ ========================================');
    // ignore: avoid_print
    print('✅ CryptoMLService initialization complete');
    // ignore: avoid_print
    print('✅ ========================================');
    // ignore: avoid_print
    print('   Total models available: ${18 + generalSuccess}');
    // ignore: avoid_print
    print('   ✅ Coin-specific loaded: $successCount/18');
    // ignore: avoid_print
    print('   ✅ General models loaded: $generalSuccess/2 (5m, 1d)');
    // ignore: avoid_print
    print('   ✅ TOTAL loaded: ${successCount + generalSuccess}/${18 + 2}');
    // ignore: avoid_print
    print('   ❌ Failed to load: ${failCount + generalFail}');
    // ignore: avoid_print
    print('✅ ========================================');
    // ignore: avoid_print
    print('');

    if (successCount == 0) {
      // ignore: avoid_print
      print('⚠️  WARNING: No ML models loaded! Predictions will use fallback logic.');
    }
  }

  /// Încarcă un model per-coin din assets/models/ (acestea MERG!)
  Future<bool> loadPerCoinModel(String coin) async {
    final key = coin; // Folosim doar numele monedei ca key

    try {
      final modelPath = 'assets/models/${coin.toLowerCase()}_model.tflite';

      // ignore: avoid_print
      print('📦 Loading $coin model from $modelPath');

      // Încearcă mai multe configurații până găsește una care merge
      Interpreter? interpreter;

      // CONFIG 1: Cu 2 threads, fără delegate (cel mai simplu)
      try {
        final options1 = InterpreterOptions()..threads = 2;
        interpreter = await Interpreter.fromAsset(modelPath, options: options1);
        // ignore: avoid_print
        print('   ✅ $coin loaded with basic config (2 threads)');
      } catch (e1) {
        // CONFIG 2: Cu 1 thread (minimalist)
        try {
          final options2 = InterpreterOptions()..threads = 1;
          interpreter = await Interpreter.fromAsset(modelPath, options: options2);
          // ignore: avoid_print
          print('   ✅ $coin loaded with minimal config (1 thread)');
        } catch (e2) {
          // CONFIG 3: Fără opțiuni (default)
          try {
            interpreter = await Interpreter.fromAsset(modelPath);
            // ignore: avoid_print
            print('   ✅ $coin loaded with default config');
          } catch (e3) {
            // ignore: avoid_print
            print('   ❌ $coin: All load attempts failed');
            return false;
          }
        }
      }

      _interpreters[key] = interpreter;

      // Metadata pentru modelele per-coin (76 features, 3 classes)
      _metadata[key] = {
        'coin': coin.toUpperCase(),
        'num_features': 76,
        'num_classes': 3,
        'sequence_length': 60,
      };

      // Scaler default (modelele per-coin sunt deja normalizate)
      _scalers[key] = {
        'mean': List<double>.filled(76, 0.0),
        'std': List<double>.filled(76, 1.0),
      };

      // ignore: avoid_print
      print('   📊 $coin: 60x76 -> 3 classes (SELL, HOLD, BUY)');
      return true;
    } catch (e) {
      // ignore: avoid_print
      print('   ❌ Error loading $coin: $e');
      return false;
    }
  }

  /// Încarcă un model specific
  Future<bool> loadModel(String coin, String timeframe) async {
    final key = '${coin}_$timeframe';

    try {
      // NOILE modele sunt în assets/ml/ cu format: {coin}_{timeframe}_model.tflite
      final coinLower = coin.toLowerCase();

      // 1. Încarcă modelul TFLite
      // General models: assets/ml/general_5m.tflite (no _model suffix)
      // Coin-specific models: assets/ml/btc_5m_model.tflite (with _model suffix)
      final modelPath = coin == 'general'
          ? 'assets/ml/general_$timeframe.tflite'
          : 'assets/ml/${coinLower}_${timeframe}_model.tflite';

      // ignore: avoid_print
      print('📦 Loading $coin $timeframe from $modelPath');

      // Încearcă cu Select TF Ops enabled (pentru LSTM/GRU support)
      Interpreter? interpreter;

      try {
        // Verifică dacă fișierul există în asset bundle
        try {
          await rootBundle.load(modelPath);
          // ignore: avoid_print
          print('   📁 Asset file exists in bundle');
        } catch (assetError) {
          // ignore: avoid_print
          print('   ❌ Asset NOT found in bundle: $assetError');
          return false;
        }

        // Încearcă FĂRĂ opțiuni (pentru a evita delegate issues)
        interpreter = await Interpreter.fromAsset(modelPath);
        // ignore: avoid_print
        print('   ✅ Loaded with Select TF Ops support');
      } catch (e) {
        // ignore: avoid_print
        print('   ❌ Failed to load interpreter: $e');
        return false;
      }

      _interpreters[key] = interpreter;

      // 2. Încarcă metadata
      final metadataPath = coin == 'general'
          ? 'assets/ml/general_${timeframe}_metadata.json'
          : 'assets/ml/${coinLower}_${timeframe}_metadata.json';
      final metadataString = await rootBundle.loadString(metadataPath);
      final decoded = json.decode(metadataString) as Map<String, dynamic>;
      _metadata[key] = decoded;

      // 3. Încarcă scaler din JSON (FIX: nu mai folosim identity scaler!)
      final expectedLen = (_metadata[key]?['num_features'] as num?)?.toInt() ?? 76;
      final scalerPath = _metadata[key]?['scaler_path'] as String? ??
          (coin == 'general'
              ? 'general_${timeframe}_scaler.json'
              : '${coinLower}_${timeframe}_scaler.json');

      try {
        final scalerString = await rootBundle.loadString('assets/ml/$scalerPath');
        final scalerData = json.decode(scalerString) as Map<String, dynamic>;
        _scalers[key] = {
          'mean': (scalerData['mean'] as List).cast<double>(),
          'std': (scalerData['std'] as List).cast<double>(),
        };
        // ignore: avoid_print
        print('   📊 Loaded scaler: ${_scalers[key]!['mean']!.length} features (mean[0]=${_scalers[key]!['mean']![0].toStringAsFixed(4)}, std[0]=${_scalers[key]!['std']![0].toStringAsFixed(4)})');
      } catch (e) {
        // ignore: avoid_print
        print('   ⚠️  Could not load scaler from $scalerPath, using identity: $e');
        _scalers[key] = {
          'mean': List<double>.filled(expectedLen, 0.0),
          'std': List<double>.filled(expectedLen, 1.0),
        };
      }

      final acc = (decoded['test_accuracy'] as num?)?.toDouble() ?? 0.0;
      // ignore: avoid_print
      print('   ✅ $coin $timeframe loaded - Accuracy: ${(acc * 100).toStringAsFixed(1)}%');
      return true;
    } catch (e) {
      // ignore: avoid_print
      print('   ❌ Error loading $coin $timeframe: $e');
      return false;
    }
  }

  /// Obține predicția pentru o monedă (MULTI-TIMEFRAME WEIGHTED ENSEMBLE)
  /// NOW fetches candles for EACH model's timeframe!
  Future<CryptoPrediction> getPrediction({
    required String coin,
    required String symbol, // NEW: Exchange symbol (e.g., BTCEUR, BTCUSDT)
    String timeframe = '5m',
    bool silent = false,
    BaseExchangeService? exchangeService, // NEW: Pass exchange service for volume calculation
  }) async {
    // ignore: avoid_print
    print('');
    if (!silent) {
      // ignore: avoid_print
      print('🎯 ==========================================');
      // ignore: avoid_print
      print('🎯 MULTI-TIMEFRAME ENSEMBLE for ${coin.toUpperCase()} @ $timeframe');
      // ignore: avoid_print
      print('🎯 ==========================================');
    }

    final weightedPredictions = <_WeightedPrediction>[];

    // PHASE 3 PILOT: Check if Phase 3 weights should be applied for this coin+timeframe
    final bool applyPhase3 = _isPhase3Enabled(coin, timeframe);
    if (!silent && applyPhase3) {
      // ignore: avoid_print
      print('🚀 Phase 3 PILOT ACTIVE for ${coin.toUpperCase()}@$timeframe');
    }

    // PHASE 3: We'll calculate ATR when we fetch candles for the requested timeframe
    double volatility = 0.02; // Default 2% volatility

    // PHASE 3: Fetch volume percentile with caching (5 min TTL) - only if pilot active
    double volumePercentile = 0.5; // Default to median
    if (applyPhase3) {
      try {
        // Use the symbol parameter directly (e.g., BTCEUR, BTCUSDT, BTCUSD, BTCUSDC)
        // Check cache first (with exchange-specific key to avoid mixing data between exchanges)
        final service = exchangeService ?? _binanceService;
        final cacheKey = '${service.exchangeName}_$symbol';
        final cached = _volumeCache[cacheKey];
        if (cached != null && DateTime.now().difference(cached.$2) < _volumeCacheTTL) {
          volumePercentile = cached.$1;
          if (!silent) {
            // ignore: avoid_print
            print('📊 Phase 3: Volume percentile for $symbol on ${service.exchangeName}: ${(volumePercentile * 100).toStringAsFixed(1)}% (cached)');
          }
        } else {
          // Not cached, fetch from API
          volumePercentile = await service.getVolumePercentile(symbol);

          // Cache for 5 minutes (include exchange name in cache key to avoid mixing data)
          _volumeCache[cacheKey] = (volumePercentile, DateTime.now());

          if (!silent) {
            // ignore: avoid_print
            print('📊 Phase 3: Volume percentile for $symbol on ${service.exchangeName}: ${(volumePercentile * 100).toStringAsFixed(1)}%');
          }
        }
      } catch (e) {
        if (!silent) {
          // ignore: avoid_print
          print('⚠️  Phase 3: Failed to fetch volume percentile for $symbol, using default 0.5: $e');
        }
      }
    }

    // PHASE 4: Fetch Volume Profile (bid/ask imbalance + whale walls)
    double bidAskRatio = 1.0; // Default to neutral (1.0 = balanced)
    int whaleWallCount = 0;
    if (applyPhase3) {
      try {
        final service = exchangeService ?? _binanceService;
        final volumeProfile = await _volumeProfileService.analyzeVolume(
          symbol: symbol,
          exchange: service.exchangeName.toLowerCase(),
          depth: 100,
        );

        bidAskRatio = volumeProfile.bidAskRatio;
        whaleWallCount = volumeProfile.whaleWalls.length;

        if (!silent) {
          // ignore: avoid_print
          print('📊 Phase 4: Order book for $symbol → bidAskRatio=${bidAskRatio.toStringAsFixed(2)}, whaleWalls=$whaleWallCount, signal=${volumeProfile.getSignal()}');
        }
      } catch (e) {
        if (!silent) {
          // ignore: avoid_print
          print('⚠️  Phase 4: Failed to fetch order book for $symbol, using defaults: $e');
        }
      }
    }

    // STEP 1: Load ALL coin-specific models across ALL timeframes with FALLBACK
    // NEW: Fetch candles for EACH model's timeframe!
    final allTimeframes = ['5m', '15m', '1h', '4h', '1d'];

    // Normalize coin symbol: "BTCUSD" → "btc", "BTCEUR" → "btc", "BTC" → "btc"
    final normalizedCoin = coin.toLowerCase().replaceAll(RegExp(r'(usd|eur|usdt|usdc)$'), '');

    // Track which models we've already loaded to avoid duplicates
    final Set<String> loadedModels = {};

    for (final tf in allTimeframes) {
      // Get best available model for this timeframe (with fallback)
      final coinKey = _getBestModelKey(normalizedCoin, tf);

      // Skip if no model found or already loaded
      if (coinKey == null || loadedModels.contains(coinKey)) {
        continue;
      }

      loadedModels.add(coinKey);

      try {
        // Extract actual timeframe from model key (e.g., "btc_1h" → "1h")
        final actualTf = coinKey.split('_').last;

        // Fetch candles for the ACTUAL model's timeframe (not requested tf)
        final service = exchangeService ?? _binanceService;
        final result = await service.getFeaturesWithATRFallback(symbol, interval: actualTf);

        // Calculate ATR for the requested timeframe (for weights)
        if (actualTf == timeframe) {
          volatility = result.atr;
          if (!silent) {
            // ignore: avoid_print
            print('📈 ATR (volatility): ${(volatility * 100).toStringAsFixed(2)}% (from $actualTf candles)');
          }
        }

        final pred = await _getPredictionWithModel(
          coinKey,
          result.features,
          coin: coin,
          timeframe: actualTf,
          atr: volatility,
          volumePercentile: volumePercentile,
          bidAskRatio: bidAskRatio,
        );

        // ADAPTIVE MODEL SELECTION: Filter models based on market conditions
        // High volatility (ATR > 2.0) → skip long timeframes (slow to react)
        if (volatility > 2.0 && ['1d', '7d', '4h'].contains(actualTf)) {
          if (!silent) {
            // ignore: avoid_print
            print('   ⚡ [Adaptive Selection] HIGH VOLATILITY (ATR=${(volatility * 100).toStringAsFixed(2)}%) → skipping long tf $coinKey');
          }
          continue;
        }
        // Low volume (< 30% percentile) → skip short timeframes (noisy signals)
        if (volumePercentile < 0.30 && !['1h', '4h', '1d', '7d'].contains(actualTf)) {
          if (!silent) {
            // ignore: avoid_print
            print('   🔇 [Adaptive Selection] LOW VOLUME (percentile=${(volumePercentile * 100).toStringAsFixed(1)}%) → skipping short tf $coinKey');
          }
          continue;
        }
        if (!silent) {
          // ignore: avoid_print
          print('   ✅ [Adaptive Selection] NORMAL CONDITIONS → using $coinKey');
        }

        // PHASE 3 PILOT: Apply Phase 3 weights if enabled for this coin+timeframe
        final double weight;
        if (applyPhase3) {
          // Use Phase 3 enhanced weights (real ATR + volume boost + recency penalty)
          final trainedDate = _getTrainedDate(coinKey);
          weight = EnsembleWeightsV2.calculateTimeframeWeight(
            requestedTf: timeframe,
            modelTf: actualTf,
              coin: coin,
              atr: volatility, // Real ATR from candles
              modelKey: coinKey,
              isGeneral: false,
              volumePercentile: volumePercentile,
              trainedDate: trainedDate,
            );
        } else {
          // Use existing logic (preview mode)
          weight = _calculateTimeframeWeight(timeframe, actualTf);
        }

        // Apply time-based weight adjustment (Asia/Europe/US sessions)
        final adjustedWeight = _getTimeBasedWeight(coinKey, weight);
        weightedPredictions.add(_WeightedPrediction(pred, adjustedWeight, coinKey));
      } catch (e) {
        // ignore: avoid_print
        print('   ❌ Error loading $coinKey: $e');
      }
    }

    // STEP 2: Load ALL general models
    // NEW: Fetch candles for EACH general model's timeframe!

    for (final tf in ['5m', '1d']) {
      final generalKey = 'general_$tf';
      if (_interpreters.containsKey(generalKey)) {
        try {
          // Fetch candles for THIS general model's timeframe (using exchange-specific service)
          final service = exchangeService ?? _binanceService;
          final result = await service.getFeaturesWithATRFallback(symbol, interval: tf);

          final pred = await _getPredictionWithModel(
            generalKey,
            result.features,
            coin: coin,
            timeframe: timeframe, // Use requested timeframe for confidence
            atr: result.atr,
            volumePercentile: volumePercentile,
            bidAskRatio: bidAskRatio,
          );

          // ADAPTIVE MODEL SELECTION: Filter general models based on market conditions
          // High volatility (ATR > 2.0) → skip long timeframes (slow to react)
          if (volatility > 2.0 && ['1d', '7d', '4h'].contains(tf)) {
            if (!silent) {
              // ignore: avoid_print
              print('   ⚡ [Adaptive Selection] HIGH VOLATILITY (ATR=${(volatility * 100).toStringAsFixed(2)}%) → skipping long tf $generalKey');
            }
            continue;
          }
          // Low volume (< 30% percentile) → skip short timeframes (noisy signals)
          if (volumePercentile < 0.30 && !['1h', '4h', '1d', '7d'].contains(tf)) {
            if (!silent) {
              // ignore: avoid_print
              print('   🔇 [Adaptive Selection] LOW VOLUME (percentile=${(volumePercentile * 100).toStringAsFixed(1)}%) → skipping short tf $generalKey');
            }
            continue;
          }
          if (!silent) {
            // ignore: avoid_print
            print('   ✅ [Adaptive Selection] NORMAL CONDITIONS → using $generalKey');
          }

          // PHASE 3 PILOT: Apply Phase 3 weights if enabled for this coin+timeframe
          final double weight;
          if (applyPhase3) {
            // Use Phase 3 enhanced weights (real ATR + volume boost + recency penalty for general models)
            final trainedDate = _getTrainedDate(generalKey);
            weight = EnsembleWeightsV2.calculateTimeframeWeight(
              requestedTf: timeframe,
              modelTf: tf,
              coin: coin,
              atr: volatility, // Real ATR from candles
              modelKey: generalKey,
              isGeneral: true,
              volumePercentile: volumePercentile,
              trainedDate: trainedDate,
            );
          } else {
            // Use existing logic (general penalty 0.6x)
            weight = _calculateTimeframeWeight(timeframe, tf) * 0.6;
          }
          
          // Apply time-based weight adjustment (Asia/Europe/US sessions)
          final adjustedWeight = _getTimeBasedWeight(generalKey, weight);
          weightedPredictions.add(_WeightedPrediction(pred, adjustedWeight, generalKey));
        } catch (e) {
          // ignore: avoid_print
          print('   ❌ Error loading $generalKey: $e');
        }
      }
    }

    // Log loaded models with fallback info
    if (!silent && weightedPredictions.isNotEmpty) {
      final modelKeys = weightedPredictions.map((wp) => wp.modelKey).toList();
      // ignore: avoid_print
      print('🔍 Found ${modelKeys.length} models for ${coin.toUpperCase()}: ${modelKeys.join(", ")}');
    }

    // STEP 3: Return neutral if no models available
    if (weightedPredictions.isEmpty) {
      // ignore: avoid_print
      print('⚠️ No models available, returning neutral HOLD');
      // ignore: avoid_print
      print('🎯 ==========================================');
      // ignore: avoid_print
      print('');
      return _getNeutralPrediction();
    }

    // STEP 4: Combine using WEIGHTED ENSEMBLE
    var ensemble = getWeightedEnsemblePrediction(
      weightedPredictions,
      atr: volatility,
      volumePercentile: volumePercentile,
    );

    // PHASE 4: FINAL DECISION ENGINE
    // Anti-chop filter + Trend boost + Micro-trend confirmation
    final atrPercent = volatility * 100;
    final volPercentile = volumePercentile;
    var finalAction = ensemble.action;
    var finalConfidence = ensemble.confidence;
    String decisionReason = 'Normal market conditions';

    // 1. ANTI-CHOP FILTER: Low volatility + High liquidity + Low confidence → HOLD
    if (atrPercent < 0.15 && volPercentile > 85.0 && finalConfidence < 0.55) {
      if (!silent) {
        // ignore: avoid_print
        print('🚫 ANTI-CHOP TRIGGERED: ATR=${atrPercent.toStringAsFixed(2)}%, Vol=${volPercentile.toStringAsFixed(0)}%, Conf=${(finalConfidence*100).toStringAsFixed(1)}%');
        // ignore: avoid_print
        print('   → Forcing HOLD to avoid whipsaw');
      }

      finalAction = 'HOLD';
      finalConfidence = 0.38;
      decisionReason = 'Chop zone: low ATR + high liquidity → avoid false signal';
    }
    // 2. TREND BOOST: High volatility → Boost dominant direction only
    else if (atrPercent > 0.30) {
      // FIX: Only boost the DOMINANT direction (buy > sell OR sell > buy)
      final buy = ensemble.probabilities['BUY'] ?? 0.0;
      final sell = ensemble.probabilities['SELL'] ?? 0.0;

      // Only apply trend boost if there's a clear direction (NOT when buy ≈ sell)
      if ((buy > sell && finalAction == 'BUY') || (sell > buy && finalAction == 'SELL')) {
        final boost = 1.20; // +20% confidence in strong trends
        finalConfidence = (finalConfidence * boost).clamp(0.0, 0.95);
        decisionReason = 'High volatility - strong trend detected';

        if (!silent) {
          // ignore: avoid_print
          print('📈 TREND BOOST: ATR=${atrPercent.toStringAsFixed(2)}% → +20% confidence on ${finalAction}');
        }
      } else {
        // No boost when direction is unclear or HOLD
        decisionReason = 'High volatility but no clear direction';
        if (!silent) {
          // ignore: avoid_print
          print('⚠️ TREND BOOST SKIPPED: ATR=${atrPercent.toStringAsFixed(2)}% but BUY≈SELL or HOLD');
        }
      }
    }
    // 3. MICRO-TREND CONFIRMATION: Moderate volatility + Good confidence → Small boost
    else if (atrPercent > 0.18 && finalConfidence > 0.48) {
      final boost = 1.08; // +8% confidence for confirmed micro-trends
      finalConfidence = (finalConfidence * boost).clamp(0.0, 0.90);
      decisionReason = 'Micro-trend confirmed - moderate volatility';

      if (!silent) {
        // ignore: avoid_print
        print('📊 MICRO-TREND CONFIRMED: ATR=${atrPercent.toStringAsFixed(2)}% → +8% confidence');
      }
    }
    else {
      decisionReason = atrPercent < 0.20
          ? 'Low volatility - moderate confidence'
          : 'Normal market conditions';
    }

    // Update ensemble with final decision
    ensemble = CryptoPrediction(
      action: finalAction,
      confidence: finalConfidence,
      probabilities: ensemble.probabilities,
      signalStrength: ensemble.signalStrength,
      modelAccuracy: ensemble.modelAccuracy,
      timestamp: ensemble.timestamp,
      atr: ensemble.atr,
      volumePercentile: ensemble.volumePercentile,
      isEnsemble: ensemble.isEnsemble,
      decisionReason: decisionReason, // Pass decision reason from Phase 4
    );

    // ignore: avoid_print
    print('');
    if (!silent) {
      // ignore: avoid_print
      print('✅ WEIGHTED ENSEMBLE RESULT:');
      // ignore: avoid_print
      print('   🎯 Action: ${ensemble.action}');
      // ignore: avoid_print
      print('   💪 Confidence: ${(ensemble.confidence * 100).toStringAsFixed(1)}%');
      // ignore: avoid_print
      print('   📊 Models used: ${weightedPredictions.length}');
      // ignore: avoid_print
      print('   📈 SELL: ${(ensemble.probabilities["SELL"]! * 100).toStringAsFixed(1)}%');
      // ignore: avoid_print
      print('   ⏸️  HOLD: ${(ensemble.probabilities["HOLD"]! * 100).toStringAsFixed(1)}%');
      // ignore: avoid_print
      print('   📉 BUY:  ${(ensemble.probabilities["BUY"]! * 100).toStringAsFixed(1)}%');
      // ignore: avoid_print
      print('🎯 ==========================================');
      // PHASE 4: Preview market context
      // ignore: avoid_print
      print('');
      // ignore: avoid_print
      print('🔮 Phase 4 preview: ATR=${(volatility * 100).toStringAsFixed(2)}%, liquidity=${(volumePercentile * 100).toStringAsFixed(0)}%');
      // ignore: avoid_print
      print('');

      // FINAL DECISION SUMMARY
      // ignore: avoid_print
      print('📊 FINAL DECISION: ${ensemble.action} (${(ensemble.confidence * 100).toStringAsFixed(1)}%) | Reason: $decisionReason');
      // ignore: avoid_print
      print('   Signal Strength: ${(ensemble.signalStrength * 100).toStringAsFixed(1)}%');
      // ignore: avoid_print
      print('   ATR: ${(volatility * 100).toStringAsFixed(2)}% | Volume Percentile: ${(volumePercentile * 100).toStringAsFixed(0)}%');
      // ignore: avoid_print
      print('');
    }

    // LOW VOLUME OVERRIDE: Force HOLD for extreme low volume on short timeframes
    // This runs AFTER ensemble display, so we always see the ensemble result in logs
    if (volumePercentile < 0.05 && (timeframe == '5m' || timeframe == '15m')) {
      if (!silent) {
        // ignore: avoid_print
        print('⚠️  [Low Volume Override] Extreme low volume (${(volumePercentile * 100).toStringAsFixed(1)}%) - forcing HOLD');
      }
      return CryptoPrediction(
        action: 'HOLD',
        confidence: 0.40,
        probabilities: ensemble.probabilities,
        signalStrength: 0.0,
        modelAccuracy: ensemble.modelAccuracy,
        timestamp: DateTime.now(),
        isEnsemble: true,
        atr: volatility,
        volumePercentile: volumePercentile,
        decisionReason: 'Extreme low volume override (<5%) on last candle',
      );
    }

    // PHASE 4: Return prediction with market context (ATR + volume + decision reason)
    return CryptoPrediction(
      action: ensemble.action,
      confidence: ensemble.confidence,
      probabilities: ensemble.probabilities,
      signalStrength: ensemble.signalStrength,
      modelAccuracy: ensemble.modelAccuracy,
      timestamp: ensemble.timestamp,
      isEnsemble: ensemble.isEnsemble,
      atr: volatility,
      volumePercentile: volumePercentile,
      decisionReason: ensemble.decisionReason, // Already set in Phase 4
    );
  }

  /// Returnează o predicție neutră HOLD când modelele nu sunt disponibile
  CryptoPrediction _getNeutralPrediction() {
    return CryptoPrediction(
      action: 'HOLD',
      confidence: 0.5,
      probabilities: {
        'SELL': 0.25,
        'HOLD': 0.50,
        'BUY': 0.25,
      },
      signalStrength: 0.0,
      modelAccuracy: 0.0,
      timestamp: DateTime.now(),
    );
  }

  /// Execută predicția cu un model specific
  Future<CryptoPrediction> _getPredictionWithModel(
    String modelKey,
    List<List<double>> priceData,
    {
      bool silent = false,
      String? coin,
      String? timeframe,
      double? atr,
      double? volumePercentile,
      double? bidAskRatio = 1.0,
    }
  ) async {
    final interpreter = _interpreters[modelKey]!;
    final scaler = _scalers[modelKey]!;
    final metadata = _metadata[modelKey]!;

    // Validare timesteps
    if (priceData.length != 60) {
      throw Exception('Need exactly 60 timesteps, got ${priceData.length}');
    }

    // Noile modele acceptă 76 features
    final expectedFeatures = (metadata['num_features'] as num?)?.toInt() ?? 76;
    if (priceData[0].length != expectedFeatures) {
      throw Exception('Need exactly $expectedFeatures features per timestep, got ${priceData[0].length}');
    }

    // Calculate signal strength (% of non-zero features) BEFORE normalization
    // PATCH 3: Dynamic Signal Strength - doar ultimele 15 timesteps (mai sensibil la schimbări recente)
    const threshold = 0.1; // Threshold mai ridicat pentru features "active"
    const recentWindow = 15; // Doar ultimele 15 timesteps

    int activeCount = 0;
    int totalFeatures = 0;
    final recentData = priceData.length > recentWindow
        ? priceData.sublist(priceData.length - recentWindow)
        : priceData;

    for (final row in recentData) {
      for (final val in row) {
        if (val.abs() > threshold) activeCount++;
        totalFeatures++;
      }
    }
    final signalStrength = totalFeatures > 0
        ? (activeCount / totalFeatures * 100).clamp(0.0, 100.0) / 100.0
        : 0.0;

    // DEBUG RAW INPUT (before normalization)
    if (!silent && priceData.isNotEmpty) {
      final firstRowRaw = priceData.first;
      final lastRowRaw = priceData.last;
      // ignore: avoid_print
      print('🔬 DEBUG RAW INPUT: First row [0-5]: [${firstRowRaw.take(6).map((v) => v.toStringAsFixed(4)).join(', ')}]');
      // ignore: avoid_print
      print('🔬 DEBUG RAW INPUT: Last row [0-5]: [${lastRowRaw.take(6).map((v) => v.toStringAsFixed(4)).join(', ')}]');
      // ignore: avoid_print
      print('🎯 SIGNAL STRENGTH (last $recentWindow timesteps): ${(signalStrength * 100).toStringAsFixed(1)}% features active ($activeCount / $totalFeatures)');
    }

    // Normalizare
    final normalizedData = _normalizeData(priceData, scaler);

    // DEBUG: Log first and last feature values to detect if input changes
    if (!silent && normalizedData.isNotEmpty) {
      final firstRow = normalizedData.first;
      final lastRow = normalizedData.last;
      // ignore: avoid_print
      print('🔬 DEBUG NORMALIZED: First row [0-5]: [${firstRow.take(6).map((v) => v.toStringAsFixed(4)).join(', ')}]');
      // ignore: avoid_print
      print('🔬 DEBUG NORMALIZED: Last row [0-5]: [${lastRow.take(6).map((v) => v.toStringAsFixed(4)).join(', ')}]');
    }

    // Input: [1, 60, 76]
    final List<List<List<double>>> input = [normalizedData];

    // Output: [1, 3] (SELL, HOLD, BUY)
    final numClasses = (metadata['num_classes'] as num?)?.toInt() ?? 3;
    final List<List<double>> output = List<List<double>>.generate(
      1,
      (_) => List<double>.filled(numClasses, 0.0),
    );

    interpreter.run(input, output);

    // DEBUG: Log raw model output
    if (!silent) {
      // ignore: avoid_print
      print('🔬 DEBUG OUTPUT ($modelKey): RAW probabilities = [${output[0].map((v) => v.toStringAsFixed(6)).join(', ')}]');
    }

    // Apply DYNAMIC temperature scaling based on signal strength
    // More active features → lower T (trust model more)
    // Fewer active features → higher T (model less reliable)
    var probabilities = output[0];

    // Calculate dynamic temperature with nuanced scaling
    // RELAXED temperature thresholds to preserve model conviction:
    //   - signal < 20% → T = 10.0 (very low signal → dampening)
    //   - signal < 30% → T = 6.0 (low signal → moderate dampening)
    //   - signal < 40% → T = 4.0 (medium signal → light dampening)
    //   - signal < 50% → T = 3.0 (good signal → minimal dampening)
    //   - signal >= 50% → T = 2.0 (strong signal → preserve confidence)
    final signalPercent = signalStrength * 100;
    final double temperature = signalPercent < 20 ? 10.0
                              : signalPercent < 30 ? 6.0
                              : signalPercent < 40 ? 4.0
                              : signalPercent < 50 ? 3.0
                              : 2.0;

    final maxProb = probabilities.reduce((a, b) => a > b ? a : b);

    // Always apply temperature scaling if confidence > 75% OR signal strength < 50%
    if (maxProb > 0.75 || signalStrength < 0.50) {
      if (!silent) {
        // ignore: avoid_print
        print('   🔥 BEFORE scaling: [${probabilities.map((p) => p.toStringAsFixed(4)).join(", ")}]');
      }

      probabilities = _applyTemperatureScaling(probabilities, temperature);

      if (!silent) {
        // ignore: avoid_print
        print('   🌡️  Dynamic T=${temperature.toStringAsFixed(1)} (signal=${(signalStrength*100).toStringAsFixed(1)}%) - was ${(maxProb * 100).toStringAsFixed(1)}% confident');
        // ignore: avoid_print
        print('   ✅ AFTER scaling: [${probabilities.map((p) => p.toStringAsFixed(4)).join(", ")}]');
      }
    }

    // STEP 1: Apply bullish/bearish bias on individual model predictions
    // (before combining in ensemble) - based on volume, volatility, AND order book
    final atrPercent = (atr ?? 0.02) * 100;
    final volPercent = (volumePercentile ?? 0.5) * 100;

    // Get current BUY and SELL probabilities
    final currentBuy = probabilities.length == 3 ? probabilities[2] : (probabilities.length == 2 ? probabilities[1] : 0.0);
    final currentSell = probabilities[0];

    // PHASE 4: Bid/Ask imbalance bias (order book pressure)
    final ratio = bidAskRatio ?? 1.0; // Default to neutral if null
    if (ratio > 1.2) {
      // Strong buying pressure (more bids than asks)
      if (currentBuy > currentSell) {
        // Apply +5% bullish bias to BUY probability
        if (probabilities.length == 3) {
          probabilities[2] = (probabilities[2] + 0.05).clamp(0.0, 1.0);
        } else if (probabilities.length == 2) {
          probabilities[1] = (probabilities[1] + 0.05).clamp(0.0, 1.0);
        }

        if (!silent) {
          // ignore: avoid_print
          print('📈 ORDER BOOK BULLISH BIAS in $modelKey: +5% to BUY (bidAskRatio=${ratio.toStringAsFixed(2)})');
        }
      }
    } else if (ratio < 0.8) {
      // Strong selling pressure (more asks than bids)
      if (currentSell > currentBuy) {
        // Apply +5% bearish bias to SELL probability
        probabilities[0] = (probabilities[0] + 0.05).clamp(0.0, 1.0);

        if (!silent) {
          // ignore: avoid_print
          print('📉 ORDER BOOK BEARISH BIAS in $modelKey: +5% to SELL (bidAskRatio=${ratio.toStringAsFixed(2)})');
        }
      }
    }

    // PHASE 3: Volume percentile bias (existing logic)
    if (volPercent > 90.0 && atrPercent < 50.0) {
      if (currentBuy > currentSell) {
        // Apply +10% bullish bias to BUY probability
        if (probabilities.length == 3) {
          probabilities[2] = (probabilities[2] + 0.10).clamp(0.0, 1.0);
        } else if (probabilities.length == 2) {
          probabilities[1] = (probabilities[1] + 0.10).clamp(0.0, 1.0);
        }

        if (!silent) {
          // ignore: avoid_print
          print('📈 VOLUME BULLISH BIAS in $modelKey: +10% to BUY (vol=${volPercent.toStringAsFixed(0)}%, ATR=${atrPercent.toStringAsFixed(2)}%)');
        }
      }
    }

    final maxIndex = _argmax(probabilities);

    // Extract coin and timeframe from modelKey if not provided
    // modelKey format: "btc_5m" or "general_1d"
    final extractedCoin = coin ?? modelKey.split('_').first;
    final extractedTimeframe = timeframe ?? modelKey.split('_').last;

    // Calculate calibrated confidence based on:
    // 1. Model accuracy (different per timeframe/coin)
    // 2. Prediction certainty (entropy of probabilities)
    // 3. Timeframe adjustment (longer timeframe = less confidence)
    final rawConfidence = probabilities[maxIndex];
    final confidence = _calculateCalibratedConfidence(
      rawConfidence: rawConfidence,
      probabilities: probabilities,
      modelAccuracy: (metadata['test_accuracy'] as num?)?.toDouble() ?? 0.5,
      timeframe: extractedTimeframe,
      coin: extractedCoin,
    );

    // Handle binary (2-class) vs ternary (3-class) classification
    String action;
    Map<String, double> probMap;

    if (numClasses == 2) {
      // Binary: DOWN (0) vs UP (1) -> map to SELL vs BUY
      action = maxIndex == 0 ? 'SELL' : 'BUY';
      probMap = {
        'SELL': probabilities[0],  // DOWN
        'HOLD': 0.0,               // No HOLD in binary
        'BUY': probabilities[1],   // UP
      };
    } else {
      // Ternary: SELL, HOLD, BUY
      action = <String>['SELL', 'HOLD', 'BUY'][maxIndex];
      probMap = {
        'SELL': probabilities[0],
        'HOLD': probabilities[1],
        'BUY': probabilities[2],
      };
    }

    final predictionEntropy = _calculateSignalStrength(probabilities);
    final accuracy = (metadata['test_accuracy'] as num?)?.toDouble() ?? 0.0;

    return CryptoPrediction(
      action: action,
      confidence: confidence,
      probabilities: probMap,
      signalStrength: predictionEntropy,
      modelAccuracy: accuracy,
      timestamp: DateTime.now(),
    );
  }

  /// PATCH 2: Rolling normalization - normalizează pe fereastră glisantă (ultimele 30 candles)
  /// Mai rapid și mai sensibil la schimbările recente de preț
  List<List<double>> _normalizeData(
    List<List<double>> data,
    Map<String, dynamic> scaler,
  ) {
    const lookback = 30; // Rolling window de 30 candles
    final normalized = <List<double>>[];

    for (int t = 0; t < data.length; t++) {
      final start = t >= lookback ? t - lookback + 1 : 0;
      final window = data.sublist(start, t + 1);

      final row = <double>[];
      for (int f = 0; f < data[0].length; f++) {
        // CRITICAL FIX: Pattern features (indices 0-5) are binary (0.0 or 1.0)
        // DO NOT normalize binary features - models were trained on 0/1 values
        if (f < 6) {
          // Keep pattern features as-is (0.0 or 1.0)
          row.add(data[t][f]);
        } else {
          // Normalize continuous features (indices 6-75)
          final col = window.map((r) => r[f]).toList();
          final mean = col.reduce((a, b) => a + b) / col.length;
          final variance = col.map((x) => (x - mean) * (x - mean)).reduce((a, b) => a + b) / col.length;
          final std = variance > 0 ? sqrt(variance) : 0.0;
          final value = std > 1e-8 ? (data[t][f] - mean) / std : 0.0;
          row.add(double.parse(value.toStringAsFixed(6)));
        }
      }
      normalized.add(row);
    }
    return normalized;
  }

  /// Găsește indexul valorii maxime
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

  /// Apply temperature scaling to soften overconfident predictions
  /// Temperature > 1.0 makes distribution more uniform (less extreme)
  /// Temperature < 1.0 makes distribution more peaked (more extreme)
  ///
  /// Formula: softmax(log(probs) / T)
  List<double> _applyTemperatureScaling(List<double> probs, double temperature) {
    if (temperature == 1.0) return probs;

    final epsilon = 1e-10; // Prevent log(0)

    // Convert probabilities to logits: log(p)
    final logits = probs.map((p) => log(p + epsilon)).toList();

    // Apply temperature: logits / T
    final scaledLogits = logits.map((l) => l / temperature).toList();

    // Apply softmax with numerical stability (subtract max)
    final maxLogit = scaledLogits.reduce((a, b) => a > b ? a : b);
    final expValues = scaledLogits.map((l) => exp(l - maxLogit)).toList();
    final sumExp = expValues.reduce((a, b) => a + b);

    return expValues.map((e) => e / sumExp).toList();
  }

  /// Calculează puterea semnalului (0.0-1.0)
  /// Returns the difference between top 2 probabilities (conviction metric)
  double _calculateSignalStrength(List<double> probabilities) {
    if (probabilities.length < 2) return 0.0;

    final sorted = probabilities.toList()..sort();
    final maxVal = sorted.last;
    final secondMax = sorted[sorted.length - 2];
    final diff = maxVal - secondMax;
    return diff.clamp(0.0, 1.0); // Returns 0.0-1.0 (NOT 0-100)
  }

  /// Calculate calibrated confidence - varies by timeframe, coin, and model accuracy
  double _calculateCalibratedConfidence({
    required double rawConfidence,
    required List<double> probabilities,
    required double modelAccuracy,
    required String timeframe,
    required String coin,
  }) {
    // 1. Start with raw model confidence
    double calibrated = rawConfidence;

    // 2. Adjust by model accuracy (models with higher accuracy get confidence boost)
    // Example: 60% accuracy model → 1.2x boost, 40% accuracy → 0.8x penalty
    final accuracyMultiplier = 0.5 + (modelAccuracy * 1.0);
    calibrated *= accuracyMultiplier;

    // 3. Calculate entropy (how certain is the model?)
    // Low entropy (e.g., [0.9, 0.05, 0.05]) = high certainty → boost confidence
    // High entropy (e.g., [0.4, 0.3, 0.3]) = low certainty → reduce confidence
    double entropy = 0.0;
    for (final p in probabilities) {
      if (p > 0.0001) {
        final clampedP = p.clamp(0.0001, 1.0);
        entropy += -(p * log(clampedP) / 2.302585); // log base 10
      }
    }
    final maxEntropy = 1.0; // Max entropy for 3 classes
    final certainty = 1.0 - (entropy / maxEntropy).clamp(0, 1);
    calibrated *= (0.7 + certainty * 0.3); // Apply certainty boost (0.7x - 1.0x)

    // 4. Timeframe adjustment (longer timeframe = less confidence)
    final timeframeMultipliers = {
      '5m': 1.0,    // Short term = highest confidence
      '15m': 0.95,  // Slight reduction
      '1h': 0.9,    // Medium term
      '4h': 0.85,   // Longer term
      '1d': 0.75,   // Daily = much less confident
    };
    final tfMultiplier = timeframeMultipliers[timeframe] ?? 0.9;
    calibrated *= tfMultiplier;

    // 5. Coin-specific adjustment (some coins are more predictable)
    // BTC/ETH are generally more predictable than small caps
    final coinMultipliers = {
      'btc': 1.05,
      'eth': 1.03,
      'bnb': 1.0,
      'sol': 0.98,
      'trump': 0.90,  // High volatility meme coin
      'wlfi': 0.90,   // High volatility small cap
      'general': 0.95, // General model is less confident than coin-specific
    };
    final coinMultiplier = coinMultipliers[coin.toLowerCase()] ?? 0.95;
    calibrated *= coinMultiplier;

    // 6. Final clamp to realistic range (30% - 95%)
    // We never want to show 100% confidence (overconfident)
    // We never want to show <30% confidence (too weak to show)
    return calibrated.clamp(0.30, 0.95);
  }

  /// Obține predicții pentru toate monedele
  Future<Map<String, CryptoPrediction>> getAllPredictions({
    required Map<String, String> symbolMap, // NEW: coin -> symbol mapping (e.g., 'btc' -> 'BTCEUR')
    String timeframe = '5m',
  }) async {
    final results = <String, CryptoPrediction>{};
    for (final coin in symbolMap.keys) {
      try {
        results[coin] = await getPrediction(
          coin: coin,
          symbol: symbolMap[coin]!,
          timeframe: timeframe,
        );
      } catch (e) {
        // ignore: avoid_print
        print('⚠️ Error getting prediction for $coin: $e');
        // Adaugă predicție neutră pentru monedele cu erori
        results[coin] = _getNeutralPrediction();
      }
    }
    return results;
  }

  /// Verifică dacă un model este încărcat
  bool isModelLoaded(String coin, String timeframe) {
    final key = '${coin}_$timeframe';
    return _interpreters.containsKey(key);
  }

  /// Obține numărul de modele încărcate
  int get loadedModelsCount => _interpreters.length;

  /// Obține lista de modele încărcate
  List<String> get loadedModels => _interpreters.keys.toList();

  /// Verifică dacă serviciul are cel puțin un model încărcat
  bool get hasAnyModels => _interpreters.isNotEmpty;

  /// Calculate timeframe distance weight using exponential decay
  /// Closer timeframes get higher weights
  double _calculateTimeframeWeight(String requestedTf, String modelTf) {
    // Map timeframes to minutes for distance calculation
    final tfToMinutes = {
      '5m': 5,
      '15m': 15,
      '1h': 60,
      '4h': 240,
      '1d': 1440,
    };

    final requestedMinutes = tfToMinutes[requestedTf] ?? 60;
    final modelMinutes = tfToMinutes[modelTf] ?? 60;

    // Exact match gets highest weight (0.35)
    if (requestedTf == modelTf) {
      return 0.35;
    }

    // Calculate distance in log space (to handle large differences)
    final distance = (requestedMinutes / modelMinutes).abs();
    final logDistance = (distance > 1.0 ? distance : 1.0 / distance);

    // Exponential decay: weight = 0.15 * exp(-0.5 * log(distance))
    // Examples:
    // - 1h requested, 15m model: distance=4, weight ≈ 0.11
    // - 1h requested, 4h model: distance=4, weight ≈ 0.11
    // - 1h requested, 1d model: distance=24, weight ≈ 0.05
    final weight = 0.15 * (1.0 / (logDistance + 0.5));

    return weight.clamp(0.05, 0.35);
  }

  /// WEIGHTED ENSEMBLE - combines predictions with timeframe-based weights
  CryptoPrediction getWeightedEnsemblePrediction(
    List<_WeightedPrediction> weightedPredictions, {
    double? atr,
    double? volumePercentile,
  }) {
    if (weightedPredictions.isEmpty) {
      throw Exception('No predictions to ensemble');
    }

    // Normalize weights to sum to 1.0
    final totalWeight = weightedPredictions.fold<double>(0.0, (sum, wp) => sum + wp.weight);
    final normalizedWeights = weightedPredictions.map((wp) => wp.weight / totalWeight).toList();

    // Calculate weighted average of probabilities
    final avgProb = <String, double>{'SELL': 0.0, 'HOLD': 0.0, 'BUY': 0.0};
    for (var i = 0; i < weightedPredictions.length; i++) {
      final wp = weightedPredictions[i];
      final weight = normalizedWeights[i];
      avgProb['SELL'] = avgProb['SELL']! + (wp.prediction.probabilities['SELL']! * weight);
      avgProb['HOLD'] = avgProb['HOLD']! + (wp.prediction.probabilities['HOLD']! * weight);
      avgProb['BUY'] = avgProb['BUY']! + (wp.prediction.probabilities['BUY']! * weight);
    }

    // PATCH 1: Dynamic confidence cu micro-boost bazat pe ATR și volum
    final sell = avgProb['SELL']!;
    final hold = avgProb['HOLD']!;
    final buy = avgProb['BUY']!;

    // STEP 3: Choose action based on argmax (highest probability wins)
    // FIX: Alege BUY dacă buy > sell, chiar dacă < 0.50
    var finalAction = 'HOLD';
    var finalConfidence = 0.0;

    if (buy > sell && buy > hold) {
      finalAction = 'BUY';
      finalConfidence = buy;
    } else if (sell > buy && sell > hold) {
      finalAction = 'SELL';
      finalConfidence = sell;
    } else {
      finalAction = 'HOLD';
      finalConfidence = hold;
    }

    // CONSENSUS BOOST: If 3+ models agree on the same action, boost confidence
    // This helps escape the "HOLD 35%" trap when multiple models weakly agree
    int strongAgreementCount = 0;
    for (final wp in weightedPredictions) {
      // Count models that agree with final action with >35% confidence
      final modelAction = wp.prediction.action;
      final modelConfidence = wp.prediction.confidence;
      if (modelAction == finalAction && modelConfidence > 0.35) {
        strongAgreementCount++;
      }
    }

    // Apply consensus multiplier
    double consensusMultiplier = 1.0;
    if (strongAgreementCount >= 3 && strongAgreementCount < 4) {
      consensusMultiplier = 1.10; // +10% boost for 3 models
      // ignore: avoid_print
      print('🤝 CONSENSUS BOOST: $strongAgreementCount models agree on $finalAction → +10% confidence');
    } else if (strongAgreementCount >= 4) {
      consensusMultiplier = 1.15; // +15% boost for 4+ models
      // ignore: avoid_print
      print('🤝 CONSENSUS BOOST: $strongAgreementCount models agree on $finalAction → +15% confidence');
    }

    // Apply volume confirmation multiplier if available
    double volumeMultiplier = 1.0;
    if (volumePercentile != null) {
      if (volumePercentile > 0.90) {
        volumeMultiplier = 1.15; // +15% for very high volume
        // ignore: avoid_print
        print('📊 VOLUME CONFIRMATION: ${(volumePercentile * 100).toStringAsFixed(0)}% percentile → +15% confidence');
      } else if (volumePercentile > 0.80) {
        volumeMultiplier = 1.10; // +10% for high volume
        // ignore: avoid_print
        print('📊 VOLUME CONFIRMATION: ${(volumePercentile * 100).toStringAsFixed(0)}% percentile → +10% confidence');
      }
    }

    // Apply both multipliers and clamp to max 75% confidence
    finalConfidence = (finalConfidence * consensusMultiplier * volumeMultiplier).clamp(0.30, 0.75);

    // Weighted average signal strength
    var avgSignalStrength = 0.0;
    for (var i = 0; i < weightedPredictions.length; i++) {
      final wp = weightedPredictions[i];
      final weight = normalizedWeights[i];
      avgSignalStrength += wp.prediction.signalStrength * weight;
    }

    // PATTERN CONFLICT DETECTION: Check if bullish and bearish patterns coexist
    // This indicates market indecision/consolidation → reduce confidence
    int bullishPatterns = 0;
    int bearishPatterns = 0;

    // Count bullish and bearish patterns from weighted predictions
    // We check the last timestep (t=59) features for pattern detection
    // Bullish: Bullish Engulfing (11), Piercing Line (13), Bullish Harami (15), Tweezer Bottom (17), Morning Star (19), Three White Soldiers (21), Rising Three (23)
    // Bearish: Bearish Engulfing (12), Dark Cloud Cover (14), Bearish Harami (16), Tweezer Top (18), Evening Star (20), Three Black Crows (22), Falling Three (24)

    for (final wp in weightedPredictions) {
      // Access raw features from prediction metadata if available
      // Since we don't have direct access to features here, we'll use a simplified approach
      // based on the action probabilities and model behavior
      final probMap = wp.prediction.probabilities;
      if (probMap['BUY']! > 0.40) bullishPatterns++;
      if (probMap['SELL']! > 0.40) bearishPatterns++;
    }

    // Calculate conflict score (0.0 = no conflict, 1.0 = maximum conflict)
    final totalPatterns = bullishPatterns + bearishPatterns;
    final conflictScore = totalPatterns > 0
        ? (bullishPatterns - bearishPatterns).abs() / totalPatterns
        : 0.0;

    // Apply conflict penalty: if both bullish and bearish patterns exist, reduce confidence by 20%
    if (bullishPatterns > 0 && bearishPatterns > 0) {
      finalConfidence *= 0.80; // 20% penalty for conflicting patterns
      // ignore: avoid_print
      print('⚠️  PATTERN CONFLICT: $bullishPatterns bullish vs $bearishPatterns bearish → -20% confidence');
      // ignore: avoid_print
      print('   Conflict Score: ${(conflictScore * 100).toStringAsFixed(1)}% (0%=clear, 100%=balanced conflict)');
    }

    // SIGNAL STRENGTH THRESHOLD: Force HOLD if signal strength < 3%
    // Low signal strength indicates weak/noisy data → not confident enough for BUY/SELL
    // Reduced from 5% to 3% to allow more trading signals in normal market conditions
    const double minSignalStrength = 0.03; // 3% minimum
    if (avgSignalStrength < minSignalStrength && (finalAction == 'BUY' || finalAction == 'SELL')) {
      // ignore: avoid_print
      print('⚠️  SIGNAL TOO WEAK: ${(avgSignalStrength * 100).toStringAsFixed(1)}% < ${(minSignalStrength * 100).toStringAsFixed(1)}% → Forcing HOLD');
      finalAction = 'HOLD';
      finalConfidence = 0.50; // Neutral confidence for forced HOLD
    }

    return CryptoPrediction(
      action: finalAction,
      confidence: finalConfidence,
      probabilities: avgProb,
      signalStrength: avgSignalStrength,
      modelAccuracy: finalConfidence, // Use final confidence as accuracy
      timestamp: DateTime.now(),
      isEnsemble: true,
      atr: atr,
      volumePercentile: volumePercentile,
    );
  }

  /// Strategia de ensemble - combină multiple predicții (LEGACY - folosim weighted ensemble acum)
  CryptoPrediction getEnsemblePrediction(List<CryptoPrediction> predictions) {
    if (predictions.isEmpty) {
      throw Exception('No predictions to ensemble');
    }

    final avgProb = <String, double>{'SELL': 0.0, 'HOLD': 0.0, 'BUY': 0.0};
    for (final p in predictions) {
      avgProb['SELL'] = avgProb['SELL']! + p.probabilities['SELL']!;
      avgProb['HOLD'] = avgProb['HOLD']! + p.probabilities['HOLD']!;
      avgProb['BUY'] = avgProb['BUY']! + p.probabilities['BUY']!;
    }
    final count = predictions.length.toDouble();
    avgProb.updateAll((_, v) => v / count);

    var finalAction = 'HOLD';
    var maxProb = 0.0;
    avgProb.forEach((action, prob) {
      if (prob > maxProb) {
        maxProb = prob;
        finalAction = action;
      }
    });

    final avgConfidence = predictions.map((p) => p.confidence).reduce((a, b) => a + b) / count;
    final avgSignalStrength = predictions.map((p) => p.signalStrength).reduce((a, b) => a + b) / count;

    return CryptoPrediction(
      action: finalAction,
      confidence: maxProb,
      probabilities: avgProb,
      signalStrength: avgSignalStrength,
      modelAccuracy: avgConfidence,
      timestamp: DateTime.now(),
      isEnsemble: true,
    );
  }

  /// PHASE 3: Get trained_date from model registry for recency calculations
  String? _getTrainedDate(String modelKey) {
    if (_modelRegistry == null) {
      // Default to current date if registry not loaded
      return DateTime.now().toIso8601String().split('T')[0];
    }

    try {
      final models = _modelRegistry!['models'] as List?;
      if (models == null) {
        return DateTime.now().toIso8601String().split('T')[0];
      }

      for (final model in models) {
        if (model is Map<String, dynamic> && model['id'] == modelKey) {
          final trainedDate = model['trained_date'] as String?;
          // Return trained_date if found, otherwise default to current date
          return trainedDate ?? DateTime.now().toIso8601String().split('T')[0];
        }
      }
    } catch (e) {
      // ignore: avoid_print
      print('⚠️  Error reading trained_date for $modelKey: $e');
    }

    // Model not found in registry, default to current date
    return DateTime.now().toIso8601String().split('T')[0];
  }

  /// Cleanup - eliberează resursele
  void dispose() {
    for (final interpreter in _interpreters.values) {
      interpreter.close();
    }
    _interpreters.clear();
    _scalers.clear();
    _metadata.clear();
  }
}

/// Clasă pentru rezultatul predicției
class CryptoPrediction {
  final String action; // SELL, HOLD, BUY
  final double confidence; // 0.0 - 1.0
  final Map<String, double> probabilities;
  final double signalStrength; // 0.0 - 1.0 (conviction: diff between top 2 probs)
  final double modelAccuracy;
  final DateTime timestamp;
  final bool isEnsemble;
  
  // PHASE 4: Market context for UI display
  final double? atr; // Average True Range (volatility)
  final double? volumePercentile; // 0.0-1.0 (market liquidity rank)
  final String? decisionReason; // Reason for the final decision (Phase 4)

  CryptoPrediction({
    required this.action,
    required this.confidence,
    required this.probabilities,
    required this.signalStrength,
    required this.modelAccuracy,
    required this.timestamp,
    this.isEnsemble = false,
    this.atr,
    this.volumePercentile,
    this.decisionReason,
  });

  bool get isStrongSignal => confidence > 0.70;
  bool get shouldAct => isStrongSignal && action != 'HOLD';

  String get actionEmoji {
    switch (action) {
      case 'BUY':
        return '🟢';
      case 'SELL':
        return '🔴';
      default:
        return '⚪';
    }
  }

  String get signalDescription {
    if (signalStrength > 80) return 'Very Strong';
    if (signalStrength > 60) return 'Strong';
    if (signalStrength > 40) return 'Moderate';
    if (signalStrength > 20) return 'Weak';
    return 'Very Weak';
  }

  @override
  String toString() {
    return '$actionEmoji $action (${(confidence * 100).toStringAsFixed(1)}%) - $signalDescription signal';
  }
}

/// Helper class for weighted predictions
class _WeightedPrediction {
  final CryptoPrediction prediction;
  final double weight;
  final String modelKey;

  _WeightedPrediction(this.prediction, this.weight, this.modelKey);
}

/// Helper method: Adjust model weight based on trading session (Asia/Europe/US)
double _getTimeBasedWeight(String modelId, double baseWeight) {
  try {
    final now = DateTime.now().toUtc();
    final hour = now.hour;
    double multiplier = 1.0;

    // ASIA SESSION (1-8 UTC) - Favor longer timeframes (1h/4h), penalize short (5m/15m)
    if (hour >= 1 && hour < 8) {
      if (modelId.contains('1h') || modelId.contains('4h')) {
        multiplier = 1.4;
      } else if (modelId.contains('5m') || modelId.contains('15m')) {
        multiplier = 0.7;
      }
      // ignore: avoid_print
      print('🌏 [Asia Session] Model $modelId: weight ${baseWeight.toStringAsFixed(2)} → ${(baseWeight * multiplier).toStringAsFixed(2)}');
    }
    // EUROPE SESSION (8-14 UTC) - No adjustment (balanced trading)
    else if (hour >= 8 && hour < 14) {
      multiplier = 1.0;
      // ignore: avoid_print
      print('🇪🇺 [Europe Session] Model $modelId: weight ${baseWeight.toStringAsFixed(2)} (unchanged)');
    }
    // US SESSION (14-22 UTC) - Favor short timeframes (5m/15m), penalize long (1d/4h)
    else if (hour >= 14 && hour < 22) {
      if (modelId.contains('5m') || modelId.contains('15m')) {
        multiplier = 1.5;
      } else if (modelId.contains('1d') || modelId.contains('4h')) {
        multiplier = 0.5;
      }
      // ignore: avoid_print
      print('🇺🇸 [US Session] Model $modelId: weight ${baseWeight.toStringAsFixed(2)} → ${(baseWeight * multiplier).toStringAsFixed(2)}');
    }
    // OFF-HOURS (22-1 UTC) - No adjustment
    else {
      multiplier = 1.0;
      // ignore: avoid_print
      print('🌙 [Off-Hours] Model $modelId: weight ${baseWeight.toStringAsFixed(2)} (unchanged)');
    }

    return baseWeight * multiplier;
  } catch (e) {
    // ignore: avoid_print
    print('⚠️  [Time-Based Weights] Error: $e - using base weight');
    return baseWeight; // Safe fallback
  }
}

/// Exemplu de utilizare (doar pentru test rapid)
class CryptoMLExample {
  static Future<void> runExample() async {
    final mlService = CryptoMLService();
    await mlService.initialize();

    // DEPRECATED TEST CODE - New architecture requires real Binance symbols
    // Use ai_strategies_screen.dart or ai_prediction_page.dart for real testing

    final btcPrediction = await mlService.getPrediction(
      coin: 'btc',
      symbol: 'BTCEUR', // Now requires actual Binance symbol
      timeframe: '5m',
    );

    // ignore: avoid_print
    print('BTC Prediction: $btcPrediction');

    final allPredictions = await mlService.getAllPredictions(
      symbolMap: {
        'btc': 'BTCEUR',
        'eth': 'ETHEUR',
        'bnb': 'BNBEUR',
      },
      timeframe: '5m',
    );

    allPredictions.forEach((coin, prediction) {
      // ignore: avoid_print
      print('$coin: ${prediction.action} (${(prediction.confidence * 100).toStringAsFixed(1)}%)');
    });

    final ensemble = mlService.getEnsemblePrediction(allPredictions.values.toList());
    // ignore: avoid_print
    print('\n📊 ENSEMBLE PREDICTION: $ensemble');
  }
}



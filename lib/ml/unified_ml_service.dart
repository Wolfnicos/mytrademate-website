import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'dart:convert' show utf8;
// import 'package:tflite_flutter/tflite_flutter.dart';
// import '../services/full_feature_builder.dart';
import '../services/binance_service.dart';
import 'model_registry.dart';
import 'crypto_ml_service.dart';

/// Unified ML Service:
/// - Loads Model Registry from assets
/// - Normalizes labels to [SELL,HOLD,BUY]
/// - Applies per-model temperature scaling (+bias on logits)
/// - Weighted averaging ensemble using weights from registry
/// - Confidence gating per timeframe
/// - Feature parity guard via feature_hash
/// - Consistent fallback when models/data missing
class UnifiedMLService {
  static final UnifiedMLService _instance = UnifiedMLService._internal();
  factory UnifiedMLService() => _instance;
  UnifiedMLService._internal();

  ModelRegistryV1? _registry;
  bool _initialized = false;

  bool get isInitialized => _initialized;

  Future<void> initialize() async {
    try {
      _registry = await ModelRegistryV1.loadFromAssets();
      _initialized = true;
      debugPrint('✅ UnifiedMLService initialized with registry schema=${_registry?.schema ?? ''}'); 
    } catch (e) {
      _initialized = false;
      debugPrint('❌ UnifiedMLService: failed to load registry → $e');
    }
  }

  /// Compute features and return a unified decision
  Future<UnifiedDecisionResult> predict({
    required String symbol, // e.g., BTCUSDT
    required String timeframe, // '15m','1h','4h','1d','7d'
  }) async {
    final ModelRegistryV1? reg = _registry;
    if (!_initialized || reg == null) {
      // Unified telemetry log
      _logTelemetry(
        coin: _extractBase(symbol),
        tf: timeframe,
        ids: const <String>[],
        weights: const <double>[],
        temps: const <double>[],
        pFinal: const <double>[0.33, 0.34, 0.33],
        action: 'HOLD',
        confidence: 0.33,
        confThresh: 0.0,
        featureHashOk: false,
        reason: 'registry_not_loaded',
      );
      return UnifiedDecisionResult(
        action: 'HOLD',
        confidence: 0.33,
        probabilities: const <double>[0.33, 0.34, 0.33],
        timeframe: timeframe,
        usedModelIds: const <String>[],
        featureHashOk: false,
        reason: 'registry_not_loaded',
      );
    }

    // Feature-parity guard BEFORE inference
    final String runtimeHash = _computeRuntimeFeatureHash();
    if ((reg.featureHash).isNotEmpty && runtimeHash != reg.featureHash) {
      final String tfNormEarly = reg.normalizeTimeframe(timeframe);
      debugPrint('❌ UnifiedML: data_quality=BAD — feature hash mismatch. runtime=$runtimeHash expected=${reg.featureHash}');
      _logTelemetry(
        coin: _extractBase(symbol),
        tf: tfNormEarly,
        ids: const <String>[],
        weights: const <double>[],
        temps: const <double>[],
        pFinal: _fallbackProbs('HOLD'),
        action: 'HOLD',
        confidence: 0.33,
        confThresh: reg.thresholdForTimeframe(tfNormEarly),
        featureHashOk: false,
        reason: 'feature_hash_mismatch',
      );
      return UnifiedDecisionResult(
        action: 'HOLD',
        confidence: reg.fallback.confidence,
        probabilities: _fallbackProbs('HOLD'),
        timeframe: tfNormEarly,
        usedModelIds: const <String>[],
        featureHashOk: false,
        reason: 'feature_hash_mismatch',
      );
    }

    // Build features (60 x 76) or return fallback on insufficient candles
    List<List<double>> features;
    try {
      features = await BinanceService().getFeaturesForModel(symbol, interval: timeframe);
    } catch (e) {
      final String tfNormEarly = reg.normalizeTimeframe(timeframe);
      debugPrint('❌ UnifiedML: insufficient_data — failed to build features (e.g., SMA200 needs >=260 candles). error=$e');
      _logTelemetry(
        coin: _extractBase(symbol),
        tf: tfNormEarly,
        ids: const <String>[],
        weights: const <double>[],
        temps: const <double>[],
        pFinal: _fallbackProbs('HOLD'),
        action: 'HOLD',
        confidence: reg.fallback.confidence,
        confThresh: reg.thresholdForTimeframe(tfNormEarly),
        featureHashOk: false,
        reason: 'insufficient_data',
      );
      return UnifiedDecisionResult(
        action: reg.fallback.action,
        confidence: reg.fallback.confidence,
        probabilities: _fallbackProbs('HOLD'),
        timeframe: tfNormEarly,
        usedModelIds: const <String>[],
        featureHashOk: false,
        reason: 'insufficient_data',
      );
    }

    // Feature parity guard result (post-build confirmation)
    final bool featureHashOk = (reg.featureHash).isEmpty || _verifyRuntimeFeatureHash(reg.featureHash);

    final String coin = _extractBase(symbol);
    final String tfNorm = reg.normalizeTimeframe(timeframe);

    // Collect model predictions
    final selected = reg.selectModels(coinUpper: coin, timeframe: tfNorm);
    if (selected.isEmpty) {
      // If no per-coin models, try general-only for tf
      final general = reg.selectModels(coinUpper: '*', timeframe: tfNorm);
      if (general.isEmpty) {
        debugPrint('⚠️ UnifiedML: model unavailable for coin=$coin tf=$tfNorm → using registry fallback HOLD');
        _logTelemetry(
          coin: coin,
          tf: tfNorm,
          ids: const <String>[],
          weights: const <double>[],
          temps: const <double>[],
          pFinal: _fallbackProbs('HOLD'),
          action: reg.fallback.action,
          confidence: reg.fallback.confidence,
          confThresh: reg.thresholdForTimeframe(tfNorm),
          featureHashOk: true,
          reason: 'model_unavailable',
        );
        return UnifiedDecisionResult(
          action: reg.fallback.action,
          confidence: reg.fallback.confidence,
          probabilities: _fallbackProbs(reg.fallback.action),
          timeframe: tfNorm,
          usedModelIds: const <String>[],
          featureHashOk: featureHashOk,
          reason: 'model_unavailable',
        );
      }
    }
    final modelsToUse = selected.isNotEmpty ? selected : reg.selectModels(coinUpper: '*', timeframe: tfNorm);

    // ADAPTIVE MODEL SELECTION: Filter models based on market conditions
    final List<ModelEntry> adaptiveModels = _applyAdaptiveSelection(modelsToUse, features);

    // For execution, we rely on CryptoMLService interpreters naming convention
    // model ids align with coin+tf (e.g., btc_1h, general_1h)
    final probsAccum = List<double>.filled(3, 0.0);
    double totalW = 0.0;
    final usedIds = <String>[];
    final usedWeights = <double>[];
    final usedTemps = <double>[];

    for (final m in adaptiveModels) {
      try {
        final Map<String, double> pMap = await _predictWithCryptoService(modelId: m.id, coin: m.coin, timeframe: m.tf, features: features);
        // Normalize incoming labels to registry order
        final List<double> p = _reorderToRegistry(pMap, m.labels, reg.labelOrder);
        // Apply bias on logits then temperature scaling
        final List<double> pCal = _calibrate(p, temperature: m.temp, bias: m.bias);
        // Weighted sum
        probsAccum[0] += pCal[0] * m.w;
        probsAccum[1] += pCal[1] * m.w;
        probsAccum[2] += pCal[2] * m.w;
        totalW += m.w;
        usedIds.add(m.id);
        usedWeights.add(m.w);
        usedTemps.add(m.temp);
      } catch (e) {
        debugPrint('⚠️ UnifiedMLService: model ${m.id} failed → $e');
      }
    }

    if (totalW <= 0) {
      // Telemetry
      _logTelemetry(
        coin: coin,
        tf: tfNorm,
        ids: usedIds,
        weights: usedWeights,
        temps: usedTemps,
        pFinal: _fallbackProbs('HOLD'),
        action: reg.fallback.action,
        confidence: reg.fallback.confidence,
        confThresh: reg.thresholdForTimeframe(tfNorm),
        featureHashOk: featureHashOk,
        reason: 'no_active_models',
      );
      return UnifiedDecisionResult(
        action: reg.fallback.action,
        confidence: reg.fallback.confidence,
        probabilities: _fallbackProbs(reg.fallback.action),
        timeframe: tfNorm,
        usedModelIds: usedIds,
        featureHashOk: featureHashOk,
        reason: 'no_active_models',
      );
    }

    // Normalize final ensemble
    final List<double> pFinal = probsAccum.map((v) => v / totalW).toList(growable: false);

    // Apply consensus bonus if multiple models strongly agree
    final consensusResult = _applyConsensusBonus(pFinal, usedIds.length);
    final List<double> pFinalWithBonus = consensusResult.probabilities;
    final String consensusReason = consensusResult.reason;

    // METADATA FILTER: Check signal quality before trading
    final bool shouldTrade = _shouldTradeBasedOnMetadata(features);
    if (!shouldTrade) {
      // Low volume or poor market conditions - force HOLD
      debugPrint('🚫 [Metadata Filter] LOW VOLUME or poor conditions → forcing HOLD');
      _logTelemetry(
        coin: coin,
        tf: tfNorm,
        ids: usedIds,
        weights: usedWeights,
        temps: usedTemps,
        pFinal: pFinalWithBonus,
        action: 'HOLD',
        confidence: pFinalWithBonus[1],
        confThresh: reg.thresholdForTimeframe(tfNorm),
        featureHashOk: featureHashOk,
        reason: 'metadata_filter_low_volume',
      );
      return UnifiedDecisionResult(
        action: 'HOLD',
        confidence: pFinalWithBonus[1],
        probabilities: pFinalWithBonus,
        timeframe: tfNorm,
        usedModelIds: usedIds,
        featureHashOk: featureHashOk,
        reason: 'metadata_filter_low_volume',
      );
    }

    // Gating by timeframe threshold + optional risk adjustment based on volatility z-score
    double gate = reg.thresholdForTimeframe(tfNorm);
    double usedGate = gate;
    String reason = consensusReason.isNotEmpty ? consensusReason : 'ok';

    // Optional: risk-based threshold bump if volatility is high
    final double? volZ = _estimateVolatilityZ(features);
    if (volZ != null && reg.risk != null && volZ > reg.risk!.volZLimit && reg.risk!.volThreshIncrement > 0) {
      usedGate = (gate + reg.risk!.volThreshIncrement).clamp(0.0, 0.95);
    }

    final int argMax = _argmax(pFinalWithBonus);
    final double conf = pFinalWithBonus[argMax];

    if (conf < usedGate) {
      // Telemetry
      _logTelemetry(
        coin: coin,
        tf: tfNorm,
        ids: usedIds,
        weights: usedWeights,
        temps: usedTemps,
        pFinal: pFinalWithBonus,
        action: 'HOLD',
        confidence: pFinalWithBonus[1],
        confThresh: usedGate,
        featureHashOk: featureHashOk,
        reason: 'below_threshold',
      );
      return UnifiedDecisionResult(
        action: 'HOLD',
        confidence: pFinalWithBonus[1],
        probabilities: pFinalWithBonus,
        timeframe: tfNorm,
        usedModelIds: usedIds,
        featureHashOk: featureHashOk,
        reason: 'below_threshold',
      );
    }

    final String action = reg.labelOrder[argMax];
    // Telemetry
    _logTelemetry(
      coin: coin,
      tf: tfNorm,
      ids: usedIds,
      weights: usedWeights,
      temps: usedTemps,
      pFinal: pFinalWithBonus,
      action: action,
      confidence: conf,
      confThresh: usedGate,
      featureHashOk: featureHashOk,
      reason: reason,
    );
    return UnifiedDecisionResult(
      action: action,
      confidence: conf,
      probabilities: pFinalWithBonus,
      timeframe: tfNorm,
      usedModelIds: usedIds,
      featureHashOk: featureHashOk,
      reason: reason,
    );
  }

  // --- Helpers ---
  String _extractBase(String symbol) {
    // BTCUSDT, BTCEUR, BTC/USDT
    String s = symbol.replaceAll('/', '').toUpperCase();
    for (final q in const <String>['USDT','USDC','USD','EUR']) {
      if (s.endsWith(q)) {
        return s.substring(0, s.length - q.length);
      }
    }
    return s;
  }

  void _logTelemetry({
    required String coin,
    required String tf,
    required List<String> ids,
    required List<double> weights,
    required List<double> temps,
    required List<double> pFinal,
    required String action,
    required double confidence,
    required double confThresh,
    required bool featureHashOk,
    required String reason,
  }) {
    final String weightsStr = weights.isEmpty ? '[]' : '[${weights.map((w) => w.toStringAsFixed(2)).join(', ')}]';
    final String tempsStr = temps.isEmpty ? '[]' : '[${temps.map((t) => t.toStringAsFixed(2)).join(', ')}]';
    final String pStr = '[${pFinal.map((p) => p.toStringAsFixed(4)).join(', ')}]';
    final String dq = featureHashOk ? 'OK' : 'BAD';
    debugPrint('');
    debugPrint('🎯 ENSEMBLE PREDICTION $coin @ ${tf.toUpperCase()}');
    debugPrint('models_used=$ids, weights=$weightsStr, temps=$tempsStr, labels=["SELL","HOLD","BUY"]');
    debugPrint('P_final=$pStr, action=$action, confidence=${confidence.toStringAsFixed(4)}, confThresh=${confThresh.toStringAsFixed(2)}');
    debugPrint('data_quality=$dq${reason.isNotEmpty ? ', reason=$reason' : ''}');
  }

  Future<Map<String, double>> _predictWithCryptoService({required String modelId, required String coin, required String timeframe, required List<List<double>> features}) async {
    // DEPRECATED: This method is no longer compatible with new multi-timeframe fetch architecture
    // CryptoMLService now fetches candles internally for each model's timeframe
    throw UnimplementedError('_predictWithCryptoService is deprecated. Use CryptoMLService.getPrediction directly with symbol parameter.');

    // OLD CODE (kept for reference):
    // if (!CryptoMLService().isModelLoaded(coin.toLowerCase(), timeframe)) {
    //   await CryptoMLService().loadModel(coin.toLowerCase(), timeframe);
    // }
    // final pred = await CryptoMLService().getPrediction(
    //   coin: coin == '*' ? 'general' : coin.toLowerCase(),
    //   symbol: 'UNKNOWN', // Would need actual symbol here
    //   timeframe: timeframe,
    // );
    // return pred.probabilities;
  }

  List<double> _reorderToRegistry(Map<String, double> pMap, List<String> modelLabels, List<String> registryOrder) {
    // Ensure we can handle binary outputs (HOLD might be 0)
    final double sell = pMap['SELL'] ?? 0.0;
    final double hold = pMap['HOLD'] ?? 0.0;
    final double buy = pMap['BUY'] ?? 0.0;
    // Normalize to sum 1 across three slots (allow 0 HOLD for binary)
    double sum = sell + hold + buy;
    if (sum <= 0) {
      return const <double>[1/3, 1/3, 1/3];
    }
    final norm = <double>[sell / sum, hold / sum, buy / sum];
    // Registry order is fixed [SELL,HOLD,BUY]
    return norm;
  }

  List<double> _calibrate(List<double> probs, {required double temperature, required List<double> bias}) {
    // p -> logit clip, temperature scaling, then bias: softmax((logits / T) + bias)
    final double eps = 1e-6;
    final List<double> logits = <double>[
      math.log((probs[0]).clamp(eps, 1.0)),
      math.log((probs[1]).clamp(eps, 1.0)),
      math.log((probs[2]).clamp(eps, 1.0)),
    ];
    final double T = (temperature <= 0) ? 1.0 : temperature;
    final List<double> scaled = List<double>.generate(logits.length, (int i) {
      final double b = i < bias.length ? bias[i] : 0.0;
      return (logits[i] / T) + b;
    }, growable: false);
    return _softmax(scaled);
  }

  List<double> _softmax(List<double> logits) {
    final double maxLogit = logits.reduce(math.max);
    final List<double> expVals = logits.map((l) => math.exp(l - maxLogit)).toList(growable: false);
    final double sumExp = expVals.reduce((a, b) => a + b);
    if (sumExp <= 0) {
      return const <double>[1/3, 1/3, 1/3];
    }
    return expVals.map((e) => e / sumExp).toList(growable: false);
  }

  int _argmax(List<double> v) {
    int idx = 0; double best = v[0];
    for (int i = 1; i < v.length; i++) {
      if (v[i] > best) { best = v[i]; idx = i; }
    }
    return idx;
  }

  List<double> _fallbackProbs(String action) {
    switch (action) {
      case 'SELL':
        return const <double>[0.6, 0.2, 0.2];
      case 'BUY':
        return const <double>[0.2, 0.2, 0.6];
      default:
        return const <double>[0.33, 0.34, 0.33];
    }
  }

  // (removed old _checkFeatureHash) — now using runtime hash verification

  // Compose deterministic feature spec string and compute SHA256
  String _computeRuntimeFeatureHash() {
    // NOTE: Keep this spec in sync with FullFeatureBuilder
    // keep list in spec string to avoid unused variable warning
    const String spec =
      'features:76;window:60;'
      'patterns:'
      'doji,dragonfly_doji,gravestone_doji,long_legged_doji,hammer,inverted_hammer,shooting_star,hanging_man,'
      'spinning_top,marubozu_bullish,marubozu_bearish,bullish_engulfing,bearish_engulfing,piercing_line,'
      'dark_cloud_cover,bullish_harami,bearish_harami,tweezer_bottom,tweezer_top,morning_star,evening_star,'
      'three_white_soldiers,three_black_crows,rising_three,falling_three;'
      'price_action:returns,log_returns,volatility,hl_range,close_position;'
      'rsi:14;'
      'macd:12,26,9;'
      'bollinger:20,2.0;'
      'atr:14;'
      'adx:14;'
      'stoch:14,k3;'
      'ichimoku:tenkan9,kijun26,senkouB52;'
      'volume_sma:20;'
      'ma:20,50,200;'
      'trend:higher_high,lower_low,uptrend,downtrend;'
      'scaler:identity_76';
    final List<int> bytes = utf8.encode(spec);
    return crypto.sha256.convert(bytes).toString();
  }

  bool _verifyRuntimeFeatureHash(String expected) {
    try {
      final String current = _computeRuntimeFeatureHash();
      return current == expected;
    } catch (_) {
      return false;
    }
  }

  // Simple realized volatility z-score estimator over the last 60 closes (approx from features)
  // We approximate close returns as first price-action feature (returns). If unavailable, return null.
  double? _estimateVolatilityZ(List<List<double>> features) {
    try {
      if (features.isEmpty || features[0].length < 30) {
        return null;
      }
      // FullFeatureBuilder: index 25 = returns, 30 = RSI; use 25 as simple daily-ish return proxy
      final int n = features.length;
      final List<double> rets = List<double>.generate(n, (int i) => features[i][25]);

      double mean = 0.0;
      for (int i = 0; i < rets.length; i++) {
        mean += rets[i];
      }
      mean = mean / (rets.isEmpty ? 1 : rets.length);

      double variance = 0.0;
      for (int i = 0; i < rets.length; i++) {
        final double d = rets[i] - mean;
        variance += d * d;
      }
      final int denom = (rets.length > 1) ? (rets.length - 1) : 1;
      variance = variance / denom;
      final double stdev = math.sqrt(variance);

      // Use long-term typical stdev baseline (fallback)
      const double baseline = 0.01;
      if (baseline <= 0) {
        return null;
      }
      final double z = (stdev - baseline) / (baseline + 1e-12);
      return z;
    } catch (_) {
      return null;
    }
  }

  /// METADATA FILTER: Check if we should trade based on market conditions
  /// Returns false if volume is too low (< 30% of average)
  /// Does NOT modify features - only reads from them
  bool _shouldTradeBasedOnMetadata(List<List<double>> features) {
    try {
      if (features.isEmpty || features.first.length <= 4) {
        return true; // Safe default: allow trading if we can't calculate
      }

      // Volume is at feature index 4
      final volumeValues = features.map((row) => row[4]).toList();
      if (volumeValues.isEmpty || volumeValues.length < 2) {
        return true; // Safe default
      }

      // Calculate average volume
      final avgVolume = volumeValues.reduce((a, b) => a + b) / volumeValues.length;

      // Get latest volume
      final latestVolume = volumeValues.last;

      // Skip trading if volume is too low (< 30% of average)
      if (latestVolume < avgVolume * 0.3) {
        debugPrint('📉 [Volume Check] Current: ${latestVolume.toStringAsFixed(2)}, Avg: ${avgVolume.toStringAsFixed(2)} (${((latestVolume / avgVolume) * 100).toStringAsFixed(1)}%)');
        return false; // Low volume - don't trade
      }

      return true; // Normal volume - allow trading
    } catch (e) {
      debugPrint('⚠️ [Metadata Filter] Error: $e - defaulting to ALLOW trading');
      return true; // Safe default: allow trading on error
    }
  }

  /// ADAPTIVE MODEL SELECTION: Filter models based on market conditions
  /// High volatility → exclude long-timeframe models (1d, 4h)
  /// Low volume → trust only higher timeframes (1h, 1d)
  /// Normal conditions → use all models
  List<ModelEntry> _applyAdaptiveSelection(List<ModelEntry> models, List<List<double>> features) {
    if (models.isEmpty || features.isEmpty) {
      return models;
    }

    // Calculate market conditions from features
    final double? atr = _calculateATR(features);
    final double? volumePercentile = _calculateVolumePercentile(features);

    // If we can't calculate conditions, use all models (safe fallback)
    if (atr == null || volumePercentile == null) {
      debugPrint('📊 [Adaptive Selection] Using all ${models.length} models (no market data)');
      return models;
    }

    // HIGH VOLATILITY: Exclude long-timeframe models (too slow to react)
    if (atr > 2.0) {
      final filtered = models.where((m) => !['1d', '7d', '4h'].contains(m.tf)).toList();
      if (filtered.isNotEmpty) {
        debugPrint('⚡ [Adaptive Selection] HIGH VOLATILITY (ATR=$atr) → using ${filtered.length}/${models.length} models (excluded 1d/4h)');
        return filtered;
      }
    }

    // LOW VOLUME: Trust only higher timeframes (less noise)
    if (volumePercentile < 30) {
      final filtered = models.where((m) => ['1h', '4h', '1d', '7d'].contains(m.tf)).toList();
      if (filtered.isNotEmpty) {
        debugPrint('🔇 [Adaptive Selection] LOW VOLUME (percentile=$volumePercentile) → using ${filtered.length}/${models.length} models (1h+ only)');
        return filtered;
      }
    }

    // NORMAL CONDITIONS: Use all models
    debugPrint('✅ [Adaptive Selection] NORMAL CONDITIONS (ATR=$atr, vol=$volumePercentile) → using all ${models.length} models');
    return models;
  }

  /// Calculate ATR (Average True Range) from features
  /// ATR is typically in feature indices 20-25 (depending on feature engineering)
  double? _calculateATR(List<List<double>> features) {
    try {
      // ATR is feature index 21 in our 76-feature pipeline
      // (close, open, high, low, volume, sma5-200, ema12-200, rsi, macd, bb, atr, obv, etc.)
      final atrValues = features.map((row) => row.length > 21 ? row[21] : 0.0).toList();
      if (atrValues.isEmpty) return null;

      // Return average ATR across all candles
      return atrValues.reduce((a, b) => a + b) / atrValues.length;
    } catch (e) {
      debugPrint('⚠️ [ATR Calculation] Failed: $e');
      return null;
    }
  }

  /// Calculate volume percentile from features
  /// Returns percentile (0-100) of current volume vs recent history
  double? _calculateVolumePercentile(List<List<double>> features) {
    try {
      // Volume is feature index 4 in our 76-feature pipeline
      final volumeValues = features.map((row) => row.length > 4 ? row[4] : 0.0).toList();
      if (volumeValues.isEmpty || volumeValues.length < 2) return null;

      // Calculate percentile of latest volume vs historical
      final latestVolume = volumeValues.last;
      final sorted = List<double>.from(volumeValues)..sort();
      final rank = sorted.indexWhere((v) => v >= latestVolume);

      return (rank / sorted.length) * 100.0;
    } catch (e) {
      debugPrint('⚠️ [Volume Percentile] Failed: $e');
      return null;
    }
  }

  /// Apply consensus bonus when multiple models strongly agree
  /// Returns modified probabilities with potential confidence boost
  _ConsensusResult _applyConsensusBonus(List<double> probs, int modelCount) {
    // Need at least 3 models for meaningful consensus
    if (modelCount < 3) {
      return _ConsensusResult(probabilities: probs, reason: '');
    }

    // Check if we have strong agreement (one action has >55% probability)
    final int argMax = _argmax(probs);
    final double maxProb = probs[argMax];

    if (maxProb < 0.55) {
      // No strong consensus
      return _ConsensusResult(probabilities: probs, reason: '');
    }

    // Apply consensus bonus: boost the winning action by up to 15%
    // The more models agree, the stronger the boost
    final double consensusStrength = (maxProb - 0.55) / 0.45; // 0.0 to 1.0
    final double boost = 0.15 * consensusStrength; // Up to 15% boost

    // Create boosted probabilities
    final List<double> boosted = List<double>.from(probs);
    boosted[argMax] = math.min(0.95, boosted[argMax] + boost);

    // Renormalize to ensure sum = 1.0
    final double sum = boosted.reduce((a, b) => a + b);
    final List<double> normalized = boosted.map((p) => p / sum).toList(growable: false);

    final String action = argMax == 0 ? 'SELL' : (argMax == 2 ? 'BUY' : 'HOLD');
    debugPrint('🤝 [Consensus Bonus] $modelCount models agree on $action: ${maxProb.toStringAsFixed(3)} → ${normalized[argMax].toStringAsFixed(3)} (+${boost.toStringAsFixed(3)})');

    return _ConsensusResult(
      probabilities: normalized,
      reason: 'consensus_boost_$action',
    );
  }
}

/// Result of consensus bonus calculation
class _ConsensusResult {
  final List<double> probabilities;
  final String reason;

  _ConsensusResult({required this.probabilities, required this.reason});
}

// Global singleton
final UnifiedMLService unifiedMLService = UnifiedMLService();



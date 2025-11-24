import 'package:flutter/foundation.dart';
import 'dart:math';
import '../crypto_ml_service.dart';
import '../microstructure/exchange_microstructure_analyzer.dart';
import '../rules/trading_rule_engine.dart';
import '../../services/base_exchange_service.dart';

/// Hybrid Prediction Engine
///
/// Combines ML predictions with microstructure analysis and trading rules.
///
/// CRITICAL SAFETY FEATURES:
/// - Disabled by default (isEnabled = false)
/// - kDebugMode guard (only runs in debug mode initially)
/// - NEVER contradicts ML predictions (same signal direction)
/// - NEVER reduces confidence below original ML confidence
/// - Returns original prediction on ANY error
/// - No new API calls (uses existing data)
///
/// Enhancement strategy:
/// 1. Get ML prediction (existing 20-model ensemble)
/// 2. Analyze microstructure (if enabled)
/// 3. Check trading rules (if enabled)
/// 4. Combine signals SAFELY (only boost confidence if all agree)
class HybridPredictionEngine {
  /// 🔒 SAFETY: Master feature flag (DEFAULT: DISABLED)
  static bool isEnabled = true;

  /// Enhance an existing ML prediction with microstructure + rules
  ///
  /// GUARANTEES:
  /// - Never returns null (returns original on error)
  /// - Never changes signal direction
  /// - Never reduces confidence
  /// - Fails silently on any error
  ///
  /// Parameters:
  /// - original: ML prediction from existing 20-model ensemble
  /// - coin: Coin symbol (BTC, ETH, etc.)
  /// - symbol: Trading pair (BTCUSDT, ETHEUR, etc.)
  /// - timeframe: Timeframe (5m, 15m, 1h, 4h, 1d)
  /// - exchangeService: Exchange service (for getting exchange name)
  ///
  /// Returns:
  /// - Enhanced prediction with potentially higher confidence
  /// - Original prediction on any error
  static Future<CryptoPrediction> enhance(
    CryptoPrediction original, {
    required String coin,
    required String symbol,
    required String timeframe,
    required BaseExchangeService? exchangeService,
  }) async {
    // SAFETY CHECK 1: Master flag
    if (!isEnabled) return original;

    // SAFETY CHECK 2: Debug mode only (initially)
    if (!kDebugMode) return original;

    try {
      debugPrint('[HybridPrediction] 🔬 Enhancing $coin prediction: ${original.action} (${(original.confidence * 100).toStringAsFixed(1)}%)');

      // STEP 1: Get microstructure features (using existing VolumeProfileService)
      Map<String, double>? microFeatures;
      if (ExchangeMicrostructureAnalyzer.isEnabled) {
        try {
          microFeatures = await ExchangeMicrostructureAnalyzer.analyze(
            coin: coin,
            symbol: symbol,
            exchange: exchangeService?.exchangeName ?? 'Binance',
          );
        } catch (e) {
          debugPrint('[HybridPrediction] ⚠️ Microstructure analysis failed: $e');
          microFeatures = null; // Continue without microstructure
        }
      }

      // STEP 2: Check trading rules (using existing candle data)
      RuleSignal? ruleSignal;
      if (TradingRuleEngine.isEnabled) {
        try {
          ruleSignal = await TradingRuleEngine.evaluate(
            coin: coin,
            symbol: symbol,
            timeframe: timeframe,
            mlSignal: original.action,
          );
        } catch (e) {
          debugPrint('[HybridPrediction] ⚠️ Rule evaluation failed: $e');
          ruleSignal = null; // Continue without rules
        }
      }

      // STEP 3: Check for microstructure OVERRIDE conditions
      final overrideResult = _checkMicrostructureOverride(
        original: original,
        microFeatures: microFeatures,
      );

      if (overrideResult != null) {
        debugPrint('[HybridPrediction] ⚠️ MICROSTRUCTURE OVERRIDE: ${original.action} → ${overrideResult.action}');
        debugPrint('[HybridPrediction] Reason: ${overrideResult.decisionReason}');
        return overrideResult;
      }

      // STEP 4: AGGRESSIVE combination - calculate enhanced confidence
      final enhancedConfidence = _calculateEnhancedConfidence(
        mlConfidence: original.confidence,
        mlAction: original.action,
        microFeatures: microFeatures,
        ruleSignal: ruleSignal,
        volumePercentile: original.volumePercentile,
      );

      // Allow confidence reduction if microstructure strongly disagrees
      final finalConfidence = enhancedConfidence;

      debugPrint('[HybridPrediction] ✅ Enhanced confidence: ${(original.confidence * 100).toStringAsFixed(1)}% → ${(finalConfidence * 100).toStringAsFixed(1)}%');

      // STEP 5: Detect conflicts for UI
      final conflictIndicator = _detectConflict(
        mlAction: original.action,
        microFeatures: microFeatures,
      );

      // STEP 6: Return enhanced prediction (can change signal if overridden)
      return CryptoPrediction(
        action: original.action,
        confidence: finalConfidence,
        probabilities: original.probabilities,
        signalStrength: original.signalStrength,
        modelAccuracy: original.modelAccuracy,
        timestamp: original.timestamp,
        isEnsemble: true,
        atr: original.atr,
        volumePercentile: original.volumePercentile,
        decisionReason: _buildDecisionReason(
          original.decisionReason,
          microFeatures,
          ruleSignal,
          conflictIndicator,
        ),
      );

    } catch (e) {
      // SAFETY: Return original prediction on ANY error
      debugPrint('[HybridPrediction] ❌ Enhancement error: $e');
      debugPrint('[HybridPrediction] 🔙 Returning original prediction');
      return original;
    }
  }

  /// Calculate enhanced confidence by combining ML + microstructure + rules
  ///
  /// AGGRESSIVE Enhancement logic:
  /// - Start with ML confidence (baseline)
  /// - Add +5-30% if microstructure confirms (based on volume)
  /// - Subtract up to -20% if microstructure strongly disagrees
  /// - Add +up to 10% if rules confirm signal
  /// - Cap at 0.95 maximum, floor at 0.15 minimum
  static double _calculateEnhancedConfidence({
    required double mlConfidence,
    required String mlAction,
    Map<String, double>? microFeatures,
    RuleSignal? ruleSignal,
    double? volumePercentile,
  }) {
    // Start with ML confidence (baseline)
    var confidence = mlConfidence;

    // Boost 1: AGGRESSIVE Microstructure (5-30% based on volume)
    if (microFeatures != null && microFeatures.isNotEmpty) {
      final signalMatch = microFeatures['signal_match'] ?? 0.0;
      final volumePct = (volumePercentile ?? 50.0) / 100.0; // 0.0-1.0

      // Calculate microstructure impact (5-30% based on volume)
      final baseImpact = 0.05; // 5% minimum
      final volumeBonus = volumePct > 0.7 ? (volumePct - 0.7) * 0.83 : 0.0; // Up to 25% extra when volume > 70th percentile
      final maxImpact = baseImpact + volumeBonus; // 5-30%

      if (mlAction == 'HOLD') {
        // Special logic for HOLD - be CONSERVATIVE
        // HOLD means ML is uncertain, so microstructure can guide better

        // Check if microstructure is also neutral (confirms uncertainty)
        final bool microNeutral = signalMatch.abs() < 0.3; // Very neutral

        // Check if microstructure has clear opinion
        final bool microBullish = signalMatch > 0.5;
        final bool microBearish = signalMatch < -0.5;

        if (microNeutral) {
          // Microstructure also uncertain → boost HOLD confidence slightly
          confidence += 0.03; // +3% when both agree market is unclear
          debugPrint('[HybridPrediction] ⚖️  Microstructure NEUTRAL, confirms HOLD (+3%)');
        } else if (microBullish || microBearish) {
          // Microstructure has opinion but ML says HOLD
          // Reduce HOLD confidence SLIGHTLY to reflect conflict
          final reduction = maxImpact * 0.3; // Only 30% of normal impact (1.5-9%)
          confidence -= reduction;
          final direction = microBullish ? 'BUY' : 'SELL';
          debugPrint('[HybridPrediction] ⚠️  HOLD but orderbook suggests $direction (-${(reduction * 100).toStringAsFixed(1)}%)');
        }
      } else {
        // Normal BUY/SELL logic
        // Check if microstructure confirms ML signal
        final bool microConfirms = (mlAction == 'BUY' && signalMatch > 0.5) ||
            (mlAction == 'SELL' && signalMatch < -0.5);

        // Check if microstructure STRONGLY disagrees
        final bool microDisagrees = (mlAction == 'BUY' && signalMatch < -0.5) ||
            (mlAction == 'SELL' && signalMatch > 0.5);

        if (microConfirms) {
          confidence += maxImpact;
          debugPrint('[HybridPrediction] 📈 Microstructure confirms $mlAction (+${(maxImpact * 100).toStringAsFixed(1)}%, vol=${(volumePct * 100).toStringAsFixed(0)}%)');
        } else if (microDisagrees) {
          // REDUCE confidence when microstructure disagrees
          final penalty = min(0.20, maxImpact * 2); // Up to -20% penalty
          confidence -= penalty;
          debugPrint('[HybridPrediction] 📉 Microstructure DISAGREES with $mlAction (-${(penalty * 100).toStringAsFixed(1)}%)');
        }
      }
    }

    // Boost 2: Rule confirmation (+up to 10%)
    if (ruleSignal != null && ruleSignal.signal == mlAction) {
      final ruleBoost = ruleSignal.confidence * 0.1; // Up to +10%
      confidence += ruleBoost;
      debugPrint('[HybridPrediction] 📋 Rules confirm $mlAction (+${(ruleBoost * 100).toStringAsFixed(1)}%)');
    }

    // Cap at 0.95 maximum, floor at 0.15 minimum
    return confidence.clamp(0.15, 0.95);
  }

  /// Build enhanced decision reason combining ML + microstructure + rules
  static String? _buildDecisionReason(
    String? originalReason,
    Map<String, double>? microFeatures,
    RuleSignal? ruleSignal,
    String? conflictIndicator,
  ) {
    if (originalReason == null) return null;

    final enhancements = <String>[];

    // Add conflict warning first (if present)
    if (conflictIndicator != null) {
      enhancements.add('⚠️ $conflictIndicator');
    }

    // Add microstructure insights
    if (microFeatures != null && microFeatures.isNotEmpty) {
      final bidAskRatio = microFeatures['bid_ask_ratio'];
      if (bidAskRatio != null) {
        if (bidAskRatio > 2.5) {
          enhancements.add('extreme buy pressure (${bidAskRatio.toStringAsFixed(1)}x)');
        } else if (bidAskRatio > 2.0) {
          enhancements.add('strong buy pressure');
        } else if (bidAskRatio < 0.4) {
          enhancements.add('extreme sell pressure (${bidAskRatio.toStringAsFixed(1)}x)');
        } else if (bidAskRatio < 0.5) {
          enhancements.add('strong sell pressure');
        }
      }
    }

    // Add rule insights
    if (ruleSignal != null) {
      enhancements.add(ruleSignal.reason);
    }

    // Combine with original reason
    if (enhancements.isEmpty) return originalReason;
    return '$originalReason + ${enhancements.join(", ")}';
  }

  /// Check if microstructure should OVERRIDE ML prediction
  ///
  /// Override conditions:
  /// 1. Microstructure confidence > 80% (very strong signal)
  /// 2. Opposes ML signal direction OR ML says HOLD
  /// 3. Extreme bid/ask ratio (<0.4 or >2.5)
  /// 4. High volume (>70th percentile)
  ///
  /// Returns: Override prediction or null
  static CryptoPrediction? _checkMicrostructureOverride({
    required CryptoPrediction original,
    Map<String, double>? microFeatures,
  }) {
    if (microFeatures == null || microFeatures.isEmpty) return null;

    final bidAskRatio = microFeatures['bid_ask_ratio'] ?? 1.0;
    final signalMatch = microFeatures['signal_match'] ?? 0.0;
    final volumePct = original.volumePercentile ?? 50.0;

    // Check override conditions
    final bool extremeBidAsk = bidAskRatio < 0.4 || bidAskRatio > 2.5;
    final bool highVolume = volumePct > 70.0; // More strict: 70th percentile
    final bool strongMicroSignal = signalMatch.abs() > 0.8; // 80% confidence

    // Determine microstructure signal
    String? microSignal;
    if (signalMatch > 0.8) {
      microSignal = 'BUY';
    } else if (signalMatch < -0.8) {
      microSignal = 'SELL';
    }

    if (microSignal == null) return null; // Microstructure not clear enough

    // Check if should override
    final bool opposes = (original.action == 'BUY' && microSignal == 'SELL') ||
                         (original.action == 'SELL' && microSignal == 'BUY');
    final bool mlUncertain = original.action == 'HOLD';

    // OVERRIDE if:
    // - ML opposes microstructure AND extreme conditions
    // - OR ML is uncertain (HOLD) AND microstructure very clear with extreme conditions
    if (strongMicroSignal && extremeBidAsk && highVolume && (opposes || mlUncertain)) {
      final reason = mlUncertain
          ? 'MICROSTRUCTURE OVERRIDE: ML uncertain (HOLD) but extreme market pressure (bid/ask=${bidAskRatio.toStringAsFixed(2)}, vol=${volumePct.toStringAsFixed(0)}%) clearly indicates $microSignal'
          : 'MICROSTRUCTURE OVERRIDE: ML said ${original.action} but extreme market pressure (bid/ask=${bidAskRatio.toStringAsFixed(2)}, vol=${volumePct.toStringAsFixed(0)}%) indicates $microSignal';

      return CryptoPrediction(
        action: microSignal, // Use microstructure signal
        confidence: 0.70, // Moderate-high confidence in override
        probabilities: original.probabilities,
        signalStrength: original.signalStrength,
        modelAccuracy: original.modelAccuracy,
        timestamp: original.timestamp,
        isEnsemble: true,
        atr: original.atr,
        volumePercentile: volumePct,
        decisionReason: reason,
      );
    }

    return null; // No override
  }

  /// Detect conflict between ML and microstructure signals
  ///
  /// Returns: Conflict description or null
  static String? _detectConflict({
    required String mlAction,
    Map<String, double>? microFeatures,
  }) {
    if (microFeatures == null || microFeatures.isEmpty) return null;

    final signalMatch = microFeatures['signal_match'] ?? 0.0;
    final bidAskRatio = microFeatures['bid_ask_ratio'] ?? 1.0;

    // Determine microstructure signal
    String? microSignal;
    if (signalMatch > 0.5) {
      microSignal = 'BUY';
    } else if (signalMatch < -0.5) {
      microSignal = 'SELL';
    } else {
      return null; // Neutral, no conflict
    }

    // Check for conflict
    if (mlAction != microSignal) {
      return 'ML=$mlAction vs Orderbook=$microSignal (ratio=${bidAskRatio.toStringAsFixed(2)})';
    }

    return null; // No conflict
  }

  /// Enable the hybrid prediction engine
  static void enable() {
    isEnabled = true;
    debugPrint('[HybridPrediction] ✅ Hybrid prediction engine ENABLED');
  }

  /// Disable the hybrid prediction engine
  static void disable() {
    isEnabled = false;
    debugPrint('[HybridPrediction] 🔒 Hybrid prediction engine DISABLED');
  }

  /// Enable all components (hybrid + microstructure + rules)
  static void enableAll() {
    HybridPredictionEngine.enable();
    ExchangeMicrostructureAnalyzer.enable();
    TradingRuleEngine.enable();
    debugPrint('[HybridPrediction] ✅ ALL hybrid components ENABLED');
  }

  /// Disable all components
  static void disableAll() {
    HybridPredictionEngine.disable();
    ExchangeMicrostructureAnalyzer.disable();
    TradingRuleEngine.disable();
    debugPrint('[HybridPrediction] 🔒 ALL hybrid components DISABLED');
  }
}

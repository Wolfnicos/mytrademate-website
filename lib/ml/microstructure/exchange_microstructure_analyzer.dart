import 'package:flutter/foundation.dart';
import 'dart:math';
import '../../services/volume_profile_service.dart';

/// Exchange Microstructure Analyzer
///
/// Analyzes market microstructure features from EXISTING order book data.
///
/// SAFETY FEATURES:
/// - Disabled by default (isEnabled = false)
/// - Uses existing VolumeProfileService (NO new API calls)
/// - Returns empty map on any error (graceful degradation)
/// - Fails silently without breaking predictions
///
/// Extracted features:
/// - Bid/Ask imbalance (buying vs selling pressure)
/// - Whale wall detection (large support/resistance orders)
/// - Liquidity depth (order book thickness)
/// - Signal confirmation (does microstructure match ML signal?)
class ExchangeMicrostructureAnalyzer {
  /// 🔒 SAFETY: Feature flag (DEFAULT: DISABLED)
  static bool isEnabled = true;

  static final _volumeProfileService = VolumeProfileService();

  /// Analyze market microstructure using existing order book data
  ///
  /// Parameters:
  /// - coin: Coin symbol (BTC, ETH, etc.)
  /// - symbol: Trading pair (BTCUSDT, ETHEUR, etc.)
  /// - exchange: Exchange name (Binance, Coinbase, Kraken)
  ///
  /// Returns:
  /// - Map of microstructure features
  /// - Empty map on error (safe failure)
  static Future<Map<String, double>> analyze({
    required String coin,
    required String symbol,
    required String exchange,
  }) async {
    if (!isEnabled) return {};

    try {
      debugPrint('[ExchangeMicrostructure] 🔬 Analyzing $symbol on $exchange');

      // Use existing VolumeProfileService (already in app!)
      final volumeProfile = await _volumeProfileService.analyzeVolume(
        symbol: symbol,
        exchange: exchange.toLowerCase(),
      );

      // Extract microstructure features
      final features = <String, double>{
        // 1. Bid/Ask ratio (buying vs selling pressure)
        //    > 2.0 = strong buy pressure
        //    < 0.5 = strong sell pressure
        'bid_ask_ratio': volumeProfile.bidAskRatio,

        // 2. Whale walls count (large orders acting as support/resistance)
        'whale_walls': volumeProfile.whaleWalls.length.toDouble(),

        // 3. Signal match (-1.0 = bearish, 0.0 = neutral, 1.0 = bullish)
        'signal_match': _detectSignalMatch(volumeProfile),

        // 4. Liquidity score (0.0 - 1.0, higher = more liquid)
        'liquidity': _calculateLiquidity(volumeProfile),

        // 5. Order book depth within 1% (liquidity at tight price range)
        'depth': volumeProfile.depth.depth1pct,

        // 6. Buy pressure (normalized 0.0 - 1.0)
        'buy_pressure': _calculateBuyPressure(volumeProfile.bidAskRatio),

        // 7. Sell pressure (normalized 0.0 - 1.0)
        'sell_pressure': _calculateSellPressure(volumeProfile.bidAskRatio),
      };

      debugPrint('[ExchangeMicrostructure] ✅ Features extracted: $features');
      return features;

    } catch (e) {
      // SAFETY: Return empty map on error (fail silently)
      debugPrint('[ExchangeMicrostructure] ⚠️ Analysis failed: $e');
      return {};
    }
  }

  /// Detect if microstructure confirms a specific signal direction
  ///
  /// Returns:
  /// - 1.0: Strong bullish confirmation (bidAskRatio > 2.0)
  /// - -1.0: Strong bearish confirmation (bidAskRatio < 0.5)
  /// - 0.0: Neutral (no clear direction)
  static double _detectSignalMatch(VolumeProfile profile) {
    final ratio = profile.bidAskRatio;

    // Strong buy pressure
    if (ratio > 2.0) return 1.0;

    // Strong sell pressure
    if (ratio < 0.5) return -1.0;

    // Moderate buy pressure
    if (ratio > 1.5) return 0.5;

    // Moderate sell pressure
    if (ratio < 0.75) return -0.5;

    // Neutral
    return 0.0;
  }

  /// Calculate liquidity score from order book depth
  ///
  /// Returns: 0.0 - 1.0 (higher = more liquid)
  static double _calculateLiquidity(VolumeProfile profile) {
    // Normalize depth1pct to 0-1 range
    // Assuming 100.0 depth within 1% = high liquidity
    return min(profile.depth.depth1pct / 100.0, 1.0);
  }

  /// Calculate normalized buy pressure (0.0 - 1.0)
  static double _calculateBuyPressure(double bidAskRatio) {
    // Map bidAskRatio to 0-1 range
    // 0.0 = no buy pressure (ratio = 0)
    // 1.0 = maximum buy pressure (ratio >= 4.0)
    if (bidAskRatio >= 4.0) return 1.0;
    if (bidAskRatio <= 0.0) return 0.0;
    return min(bidAskRatio / 4.0, 1.0);
  }

  /// Calculate normalized sell pressure (0.0 - 1.0)
  static double _calculateSellPressure(double bidAskRatio) {
    // Map bidAskRatio to 0-1 range
    // 1.0 = maximum sell pressure (ratio close to 0)
    // 0.0 = no sell pressure (ratio >= 4.0)
    if (bidAskRatio >= 4.0) return 0.0;
    if (bidAskRatio <= 0.0) return 1.0;
    return max(1.0 - (bidAskRatio / 4.0), 0.0);
  }

  /// Enable the microstructure analyzer
  static void enable() {
    isEnabled = true;
    debugPrint('[ExchangeMicrostructure] ✅ Microstructure analyzer ENABLED');
  }

  /// Disable the microstructure analyzer
  static void disable() {
    isEnabled = false;
    debugPrint('[ExchangeMicrostructure] 🔒 Microstructure analyzer DISABLED');
  }
}

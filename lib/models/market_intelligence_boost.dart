/// Market Intelligence Boost Model
///
/// Calculates confidence boost based on alignment between ML prediction
/// and external market indicators (Fear & Greed, News, Global Trends, etc.)
class MarketIntelligenceBoost {
  final int confidenceBoost; // -20% to +20%
  final String fearGreedLevel; // "Extreme Fear", "Fear", "Neutral", "Greed", "Extreme Greed"
  final int fearGreedValue; // 0-100
  final String newsSentiment; // "Bullish", "Neutral", "Bearish"
  final double newsSentimentScore; // -1.0 to 1.0
  final String globalMarketTrend; // "bullish", "neutral", "bearish"
  final double globalMarketCap; // Total market cap
  final double globalMarketCapChange24h; // % change
  final Map<String, double> multiExchangePrices; // Exchange -> Price
  final double priceSpread; // % spread between exchanges
  final List<String> reasonsForBoost; // Human-readable reasons

  const MarketIntelligenceBoost({
    required this.confidenceBoost,
    required this.fearGreedLevel,
    required this.fearGreedValue,
    required this.newsSentiment,
    required this.newsSentimentScore,
    required this.globalMarketTrend,
    required this.globalMarketCap,
    required this.globalMarketCapChange24h,
    required this.multiExchangePrices,
    required this.priceSpread,
    required this.reasonsForBoost,
  });

  /// Calculate confidence boost based on alignment with ML prediction
  static int calculateBoost({
    required String mlDirection, // BUY/SELL/HOLD
    required double mlConfidence,
    required int fearGreedValue,
    required double newsSentiment,
    required String marketTrend,
  }) {
    int boost = 0;

    // Fear & Greed alignment (±15%)
    // Contrarian logic: Buy when fearful, sell when greedy
    if (mlDirection == 'BUY' && fearGreedValue < 25) {
      boost += 15; // Extreme fear + buy = contrarian opportunity
    } else if (mlDirection == 'BUY' && fearGreedValue > 75) {
      boost -= 12; // Extreme greed + buy = risky (top buying)
    } else if (mlDirection == 'SELL' && fearGreedValue > 75) {
      boost += 15; // Extreme greed + sell = good timing (top selling)
    } else if (mlDirection == 'SELL' && fearGreedValue < 25) {
      boost -= 12; // Extreme fear + sell = might miss bottom
    }

    // News sentiment alignment (±8%)
    if (mlDirection == 'BUY' && newsSentiment > 0.6) {
      boost += 8; // Bullish news confirms buy
    } else if (mlDirection == 'SELL' && newsSentiment < -0.6) {
      boost += 8; // Bearish news confirms sell
    } else if (mlDirection == 'BUY' && newsSentiment < -0.6) {
      boost -= 8; // Bearish news contradicts buy
    } else if (mlDirection == 'SELL' && newsSentiment > 0.6) {
      boost -= 8; // Bullish news contradicts sell
    }

    // Global market trend alignment (±5%)
    if (marketTrend == 'bullish' && mlDirection == 'BUY') {
      boost += 5; // Bull market confirms buy
    } else if (marketTrend == 'bearish' && mlDirection == 'SELL') {
      boost += 5; // Bear market confirms sell
    } else if (marketTrend == 'bullish' && mlDirection == 'SELL') {
      boost -= 5; // Selling in bull market
    } else if (marketTrend == 'bearish' && mlDirection == 'BUY') {
      boost -= 5; // Buying in bear market
    }

    // Clamp to ±20%
    return boost.clamp(-20, 20);
  }

  /// Generate human-readable reasons for the boost
  static List<String> generateReasons({
    required int boost,
    required String mlDirection,
    required int fearGreedValue,
    required double newsSentiment,
    required String marketTrend,
  }) {
    final List<String> reasons = [];

    if (boost > 0) {
      reasons.add('✓ Market conditions SUPPORT $mlDirection signal (+$boost%)');
    } else if (boost < 0) {
      reasons.add('⚠ Market conditions CONTRADICT $mlDirection signal ($boost%)');
    } else {
      reasons.add('○ Neutral market conditions (no boost)');
    }

    // Fear & Greed reasoning
    if (mlDirection == 'BUY' && fearGreedValue < 25) {
      reasons.add('✓ Extreme Fear ($fearGreedValue/100) - good contrarian entry');
    } else if (mlDirection == 'SELL' && fearGreedValue > 75) {
      reasons.add('✓ Extreme Greed ($fearGreedValue/100) - good time to exit');
    } else if (mlDirection == 'BUY' && fearGreedValue > 75) {
      reasons.add('⚠ Extreme Greed ($fearGreedValue/100) - risky to buy high');
    } else if (mlDirection == 'SELL' && fearGreedValue < 25) {
      reasons.add('⚠ Extreme Fear ($fearGreedValue/100) - might sell bottom');
    }

    // News sentiment reasoning
    final sentimentStr = newsSentiment > 0.6
        ? 'Bullish'
        : newsSentiment < -0.6
            ? 'Bearish'
            : 'Neutral';
    if ((mlDirection == 'BUY' && newsSentiment > 0.6) ||
        (mlDirection == 'SELL' && newsSentiment < -0.6)) {
      reasons.add('✓ $sentimentStr news confirms ML prediction');
    } else if ((mlDirection == 'BUY' && newsSentiment < -0.6) ||
        (mlDirection == 'SELL' && newsSentiment > 0.6)) {
      reasons.add('⚠ $sentimentStr news contradicts ML prediction');
    }

    // Market trend reasoning
    if ((mlDirection == 'BUY' && marketTrend == 'bullish') ||
        (mlDirection == 'SELL' && marketTrend == 'bearish')) {
      reasons.add('✓ ${marketTrend.toUpperCase()} global trend aligned');
    } else if ((mlDirection == 'BUY' && marketTrend == 'bearish') ||
        (mlDirection == 'SELL' && marketTrend == 'bullish')) {
      reasons.add('⚠ ${marketTrend.toUpperCase()} global trend contradicts');
    }

    return reasons;
  }

  /// Apply boost to ML confidence
  double applyBoost(double originalConfidence) {
    final boosted = originalConfidence + (confidenceBoost / 100);
    return boosted.clamp(0.0, 1.0);
  }
}

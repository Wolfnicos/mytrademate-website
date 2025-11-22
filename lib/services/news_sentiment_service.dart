import 'package:flutter/foundation.dart';

/// News Sentiment Service
///
/// Simplified sentiment analysis based on price momentum and volume
/// (Alternative: Could integrate CryptoPanic API or NewsAPI for real news)
class NewsSentimentService {
  static final NewsSentimentService _instance = NewsSentimentService._internal();
  factory NewsSentimentService() => _instance;
  NewsSentimentService._internal();

  /// Get news sentiment for a symbol
  ///
  /// Simplified version: Uses price momentum as proxy for sentiment
  /// (Real version would fetch actual news from CryptoPanic/NewsAPI)
  Future<NewsSentiment> getNewsSentiment({
    required String symbol,
    double? priceChange24h,
    double? volumeChange24h,
  }) async {
    try {
      // Simplified sentiment calculation based on momentum
      // In production, this would fetch real news from APIs
      final sentimentScore = _calculateSentimentFromMomentum(
        priceChange24h ?? 0.0,
        volumeChange24h ?? 0.0,
      );

      final sentiment = sentimentScore > 0.3
          ? 'Bullish'
          : sentimentScore < -0.3
              ? 'Bearish'
              : 'Neutral';

      debugPrint('[NewsSentiment] 📰 Sentiment for $symbol: $sentiment (${(sentimentScore * 100).toStringAsFixed(1)}%)');

      return NewsSentiment(
        symbol: symbol,
        sentimentScore: sentimentScore,
        overallSentiment: sentiment,
        articlesAnalyzed: 0, // Placeholder - would be actual count with real API
      );
    } catch (e) {
      debugPrint('[NewsSentiment] ❌ Error calculating sentiment: $e');
      return NewsSentiment(
        symbol: symbol,
        sentimentScore: 0.0,
        overallSentiment: 'Neutral',
        articlesAnalyzed: 0,
      );
    }
  }

  /// Calculate sentiment from price/volume momentum
  /// Returns value between -1.0 (very bearish) and 1.0 (very bullish)
  double _calculateSentimentFromMomentum(double priceChange, double volumeChange) {
    // Strong positive momentum = bullish sentiment
    double sentiment = 0.0;

    // Price change component (-50% to +50% → -0.5 to +0.5)
    sentiment += (priceChange / 100).clamp(-0.5, 0.5);

    // Volume change component (high volume amplifies sentiment)
    if (volumeChange > 50 && priceChange > 0) {
      sentiment += 0.3; // High volume + price up = very bullish
    } else if (volumeChange > 50 && priceChange < 0) {
      sentiment -= 0.3; // High volume + price down = very bearish
    }

    return sentiment.clamp(-1.0, 1.0);
  }
}

/// News Sentiment data model
class NewsSentiment {
  final String symbol;
  final double sentimentScore; // -1.0 (very bearish) to 1.0 (very bullish)
  final String overallSentiment; // "Bullish", "Neutral", "Bearish"
  final int articlesAnalyzed;

  const NewsSentiment({
    required this.symbol,
    required this.sentimentScore,
    required this.overallSentiment,
    required this.articlesAnalyzed,
  });

  /// Get emoji for sentiment
  String get emoji {
    if (sentimentScore > 0.6) return '📈'; // Very Bullish
    if (sentimentScore > 0.3) return '🟢'; // Bullish
    if (sentimentScore < -0.6) return '📉'; // Very Bearish
    if (sentimentScore < -0.3) return '🔴'; // Bearish
    return '⚪'; // Neutral
  }
}

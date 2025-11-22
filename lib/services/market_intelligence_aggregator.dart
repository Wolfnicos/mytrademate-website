import 'package:flutter/foundation.dart';
import 'package:mytrademate/models/market_intelligence_boost.dart';
import 'package:mytrademate/services/fear_greed_service.dart';
import 'package:mytrademate/services/news_sentiment_service.dart';
import 'package:mytrademate/services/global_market_context_service.dart';
import 'package:mytrademate/services/multi_exchange_aggregator_service.dart';

/// Market Intelligence Aggregator
///
/// Combines all market intelligence sources (Fear & Greed, News, Global Market, Multi-Exchange)
/// and calculates confidence boost for ML predictions
class MarketIntelligenceAggregator {
  static final MarketIntelligenceAggregator _instance = MarketIntelligenceAggregator._internal();
  factory MarketIntelligenceAggregator() => _instance;
  MarketIntelligenceAggregator._internal();

  final FearGreedService _fearGreed = FearGreedService();
  final NewsSentimentService _newsSentiment = NewsSentimentService();
  final GlobalMarketContextService _globalMarket = GlobalMarketContextService();
  final MultiExchangeAggregatorService _multiExchange = MultiExchangeAggregatorService();

  /// Get comprehensive market intelligence boost
  Future<MarketIntelligenceBoost> getBoost({
    required String symbol,
    required String mlDirection, // BUY/SELL/HOLD
    required double mlConfidence,
    double? priceChange24h,
    double? volumeChange24h,
  }) async {
    try {
      debugPrint('[MarketIntelligence] Fetching data for $symbol (ML: $mlDirection @ ${(mlConfidence * 100).toStringAsFixed(1)}%)...');

      // Fetch all intelligence sources in parallel
      final results = await Future.wait([
        _fearGreed.getCurrentIndex(),
        _newsSentiment.getNewsSentiment(
          symbol: symbol,
          priceChange24h: priceChange24h,
          volumeChange24h: volumeChange24h,
        ),
        _globalMarket.getGlobalData(),
        _multiExchange.getData(symbol),
      ]);

      final fearGreedIndex = results[0] as FearGreedIndex;
      final newsSentiment = results[1] as NewsSentiment;
      final globalMarket = results[2] as GlobalMarketData;
      final multiExchange = results[3] as MultiExchangeData;

      // Calculate confidence boost
      final boost = MarketIntelligenceBoost.calculateBoost(
        mlDirection: mlDirection,
        mlConfidence: mlConfidence,
        fearGreedValue: fearGreedIndex.value,
        newsSentiment: newsSentiment.sentimentScore,
        marketTrend: globalMarket.trend,
      );

      // Generate reasons
      final reasons = MarketIntelligenceBoost.generateReasons(
        boost: boost,
        mlDirection: mlDirection,
        fearGreedValue: fearGreedIndex.value,
        newsSentiment: newsSentiment.sentimentScore,
        marketTrend: globalMarket.trend,
      );

      debugPrint('[MarketIntelligence] ✅ Boost: ${boost > 0 ? '+' : ''}$boost% | Reasons: ${reasons.length}');

      return MarketIntelligenceBoost(
        confidenceBoost: boost,
        fearGreedLevel: fearGreedIndex.classification,
        fearGreedValue: fearGreedIndex.value,
        newsSentiment: newsSentiment.overallSentiment,
        newsSentimentScore: newsSentiment.sentimentScore,
        globalMarketTrend: globalMarket.trend,
        globalMarketCap: globalMarket.totalMarketCap,
        globalMarketCapChange24h: globalMarket.marketCapChange24h,
        multiExchangePrices: multiExchange.prices,
        priceSpread: multiExchange.spread,
        reasonsForBoost: reasons,
      );
    } catch (e) {
      debugPrint('[MarketIntelligence] ❌ Error fetching data: $e');
      // Return neutral boost on error
      return MarketIntelligenceBoost(
        confidenceBoost: 0,
        fearGreedLevel: 'Neutral',
        fearGreedValue: 50,
        newsSentiment: 'Neutral',
        newsSentimentScore: 0.0,
        globalMarketTrend: 'neutral',
        globalMarketCap: 0.0,
        globalMarketCapChange24h: 0.0,
        multiExchangePrices: {},
        priceSpread: 0.0,
        reasonsForBoost: ['○ Unable to fetch market intelligence'],
      );
    }
  }
}

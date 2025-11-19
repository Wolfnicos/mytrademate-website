import 'package:flutter/foundation.dart';
import 'package:mytrademate/services/binance_service.dart';
import 'package:mytrademate/services/coinbase_service.dart';
import 'package:mytrademate/services/kraken_service.dart';

/// Multi-Exchange Aggregator Service
///
/// Fetches prices from multiple exchanges and calculates spread
/// Helps identify arbitrage opportunities and price manipulation
class MultiExchangeAggregatorService {
  static final MultiExchangeAggregatorService _instance = MultiExchangeAggregatorService._internal();
  factory MultiExchangeAggregatorService() => _instance;
  MultiExchangeAggregatorService._internal();

  final BinanceService _binance = BinanceService();
  final CoinbaseService _coinbase = CoinbaseService();
  final KrakenService _kraken = KrakenService();

  /// Get prices from all exchanges
  Future<MultiExchangeData> getData(String symbol) async {
    final Map<String, double> prices = {};

    // Fetch from Binance
    try {
      final binanceTicker = await _binance.fetchTicker24h(symbol);
      prices['Binance'] = binanceTicker['lastPrice'] ?? 0.0;
    } catch (e) {
      debugPrint('[MultiExchange] Binance error: $e');
    }

    // Fetch from Coinbase
    try {
      final coinbaseTicker = await _coinbase.fetchTicker24h(symbol);
      prices['Coinbase'] = coinbaseTicker['lastPrice'] ?? 0.0;
    } catch (e) {
      debugPrint('[MultiExchange] Coinbase error: $e');
    }

    // Fetch from Kraken
    try {
      final krakenTicker = await _kraken.fetchTicker24h(symbol);
      prices['Kraken'] = krakenTicker['lastPrice'] ?? 0.0;
    } catch (e) {
      debugPrint('[MultiExchange] Kraken error: $e');
    }

    // Calculate spread
    final spread = _calculateSpread(prices);

    debugPrint('[MultiExchange] Prices: ${prices.entries.map((e) => '${e.key}: \$${e.value.toStringAsFixed(2)}').join(', ')}');
    debugPrint('[MultiExchange] Spread: ${(spread * 100).toStringAsFixed(3)}%');

    return MultiExchangeData(
      prices: prices,
      spread: spread,
    );
  }

  /// Calculate price spread across exchanges
  /// Returns percentage difference between highest and lowest price
  double _calculateSpread(Map<String, double> prices) {
    if (prices.isEmpty) return 0.0;

    final values = prices.values.where((p) => p > 0).toList();
    if (values.isEmpty) return 0.0;

    final highest = values.reduce((a, b) => a > b ? a : b);
    final lowest = values.reduce((a, b) => a < b ? a : b);

    if (lowest == 0) return 0.0;

    return ((highest - lowest) / lowest);
  }
}

/// Multi-Exchange Data model
class MultiExchangeData {
  final Map<String, double> prices; // Exchange name -> price
  final double spread; // % spread (0.0 - 1.0)

  const MultiExchangeData({
    required this.prices,
    required this.spread,
  });

  /// Get average price across all exchanges
  double get averagePrice {
    final values = prices.values.where((p) => p > 0);
    if (values.isEmpty) return 0.0;
    return values.reduce((a, b) => a + b) / values.length;
  }

  /// Check if spread is suspiciously high (possible manipulation)
  bool get isHighSpread {
    return spread > 0.01; // > 1% spread
  }

  /// Get spread as percentage string
  String get spreadPercentage {
    return '${(spread * 100).toStringAsFixed(3)}%';
  }
}

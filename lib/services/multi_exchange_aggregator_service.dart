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

    // Fetch from Binance (uses format: BTCUSDT)
    try {
      final binanceTicker = await _binance.fetchTicker24h(symbol);
      prices['Binance'] = binanceTicker['lastPrice'] ?? 0.0;
    } catch (e) {
      debugPrint('[MultiExchange] Binance error: $e');
    }

    // Fetch from Coinbase (uses format: BTC-USD)
    try {
      final coinbaseSymbol = _normalizeCoinbaseSymbol(symbol);
      if (coinbaseSymbol != null) {
        final coinbaseTicker = await _coinbase.fetchTicker24h(coinbaseSymbol);
        prices['Coinbase'] = coinbaseTicker['lastPrice'] ?? 0.0;
        debugPrint('[MultiExchange] ✅ Coinbase: \$${prices['Coinbase']!.toStringAsFixed(2)}');
      } else {
        debugPrint('[MultiExchange] ⏭️  Coinbase: Skipped (symbol not supported)');
      }
    } catch (e) {
      // Only log errors for pairs we expected to work
      debugPrint('[MultiExchange] ❌ Coinbase error: $e');
    }

    // Fetch from Kraken (uses format: XBTUSD)
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

  /// Normalize symbol for Coinbase (BTCEUR → BTC-EUR)
  /// Returns null if symbol cannot be parsed or Coinbase doesn't support the pair
  String? _normalizeCoinbaseSymbol(String symbol) {
    // Already in correct format
    if (symbol.contains('-')) return symbol;

    // Parse symbol to extract base and quote
    // Supported quotes on Coinbase: USD, EUR, USDC (mainly USD, limited EUR/USDC)
    final match = RegExp(r'^([A-Z]+)(USD|EUR|USDC|USDT)$').firstMatch(symbol);
    if (match == null) {
      debugPrint('[MultiExchange] ⚠️  Coinbase: Cannot parse symbol: $symbol');
      return null;
    }

    final base = match.group(1)!;
    final quote = match.group(2)!;

    // Coinbase is primarily a crypto exchange, not forex
    // Skip forex pairs like EUR/USD, GBP/USD
    const fiatBases = {'EUR', 'USD', 'GBP', 'JPY', 'CHF', 'AUD', 'CAD', 'NZD'};
    if (fiatBases.contains(base)) {
      debugPrint('[MultiExchange] ⚠️  Coinbase: Skipping forex pair: $symbol (Coinbase doesn\'t support forex)');
      return null;
    }

    // Coinbase has limited EUR support (mostly major coins like BTC, ETH)
    if (quote == 'EUR') {
      const coinsWithEUR = {'BTC', 'ETH', 'SOL', 'AVAX', 'LINK', 'XRP'};
      if (!coinsWithEUR.contains(base)) {
        debugPrint('[MultiExchange] ⚠️  Coinbase: $base-EUR not supported (use USD instead)');
        return null;
      }
    }

    // Coinbase doesn't support USDT for all coins (prefer USD)
    if (quote == 'USDT') {
      // Only major coins have USDT on Coinbase
      const majorCoins = {'BTC', 'ETH', 'SOL', 'AVAX', 'LINK'};
      if (!majorCoins.contains(base)) {
        debugPrint('[MultiExchange] ⚠️  Coinbase: $base-USDT not supported');
        return null;
      }
    }

    // Use CoinbaseService's buildTradingPair to ensure correct formatting
    return _coinbase.buildTradingPair(base, quote);
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

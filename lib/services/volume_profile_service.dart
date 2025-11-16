import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'dart:math';

/// Volume Profile Analysis Service
///
/// Analyzes order book data to detect:
/// - Bid/Ask imbalance (buying vs selling pressure)
/// - Whale walls (large orders that act as support/resistance)
/// - Volume percentiles (unusual trading activity)
/// - Order book depth (liquidity at different price levels)
///
/// Uses FREE public data from exchange APIs (no paid subscriptions needed)
class VolumeProfileService {
  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
    ),
  );

  // Cache for reducing API calls
  final Map<String, CachedOrderBook> _cache = {};
  static const Duration _cacheDuration = Duration(seconds: 30);

  // Historical volume data for percentile calculation
  final Map<String, List<double>> _volumeHistory = {};
  static const int _maxHistoryLength = 100;

  /// Fetch and analyze order book for a symbol
  ///
  /// Returns comprehensive volume profile metrics
  Future<VolumeProfile> analyzeVolume({
    required String symbol,
    required String exchange,
    int depth = 100, // Number of order book levels to fetch
  }) async {
    final cacheKey = '${exchange}_$symbol';

    // Check cache
    if (_isCacheValid(cacheKey)) {
      return _analyzeOrderBook(_cache[cacheKey]!.data, symbol);
    }

    try {
      // Fetch order book from exchange
      final orderBook = await _fetchOrderBook(
        symbol: symbol,
        exchange: exchange,
        depth: depth,
      );

      // Cache the data
      _cache[cacheKey] = CachedOrderBook(
        data: orderBook,
        timestamp: DateTime.now(),
      );

      return _analyzeOrderBook(orderBook, symbol);
    } catch (e) {
      debugPrint('❌ VolumeProfileService: Error analyzing volume: $e');
      return _neutralProfile();
    }
  }

  /// Fetch order book from exchange API
  Future<OrderBookData> _fetchOrderBook({
    required String symbol,
    required String exchange,
    required int depth,
  }) async {
    switch (exchange.toLowerCase()) {
      case 'binance':
        return _fetchBinanceOrderBook(symbol, depth);
      case 'kraken':
        return _fetchKrakenOrderBook(symbol, depth);
      case 'coinbase':
        return _fetchCoinbaseOrderBook(symbol, depth);
      default:
        throw ArgumentError('Unsupported exchange: $exchange');
    }
  }

  /// Fetch Binance order book
  Future<OrderBookData> _fetchBinanceOrderBook(String symbol, int depth) async {
    final response = await _dio.get(
      'https://api.binance.com/api/v3/depth',
      queryParameters: {
        'symbol': symbol.toUpperCase(),
        'limit': min(depth, 5000), // Binance max is 5000
      },
    );

    if (response.statusCode != 200) {
      throw Exception('Binance API error: ${response.statusCode}');
    }

    final data = response.data as Map<String, dynamic>;
    final bids = (data['bids'] as List)
        .map((e) => OrderLevel(
              price: double.parse(e[0] as String),
              quantity: double.parse(e[1] as String),
            ))
        .toList();

    final asks = (data['asks'] as List)
        .map((e) => OrderLevel(
              price: double.parse(e[0] as String),
              quantity: double.parse(e[1] as String),
            ))
        .toList();

    return OrderBookData(bids: bids, asks: asks);
  }

  /// Fetch Kraken order book
  Future<OrderBookData> _fetchKrakenOrderBook(String symbol, int depth) async {
    // Convert symbol format (BTCUSDT -> XBTUSDT for Kraken)
    final krakenSymbol = symbol
        .toUpperCase()
        .replaceAll('BTC', 'XBT')
        .replaceAll('USDT', 'USD');

    final response = await _dio.get(
      'https://api.kraken.com/0/public/Depth',
      queryParameters: {
        'pair': krakenSymbol,
        'count': min(depth, 500), // Kraken max is 500
      },
    );

    if (response.statusCode != 200) {
      throw Exception('Kraken API error: ${response.statusCode}');
    }

    final data = response.data as Map<String, dynamic>;
    final result = data['result'] as Map<String, dynamic>;
    final pairData = result.values.first as Map<String, dynamic>;

    final bids = (pairData['bids'] as List)
        .map((e) => OrderLevel(
              price: double.parse(e[0] as String),
              quantity: double.parse(e[1] as String),
            ))
        .toList();

    final asks = (pairData['asks'] as List)
        .map((e) => OrderLevel(
              price: double.parse(e[0] as String),
              quantity: double.parse(e[1] as String),
            ))
        .toList();

    return OrderBookData(bids: bids, asks: asks);
  }

  /// Fetch Coinbase order book
  Future<OrderBookData> _fetchCoinbaseOrderBook(String symbol, int depth) async {
    // Convert symbol format (BTCUSDT -> BTC-USD, BTCEUR -> BTC-EUR for Coinbase)
    final upperSymbol = symbol.toUpperCase();

    String pair;
    if (upperSymbol.endsWith('EUR')) {
      // EUR pair: BTCEUR -> BTC-EUR
      final base = upperSymbol.replaceAll('EUR', '');
      pair = '$base-EUR';
    } else if (upperSymbol.endsWith('USDT')) {
      // USDT pair: BTCUSDT -> BTC-USD
      final base = upperSymbol.replaceAll('USDT', '');
      pair = '$base-USD';
    } else if (upperSymbol.endsWith('USDC')) {
      // USDC pair: BTCUSDC -> BTC-USD
      final base = upperSymbol.replaceAll('USDC', '');
      pair = '$base-USD';
    } else {
      // Default: assume USD
      pair = '$upperSymbol-USD';
    }

    final response = await _dio.get(
      'https://api.exchange.coinbase.com/products/$pair/book',
      queryParameters: {
        'level': 2, // Level 2 = Top 50 bids/asks
      },
    );

    if (response.statusCode != 200) {
      throw Exception('Coinbase API error: ${response.statusCode}');
    }

    final data = response.data as Map<String, dynamic>;

    final bids = (data['bids'] as List)
        .map((e) => OrderLevel(
              price: double.parse(e[0] as String),
              quantity: double.parse(e[1] as String),
            ))
        .toList();

    final asks = (data['asks'] as List)
        .map((e) => OrderLevel(
              price: double.parse(e[0] as String),
              quantity: double.parse(e[1] as String),
            ))
        .toList();

    return OrderBookData(bids: bids, asks: asks);
  }

  /// Analyze order book data to extract volume profile metrics
  VolumeProfile _analyzeOrderBook(OrderBookData orderBook, String symbol) {
    // Calculate bid/ask volumes
    final bidVolume = orderBook.bids.fold<double>(
      0.0,
      (sum, level) => sum + level.quantity,
    );

    final askVolume = orderBook.asks.fold<double>(
      0.0,
      (sum, level) => sum + level.quantity,
    );

    // Bid/Ask Imbalance Ratio
    // > 1.0 = More bids (bullish pressure)
    // < 1.0 = More asks (bearish pressure)
    final bidAskRatio = askVolume > 0 ? bidVolume / askVolume : 1.0;

    // Detect whale walls (large single orders)
    final whaleWalls = _detectWhaleWalls(orderBook);

    // Calculate order book depth (how much liquidity exists)
    final depth = _calculateDepth(orderBook);

    // Calculate volume percentile (is current volume unusual?)
    final volumePercentile = _calculateVolumePercentile(
      symbol,
      bidVolume + askVolume,
    );

    // Calculate spread (tightness of market)
    final spread = _calculateSpread(orderBook);

    return VolumeProfile(
      bidAskRatio: bidAskRatio,
      bidVolume: bidVolume,
      askVolume: askVolume,
      whaleWalls: whaleWalls,
      depth: depth,
      volumePercentile: volumePercentile,
      spread: spread,
      timestamp: DateTime.now(),
    );
  }

  /// Detect whale walls (large orders that can act as support/resistance)
  List<WhaleWall> _detectWhaleWalls(OrderBookData orderBook) {
    final allLevels = [
      ...orderBook.bids.map((l) => WhaleWall(
            price: l.price,
            quantity: l.quantity,
            side: 'bid',
          )),
      ...orderBook.asks.map((l) => WhaleWall(
            price: l.price,
            quantity: l.quantity,
            side: 'ask',
          )),
    ];

    // Sort by quantity
    allLevels.sort((a, b) => b.quantity.compareTo(a.quantity));

    // Calculate median quantity
    final quantities = allLevels.map((w) => w.quantity).toList();
    final median = _calculateMedian(quantities);

    // Whale wall = order > 3x median (statistically significant)
    final whaleThreshold = median * 3.0;

    return allLevels
        .where((wall) => wall.quantity > whaleThreshold)
        .take(10) // Top 10 whale walls
        .toList();
  }

  /// Calculate order book depth (total liquidity)
  OrderBookDepth _calculateDepth(OrderBookData orderBook) {
    // Calculate depth at different price distances from mid price
    final midPrice = _calculateMidPrice(orderBook);

    // 1% depth (liquidity within 1% of mid price)
    final depth1pct = _calculateDepthAtDistance(orderBook, midPrice, 0.01);

    // 2% depth
    final depth2pct = _calculateDepthAtDistance(orderBook, midPrice, 0.02);

    // 5% depth
    final depth5pct = _calculateDepthAtDistance(orderBook, midPrice, 0.05);

    return OrderBookDepth(
      depth1pct: depth1pct,
      depth2pct: depth2pct,
      depth5pct: depth5pct,
    );
  }

  /// Calculate depth at a specific distance from mid price
  double _calculateDepthAtDistance(
    OrderBookData orderBook,
    double midPrice,
    double distancePct,
  ) {
    final lowerBound = midPrice * (1 - distancePct);
    final upperBound = midPrice * (1 + distancePct);

    final bidDepth = orderBook.bids
        .where((level) => level.price >= lowerBound)
        .fold<double>(0.0, (sum, level) => sum + level.quantity);

    final askDepth = orderBook.asks
        .where((level) => level.price <= upperBound)
        .fold<double>(0.0, (sum, level) => sum + level.quantity);

    return bidDepth + askDepth;
  }

  /// Calculate mid price (average of best bid and best ask)
  double _calculateMidPrice(OrderBookData orderBook) {
    if (orderBook.bids.isEmpty || orderBook.asks.isEmpty) return 0.0;

    final bestBid = orderBook.bids.first.price;
    final bestAsk = orderBook.asks.first.price;

    return (bestBid + bestAsk) / 2.0;
  }

  /// Calculate spread (tightness of market)
  double _calculateSpread(OrderBookData orderBook) {
    if (orderBook.bids.isEmpty || orderBook.asks.isEmpty) return 0.0;

    final bestBid = orderBook.bids.first.price;
    final bestAsk = orderBook.asks.first.price;

    // Spread in basis points (1 bp = 0.01%)
    return ((bestAsk - bestBid) / bestBid) * 10000;
  }

  /// Calculate volume percentile (is current volume unusual?)
  double _calculateVolumePercentile(String symbol, double currentVolume) {
    // Initialize history if needed
    _volumeHistory[symbol] ??= [];

    // Add current volume to history
    _volumeHistory[symbol]!.add(currentVolume);

    // Trim history to max length
    if (_volumeHistory[symbol]!.length > _maxHistoryLength) {
      _volumeHistory[symbol]!.removeAt(0);
    }

    // Calculate percentile
    final history = List<double>.from(_volumeHistory[symbol]!);
    history.sort();

    final index = history.indexOf(currentVolume);
    return index / history.length;
  }

  /// Calculate median of a list
  double _calculateMedian(List<double> values) {
    if (values.isEmpty) return 0.0;

    final sorted = List<double>.from(values)..sort();
    final mid = sorted.length ~/ 2;

    if (sorted.length % 2 == 0) {
      return (sorted[mid - 1] + sorted[mid]) / 2.0;
    } else {
      return sorted[mid];
    }
  }

  /// Normalize volume profile features for ML model
  ///
  /// Returns [bidAskRatioNorm, volumePercentileNorm, spreadNorm]
  List<double> normalizeFeatures(VolumeProfile profile) {
    // Bid/Ask Ratio normalization
    // Typical range: 0.5 to 2.0
    // Log scale to handle extremes
    final bidAskLog = log(profile.bidAskRatio.clamp(0.1, 10.0));
    final bidAskNorm = (bidAskLog / log(2.0)).clamp(-2.0, 2.0);

    // Volume Percentile already 0-1
    final volumePercentileNorm = profile.volumePercentile;

    // Spread normalization
    // Typical range: 1-50 basis points
    // Tight spread (<5bp) = liquid market, good for scalping
    final spreadNorm = (profile.spread / 10.0).clamp(0.0, 5.0);

    return [bidAskNorm, volumePercentileNorm, spreadNorm];
  }

  /// Check if cached data is still valid
  bool _isCacheValid(String key) {
    if (!_cache.containsKey(key)) return false;

    final cached = _cache[key]!;
    final age = DateTime.now().difference(cached.timestamp);
    return age < _cacheDuration;
  }

  /// Neutral fallback profile
  VolumeProfile _neutralProfile() {
    return VolumeProfile(
      bidAskRatio: 1.0,
      bidVolume: 0.0,
      askVolume: 0.0,
      whaleWalls: [],
      depth: OrderBookDepth(depth1pct: 0.0, depth2pct: 0.0, depth5pct: 0.0),
      volumePercentile: 0.5,
      spread: 0.0,
      timestamp: DateTime.now(),
    );
  }

  /// Clear cache
  void clearCache() {
    _cache.clear();
  }

  /// Clear volume history
  void clearVolumeHistory() {
    _volumeHistory.clear();
  }
}

/// Order book data structure
class OrderBookData {
  final List<OrderLevel> bids;
  final List<OrderLevel> asks;

  OrderBookData({required this.bids, required this.asks});
}

/// Single order level in the order book
class OrderLevel {
  final double price;
  final double quantity;

  OrderLevel({required this.price, required this.quantity});
}

/// Volume profile analysis result
class VolumeProfile {
  final double bidAskRatio; // > 1.0 = bullish, < 1.0 = bearish
  final double bidVolume; // Total bid volume
  final double askVolume; // Total ask volume
  final List<WhaleWall> whaleWalls; // Large orders
  final OrderBookDepth depth; // Liquidity at different levels
  final double volumePercentile; // 0-1, higher = unusual volume
  final double spread; // In basis points
  final DateTime timestamp;

  VolumeProfile({
    required this.bidAskRatio,
    required this.bidVolume,
    required this.askVolume,
    required this.whaleWalls,
    required this.depth,
    required this.volumePercentile,
    required this.spread,
    required this.timestamp,
  });

  /// Trading signal interpretation
  String getSignal() {
    // Strong bullish: High bid/ask ratio + unusual volume + whale support
    if (bidAskRatio > 1.3 && volumePercentile > 0.8) {
      return 'strong_bullish';
    }

    // Moderate bullish
    if (bidAskRatio > 1.1 && volumePercentile > 0.6) {
      return 'bullish';
    }

    // Strong bearish: Low bid/ask ratio + unusual volume + whale resistance
    if (bidAskRatio < 0.7 && volumePercentile > 0.8) {
      return 'strong_bearish';
    }

    // Moderate bearish
    if (bidAskRatio < 0.9 && volumePercentile > 0.6) {
      return 'bearish';
    }

    return 'neutral';
  }

  @override
  String toString() {
    return 'VolumeProfile(bidAsk: ${bidAskRatio.toStringAsFixed(2)}, '
        'volumePct: ${(volumePercentile * 100).toStringAsFixed(0)}%, '
        'spread: ${spread.toStringAsFixed(1)}bp, '
        'whales: ${whaleWalls.length}, '
        'signal: ${getSignal()})';
  }
}

/// Whale wall (large order)
class WhaleWall {
  final double price;
  final double quantity;
  final String side; // 'bid' or 'ask'

  WhaleWall({
    required this.price,
    required this.quantity,
    required this.side,
  });

  /// Is this a support wall? (large bid below current price)
  bool isSupport(double currentPrice) => side == 'bid' && price < currentPrice;

  /// Is this a resistance wall? (large ask above current price)
  bool isResistance(double currentPrice) => side == 'ask' && price > currentPrice;

  @override
  String toString() {
    return 'WhaleWall($side @ ${price.toStringAsFixed(2)}: ${quantity.toStringAsFixed(2)})';
  }
}

/// Order book depth at different price levels
class OrderBookDepth {
  final double depth1pct; // Liquidity within 1% of mid price
  final double depth2pct; // Liquidity within 2%
  final double depth5pct; // Liquidity within 5%

  OrderBookDepth({
    required this.depth1pct,
    required this.depth2pct,
    required this.depth5pct,
  });

  /// Is the market liquid enough for trading?
  bool isLiquid(double minDepth) => depth1pct > minDepth;

  @override
  String toString() {
    return 'Depth(1%: ${depth1pct.toStringAsFixed(2)}, '
        '2%: ${depth2pct.toStringAsFixed(2)}, '
        '5%: ${depth5pct.toStringAsFixed(2)})';
  }
}

/// Cached order book entry
class CachedOrderBook {
  final OrderBookData data;
  final DateTime timestamp;

  CachedOrderBook({required this.data, required this.timestamp});
}

/// Example usage:
///
/// ```dart
/// final volumeService = VolumeProfileService();
///
/// // Analyze volume for BTCUSDT on Binance
/// final profile = await volumeService.analyzeVolume(
///   symbol: 'BTCUSDT',
///   exchange: 'binance',
///   depth: 100,
/// );
///
/// print(profile);
/// // Output: VolumeProfile(bidAsk: 1.15, volumePct: 75%, spread: 2.3bp, whales: 3, signal: bullish)
///
/// // Check for whale walls
/// for (final wall in profile.whaleWalls) {
///   if (wall.isSupport(50000)) {
///     print('🐋 Support wall at ${wall.price}');
///   }
/// }
///
/// // Get trading signal
/// final signal = profile.getSignal();
/// if (signal == 'strong_bullish') {
///   print('✅ Strong buy pressure detected!');
/// }
///
/// // Normalize for ML model
/// final features = volumeService.normalizeFeatures(profile);
/// print('Normalized features: $features');
/// ```

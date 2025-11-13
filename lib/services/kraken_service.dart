import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:crypto/crypto.dart';

import '../models/candle.dart';
import 'base_exchange_service.dart';

/// Kraken Exchange API Service
/// Implements BaseExchangeService for Kraken API
///
/// API Documentation: https://docs.kraken.com/rest/
class KrakenService implements BaseExchangeService {
  static const String _baseHost = 'api.kraken.com';
  static const String _storageKeyPrefix = 'kraken_';
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  // Singleton pattern
  static final KrakenService _instance = KrakenService._internal();
  factory KrakenService() => _instance;
  KrakenService._internal();

  String? _apiKey;
  String? _apiSecret;

  // Time synchronization (Kraken doesn't require strict time sync like Binance)
  int _serverTimeOffset = 0;
  DateTime? _lastTimeSyncTime;

  @override
  String get exchangeName => 'Kraken';

  @override
  String? get apiKey => _apiKey;

  @override
  String? get apiSecret => _apiSecret;

  @override
  bool get hasCredentials => (_apiKey != null && _apiKey!.isNotEmpty && _apiSecret != null && _apiSecret!.isNotEmpty);

  @override
  String buildTradingPair(String base, String quote) {
    // Kraken format: XBTEUR, ETHEUR (BTC → XBT, simple concatenation)
    // Handle special cases:
    // - BTC → XBT (Kraken uses XBT for Bitcoin)
    // - MATIC → POL (Polygon rebranded from MATIC to POL)
    String krakenBase = base;
    if (base == 'BTC') {
      krakenBase = 'XBT';
    } else if (base == 'MATIC') {
      krakenBase = 'POL';  // Kraken migrated MATIC to POL
    }
    return '$krakenBase$quote';
  }

  // ===================================
  // Time Synchronization
  // ===================================

  @override
  Future<void> syncServerTime() async {
    try {
      final uri = Uri.https(_baseHost, '/0/public/Time');
      final localBefore = DateTime.now().millisecondsSinceEpoch;

      final response = await http.get(uri).timeout(const Duration(seconds: 5));

      if (response.statusCode != 200) {
        debugPrint('⚠️ [Kraken] Failed to sync server time: ${response.statusCode}');
        return;
      }

      final localAfter = DateTime.now().millisecondsSinceEpoch;
      final data = json.decode(response.body) as Map<String, dynamic>;
      final result = data['result'] as Map<String, dynamic>;
      final serverTime = (result['unixtime'] as int) * 1000; // Convert to milliseconds

      // Calculate offset accounting for network latency
      final networkLatency = (localAfter - localBefore) ~/ 2;
      final localTimeApprox = localBefore + networkLatency;
      _serverTimeOffset = serverTime - localTimeApprox;

      _lastTimeSyncTime = DateTime.now();
      debugPrint('✅ [Kraken] Time synchronized (offset: ${_serverTimeOffset}ms)');
    } catch (e) {
      debugPrint('⚠️ [Kraken] Time sync failed: $e (will use local time)');
    }
  }

  @override
  Future<int> getSynchronizedTimestamp() async {
    if (_lastTimeSyncTime == null ||
        DateTime.now().difference(_lastTimeSyncTime!) > const Duration(minutes: 30)) {
      await syncServerTime();
    }

    final localTime = DateTime.now().millisecondsSinceEpoch;
    return localTime + _serverTimeOffset;
  }

  // ===================================
  // Credentials Management
  // ===================================

  @override
  Future<void> loadCredentials() async {
    try {
      _apiKey = await _secureStorage.read(key: '${_storageKeyPrefix}api_key');
      _apiSecret = await _secureStorage.read(key: '${_storageKeyPrefix}api_secret');
      debugPrint('[Kraken] Credentials loaded: ${hasCredentials ? "✓" : "✗"}');
    } catch (e) {
      debugPrint('[Kraken] Error loading credentials: $e');
      _apiKey = null;
      _apiSecret = null;
    }
  }

  @override
  Future<void> saveCredentials(String apiKey, String apiSecret) async {
    // Remove ALL whitespace from credentials (common copy-paste issue)
    // Base64 should have no spaces, newlines, or tabs
    final cleanApiKey = apiKey.replaceAll(RegExp(r'\s+'), '');
    final cleanApiSecret = apiSecret.replaceAll(RegExp(r'\s+'), '');

    await _secureStorage.write(key: '${_storageKeyPrefix}api_key', value: cleanApiKey);
    await _secureStorage.write(key: '${_storageKeyPrefix}api_secret', value: cleanApiSecret);
    _apiKey = cleanApiKey;
    _apiSecret = cleanApiSecret;
    debugPrint('[Kraken] Credentials saved (removed whitespace)');
  }

  @override
  Future<void> clearCredentials() async {
    await _secureStorage.delete(key: '${_storageKeyPrefix}api_key');
    await _secureStorage.delete(key: '${_storageKeyPrefix}api_secret');
    _apiKey = null;
    _apiSecret = null;
    debugPrint('[Kraken] Credentials cleared');
  }

  @override
  Future<bool> testConnection() async {
    if (!hasCredentials) {
      return false;
    }

    try {
      await getAccountBalances();
      return true;
    } catch (e) {
      debugPrint('[Kraken] Connection test failed: $e');
      return false;
    }
  }

  // ===================================
  // Signature Generation (Kraken uses HMAC-SHA512)
  // ===================================

  String _generateSignature(String path, String nonce, String postData) {
    final decodedSecret = base64.decode(_apiSecret!);

    // SHA256 hash of (nonce + postData)
    final sha256Hash = sha256.convert(utf8.encode(nonce + postData));

    // Concatenate path + SHA256 hash
    final message = utf8.encode(path) + sha256Hash.bytes;

    // HMAC-SHA512 of message with decoded secret
    final hmac = Hmac(sha512, decodedSecret);
    final signature = hmac.convert(message);

    return base64.encode(signature.bytes);
  }

  Map<String, String> _buildHeaders(String path, String postData) {
    final nonce = DateTime.now().millisecondsSinceEpoch.toString();
    final signature = _generateSignature(path, nonce, postData);

    return {
      'API-Key': _apiKey!,
      'API-Sign': signature,
      'Content-Type': 'application/x-www-form-urlencoded',
    };
  }

  // ===================================
  // Account & Portfolio
  // ===================================

  @override
  Future<Map<String, double>> getAccountBalances() async {
    if (!hasCredentials) {
      throw Exception('[Kraken] No API credentials configured');
    }

    try {
      final path = '/0/private/Balance';
      final nonce = DateTime.now().millisecondsSinceEpoch.toString();
      final postData = 'nonce=$nonce';

      final uri = Uri.https(_baseHost, path);
      final headers = _buildHeaders(path, postData);

      final response = await http.post(
        uri,
        headers: headers,
        body: postData,
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        throw Exception('[Kraken] Failed to fetch balances: ${response.statusCode}');
      }

      final data = json.decode(response.body) as Map<String, dynamic>;
      final errors = data['error'] as List<dynamic>;

      if (errors.isNotEmpty) {
        throw Exception('[Kraken] API error: ${errors.join(", ")}');
      }

      final result = data['result'] as Map<String, dynamic>;
      final Map<String, double> balances = {};

      result.forEach((key, value) {
        final balance = double.tryParse(value.toString()) ?? 0.0;
        if (balance > 0) {
          // Remove 'X' prefix if present (XXBT -> BTC, ZEUR -> EUR)
          final asset = key.startsWith('X') || key.startsWith('Z') ? key.substring(1) : key;
          balances[asset] = balance;
        }
      });

      debugPrint('[Kraken] Fetched ${balances.length} balances');
      return balances;
    } catch (e) {
      debugPrint('[Kraken] Error fetching balances: $e');
      rethrow;
    }
  }

  // ===================================
  // Market Data
  // ===================================

  @override
  Future<List<Candle>> fetchKlines(
    String symbol,
    String interval, {
    int limit = 500,
    int? endTime,
  }) async {
    try {
      // Convert symbol to Kraken format: BTCEUR -> XBTEUR
      final krakenSymbol = _convertToKrakenSymbol(symbol);

      // Convert interval to Kraken interval (minutes)
      final krakenInterval = _convertIntervalToKraken(interval);

      final queryParams = {
        'pair': krakenSymbol,
        'interval': krakenInterval.toString(),
      };

      // Kraken API: 'since' specifies the START time
      // Calculate 'since' to get recent candles
      if (endTime != null) {
        queryParams['since'] = (endTime ~/ 1000).toString();
      } else {
        // If no endTime, calculate from current time going backwards
        // For 1d: go back 30+ days, for 1h: go back 48+ hours, etc.
        final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        final intervalMinutes = krakenInterval;
        final totalMinutes = limit * intervalMinutes;
        final sinceTime = now - (totalMinutes * 60);
        queryParams['since'] = sinceTime.toString();
      }

      final uri = Uri.https(_baseHost, '/0/public/OHLC', queryParams);
      final response = await http.get(uri).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        throw Exception('[Kraken] Failed to fetch candles: ${response.statusCode}');
      }

      final data = json.decode(response.body) as Map<String, dynamic>;
      final errors = data['error'] as List<dynamic>;

      if (errors.isNotEmpty) {
        throw Exception('[Kraken] OHLC error: ${errors.join(", ")}');
      }

      final result = data['result'] as Map<String, dynamic>;

      // Kraken returns OHLC data under a key that might differ from our request
      // (e.g., request 'XBTEUR' → response key 'XXBTZEUR')
      // Find the key that contains the pair data (it's not 'last')
      String? pairKey;
      for (final key in result.keys) {
        if (key != 'last') {
          pairKey = key;
          break;
        }
      }

      if (pairKey == null) {
        debugPrint('[Kraken] No pair data found in response');
        return [];
      }

      final pairData = result[pairKey] as List<dynamic>?;

      if (pairData == null || pairData.isEmpty) {
        return [];
      }

      // Kraken returns candles in chronological order (old → new)
      // Take the LAST 'limit' candles (most recent ones)
      final allCandles = pairData.map((c) {
        final openTimeMs = (c[0] as int) * 1000; // Convert to milliseconds
        final intervalMs = krakenInterval * 60 * 1000; // Convert minutes to milliseconds
        return Candle(
          openTime: DateTime.fromMillisecondsSinceEpoch(openTimeMs),
          open: double.parse(c[1]),
          high: double.parse(c[2]),
          low: double.parse(c[3]),
          close: double.parse(c[4]),
          volume: double.parse(c[6]),
          closeTime: DateTime.fromMillisecondsSinceEpoch(openTimeMs + intervalMs),
        );
      }).toList();

      // Skip old candles and keep only the most recent 'limit' candles
      final startIndex = allCandles.length > limit ? allCandles.length - limit : 0;
      final candles = allCandles.sublist(startIndex);

      if (candles.isNotEmpty) {
        debugPrint('[Kraken] 📊 Fetched ${candles.length} candles for $symbol @ $interval');

        // Check if last candle might be incomplete (current/live candle)
        // A candle is considered "current" if its close time is in the future or very recent (< 2 min ago)
        final now = DateTime.now();
        final lastCandle = candles.last;
        final timeSinceClose = now.difference(lastCandle.closeTime);
        final isCurrentCandle = timeSinceClose.isNegative || timeSinceClose.inMinutes < 2;

        if (isCurrentCandle && candles.length > 1) {
          final minUntilClose = lastCandle.closeTime.difference(now).inMinutes;
          debugPrint('[Kraken] ⚠️  Last candle is CURRENT/INCOMPLETE closes in $minUntilClose min');
          debugPrint('[Kraken] ✅ Using PREVIOUS candle instead');
          final prevCandle = candles[candles.length - 2];
          debugPrint('[Kraken] 📊 Current: ${lastCandle.close} | Previous: ${prevCandle.close}');
        } else {
          final minAgo = timeSinceClose.inMinutes;
          debugPrint('[Kraken] ✅ Last candle CLOSED $minAgo min ago');
          debugPrint('[Kraken] 📊 Last candle: ${lastCandle.close}');
        }
      }

      return candles;
    } catch (e) {
      debugPrint('[Kraken] Error fetching klines for $symbol: $e');
      return [];
    }
  }

  @override
  Future<Map<String, double>> fetchTicker24h(String symbol) async {
    try {
      final krakenSymbol = _convertToKrakenSymbol(symbol);

      final queryParams = {
        'pair': krakenSymbol,
      };

      final uri = Uri.https(_baseHost, '/0/public/Ticker', queryParams);
      final response = await http.get(uri).timeout(const Duration(seconds: 5));

      if (response.statusCode != 200) {
        throw Exception('[Kraken] Ticker error: ${response.statusCode}');
      }

      final data = json.decode(response.body) as Map<String, dynamic>;
      final errors = data['error'] as List<dynamic>;

      if (errors.isNotEmpty) {
        throw Exception('[Kraken] Ticker error: ${errors.join(", ")}');
      }

      final result = data['result'] as Map<String, dynamic>;

      // Kraken returns ticker data under a key that might differ from our request
      // (e.g., request 'XBTEUR' → response key 'XXBTZEUR')
      // So we get the first (and only) entry
      if (result.isEmpty) {
        throw Exception('[Kraken] No ticker data in response');
      }
      final pairData = result.values.first as Map<String, dynamic>;

      final lastPrice = double.parse(pairData['c'][0]); // Last trade price
      final open24h = double.parse(pairData['o']); // Today's opening price

      final changePercent = open24h > 0 ? ((lastPrice - open24h) / open24h) * 100 : 0.0;

      return {
        'lastPrice': lastPrice,
        'priceChangePercent': changePercent,
      };
    } catch (e) {
      debugPrint('[Kraken] Error fetching ticker for $symbol: $e');
      rethrow;
    }
  }

  @override
  Future<List<Candle>> fetchKlinesWithFallback(
    List<String> symbols,
    String interval, {
    int limit = 60,
  }) async {
    for (final symbol in symbols) {
      try {
        return await fetchKlines(symbol, interval, limit: limit);
      } catch (e) {
        debugPrint('[Kraken] Klines failed for $symbol, trying next...');
        continue;
      }
    }
    throw Exception('[Kraken] All kline symbols failed: $symbols');
  }

  @override
  Future<Map<String, double>> fetchTicker24hWithFallback(List<String> symbols) async {
    for (final symbol in symbols) {
      try {
        return await fetchTicker24h(symbol);
      } catch (e) {
        debugPrint('[Kraken] Ticker failed for $symbol, trying next...');
        continue;
      }
    }
    throw Exception('[Kraken] All ticker symbols failed: $symbols');
  }

  @override
  Future<Map<String, dynamic>> getExchangeInfo({String? symbol}) async {
    try {
      final queryParams = symbol != null ? {'pair': _convertToKrakenSymbol(symbol)} : <String, String>{};

      final uri = Uri.https(_baseHost, '/0/public/AssetPairs', queryParams);
      final response = await http.get(uri).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        throw Exception('[Kraken] Exchange info error: ${response.statusCode}');
      }

      final data = json.decode(response.body) as Map<String, dynamic>;
      final errors = data['error'] as List<dynamic>;

      if (errors.isNotEmpty) {
        throw Exception('[Kraken] Exchange info error: ${errors.join(", ")}');
      }

      return data['result'] as Map<String, dynamic>;
    } catch (e) {
      debugPrint('[Kraken] Error fetching exchange info: $e');
      rethrow;
    }
  }

  // ===================================
  // Helper Methods
  // ===================================

  /// Convert standard symbol to Kraken format
  /// Example: BTCEUR -> XBTEUR, ETHEUR -> ETHEUR
  String _convertToKrakenSymbol(String symbol) {
    // Kraken uses XBT instead of BTC
    if (symbol.startsWith('BTC')) {
      return 'XBT' + symbol.substring(3);
    }

    // Add X prefix for crypto, Z for fiat (Kraken convention)
    final quotes = ['EUR', 'USD', 'USDT', 'USDC'];
    for (final quote in quotes) {
      if (symbol.endsWith(quote)) {
        final base = symbol.substring(0, symbol.length - quote.length);
        return base + quote;
      }
    }

    return symbol;
  }

  /// Convert interval string to Kraken interval (minutes)
  int _convertIntervalToKraken(String interval) {
    final map = {
      '1m': 1,
      '5m': 5,
      '15m': 15,
      '1h': 60,
      '4h': 240,
      '1d': 1440,
    };

    return map[interval] ?? 60; // Default to 1h
  }

  /// Get 24h volume for a symbol
  Future<double> get24hVolume(String symbol) async {
    try {
      final krakenSymbol = _convertToKrakenSymbol(symbol);
      final queryParams = {'pair': krakenSymbol};
      final uri = Uri.https(_baseHost, '/0/public/Ticker', queryParams);
      final response = await http.get(uri).timeout(const Duration(seconds: 5));

      if (response.statusCode != 200) {
        return 0.0;
      }

      final data = json.decode(response.body) as Map<String, dynamic>;
      final errors = data['error'] as List<dynamic>;
      if (errors.isNotEmpty) {
        return 0.0;
      }

      final result = data['result'] as Map<String, dynamic>;
      if (result.isEmpty) {
        return 0.0;
      }

      final pairData = result.values.first as Map<String, dynamic>;
      // Kraken: 'v' = [today's volume, last 24h volume] in base currency (e.g., BTC)
      final volumeBase = double.parse(pairData['v'][1]); // Last 24h volume in BTC

      // Convert to quote currency (EUR/USD) for fair comparison across assets
      // Price 'c' = [price, lot volume] - use current price
      final price = double.parse(pairData['c'][0]);
      final volumeQuote = volumeBase * price; // Volume in EUR/USD

      return volumeQuote;
    } catch (e) {
      debugPrint('[Kraken] Error fetching volume for $symbol: $e');
      return 0.0;
    }
  }

  @override
  Future<double> getVolumePercentile(String targetSymbol, {List<String>? comparisonSymbols}) async {
    try {
      // Convert Binance-style symbol to Kraken format (BTCEUR → XBTEUR)
      final krakenTargetSymbol = _convertToKrakenSymbol(targetSymbol);

      // Extract quote currency from targetSymbol (e.g., XBTEUR → EUR)
      final RegExp quoteRegex = RegExp(r'(EUR|USD|USDC|USDT)$');
      final match = quoteRegex.firstMatch(krakenTargetSymbol);
      final quote = match?.group(1) ?? 'EUR'; // Fallback to EUR if no match

      // Build dynamic comparison list with same quote currency
      // Note: Kraken uses XBT instead of BTC
      final baseAssets = ['XBT', 'ETH', 'XRP', 'ADA', 'DOGE', 'DOT', 'LINK', 'UNI'];
      final symbols = comparisonSymbols ?? baseAssets.map((base) => '$base$quote').toList();

      // Fetch volumes for all symbols in parallel
      final volumeFutures = symbols.map((s) => get24hVolume(s));
      final volumes = await Future.wait(volumeFutures, eagerError: false);

      // Get target volume (use Kraken-converted symbol)
      final targetVolume = await get24hVolume(krakenTargetSymbol);

      // Calculate percentile: % of symbols with lower volume
      int lowerCount = 0;
      for (final vol in volumes) {
        if (vol < targetVolume) lowerCount++;
      }

      final percentile = lowerCount / volumes.length;
      debugPrint('[Kraken] 📊 Volume percentile for $krakenTargetSymbol: ${(percentile * 100).toStringAsFixed(1)}% (volume: ${targetVolume.toStringAsFixed(0)} units)');

      return percentile;
    } catch (e) {
      debugPrint('[Kraken] ❌ Failed to calculate volume percentile: $e');
      // Return median (0.5) on error - no boost or penalty
      return 0.5;
    }
  }
}

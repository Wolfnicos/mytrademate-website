import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:crypto/crypto.dart';

import '../models/candle.dart';
import 'base_exchange_service.dart';

/// Coinbase Exchange API Service
/// Implements BaseExchangeService for Coinbase Pro/Advanced Trade API
///
/// API Documentation: https://docs.cloud.coinbase.com/advanced-trade-api/docs/
class CoinbaseService implements BaseExchangeService {
  static const String _baseHost = 'api.coinbase.com';
  static const String _exchangeHost = 'api.exchange.coinbase.com'; // Public API (no auth)
  static const String _storageKeyPrefix = 'coinbase_';
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  // Singleton pattern
  static final CoinbaseService _instance = CoinbaseService._internal();
  factory CoinbaseService() => _instance;
  CoinbaseService._internal();

  String? _apiKey;
  String? _apiSecret;

  // Time synchronization
  int _serverTimeOffset = 0;
  DateTime? _lastTimeSyncTime;
  static const Duration _timeSyncInterval = Duration(minutes: 30);

  @override
  String get exchangeName => 'Coinbase';

  @override
  String? get apiKey => _apiKey;

  @override
  String? get apiSecret => _apiSecret;

  @override
  bool get hasCredentials => (_apiKey != null && _apiKey!.isNotEmpty && _apiSecret != null && _apiSecret!.isNotEmpty);

  @override
  String buildTradingPair(String base, String quote) {
    // Coinbase format: BTC-EUR, ETH-USDT (with hyphen)
    return '$base-$quote';
  }

  // ===================================
  // Time Synchronization
  // ===================================

  @override
  Future<void> syncServerTime() async {
    try {
      final uri = Uri.https(_baseHost, '/api/v3/time');
      final localBefore = DateTime.now().millisecondsSinceEpoch;

      final response = await http.get(uri).timeout(const Duration(seconds: 5));

      if (response.statusCode != 200) {
        debugPrint('⚠️ [Coinbase] Failed to sync server time: ${response.statusCode}');
        return;
      }

      final localAfter = DateTime.now().millisecondsSinceEpoch;
      final data = json.decode(response.body) as Map<String, dynamic>;
      final serverTimeStr = data['iso'] as String;
      final serverTime = DateTime.parse(serverTimeStr).millisecondsSinceEpoch;

      // Calculate offset accounting for network latency
      final networkLatency = (localAfter - localBefore) ~/ 2;
      final localTimeApprox = localBefore + networkLatency;
      _serverTimeOffset = serverTime - localTimeApprox;

      _lastTimeSyncTime = DateTime.now();
      debugPrint('✅ [Coinbase] Time synchronized (offset: ${_serverTimeOffset}ms)');
    } catch (e) {
      debugPrint('⚠️ [Coinbase] Time sync failed: $e (will use local time)');
    }
  }

  @override
  Future<int> getSynchronizedTimestamp() async {
    // Sync time on first call or if >30 mins since last sync
    if (_lastTimeSyncTime == null ||
        DateTime.now().difference(_lastTimeSyncTime!) > _timeSyncInterval) {
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
      debugPrint('[Coinbase] Credentials loaded: ${hasCredentials ? "✓" : "✗"}');
    } catch (e) {
      debugPrint('[Coinbase] Error loading credentials: $e');
      _apiKey = null;
      _apiSecret = null;
    }
  }

  @override
  Future<void> saveCredentials(String apiKey, String apiSecret) async {
    await _secureStorage.write(key: '${_storageKeyPrefix}api_key', value: apiKey);
    await _secureStorage.write(key: '${_storageKeyPrefix}api_secret', value: apiSecret);
    _apiKey = apiKey;
    _apiSecret = apiSecret;
    debugPrint('[Coinbase] Credentials saved');
  }

  @override
  Future<void> clearCredentials() async {
    await _secureStorage.delete(key: '${_storageKeyPrefix}api_key');
    await _secureStorage.delete(key: '${_storageKeyPrefix}api_secret');
    _apiKey = null;
    _apiSecret = null;
    debugPrint('[Coinbase] Credentials cleared');
  }

  @override
  Future<bool> testConnection() async {
    if (!hasCredentials) {
      return false;
    }

    try {
      // Test connection by fetching accounts
      await getAccountBalances();
      return true;
    } catch (e) {
      debugPrint('[Coinbase] Connection test failed: $e');
      return false;
    }
  }

  // ===================================
  // Signature Generation (Coinbase uses HMAC-SHA256)
  // ===================================

  String _generateSignature(String timestamp, String method, String path, String body) {
    final message = '$timestamp$method$path$body';
    final key = utf8.encode(_apiSecret!);
    final bytes = utf8.encode(message);
    final hmac = Hmac(sha256, key);
    final digest = hmac.convert(bytes);
    return digest.toString();
  }

  Map<String, String> _buildHeaders(String method, String path, {String body = ''}) {
    final timestamp = (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();
    final signature = _generateSignature(timestamp, method, path, body);

    return {
      'CB-ACCESS-KEY': _apiKey!,
      'CB-ACCESS-SIGN': signature,
      'CB-ACCESS-TIMESTAMP': timestamp,
      'Content-Type': 'application/json',
    };
  }

  // ===================================
  // Account & Portfolio
  // ===================================

  @override
  Future<Map<String, double>> getAccountBalances() async {
    if (!hasCredentials) {
      throw Exception('[Coinbase] No API credentials configured');
    }

    try {
      final path = '/api/v3/brokerage/accounts';
      final uri = Uri.https(_baseHost, path);
      final headers = _buildHeaders('GET', path);

      final response = await http.get(uri, headers: headers).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        throw Exception('[Coinbase] Failed to fetch accounts: ${response.statusCode} ${response.body}');
      }

      final data = json.decode(response.body) as Map<String, dynamic>;
      final accounts = data['accounts'] as List<dynamic>;

      final Map<String, double> balances = {};
      for (final account in accounts) {
        final currency = account['currency'] as String;
        final available = account['available_balance']?['value'] as String? ?? '0';
        final balance = double.tryParse(available) ?? 0.0;

        if (balance > 0) {
          balances[currency] = balance;
        }
      }

      debugPrint('[Coinbase] Fetched ${balances.length} balances');
      return balances;
    } catch (e) {
      debugPrint('[Coinbase] Error fetching balances: $e');
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
      // Convert symbol format: BTCEUR -> BTC-EUR
      final coinbaseSymbol = _convertToCoinbaseSymbol(symbol);

      // Convert interval to granularity (seconds)
      final granularity = _convertIntervalToGranularity(interval);

      // Coinbase Exchange API (public, no auth) - returns array of arrays
      // Format: [[timestamp, low, high, open, close, volume], ...]
      final path = '/products/$coinbaseSymbol/candles';
      final queryParams = {
        'granularity': granularity.toString(),
      };

      final uri = Uri.https(_exchangeHost, path, queryParams);
      final response = await http.get(uri).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        throw Exception('[Coinbase] Failed to fetch candles: ${response.statusCode}');
      }

      final List<dynamic> candles = json.decode(response.body) as List<dynamic>;

      return candles.take(limit).map((c) {
        final timestamp = c[0] as int; // Unix timestamp in seconds
        final timestampMs = timestamp * 1000; // Convert to milliseconds
        return Candle(
          openTime: DateTime.fromMillisecondsSinceEpoch(timestampMs),
          low: (c[1] as num).toDouble(),
          high: (c[2] as num).toDouble(),
          open: (c[3] as num).toDouble(),
          close: (c[4] as num).toDouble(),
          volume: (c[5] as num).toDouble(),
          closeTime: DateTime.fromMillisecondsSinceEpoch(timestampMs + (granularity * 1000)),
        );
      }).toList();
    } catch (e) {
      debugPrint('[Coinbase] Error fetching klines for $symbol: $e');
      return [];
    }
  }

  @override
  Future<Map<String, double>> fetchTicker24h(String symbol) async {
    try {
      final coinbaseSymbol = _convertToCoinbaseSymbol(symbol);

      // Coinbase Exchange API (public, no auth) - /products/{product-id}/ticker
      final path = '/products/$coinbaseSymbol/ticker';
      final uri = Uri.https(_exchangeHost, path);

      final response = await http.get(uri).timeout(const Duration(seconds: 5));

      if (response.statusCode != 200) {
        throw Exception('[Coinbase] Ticker error: ${response.statusCode}');
      }

      final data = json.decode(response.body) as Map<String, dynamic>;
      final price = double.tryParse(data['price'] ?? '0') ?? 0.0;

      // Get 24h stats from /products/{product-id}/stats
      final stats24hPath = '/products/$coinbaseSymbol/stats';
      final statsUri = Uri.https(_exchangeHost, stats24hPath);
      final statsResponse = await http.get(statsUri).timeout(const Duration(seconds: 5));

      double changePercent = 0.0;
      if (statsResponse.statusCode == 200) {
        final statsData = json.decode(statsResponse.body) as Map<String, dynamic>;
        final open24h = double.tryParse(statsData['open'] ?? '0') ?? 0.0;
        if (open24h > 0) {
          changePercent = ((price - open24h) / open24h) * 100;
        }
      }

      return {
        'lastPrice': price,
        'priceChangePercent': changePercent,
      };
    } catch (e) {
      debugPrint('[Coinbase] Error fetching ticker for $symbol: $e');
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
        debugPrint('[Coinbase] Klines failed for $symbol, trying next...');
        continue;
      }
    }
    throw Exception('[Coinbase] All kline symbols failed: $symbols');
  }

  @override
  Future<Map<String, double>> fetchTicker24hWithFallback(List<String> symbols) async {
    for (final symbol in symbols) {
      try {
        return await fetchTicker24h(symbol);
      } catch (e) {
        debugPrint('[Coinbase] Ticker failed for $symbol, trying next...');
        continue;
      }
    }
    throw Exception('[Coinbase] All ticker symbols failed: $symbols');
  }

  @override
  Future<Map<String, dynamic>> getExchangeInfo({String? symbol}) async {
    try {
      final path = symbol != null
          ? '/api/v3/brokerage/products/${_convertToCoinbaseSymbol(symbol)}'
          : '/api/v3/brokerage/products';

      final uri = Uri.https(_baseHost, path);
      final response = await http.get(uri).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        throw Exception('[Coinbase] Exchange info error: ${response.statusCode}');
      }

      return json.decode(response.body) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('[Coinbase] Error fetching exchange info: $e');
      rethrow;
    }
  }

  // ===================================
  // Helper Methods
  // ===================================

  /// Convert Binance-style symbol to Coinbase format
  /// Example: BTCEUR -> BTC-USD (Coinbase Exchange doesn't support EUR)
  String _convertToCoinbaseSymbol(String symbol) {
    debugPrint('[Coinbase] Converting symbol: "$symbol"');

    // Coinbase Exchange API doesn't support EUR pairs - replace with USD
    if (symbol.contains('EUR')) {
      symbol = symbol.replaceAll('EUR', 'USD');
      debugPrint('[Coinbase] Replaced EUR with USD: "$symbol"');
    }

    // If symbol already has hyphen (e.g., BTC-USD), return as-is
    if (symbol.contains('-')) {
      debugPrint('[Coinbase] Symbol already formatted: "$symbol"');
      return symbol;
    }

    // Common quote currencies
    final quotes = ['USD', 'USDT', 'USDC', 'BTC', 'ETH'];

    for (final quote in quotes) {
      if (symbol.endsWith(quote)) {
        final base = symbol.substring(0, symbol.length - quote.length);
        final result = '$base-$quote';
        debugPrint('[Coinbase] Final symbol: "$result"');
        return result;
      }
    }

    // Fallback: assume last 3-4 chars are quote currency
    if (symbol.length > 6) {
      final base = symbol.substring(0, symbol.length - 3);
      final quote = symbol.substring(symbol.length - 3);
      final result = '$base-$quote';
      debugPrint('[Coinbase] Fallback symbol: "$result"');
      return result;
    }

    debugPrint('[Coinbase] No conversion applied: "$symbol"');
    return symbol;
  }

  /// Convert interval string to Coinbase granularity (seconds)
  /// Coinbase Exchange API supports: 60, 300, 900, 3600, 21600, 86400
  /// (1min, 5min, 15min, 1h, 6h, 1d)
  int _convertIntervalToGranularity(String interval) {
    final map = {
      '1m': 60,
      '5m': 300,
      '15m': 900,
      '1h': 3600,
      '4h': 21600,  // Use 6h instead of 4h (Coinbase doesn't support 4h)
      '1d': 86400,
    };

    return map[interval] ?? 3600; // Default to 1h
  }
}

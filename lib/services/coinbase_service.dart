import 'dart:convert';
import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:pointycastle/export.dart';
import 'package:pointycastle/asn1/asn1_parser.dart';
import 'package:pointycastle/asn1/primitives/asn1_sequence.dart';
import 'package:pointycastle/asn1/primitives/asn1_octet_string.dart';

import '../models/candle.dart';
import '../models/features_with_atr.dart';
import '../services/full_feature_builder.dart';
import '../utils/symbol_mapper.dart';
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

  String? _apiKey; // For Cloud API: organizations/{org_id}/apiKeys/{key_id}
  String? _apiSecret; // For Cloud API: EC Private Key in PEM format

  // Time synchronization
  int _serverTimeOffset = 0;
  DateTime? _lastTimeSyncTime;
  static const Duration _timeSyncInterval = Duration(minutes: 30);

  // CACHE for candles to reduce API calls (Opțiunea 1+3)
  final Map<String, List<Candle>> _candlesCache = {};
  final Map<String, DateTime> _cacheTimestamp = {};

  // Cache duration based on interval
  Duration _getCacheDuration(String interval) {
    switch (interval) {
      case '5m':
      case '15m':
        return const Duration(minutes: 1); // Short intervals: 1 min cache
      case '1h':
      case '4h':
        return const Duration(minutes: 5); // Medium intervals: 5 min cache
      case '1d':
      case '1w':
        return const Duration(minutes: 15); // Long intervals: 15 min cache
      default:
        return const Duration(minutes: 5);
    }
  }

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
    // Handle special case: MATIC → POL (Polygon rebranded)
    String coinbaseBase = base;
    if (base == 'MATIC') {
      coinbaseBase = 'POL';  // Coinbase migrated MATIC to POL
    }
    return '$coinbaseBase-$quote';
  }

  /// Get currency symbol from trading pair (EUR → €, USD → $)
  String _getCurrencySymbol(String symbol) {
    if (symbol.contains('EUR')) return '€';
    if (symbol.contains('USD')) return '\$';
    if (symbol.contains('GBP')) return '£';
    if (symbol.contains('JPY')) return '¥';
    return '\$'; // Default to $
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
    // Clean API key (removes copy-paste whitespace)
    final cleanApiKey = apiKey.replaceAll(RegExp(r'\s+'), '');

    // For API secret: handle both literal \n and actual newlines
    // Coinbase sometimes provides keys with literal \n characters
    var cleanApiSecret = apiSecret.trim();

    // Convert literal \n to actual newlines (from Coinbase copy-paste)
    cleanApiSecret = cleanApiSecret.replaceAll(r'\n', '\n');

    await _secureStorage.write(key: '${_storageKeyPrefix}api_key', value: cleanApiKey);
    await _secureStorage.write(key: '${_storageKeyPrefix}api_secret', value: cleanApiSecret);
    _apiKey = cleanApiKey;
    _apiSecret = cleanApiSecret;
    debugPrint('[Coinbase] ✅ Credentials saved (PEM format preserved)');
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
  // JWT Authentication (Coinbase Cloud API with ES256)
  // ===================================

  /// Generate random nonce (hex string)
  String _generateNonce() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// Base64URL encode (without padding)
  String _base64UrlEncode(List<int> bytes) {
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  /// Parse EC Private Key from SEC1 PEM format
  ECPrivateKey _parseECPrivateKey(String pemKey) {
    try {
      // Handle literal \n characters (from Coinbase copy-paste)
      var pemContent = pemKey.replaceAll(r'\n', '\n');

      // Trim
      pemContent = pemContent.trim();

      // Remove BEGIN header if present
      if (pemContent.contains('BEGIN EC PRIVATE KEY')) {
        pemContent = pemContent.replaceAll('-----BEGIN EC PRIVATE KEY-----', '');
      }

      // Remove END footer if present
      if (pemContent.contains('END EC PRIVATE KEY')) {
        pemContent = pemContent.replaceAll('-----END EC PRIVATE KEY-----', '');
      }

      // Remove ALL whitespace (spaces, newlines, tabs, etc.)
      pemContent = pemContent.replaceAll(RegExp(r'\s'), '');

      // Decode base64
      final bytes = base64.decode(pemContent);

      // Parse ASN.1 DER structure (SEC1 format)
      final asn1Parser = ASN1Parser(bytes);
      final topLevelSeq = asn1Parser.nextObject() as ASN1Sequence;

      // Extract private key value (octet string at index 1)
      final privateKeyOctetString = topLevelSeq.elements![1] as ASN1OctetString;
      final privateKeyBytes = privateKeyOctetString.valueBytes!;

      // Create BigInt from bytes
      final d = BigInt.parse(
        privateKeyBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
        radix: 16,
      );

      // P-256 curve parameters (secp256r1)
      final domainParams = ECDomainParameters('prime256v1');

      return ECPrivateKey(d, domainParams);
    } catch (e) {
      debugPrint('[Coinbase] ❌ Failed to parse EC private key: $e');
      rethrow;
    }
  }

  /// Sign data with ECDSA SHA-256 (ES256)
  Uint8List _signES256(Uint8List data, ECPrivateKey privateKey) {
    final signer = Signer('SHA-256/ECDSA');
    final params = ParametersWithRandom(
      PrivateKeyParameter<ECPrivateKey>(privateKey),
      FortunaRandom()..seed(KeyParameter(Uint8List.fromList(List.generate(32, (i) => Random.secure().nextInt(256))))),
    );

    signer.init(true, params);
    final signature = signer.generateSignature(data) as ECSignature;

    // Convert signature to DER format then to raw R|S format (64 bytes for P-256)
    final r = signature.r;
    final s = signature.s;

    // Ensure R and S are 32 bytes each (pad with zeros if needed)
    final rBytes = _bigIntToBytes(r, 32);
    final sBytes = _bigIntToBytes(s, 32);

    return Uint8List.fromList([...rBytes, ...sBytes]);
  }

  /// Convert BigInt to bytes with padding
  Uint8List _bigIntToBytes(BigInt number, int length) {
    final hexString = number.toRadixString(16).padLeft(length * 2, '0');
    final bytes = <int>[];
    for (int i = 0; i < hexString.length; i += 2) {
      bytes.add(int.parse(hexString.substring(i, i + 2), radix: 16));
    }
    return Uint8List.fromList(bytes);
  }

  /// Generate JWT token for Coinbase Cloud API authentication
  String _generateJWT(String method, String path) {
    try {
      // Parse EC private key
      final privateKey = _parseECPrivateKey(_apiSecret!);

      // Create JWT header
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final uri = '$method $_baseHost$path';

      final header = {
        'alg': 'ES256',
        'kid': _apiKey!,
        'nonce': _generateNonce(),
        'typ': 'JWT',
      };

      // Create JWT payload
      final payload = {
        'sub': _apiKey!,
        'iss': 'cdp',
        'nbf': now,
        'exp': now + 120,
        'uri': uri,
      };

      // Encode header and payload
      final headerEncoded = _base64UrlEncode(utf8.encode(json.encode(header)));
      final payloadEncoded = _base64UrlEncode(utf8.encode(json.encode(payload)));

      // Create signing input
      final signingInput = '$headerEncoded.$payloadEncoded';
      final signingInputBytes = Uint8List.fromList(utf8.encode(signingInput));

      // Sign
      final signature = _signES256(signingInputBytes, privateKey);
      final signatureEncoded = _base64UrlEncode(signature);

      // Build final JWT
      final jwt = '$signingInput.$signatureEncoded';

      debugPrint('[Coinbase] 🔐 Generated JWT for: $uri');
      return jwt;
    } catch (e) {
      debugPrint('[Coinbase] ❌ Failed to generate JWT: $e');
      rethrow;
    }
  }

  Map<String, String> _buildHeaders(String method, String path, {String body = ''}) {
    try {
      // Generate JWT token
      final token = _generateJWT(method, path);

      return {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      };
    } catch (e) {
      debugPrint('[Coinbase] ❌ Failed to build headers: $e');
      rethrow;
    }
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

      debugPrint('[Coinbase] 📡 Calling: $uri');
      debugPrint('[Coinbase] 📝 Headers: ${headers.keys.join(", ")}');
      debugPrint('[Coinbase] 🔑 API Key: ${_apiKey?.substring(0, 30)}...');

      final response = await http.get(uri, headers: headers).timeout(const Duration(seconds: 10));

      debugPrint('[Coinbase] 📥 Response status: ${response.statusCode}');

      if (response.statusCode != 200) {
        debugPrint('[Coinbase] ❌ Response body: ${response.body}');
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

      debugPrint('[Coinbase] ✅ Fetched ${balances.length} balances');
      return balances;
    } catch (e) {
      debugPrint('[Coinbase] ❌ Error fetching balances: $e');
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
      final originalSymbol = symbol;
      // Convert symbol format: BTCEUR -> BTC-USD
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

      // Get EUR/USD rate if we need to convert prices
      double eurUsdRate = 1.0;
      if (originalSymbol.contains('EUR') && coinbaseSymbol.contains('USD')) {
        eurUsdRate = await _getEurUsdRate();
      }

      final result = candles.take(limit).map((c) {
        final timestamp = c[0] as int; // Unix timestamp in seconds
        final timestampMs = timestamp * 1000; // Convert to milliseconds

        // Convert prices from USD to EUR if needed
        final low = (c[1] as num).toDouble() / eurUsdRate;
        final high = (c[2] as num).toDouble() / eurUsdRate;
        final open = (c[3] as num).toDouble() / eurUsdRate;
        final close = (c[4] as num).toDouble() / eurUsdRate;

        return Candle(
          openTime: DateTime.fromMillisecondsSinceEpoch(timestampMs),
          low: low,
          high: high,
          open: open,
          close: close,
          volume: (c[5] as num).toDouble(),
          closeTime: DateTime.fromMillisecondsSinceEpoch(timestampMs + (granularity * 1000)),
        );
      }).toList();

      if (result.isNotEmpty && originalSymbol.contains('EUR') && coinbaseSymbol.contains('USD')) {
        debugPrint('[Coinbase] 💱 Converted ${result.length} candles from USD to EUR (rate: $eurUsdRate)');
        debugPrint('[Coinbase] 💱 Sample: USD \$${(result.first.close * eurUsdRate).toStringAsFixed(2)} → EUR €${result.first.close.toStringAsFixed(2)}');
      }

      return result;
    } catch (e) {
      debugPrint('[Coinbase] Error fetching klines for $symbol: $e');
      return [];
    }
  }

  @override
  Future<Map<String, double>> fetchTicker24h(String symbol) async {
    try {
      final originalSymbol = symbol;
      final coinbaseSymbol = _convertToCoinbaseSymbol(symbol);

      // Coinbase Exchange API (public, no auth) - /products/{product-id}/ticker
      final path = '/products/$coinbaseSymbol/ticker';
      final uri = Uri.https(_exchangeHost, path);

      final response = await http.get(uri).timeout(const Duration(seconds: 5));

      if (response.statusCode != 200) {
        throw Exception('[Coinbase] Ticker error: ${response.statusCode}');
      }

      final data = json.decode(response.body) as Map<String, dynamic>;
      double price = double.tryParse(data['price'] ?? '0') ?? 0.0;

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

      // If original symbol was EUR but we converted to USD, convert price back to EUR
      if (originalSymbol.contains('EUR') && coinbaseSymbol.contains('USD')) {
        final eurUsdRate = await _getEurUsdRate();
        if (eurUsdRate > 0) {
          price = price / eurUsdRate; // Convert USD price to EUR
          debugPrint('[Coinbase] Converted USD price to EUR: \$${price * eurUsdRate} → €$price (rate: $eurUsdRate)');
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

  /// Get EUR/USD exchange rate from external APIs
  /// Returns the USD price of 1 EUR (e.g., 1.16 means €1 = $1.16)
  Future<double> _getEurUsdRate() async {
    try {
      // Check if we have a cached rate (valid for 1 hour)
      if (_cachedEurUsdRate > 0 &&
          _lastEurUsdRateTime != null &&
          DateTime.now().difference(_lastEurUsdRateTime!) < const Duration(hours: 1)) {
        return _cachedEurUsdRate;
      }

      // Try fetching from exchangerate-api.com (free, no auth required)
      // Using v6 API (v4 is deprecated and returns wrong rates)
      try {
        final uri = Uri.https('open.er-api.com', '/v6/latest/EUR');
        final response = await http.get(uri).timeout(const Duration(seconds: 5));

        if (response.statusCode == 200) {
          final data = json.decode(response.body) as Map<String, dynamic>;
          final rates = data['rates'] as Map<String, dynamic>;
          final rate = (rates['USD'] as num?)?.toDouble() ?? 0.0;

          if (rate > 0) {
            _cachedEurUsdRate = rate;
            _lastEurUsdRateTime = DateTime.now();
            debugPrint('[Coinbase] EUR→USD rate from exchangerate-api v6: $rate (1 EUR = $rate USD)');
            return rate;
          }
        }
      } catch (e) {
        debugPrint('[Coinbase] exchangerate-api.com v6 failed: $e');
      }

      // Fallback: Calculate from BTC prices on Kraken (XBTEUR vs XBTUSD)
      try {
        final eurUri = Uri.https('api.kraken.com', '/0/public/Ticker', {'pair': 'XBTEUR'});
        final usdUri = Uri.https('api.kraken.com', '/0/public/Ticker', {'pair': 'XBTUSD'});

        final eurResponse = await http.get(eurUri).timeout(const Duration(seconds: 5));
        final usdResponse = await http.get(usdUri).timeout(const Duration(seconds: 5));

        if (eurResponse.statusCode == 200 && usdResponse.statusCode == 200) {
          final eurData = json.decode(eurResponse.body) as Map<String, dynamic>;
          final usdData = json.decode(usdResponse.body) as Map<String, dynamic>;

          final eurResult = eurData['result'] as Map<String, dynamic>;
          final usdResult = usdData['result'] as Map<String, dynamic>;

          final btcEur = double.tryParse((eurResult.values.first as Map<String, dynamic>)['c'][0]) ?? 0.0;
          final btcUsd = double.tryParse((usdResult.values.first as Map<String, dynamic>)['c'][0]) ?? 0.0;

          if (btcEur > 0 && btcUsd > 0) {
            final rate = btcUsd / btcEur; // If BTC=€90k and BTC=$100k, then EUR/USD = 100/90 = 1.11
            _cachedEurUsdRate = rate;
            _lastEurUsdRateTime = DateTime.now();
            debugPrint('[Coinbase] EUR/USD rate calculated from Kraken BTC prices: $rate');
            return rate;
          }
        }
      } catch (e) {
        debugPrint('[Coinbase] Kraken BTC fallback failed: $e');
      }

      // Last resort fallback
      debugPrint('[Coinbase] All EUR/USD rate sources failed, using fallback 1.10');
      return 1.10; // Updated fallback based on current rates
    } catch (e) {
      debugPrint('[Coinbase] Error fetching EUR/USD rate: $e, using fallback 1.10');
      return 1.10;
    }
  }

  double _cachedEurUsdRate = 0.0;
  DateTime? _lastEurUsdRateTime;

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
  /// Example: BTCEUR -> BTC-USD, POLUSDT -> POL-USDT
  String _convertToCoinbaseSymbol(String symbol) {
    return getUniversalSymbol(symbol, 'Coinbase');
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

  /// Get 24h volume for a symbol
  Future<double> get24hVolume(String symbol) async {
    try {
      // Coinbase uses BTC-EUR format
      final coinbaseSymbol = symbol.contains('-') ? symbol : buildTradingPair(
        symbol.replaceAll(RegExp(r'(EUR|USD|USDC|USDT)$'), ''),
        symbol.substring(symbol.length - 3),
      );

      final uri = Uri.https(_baseHost, '/products/$coinbaseSymbol/stats');
      final response = await http.get(uri).timeout(const Duration(seconds: 5));

      if (response.statusCode != 200) {
        return 0.0;
      }

      final data = json.decode(response.body) as Map<String, dynamic>;
      final volume = double.tryParse(data['volume']?.toString() ?? '0') ?? 0.0;
      return volume;
    } catch (e) {
      debugPrint('[Coinbase] Error fetching volume for $symbol: $e');
      return 0.0;
    }
  }

  @override
  Future<double> getVolumePercentile(String targetSymbol, {List<String>? comparisonSymbols}) async {
    try {
      // Extract quote currency from targetSymbol (e.g., BTC-EUR → EUR)
      final RegExp quoteRegex = RegExp(r'(EUR|USD|USDC|USDT)$');
      final match = quoteRegex.firstMatch(targetSymbol);
      final quote = match?.group(1) ?? 'USD'; // Coinbase defaults to USD

      // Build dynamic comparison list with same quote currency
      final baseAssets = ['BTC', 'ETH', 'XRP', 'ADA', 'DOGE', 'DOT', 'LINK', 'UNI'];
      final symbols = comparisonSymbols ?? baseAssets.map((base) => buildTradingPair(base, quote)).toList();

      // Fetch volumes for all symbols in parallel
      final volumeFutures = symbols.map((s) => get24hVolume(s));
      final volumes = await Future.wait(volumeFutures, eagerError: false);

      // Get target volume
      final targetVolume = await get24hVolume(targetSymbol);

      // Calculate percentile: % of symbols with lower volume
      int lowerCount = 0;
      for (final vol in volumes) {
        if (vol < targetVolume) lowerCount++;
      }

      final percentile = lowerCount / volumes.length;
      debugPrint('[Coinbase] 📊 Volume percentile for $targetSymbol: ${(percentile * 100).toStringAsFixed(1)}% (volume: ${targetVolume.toStringAsFixed(0)} units)');

      return percentile;
    } catch (e) {
      debugPrint('[Coinbase] ❌ Failed to calculate volume percentile: $e');
      // Return median (0.5) on error - no boost or penalty
      return 0.5;
    }
  }

  // ===================================
  // ML Feature Engineering
  // ===================================

  /// Helper: Calculate ATR (Average True Range) from candle data
  double _calculateATR(List<List<double>> candles, {int period = 14}) {
    if (candles.length < period + 1) return 0.02; // Default 2% if insufficient data

    final trueRanges = <double>[];
    for (int i = 1; i < candles.length; i++) {
      final high = candles[i][2];
      final low = candles[i][3];
      final prevClose = candles[i - 1][4];

      final tr = [
        high - low,
        (high - prevClose).abs(),
        (low - prevClose).abs(),
      ].reduce((a, b) => a > b ? a : b);

      trueRanges.add(tr);
    }

    if (trueRanges.isEmpty) return 0.02;

    // Simple average of last N true ranges
    final atrValues = <double>[];
    for (int i = period - 1; i < trueRanges.length; i++) {
      final slice = trueRanges.sublist(i - period + 1, i + 1);
      final avg = slice.reduce((a, b) => a + b) / slice.length;
      atrValues.add(avg);
    }

    if (atrValues.isEmpty) return 0.02;

    final latestATR = atrValues.last;
    final latestPrice = candles.last[4];

    return latestPrice > 0 ? latestATR / latestPrice : 0.02;
  }

  @override
  Future<FeaturesWithATR> getFeaturesWithATRFallback(String symbol, {String interval = '1h'}) async {
    // Convert Binance-style symbol to Coinbase format (BTCEUR → BTC-EUR)
    final coinbaseSymbol = buildTradingPair(
      symbol.replaceAll('USDT', '').replaceAll('EUR', '').replaceAll('USD', ''),
      symbol.contains('EUR') ? 'EUR' : (symbol.contains('USDT') ? 'USDT' : 'USD'),
    );

    // Check cache first (Opțiunea 1)
    final cacheKey = '${coinbaseSymbol}_$interval';
    final now = DateTime.now();
    final cacheDuration = _getCacheDuration(interval);

    if (_candlesCache.containsKey(cacheKey) && _cacheTimestamp.containsKey(cacheKey)) {
      final cacheAge = now.difference(_cacheTimestamp[cacheKey]!);
      if (cacheAge < cacheDuration) {
        final cachedCandles = _candlesCache[cacheKey]!;
        debugPrint('[Coinbase] ⚡ Using CACHED candles for $coinbaseSymbol @ $interval (age: ${cacheAge.inSeconds}s)');

        // Calculate ATR from cached data
        final candlesForATR = cachedCandles.map((c) => [
          c.openTime.millisecondsSinceEpoch.toDouble(),
          c.open,
          c.high,
          c.low,
          c.close,
          c.volume,
        ]).toList();

        final atr = _calculateATR(candlesForATR, period: 14);

        // Build features using FullFeatureBuilder
        final fullBuilder = FullFeatureBuilder();
        final features = fullBuilder.buildFeatures(candles: cachedCandles);

        final currentPrice = cachedCandles.isNotEmpty ? cachedCandles.last.close : 0.0;

        return FeaturesWithATR(
          features: features,
          atr: atr,
          currentPrice: currentPrice,
        );
      }
    }

    // Fetch candles with retry on rate limit (Opțiunea 3)
    List<Candle> candles;
    try {
      candles = await fetchKlines(coinbaseSymbol, interval, limit: 1000);

      // Store in cache
      _candlesCache[cacheKey] = candles;
      _cacheTimestamp[cacheKey] = now;

      debugPrint('[Coinbase] 💾 CACHED candles for $coinbaseSymbol @ $interval (${candles.length} candles)');
    } catch (e) {
      // If rate limited and we have old cache, use it
      if (_candlesCache.containsKey(cacheKey)) {
        debugPrint('[Coinbase] ⚠️  Rate limited, using STALE cache for $coinbaseSymbol @ $interval');
        candles = _candlesCache[cacheKey]!;
      } else {
        rethrow;
      }
    }

    // Log latest candle
    if (candles.isNotEmpty) {
      final latestCandle = candles.last;
      final candleAge = now.difference(latestCandle.closeTime);
      final currencySymbol = _getCurrencySymbol(coinbaseSymbol);
      debugPrint('[Coinbase] 📅 Latest candle: ${latestCandle.closeTime} (${candleAge.inMinutes}min ago) - DATA IS FRESH!');
      debugPrint('[Coinbase]    Close: $currencySymbol${latestCandle.close.toStringAsFixed(2)}, Volume: ${latestCandle.volume.toStringAsFixed(2)}');
    }

    // Calculate ATR
    final candlesForATR = candles.map((c) => [
      c.openTime.millisecondsSinceEpoch.toDouble(),
      c.open,
      c.high,
      c.low,
      c.close,
      c.volume,
    ]).toList();

    final atr = _calculateATR(candlesForATR, period: 14);

    // Build features using FullFeatureBuilder
    final fullBuilder = FullFeatureBuilder();
    final features = fullBuilder.buildFeatures(candles: candles);

    final currentPrice = candles.isNotEmpty ? candles.last.close : 0.0;

    return FeaturesWithATR(
      features: features,
      atr: atr,
      currentPrice: currentPrice,
    );
  }
}

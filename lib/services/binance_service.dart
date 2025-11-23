import 'dart:convert';
import 'dart:async';
// import 'dart:io'; // Unused - commented out
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:crypto/crypto.dart';

import '../models/candle.dart';
import '../models/features_with_atr.dart';
// import '../services/technical_indicator_calculator.dart';
import '../services/full_feature_builder.dart';
import 'base_exchange_service.dart';

/// Result wrapper for feature extraction
class FeatureResult {
  final bool ok;
  final List<List<double>>? features;
  final String? error;
  final int? need;
  final int? got;

  const FeatureResult._({
    required this.ok,
    this.features,
    this.error,
    this.need,
    this.got,
  });

  factory FeatureResult.ok(List<List<double>> features) {
    return FeatureResult._(ok: true, features: features);
  }

  factory FeatureResult.error(String error, {int? need, int? got}) {
    return FeatureResult._(ok: false, error: error, need: need, got: got);
  }
}

class BinanceService implements BaseExchangeService {
  static const String _baseHost = 'api.binance.com'; // Only LIVE mode
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  // Singleton pattern
  static final BinanceService _instance = BinanceService._internal();
  factory BinanceService() => _instance;
  BinanceService._internal();

  String? _apiKey;
  String? _apiSecret;

  // Time synchronization
  int _serverTimeOffset = 0; // Milliseconds offset between server and local time
  DateTime? _lastTimeSyncTime;
  static const Duration _timeSyncInterval = Duration(minutes: 30);

  @override
  String get exchangeName => 'Binance';

  @override
  String? get apiKey => _apiKey;

  @override
  String? get apiSecret => _apiSecret;

  @override
  bool get hasCredentials => (_apiKey != null && _apiKey!.isNotEmpty && _apiSecret != null && _apiSecret!.isNotEmpty);

  @override
  String buildTradingPair(String base, String quote) {
    // Binance format: BTCEUR, ETHUSDT (simple concatenation)
    return '$base$quote';
  }

  @override
  String getPreferredQuote(String base, String desiredQuote) {
    // Normalize to uppercase
    final baseUpper = base.toUpperCase();
    final quoteUpper = desiredQuote.toUpperCase();

    // Major coins that support EUR, USD, USDT, BTC on Binance (as of 2025)
    // Note: BUSD was deprecated by Binance in 2024
    const majorCoinsWithEUR = {
      'BTC', 'ETH', 'BNB', 'SOL', 'XRP', 'AVAX', 'LINK',
      'DOGE', 'ADA', 'DOT', 'MATIC', 'LTC', 'BCH', 'XLM',
      'UNI', 'AAVE', 'SNX', 'COMP', 'YFI', 'MKR'
    };

    // Check if coin supports EUR/USD/USDT
    if (majorCoinsWithEUR.contains(baseUpper)) {
      // If user wants EUR and coin supports it → EUR
      if (quoteUpper == 'EUR') return 'EUR';
      // If user wants USD → convert to USDT (Binance.com doesn't have pure USD pairs)
      if (quoteUpper == 'USD') {
        // Binance only has USDT, not USD
        return 'USDT';
      }
      // If user wants USDT → USDT
      if (quoteUpper == 'USDT') return 'USDT';
      // If user wants BTC → BTC (for advanced traders who measure in BTC)
      // Only return BTC if explicitly requested AND coin is not BTC itself
      if (quoteUpper == 'BTC' && baseUpper != 'BTC') return 'BTC';
      // If user wants USDC → USDC or fallback to USDT
      if (quoteUpper == 'USDC') {
        // Some coins have USDC pairs (ETH, BNB, etc.)
        if (baseUpper == 'ETH' || baseUpper == 'BNB' || baseUpper == 'SOL') {
          return 'USDC';
        }
        return 'USDT'; // Fallback to USDT for others
      }

      // Default: return desired quote if it's major, else USDT
      return quoteUpper == 'EUR' || quoteUpper == 'USD' ? quoteUpper : 'USDT';
    } else {
      // Small/mid-cap coins typically only have USDT pairs on Binance
      // Examples: TRUMP, WLFI, POL, ARB, OP
      return 'USDT';
    }
  }

  /// Synchronize local time with Binance server time
  /// This prevents "Timestamp out of recvWindow" errors due to clock skew
  @override
  Future<void> syncServerTime() async {
    try {
      final uri = Uri.https(_baseHost, '/api/v3/time');
      final localBefore = DateTime.now().millisecondsSinceEpoch;

      final response = await http.get(uri).timeout(const Duration(seconds: 5));

      if (response.statusCode != 200) {
        debugPrint('⚠️ Failed to sync server time: ${response.statusCode}');
        return;
      }

      final localAfter = DateTime.now().millisecondsSinceEpoch;
      final data = json.decode(response.body) as Map<String, dynamic>;
      final serverTime = data['serverTime'] as int;

      // Calculate offset accounting for network latency
      final networkLatency = (localAfter - localBefore) ~/ 2;
      final localTimeApprox = localBefore + networkLatency;
      _serverTimeOffset = serverTime - localTimeApprox;

      _lastTimeSyncTime = DateTime.now();
      debugPrint('✅ Time synchronized with Binance server (offset: ${_serverTimeOffset}ms)');
    } catch (e) {
      debugPrint('⚠️ Time sync failed: $e (will use local time)');
    }
  }

  /// Get current timestamp synchronized with Binance server
  /// Automatically syncs if needed (first call or >30 mins since last sync)
  @override
  Future<int> getSynchronizedTimestamp() async {
    // Sync time on first call or if >30 mins since last sync
    if (_lastTimeSyncTime == null ||
        DateTime.now().difference(_lastTimeSyncTime!) > _timeSyncInterval) {
      await syncServerTime();
    }

    return DateTime.now().millisecondsSinceEpoch + _serverTimeOffset;
  }

  /// Load API credentials from secure storage
  @override
  Future<void> loadCredentials() async {
    try {
      final rawKey = await _secureStorage.read(key: 'binance_api_key');
      final rawSecret = await _secureStorage.read(key: 'binance_api_secret');

      // Clean credentials when loading (defensive - removes quotes, whitespace)
      _apiKey = rawKey?.replaceAll(RegExp(r'\s+'), '').replaceAll("'", '').replaceAll('"', '');
      _apiSecret = rawSecret?.replaceAll(RegExp(r'\s+'), '').replaceAll("'", '').replaceAll('"', '');

      // Sync time when loading credentials (prepares for API calls)
      if (_apiKey != null && _apiSecret != null) {
        await syncServerTime();
      }
    } catch (e) {
      debugPrint('Error loading credentials: $e');
    }
  }

  /// Save API credentials to secure storage
  @override
  Future<void> saveCredentials(String apiKey, String apiSecret) async {
    // Remove ALL whitespace and quotes from credentials (common copy-paste issues)
    final cleanApiKey = apiKey.replaceAll(RegExp(r'\s+'), '').replaceAll("'", '').replaceAll('"', '');
    final cleanApiSecret = apiSecret.replaceAll(RegExp(r'\s+'), '').replaceAll("'", '').replaceAll('"', '');

    await _secureStorage.write(key: 'binance_api_key', value: cleanApiKey);
    await _secureStorage.write(key: 'binance_api_secret', value: cleanApiSecret);
    _apiKey = cleanApiKey;
    _apiSecret = cleanApiSecret;
  }

  /// Retry HTTP requests with exponential backoff
  /// Unused - kept for potential future use
  /*
  Future<http.Response> _requestWithRetry(
    Future<http.Response> Function() request, {
    int maxRetries = 3,
    Duration initialDelay = const Duration(seconds: 1),
  }) async {
    int retryCount = 0;
    
    while (true) {
      try {
        final response = await request().timeout(
          const Duration(seconds: 10),
        );
        
        // Success
        if (response.statusCode == 200) {
          return response;
        }
        
        // Rate limited - wait longer
        if (response.statusCode == 429) {
          if (retryCount >= maxRetries) {
            throw Exception('Rate limited. Please try again later.');
          }
          
          final delay = Duration(
            seconds: (2 << (retryCount + 1)), // 4s, 8s, 16s
          );
          debugPrint('Rate limited. Retrying in ${delay.inSeconds}s...');
          await Future.delayed(delay);
          retryCount++;
          continue;
        }
        
        // Other HTTP errors
        throw Exception('HTTP ${response.statusCode}: ${response.body}');
        
      } on TimeoutException {
        if (retryCount >= maxRetries) {
          throw Exception('Request timed out after $maxRetries retries');
        }
        
        final delay = Duration(
          seconds: initialDelay.inSeconds * (1 << retryCount), // 1s, 2s, 4s
        );
        debugPrint('Timeout. Retrying in ${delay.inSeconds}s...');
        await Future.delayed(delay);
        retryCount++;
        
      } on SocketException {
        if (retryCount >= maxRetries) {
          throw Exception('No internet connection');
        }
        
        final delay = Duration(
          seconds: initialDelay.inSeconds * (1 << retryCount),
        );
        debugPrint('Network error. Retrying in ${delay.inSeconds}s...');
        await Future.delayed(delay);
        retryCount++;
      }
    }
  }
  */

  /// Clear stored credentials
  @override
  Future<void> clearCredentials() async {
    await _secureStorage.delete(key: 'binance_api_key');
    await _secureStorage.delete(key: 'binance_api_secret');
    _apiKey = null;
    _apiSecret = null;
  }

  /// Test API connection
  @override
  Future<bool> testConnection() async {
    if (_apiKey == null || _apiSecret == null) {
      throw Exception('API credentials not set');
    }

    try {
      final timestamp = await getSynchronizedTimestamp();
      final queryString = 'timestamp=$timestamp';
      final signature = _generateSignature(queryString);

      final uri = Uri.https(_baseHost, '/api/v3/account', {
        'timestamp': timestamp.toString(),
        'signature': signature,
      });

      final response = await http.get(
        uri,
        headers: {'X-MBX-APIKEY': _apiKey!},
      );

      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Connection test failed: $e');
      return false;
    }
  }

  /// Get account balances
  /// Returns Map<String, double> with asset symbol as key and free balance as value
  @override
  Future<Map<String, double>> getAccountBalances() async {
    if (_apiKey == null || _apiSecret == null) {
      throw Exception('API credentials not set');
    }

    try {
      final timestamp = await getSynchronizedTimestamp();
      final queryString = 'timestamp=$timestamp';
      final signature = _generateSignature(queryString);

      final uri = Uri.https(_baseHost, '/api/v3/account', {
        'timestamp': timestamp.toString(),
        'signature': signature,
      });

      final response = await http.get(
        uri,
        headers: {'X-MBX-APIKEY': _apiKey!},
      );

      if (response.statusCode != 200) {
        throw Exception('Binance account error ${response.statusCode}: ${response.body}');
      }

      final data = json.decode(response.body) as Map<String, dynamic>;
      final balances = data['balances'] as List<dynamic>;

      final Map<String, double> result = {};
      for (final balance in balances) {
        final asset = balance['asset'] as String;
        final free = double.tryParse(balance['free'].toString()) ?? 0.0;
        final locked = double.tryParse(balance['locked'].toString()) ?? 0.0;
        final total = free + locked;
        if (total > 0) {
          result[asset] = total;
        }
      }

      return result;
    } catch (e) {
      debugPrint('Failed to fetch account balances: $e');
      rethrow;
    }
  }

  String _generateSignature(String queryString) {
    final key = utf8.encode(_apiSecret!);
    final bytes = utf8.encode(queryString);
    final hmac = Hmac(sha256, key);
    final digest = hmac.convert(bytes);
    return digest.toString();
  }

  /// Get currency symbol from trading pair (EUR → €, USD → $)
  String _getCurrencySymbol(String symbol) {
    if (symbol.contains('EUR')) return '€';
    if (symbol.contains('USD')) return '\$';
    if (symbol.contains('GBP')) return '£';
    if (symbol.contains('JPY')) return '¥';
    return '\$'; // Default to $
  }

  // Cache for exchange info to avoid repeated API calls
  Map<String, dynamic>? _exchangeInfoCache;
  DateTime? _exchangeInfoCacheTime;
  static const Duration _cacheExpiry = Duration(hours: 1);

  /// Fetch exchange information for symbols (LOT_SIZE, PRICE_FILTER, etc.)
  /// Cached for 1 hour to avoid excessive API calls
  @override
  Future<Map<String, dynamic>> getExchangeInfo({String? symbol}) async {
    // Return cached data if still valid
    if (_exchangeInfoCache != null &&
        _exchangeInfoCacheTime != null &&
        DateTime.now().difference(_exchangeInfoCacheTime!) < _cacheExpiry) {
      return _exchangeInfoCache!;
    }

    try {
      // Convert symbol format for Binance API if provided
      String? binanceSymbol;
      if (symbol != null) {
        final upperSymbol = symbol.toUpperCase();
        if (upperSymbol.endsWith('USD') && !upperSymbol.endsWith('USDT') && !upperSymbol.endsWith('BUSD')) {
          // Convert USD to USDT (Binance doesn't have raw USD pairs)
          final base = upperSymbol.replaceAll(RegExp(r'USD$'), '');
          binanceSymbol = '${base}USDT';
          debugPrint('[BinanceService] getExchangeInfo: Converting $symbol → $binanceSymbol');
        } else {
          binanceSymbol = upperSymbol;
        }
      }

      final uri = binanceSymbol != null
          ? Uri.https(_baseHost, '/api/v3/exchangeInfo', {'symbol': binanceSymbol})
          : Uri.https(_baseHost, '/api/v3/exchangeInfo');

      final response = await http.get(uri);

      if (response.statusCode != 200) {
        throw Exception('Exchange info error ${response.statusCode}: ${response.body}');
      }

      final data = json.decode(response.body) as Map<String, dynamic>;

      // Cache the result
      _exchangeInfoCache = data;
      _exchangeInfoCacheTime = DateTime.now();

      return data;
    } catch (e) {
      debugPrint('Failed to fetch exchange info: $e');
      rethrow;
    }
  }

  /// Get symbol-specific filters (LOT_SIZE, PRICE_FILTER, MIN_NOTIONAL)
  Future<Map<String, dynamic>?> getSymbolFilters(String symbol) async {
    try {
      final exchangeInfo = await getExchangeInfo(symbol: symbol);
      final symbols = exchangeInfo['symbols'] as List<dynamic>;

      if (symbols.isEmpty) {
        return null;
      }

      final symbolData = symbols.first as Map<String, dynamic>;
      final filters = symbolData['filters'] as List<dynamic>;

      final Map<String, dynamic> result = {
        'baseAsset': symbolData['baseAsset'],
        'quoteAsset': symbolData['quoteAsset'],
        'status': symbolData['status'],
      };

      // Extract important filters
      for (final filter in filters) {
        final filterMap = filter as Map<String, dynamic>;
        final filterType = filterMap['filterType'] as String;

        if (filterType == 'LOT_SIZE') {
          result['lotSize'] = {
            'minQty': double.parse(filterMap['minQty'].toString()),
            'maxQty': double.parse(filterMap['maxQty'].toString()),
            'stepSize': double.parse(filterMap['stepSize'].toString()),
          };
        } else if (filterType == 'PRICE_FILTER') {
          result['priceFilter'] = {
            'minPrice': double.parse(filterMap['minPrice'].toString()),
            'maxPrice': double.parse(filterMap['maxPrice'].toString()),
            'tickSize': double.parse(filterMap['tickSize'].toString()),
          };
        } else if (filterType == 'MIN_NOTIONAL') {
          result['minNotional'] = double.parse(filterMap['minNotional'].toString());
        }
      }

      return result;
    } catch (e) {
      debugPrint('Failed to get symbol filters: $e');
      return null;
    }
  }

  /// Validate and round quantity to comply with LOT_SIZE filter
  Future<double?> validateQuantity(String symbol, double quantity) async {
    final filters = await getSymbolFilters(symbol);
    if (filters == null || !filters.containsKey('lotSize')) {
      debugPrint('⚠️ Could not fetch LOT_SIZE filter for $symbol, using quantity as-is');
      return quantity;
    }

    final lotSize = filters['lotSize'] as Map<String, dynamic>;
    final minQty = lotSize['minQty'] as double;
    final maxQty = lotSize['maxQty'] as double;
    final stepSize = lotSize['stepSize'] as double;

    // Check minimum quantity
    if (quantity < minQty) {
      throw Exception('Quantity $quantity is below minimum $minQty for $symbol');
    }

    // Check maximum quantity
    if (quantity > maxQty) {
      throw Exception('Quantity $quantity exceeds maximum $maxQty for $symbol');
    }

    // Round to stepSize precision
    final precision = _getDecimalPlaces(stepSize);
    final rounded = _roundToStep(quantity, stepSize, precision);

    debugPrint('✅ Quantity validation: $quantity → $rounded (stepSize: $stepSize)');
    return rounded;
  }

  /// Calculate number of decimal places needed for a step size
  int _getDecimalPlaces(double stepSize) {
    final str = stepSize.toStringAsFixed(10);
    final parts = str.split('.');
    if (parts.length < 2) return 0;

    // Count non-zero decimals
    final decimals = parts[1].replaceAll(RegExp(r'0+$'), '');
    return decimals.length;
  }

  /// Round quantity to nearest step size
  double _roundToStep(double value, double stepSize, int precision) {
    final multiplier = 1 / stepSize;
    final rounded = (value * multiplier).round() / multiplier;
    return double.parse(rounded.toStringAsFixed(precision));
  }

  /// Place a MARKET order (BUY/SELL) on spot. Uses testnet when selected in settings.
  /// Either [quantity] (base units) or [quoteOrderQty] (quote currency) must be provided.
  /// Quantity will be automatically validated and rounded to comply with LOT_SIZE filter.
  Future<Map<String, dynamic>> placeMarketOrder({
    required String symbol,
    required String side, // 'BUY' | 'SELL'
    double? quantity,
    double? quoteOrderQty,
    int recvWindowMs = 5000,
  }) async {
    if (_apiKey == null || _apiSecret == null) {
      throw Exception('API credentials not set');
    }
    if ((quantity == null || quantity <= 0) && (quoteOrderQty == null || quoteOrderQty <= 0)) {
      throw Exception('Provide quantity (base) or quoteOrderQty (>0)');
    }

    // Convert symbol format for Binance API
    // Binance.com doesn't have USD pairs, only USDT
    final upperSymbol = symbol.toUpperCase();
    String binanceSymbol;
    if (upperSymbol.endsWith('USD') && !upperSymbol.endsWith('USDT') && !upperSymbol.endsWith('BUSD')) {
      // Convert USD to USDT (Binance doesn't have raw USD pairs)
      final base = upperSymbol.replaceAll(RegExp(r'USD$'), '');
      binanceSymbol = '${base}USDT';
      debugPrint('[BinanceService] placeMarketOrder: Converting $symbol → $binanceSymbol');
    } else {
      binanceSymbol = upperSymbol;
    }

    // Validate and round quantity to comply with LOT_SIZE filter
    if (quantity != null && quantity > 0) {
      try {
        quantity = await validateQuantity(binanceSymbol, quantity);
        debugPrint('✅ Validated quantity for $symbol: $quantity');
      } catch (e) {
        debugPrint('⚠️ Quantity validation failed: $e');
        rethrow; // Re-throw to show user-friendly error
      }
    }

    final int timestamp = await getSynchronizedTimestamp();
    final Map<String, String> params = <String, String>{
      'symbol': binanceSymbol,
      'side': side.toUpperCase(),
      'type': 'MARKET',
      'newOrderRespType': 'RESULT',
      'recvWindow': recvWindowMs.toString(),
      'timestamp': timestamp.toString(),
    };
    if (quantity != null && quantity > 0) {
      params['quantity'] = quantity.toString();
    } else if (quoteOrderQty != null && quoteOrderQty > 0) {
      params['quoteOrderQty'] = quoteOrderQty.toString();
    }

    // Build query string for signature
    final String queryString = params.entries.map((e) => '${e.key}=${e.value}').join('&');
    final String signature = _generateSignature(queryString);

    final uri = Uri.https(_baseHost, '/api/v3/order');
    final String body = '$queryString&signature=$signature';
    final res = await http.post(
      uri,
      headers: <String, String>{
        'X-MBX-APIKEY': _apiKey!,
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: body,
    );
    if (res.statusCode != 200) {
      throw Exception('Binance order error ${res.statusCode}: ${res.body}');
    }
    return json.decode(res.body) as Map<String, dynamic>;
  }

  /// Place a LIMIT order (BUY/SELL) on spot
  /// Order will execute only at specified price or better
  Future<Map<String, dynamic>> placeLimitOrder({
    required String symbol,
    required String side, // 'BUY' | 'SELL'
    required double quantity,
    required double price,
    String timeInForce = 'GTC', // GTC (Good Till Cancel), IOC, FOK
    int recvWindowMs = 5000,
  }) async {
    if (_apiKey == null || _apiSecret == null) {
      throw Exception('API credentials not set');
    }
    if (quantity <= 0) {
      throw Exception('Quantity must be > 0');
    }
    if (price <= 0) {
      throw Exception('Price must be > 0');
    }

    // Convert symbol format for Binance API
    // Binance.com doesn't have USD pairs, only USDT
    final upperSymbol = symbol.toUpperCase();
    String binanceSymbol;
    if (upperSymbol.endsWith('USD') && !upperSymbol.endsWith('USDT') && !upperSymbol.endsWith('BUSD')) {
      // Convert USD to USDT (Binance doesn't have raw USD pairs)
      final base = upperSymbol.replaceAll(RegExp(r'USD$'), '');
      binanceSymbol = '${base}USDT';
      debugPrint('[BinanceService] placeLimitOrder: Converting $symbol → $binanceSymbol');
    } else {
      binanceSymbol = upperSymbol;
    }

    final int timestamp = await getSynchronizedTimestamp();
    final Map<String, String> params = <String, String>{
      'symbol': binanceSymbol,
      'side': side.toUpperCase(),
      'type': 'LIMIT',
      'timeInForce': timeInForce,
      'quantity': quantity.toString(),
      'price': price.toString(),
      'newOrderRespType': 'RESULT',
      'recvWindow': recvWindowMs.toString(),
      'timestamp': timestamp.toString(),
    };

    final String queryString = params.entries.map((e) => '${e.key}=${e.value}').join('&');
    final String signature = _generateSignature(queryString);

    final uri = Uri.https(_baseHost, '/api/v3/order');
    final String body = '$queryString&signature=$signature';
    final res = await http.post(
      uri,
      headers: <String, String>{
        'X-MBX-APIKEY': _apiKey!,
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: body,
    );
    if (res.statusCode != 200) {
      throw Exception('Binance limit order error ${res.statusCode}: ${res.body}');
    }
    return json.decode(res.body) as Map<String, dynamic>;
  }

  /// Place a STOP_LOSS_LIMIT order
  /// Activates a limit order when price reaches stopPrice
  Future<Map<String, dynamic>> placeStopLimitOrder({
    required String symbol,
    required String side, // 'BUY' | 'SELL'
    required double quantity,
    required double price, // Limit price
    required double stopPrice, // Trigger price
    String timeInForce = 'GTC',
    int recvWindowMs = 5000,
  }) async {
    if (_apiKey == null || _apiSecret == null) {
      throw Exception('API credentials not set');
    }
    if (quantity <= 0 || price <= 0 || stopPrice <= 0) {
      throw Exception('Quantity, price, and stopPrice must be > 0');
    }

    // Convert symbol format for Binance API
    final upperSymbol = symbol.toUpperCase();
    String binanceSymbol;
    if (upperSymbol.endsWith('USD') && !upperSymbol.endsWith('USDT') && !upperSymbol.endsWith('BUSD')) {
      final base = upperSymbol.replaceAll(RegExp(r'USD$'), '');
      binanceSymbol = '${base}USDT';
      debugPrint('[BinanceService] placeStopLimitOrder: Converting $symbol → $binanceSymbol');
    } else {
      binanceSymbol = upperSymbol;
    }

    final int timestamp = await getSynchronizedTimestamp();
    final Map<String, String> params = <String, String>{
      'symbol': binanceSymbol,
      'side': side.toUpperCase(),
      'type': 'STOP_LOSS_LIMIT',
      'timeInForce': timeInForce,
      'quantity': quantity.toString(),
      'price': price.toString(),
      'stopPrice': stopPrice.toString(),
      'newOrderRespType': 'RESULT',
      'recvWindow': recvWindowMs.toString(),
      'timestamp': timestamp.toString(),
    };

    final String queryString = params.entries.map((e) => '${e.key}=${e.value}').join('&');
    final String signature = _generateSignature(queryString);

    final uri = Uri.https(_baseHost, '/api/v3/order');
    final String body = '$queryString&signature=$signature';
    final res = await http.post(
      uri,
      headers: <String, String>{
        'X-MBX-APIKEY': _apiKey!,
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: body,
    );
    if (res.statusCode != 200) {
      throw Exception('Binance stop-limit order error ${res.statusCode}: ${res.body}');
    }
    return json.decode(res.body) as Map<String, dynamic>;
  }

  /// Place a STOP_LOSS (market) order
  /// Activates a market order when price reaches stopPrice
  Future<Map<String, dynamic>> placeStopMarketOrder({
    required String symbol,
    required String side, // 'BUY' | 'SELL'
    required double quantity,
    required double stopPrice, // Trigger price
    int recvWindowMs = 5000,
  }) async {
    if (_apiKey == null || _apiSecret == null) {
      throw Exception('API credentials not set');
    }
    if (quantity <= 0 || stopPrice <= 0) {
      throw Exception('Quantity and stopPrice must be > 0');
    }

    // Convert symbol format for Binance API
    final upperSymbol = symbol.toUpperCase();
    String binanceSymbol;
    if (upperSymbol.endsWith('USD') && !upperSymbol.endsWith('USDT') && !upperSymbol.endsWith('BUSD')) {
      final base = upperSymbol.replaceAll(RegExp(r'USD$'), '');
      binanceSymbol = '${base}USDT';
      debugPrint('[BinanceService] placeStopMarketOrder: Converting $symbol → $binanceSymbol');
    } else {
      binanceSymbol = upperSymbol;
    }

    final int timestamp = await getSynchronizedTimestamp();
    final Map<String, String> params = <String, String>{
      'symbol': binanceSymbol,
      'side': side.toUpperCase(),
      'type': 'STOP_LOSS',
      'quantity': quantity.toString(),
      'stopPrice': stopPrice.toString(),
      'newOrderRespType': 'RESULT',
      'recvWindow': recvWindowMs.toString(),
      'timestamp': timestamp.toString(),
    };

    final String queryString = params.entries.map((e) => '${e.key}=${e.value}').join('&');
    final String signature = _generateSignature(queryString);

    final uri = Uri.https(_baseHost, '/api/v3/order');
    final String body = '$queryString&signature=$signature';
    final res = await http.post(
      uri,
      headers: <String, String>{
        'X-MBX-APIKEY': _apiKey!,
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: body,
    );
    if (res.statusCode != 200) {
      throw Exception('Binance stop-market order error ${res.statusCode}: ${res.body}');
    }
    return json.decode(res.body) as Map<String, dynamic>;
  }

  /// Fetch open spot orders (signed). If [symbol] provided, filters by symbol.
  Future<List<Map<String, dynamic>>> fetchOpenOrders({String? symbol, int recvWindowMs = 5000}) async {
    if (_apiKey == null || _apiSecret == null) {
      throw Exception('API credentials not set');
    }

    // Convert symbol format for Binance API if provided
    String? binanceSymbol;
    if (symbol != null && symbol.isNotEmpty) {
      final upperSymbol = symbol.toUpperCase();
      if (upperSymbol.endsWith('USD') && !upperSymbol.endsWith('USDT') && !upperSymbol.endsWith('BUSD')) {
        final base = upperSymbol.replaceAll(RegExp(r'USD$'), '');
        binanceSymbol = '${base}USDT';
        debugPrint('[BinanceService] fetchOpenOrders: Converting $symbol → $binanceSymbol');
      } else {
        binanceSymbol = upperSymbol;
      }
    }

    final int timestamp = await getSynchronizedTimestamp();
    final Map<String, String> params = <String, String>{
      'timestamp': timestamp.toString(),
      'recvWindow': recvWindowMs.toString(),
    };
    if (binanceSymbol != null) params['symbol'] = binanceSymbol;

    final String queryString = params.entries.map((e) => '${e.key}=${e.value}').join('&');
    final String signature = _generateSignature(queryString);

    final uri = Uri.https(_baseHost, '/api/v3/openOrders', {
      ...params,
      'signature': signature,
    });

    final res = await http.get(uri, headers: {'X-MBX-APIKEY': _apiKey!});
    if (res.statusCode != 200) {
      throw Exception('Binance openOrders error ${res.statusCode}: ${res.body}');
    }
    final List<dynamic> data = json.decode(res.body) as List<dynamic>;
    return data.cast<Map<String, dynamic>>();
  }

  /// Cancel an open order by orderId or origClientOrderId
  Future<Map<String, dynamic>> cancelOrder({
    required String symbol,
    int? orderId,
    String? origClientOrderId,
    int recvWindowMs = 5000,
  }) async {
    if (_apiKey == null || _apiSecret == null) {
      throw Exception('API credentials not set');
    }
    if (orderId == null && (origClientOrderId == null || origClientOrderId.isEmpty)) {
      throw Exception('Provide orderId or origClientOrderId');
    }

    // Convert symbol format for Binance API
    final upperSymbol = symbol.toUpperCase();
    String binanceSymbol;
    if (upperSymbol.endsWith('USD') && !upperSymbol.endsWith('USDT') && !upperSymbol.endsWith('BUSD')) {
      final base = upperSymbol.replaceAll(RegExp(r'USD$'), '');
      binanceSymbol = '${base}USDT';
      debugPrint('[BinanceService] cancelOrder: Converting $symbol → $binanceSymbol');
    } else {
      binanceSymbol = upperSymbol;
    }

    final int timestamp = await getSynchronizedTimestamp();
    final Map<String, String> params = <String, String>{
      'symbol': binanceSymbol,
      'recvWindow': recvWindowMs.toString(),
      'timestamp': timestamp.toString(),
    };
    if (orderId != null) params['orderId'] = orderId.toString();
    if (origClientOrderId != null && origClientOrderId.isNotEmpty) params['origClientOrderId'] = origClientOrderId;

    final String queryString = params.entries.map((e) => '${e.key}=${e.value}').join('&');
    final String signature = _generateSignature(queryString);

    final uri = Uri.https(_baseHost, '/api/v3/order', {
      ...params,
      'signature': signature,
    });
    final res = await http.delete(uri, headers: {'X-MBX-APIKEY': _apiKey!});
    if (res.statusCode != 200) {
      throw Exception('Binance cancel error ${res.statusCode}: ${res.body}');
    }
    return json.decode(res.body) as Map<String, dynamic>;
  }

  /// Place an OCO order (One-Cancels-the-Other) for spot.
  /// Typical use: side=SELL for take-profit + stop-loss after a BUY.
  Future<Map<String, dynamic>> placeOcoOrder({
    required String symbol,
    required String side, // 'BUY' | 'SELL'
    required double quantity,
    required double price, // take-profit price
    required double stopPrice,
    double? stopLimitPrice,
    String stopLimitTimeInForce = 'GTC',
    int recvWindowMs = 5000,
  }) async {
    if (_apiKey == null || _apiSecret == null) {
      throw Exception('API credentials not set');
    }

    // Convert symbol format for Binance API
    final upperSymbol = symbol.toUpperCase();
    String binanceSymbol;
    if (upperSymbol.endsWith('USD') && !upperSymbol.endsWith('USDT') && !upperSymbol.endsWith('BUSD')) {
      final base = upperSymbol.replaceAll(RegExp(r'USD$'), '');
      binanceSymbol = '${base}USDT';
      debugPrint('[BinanceService] placeOcoOrder: Converting $symbol → $binanceSymbol');
    } else {
      binanceSymbol = upperSymbol;
    }

    final int timestamp = await getSynchronizedTimestamp();
    final Map<String, String> params = <String, String>{
      'symbol': binanceSymbol,
      'side': side.toUpperCase(),
      'quantity': quantity.toString(),
      'price': price.toString(),
      'stopPrice': stopPrice.toString(),
      'recvWindow': recvWindowMs.toString(),
      'timestamp': timestamp.toString(),
    };
    if (stopLimitPrice != null) {
      params['stopLimitPrice'] = stopLimitPrice.toString();
      params['stopLimitTimeInForce'] = stopLimitTimeInForce;
    }

    final String queryString = params.entries.map((e) => '${e.key}=${e.value}').join('&');
    final String signature = _generateSignature(queryString);

    final uri = Uri.https(_baseHost, '/api/v3/order/oco');
    final String body = '$queryString&signature=$signature';
    final res = await http.post(
      uri,
      headers: <String, String>{
        'X-MBX-APIKEY': _apiKey!,
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: body,
    );
    if (res.statusCode != 200) {
      throw Exception('Binance OCO error ${res.statusCode}: ${res.body}');
    }
    return json.decode(res.body) as Map<String, dynamic>;
  }

  /// Fetches klines (OHLCV) for a spot symbol with configurable interval
  /// Returns up to [limit] candles between [start] and [end].
  @override
  Future<List<Candle>> fetchKlines(
    String symbol,
    String interval, {
    int limit = 500,
    int? endTime,
  }) async {
    // Convert symbol format for Binance API
    // Binance.com doesn't have USD pairs, only USDT
    final upperSymbol = symbol.toUpperCase();
    String binanceSymbol;
    if (upperSymbol.endsWith('USD') && !upperSymbol.endsWith('USDT') && !upperSymbol.endsWith('BUSD')) {
      // Convert USD to USDT (Binance doesn't have raw USD pairs)
      final base = upperSymbol.replaceAll(RegExp(r'USD$'), '');
      binanceSymbol = '${base}USDT';
      debugPrint('[BinanceService] fetchKlines: Converting $symbol → $binanceSymbol');
    } else {
      binanceSymbol = upperSymbol;
    }

    final Map<String, String> query = {
      'symbol': binanceSymbol,
      'interval': interval,
      'limit': limit.toString(),
    };
    if (endTime != null) query['endTime'] = endTime.toString();

    final uri = Uri.https(_baseHost, '/api/v3/klines', query);
    final http.Response res = await http.get(uri);
    if (res.statusCode != 200) {
      throw Exception('Binance klines error ${res.statusCode}: ${res.body}');
    }
    final List<dynamic> raw = json.decode(res.body) as List<dynamic>;
    return raw.map((e) => _parseKlineArray(e as List<dynamic>)).toList();
  }

  /// Fetches daily klines (OHLCV) for a spot symbol like 'BTCUSDT'.
  Future<List<Candle>> fetchDailyKlines(
    String symbol, {
    int? endTime,
    int limit = 1000,
  }) async {
    return fetchKlines(symbol, '1d', endTime: endTime, limit: limit);
  }

  /// Fetches hourly klines (OHLCV) for a spot symbol like 'BTCUSDT'.
  Future<List<Candle>> fetchHourlyKlines(
    String symbol, {
    int? endTime,
    int limit = 60,
  }) async {
    return fetchKlines(symbol, '1h', endTime: endTime, limit: limit);
  }

  /// Generic klines fetch for a custom interval like '15m', '1h', '4h'
  Future<List<Candle>> fetchCustomKlines(String symbol, String interval, {int limit = 60}) async {
    return fetchKlines(symbol, interval, limit: limit);
  }

  /// Fetch tradable spot pairs (symbol, base, quote) from exchangeInfo
  Future<List<Map<String, String>>> fetchTradingPairs() async {
    final uri = Uri.https(_baseHost, '/api/v3/exchangeInfo');
    final http.Response res = await http.get(uri);
    if (res.statusCode != 200) {
      throw Exception('Binance exchangeInfo error ${res.statusCode}: ${res.body}');
    }
    final Map<String, dynamic> data = json.decode(res.body) as Map<String, dynamic>;
    final List<dynamic> symbols = (data['symbols'] as List<dynamic>?) ?? <dynamic>[];
    final List<Map<String, String>> pairs = <Map<String, String>>[];
    for (final dynamic s in symbols) {
      final Map<String, dynamic> m = s as Map<String, dynamic>;
      final String status = (m['status'] ?? '').toString();
      final bool spot = (m['isSpotTradingAllowed'] ?? false) == true;
      if (status == 'TRADING' && spot) {
        final String symbol = (m['symbol'] ?? '').toString();
        final String base = (m['baseAsset'] ?? '').toString();
        final String quote = (m['quoteAsset'] ?? '').toString();
        pairs.add({'symbol': symbol, 'base': base, 'quote': quote});
      }
    }
    return pairs;
  }

  /// Fetch 24h ticker data for a symbol. Returns lastPrice and priceChangePercent.
  @override
  Future<Map<String, double>> fetchTicker24h(String symbol) async {
    // Convert symbol format for Binance API
    // Binance.com doesn't have USD pairs, only USDT
    final upperSymbol = symbol.toUpperCase();
    String binanceSymbol;
    if (upperSymbol.endsWith('USD') && !upperSymbol.endsWith('USDT') && !upperSymbol.endsWith('BUSD')) {
      // Convert USD to USDT (Binance doesn't have raw USD pairs)
      // Exclude BUSD (Binance USD is a valid quote currency)
      final base = upperSymbol.replaceAll(RegExp(r'USD$'), '');
      binanceSymbol = '${base}USDT';
      debugPrint('[BinanceService] fetchTicker24h: Converting $symbol → $binanceSymbol');
    } else {
      binanceSymbol = upperSymbol;
    }

    final uri = Uri.https(_baseHost, '/api/v3/ticker/24hr', {'symbol': binanceSymbol});
    final http.Response res = await http.get(uri);
    if (res.statusCode != 200) {
      throw Exception('Binance 24hr ticker error ${res.statusCode}: ${res.body}');
    }
    final Map<String, dynamic> data = json.decode(res.body) as Map<String, dynamic>;
    final double lastPrice = double.tryParse((data['lastPrice']).toString()) ?? 0.0;
    final double changePercent = double.tryParse((data['priceChangePercent']).toString()) ?? 0.0;
    return {'lastPrice': lastPrice, 'priceChangePercent': changePercent};
  }

  /// Get 24h trading volume for a symbol in quote currency (e.g., EUR for BTCEUR)
  /// Returns volume in quote currency (for BTCEUR, returns EUR volume)
  ///
  /// Used by Phase 3 of Enhanced Ensemble Strategy to apply volume-based confidence boost.
  /// High-volume coins (> median) get +5% confidence boost for general models.
  Future<double> get24hVolume(String symbol) async {
    try {
      // Convert symbol format for Binance API
      // Binance.com doesn't have USD pairs, only USDT
      final upperSymbol = symbol.toUpperCase();
      String binanceSymbol;
      if (upperSymbol.endsWith('USD') && !upperSymbol.endsWith('USDT') && !upperSymbol.endsWith('BUSD')) {
        // Convert USD to USDT (Binance doesn't have raw USD pairs)
        final base = upperSymbol.replaceAll(RegExp(r'USD$'), '');
        binanceSymbol = '${base}USDT';
        debugPrint('[BinanceService] 24h volume: Converting $symbol → $binanceSymbol');
      } else {
        binanceSymbol = upperSymbol;
      }

      final uri = Uri.https(_baseHost, '/api/v3/ticker/24hr', {'symbol': binanceSymbol});
      final http.Response res = await http.get(uri);
      if (res.statusCode != 200) {
        throw Exception('Binance 24hr volume error ${res.statusCode}: ${res.body}');
      }
      final Map<String, dynamic> data = json.decode(res.body) as Map<String, dynamic>;

      // quoteVolume = 24h trading volume in quote currency (e.g., EUR)
      final double quoteVolume = double.tryParse((data['quoteVolume']).toString()) ?? 0.0;
      return quoteVolume;
    } catch (e) {
      debugPrint('❌ BinanceService: Failed to fetch 24h volume for $symbol: $e');
      rethrow;
    }
  }

  /// Get 24h volumes for multiple symbols and calculate volume percentile for target symbol
  /// Returns volume percentile (0.0 to 1.0) indicating where target symbol ranks
  ///
  /// Example: percentile = 0.75 means target symbol has higher volume than 75% of comparison symbols
  ///
  /// Used by Phase 3: High-volume symbols (percentile > 0.5) get +5% confidence boost
  Future<double> getVolumePercentile(String targetSymbol, {List<String>? comparisonSymbols}) async {
    try {
      // FIX 2025: Extract quote currency and compare ONLY with same quote
      String quote;
      if (targetSymbol.endsWith('USDT') || targetSymbol.endsWith('BUSD') || targetSymbol.endsWith('USDC')) {
        quote = 'USDT';
      } else if (targetSymbol.endsWith('EUR')) {
        quote = 'EUR';
      } else if (targetSymbol.endsWith('USD')) {
        quote = 'USD';
      } else {
        quote = 'USDT'; // fallback
      }

      // TOP symbols by quote currency (updated 2025 with memecoins)
      final Map<String, List<String>> _topVolumeSymbolsByQuote = {
        'USDT': [
          'BTCUSDT', 'ETHUSDT', 'BNBUSDT', 'SOLUSDT', 'XRPUSDT',
          'DOGEUSDT', 'ADAUSDT', 'AVAXUSDT', 'TRXUSDT', 'SHIBUSDT',
          'WLFIUSDT', 'TRUMPUSDT', 'PEPEUSDT', 'BONKUSDT'  // 2025 trending memecoins
        ],
        'EUR': ['BTCEUR', 'ETHEUR', 'BNBEUR', 'SOLEUR', 'XRPEUR', 'DOGEEUR', 'ADAEUR'],
        'USD': ['BTCUSD', 'ETHUSD', 'BNBUSD', 'SOLUSD'],
      };

      final symbols = comparisonSymbols ?? _topVolumeSymbolsByQuote[quote] ?? _topVolumeSymbolsByQuote['USDT']!;

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
      debugPrint('📊 Volume percentile for $targetSymbol: ${(percentile * 100).toStringAsFixed(1)}% (volume: ${targetVolume.toStringAsFixed(0)} units)');

      return percentile;
    } catch (e) {
      debugPrint('❌ BinanceService: Failed to calculate volume percentile: $e');
      // Return median (0.5) on error - no boost or penalty
      return 0.5;
    }
  }

  /// Try multiple symbols until one works (useful for tokens with alt tickers like 1000TRUMPUSDT)
  @override
  @override
  Future<Map<String, double>> fetchTicker24hWithFallback(List<String> symbols) async {
    for (final String s in symbols) {
      try {
        return await fetchTicker24h(s);
      } catch (_) {}
    }
    throw Exception('No working symbol among: ${symbols.join(', ')}');
  }

  /// Try multiple symbols until one works for klines/candles (useful for handling USD/USDT/EUR pairs)
  @override
  Future<List<Candle>> fetchKlinesWithFallback(List<String> symbols, String interval, {int limit = 60}) async {
    for (final String s in symbols) {
      try {
        return await fetchKlines(s, interval, limit: limit);
      } catch (_) {
        // Try next symbol in list
      }
    }
    throw Exception('No working symbol among: ${symbols.join(', ')} for interval $interval');
  }

  /// Build ML features with symbol fallback (e.g., BTCUSD -> try BTCUSDT/BTCEUR/BTCUSDC)
  Future<List<List<double>>> getFeaturesForModelWithFallback(String symbol, {String interval = '1h'}) async {
    final result = await getFeaturesWithATRFallback(symbol, interval: interval);
    return result.features;
  }

  /// Build ML features + ATR with symbol fallback (for Phase 3 volatility-based weights)
  Future<FeaturesWithATR> getFeaturesWithATRFallback(String symbol, {String interval = '1h'}) async {
    final String upper = symbol.toUpperCase();
    final RegExp suffix = RegExp(r'(USDT|USDC|EUR|USD)$');
    String base = upper;
    String? quote;
    final match = suffix.firstMatch(upper);
    if (match != null) {
      quote = match.group(1);
      base = upper.substring(0, match.start);
    }

    final List<String> candidates = <String>[
      if (quote != null) '$base$quote',
      '${base}USDT',
      '${base}EUR',
      '${base}USDC',
    ];

    String resolved = candidates.first;
    for (final s in candidates) {
      try {
        // Probe minimal klines request to verify symbol validity
        await fetchKlines(s, interval, limit: 1);
        resolved = s;
        break;
      } catch (_) {
        // try next candidate
      }
    }

    // Fetch candles to calculate ATR before feature engineering
    int limit;
    switch (interval) {
      case '15m':
        limit = 1000;
        break;
      case '4h':
        limit = 1000;
        break;
      case '1d':
        limit = 1000;
        break;
      case '1w':
        limit = 1000;
        break;
      default:
        limit = 1000;
    }

    final candles = await fetchKlines(resolved, interval, limit: limit);

    // IMPORTANT: Log latest candle timestamp to prove data is FRESH
    if (candles.isNotEmpty) {
      final latestCandle = candles.last;
      final now = DateTime.now();
      final candleAge = now.difference(latestCandle.closeTime);
      final currencySymbol = _getCurrencySymbol(resolved);
      debugPrint('📅 Latest candle: ${latestCandle.closeTime} (${candleAge.inMinutes}min ago) - DATA IS FRESH!');
      debugPrint('   Close: $currencySymbol${latestCandle.close.toStringAsFixed(2)}, Volume: ${latestCandle.volume.toStringAsFixed(2)}');
    }

    // Calculate ATR from raw candles
    final candlesForATR = candles.map((c) => [
      c.openTime.millisecondsSinceEpoch.toDouble(),
      c.open,
      c.high,
      c.low,
      c.close,
      c.volume,
    ]).toList();
    
    final atr = _calculateATR(candlesForATR, period: 14);
    
    // Build features
    final fullBuilder = FullFeatureBuilder();
    final features = fullBuilder.buildFeatures(candles: candles);

    // Extract current price from latest candle
    final currentPrice = candles.isNotEmpty ? candles.last.close : 0.0;

    return FeaturesWithATR(
      features: features,
      atr: atr,
      currentPrice: currentPrice,
    );
  }

  /// Calculate ATR (Average True Range) from candles
  static double _calculateATR(List<List<double>> candles, {int period = 14}) {
    if (candles.length < period + 1) {
      debugPrint('⚠️  Insufficient candles for ATR (need ${period + 1}, got ${candles.length})');
      return 0.02; // Default 2% volatility
    }

    final trueRanges = <double>[];
    for (int i = 1; i < candles.length; i++) {
      final high = candles[i][2];
      final low = candles[i][3];
      final prevClose = candles[i - 1][4];
      final tr = _max3(high - low, (high - prevClose).abs(), (low - prevClose).abs());
      trueRanges.add(tr);
    }

    if (trueRanges.length < period) {
      return 0.02;
    }

    final lastN = trueRanges.sublist(trueRanges.length - period);
    final atrValue = lastN.reduce((a, b) => a + b) / period;
    final avgPrice = candles.map((c) => c[4]).reduce((a, b) => a + b) / candles.length;
    return avgPrice > 0 ? atrValue / avgPrice : 0.02;
  }

  static double _max3(double a, double b, double c) {
    return a > b ? (a > c ? a : c) : (b > c ? b : c);
  }

  static Candle _parseKlineArray(List<dynamic> arr) {
    // Binance kline fields:
    // 0 Open time (ms), 1 Open, 2 High, 3 Low, 4 Close, 5 Volume,
    // 6 Close time (ms), ... others not used
    final DateTime openTime = DateTime.fromMillisecondsSinceEpoch(arr[0] as int, isUtc: true).toLocal();
    final DateTime closeTime = DateTime.fromMillisecondsSinceEpoch(arr[6] as int, isUtc: true).toLocal();
    return Candle(
      openTime: openTime,
      open: double.parse(arr[1] as String),
      high: double.parse(arr[2] as String),
      low: double.parse(arr[3] as String),
      close: double.parse(arr[4] as String),
      volume: double.parse(arr[5] as String),
      closeTime: closeTime,
    );
  }

  /// Convenience method to fetch last 1 year of daily candles.
  Future<List<Candle>> fetchLastYearDaily(String symbol) async {
    // final DateTime end = DateTime.now().toUtc(); // Unused - commented out
    // final DateTime start = DateTime(end.year - 1, end.month, end.day).toUtc(); // Unused - commented out
    return fetchDailyKlines(symbol, limit: 1000);
  }

  /// Fetch ML features in the exact Python MTF order (base interval + aligned timeframes + one-hot symbol)
  /// Returns List<List<double>> with shape 60x34
  ///
  /// interval: '15m', '1h', or '4h' - determines the base timeframe
  Future<List<List<double>>> getFeaturesForModel(String symbol, {String interval = '1h'}) async {
    try {
      // Fetch data based on selected interval
      // MTF structure: base timeframe + lower timeframe + higher timeframe
      List<Candle> baseData;

      if (interval == '15m') {
        // Base: 15m, Low: 5m, High: 1h - MAXIM 1000 from Binance
        baseData = await fetchCustomKlines(symbol, '15m', limit: 1000);
      } else if (interval == '4h') {
        // Base: 4h, Low: 1h, High: 1d - MAXIM 1000 from Binance
        baseData = await fetchCustomKlines(symbol, '4h', limit: 1000);
      } else if (interval == '1d') {
        // Base: 1d (daily), Low: 4h, High: 1w - MAXIM 1000 from Binance
        baseData = await fetchCustomKlines(symbol, '1d', limit: 1000);
      } else if (interval == '1w') {
        // Base: 1w (weekly), Low: 1d, High: 1M - MAXIM 1000 from Binance
        baseData = await fetchCustomKlines(symbol, '1w', limit: 1000);
      } else {
        // Default: Base: 1h, Low: 15m, High: 4h - MAXIM 1000 from Binance
        baseData = await fetchCustomKlines(symbol, '1h', limit: 1000);
      }

      if (baseData.length < 120) {
        throw Exception('Insufficient $interval candles: got ${baseData.length}, need >=120 (for SMA100 + 60 sequence)');
      }

      debugPrint('🔧 BinanceService: Building 76 features from ${baseData.length} candles');
      final fullBuilder = FullFeatureBuilder();
      final features = fullBuilder.buildFeatures(candles: baseData);
      debugPrint('✅ BinanceService: Full features ${features.length}x${features.isNotEmpty ? features.first.length : 0} [@$interval]');
      return features;
    } catch (e) {
      debugPrint('❌ BinanceService: Error getting features → $e');
      rethrow;
    }
  }

  /// Feature extraction with structured error reporting
  Future<FeatureResult> getFeaturesForModelResult(String symbol, {String interval = '1h'}) async {
    try {
      List<Candle> baseData;
      if (interval == '15m') {
        baseData = await fetchCustomKlines(symbol, '15m', limit: 1000);
      } else if (interval == '4h') {
        baseData = await fetchCustomKlines(symbol, '4h', limit: 1000);
      } else if (interval == '1d') {
        baseData = await fetchCustomKlines(symbol, '1d', limit: 1000);
      } else if (interval == '1w') {
        baseData = await fetchCustomKlines(symbol, '1w', limit: 1000);
      } else {
        baseData = await fetchCustomKlines(symbol, '1h', limit: 1000);
      }

      if (baseData.length < 120) {
        debugPrint('❌ BinanceService: insufficient_data for $symbol @$interval need=120 got=${baseData.length}');
        return FeatureResult.error('insufficient_data', need: 120, got: baseData.length);
      }

      debugPrint('🔧 BinanceService: Building 76 features from ${baseData.length} candles');
      final fullBuilder = FullFeatureBuilder();
      final features = fullBuilder.buildFeatures(candles: baseData);
      debugPrint('✅ BinanceService: Full features ${features.length}x${features.isNotEmpty ? features.first.length.toString() : '0'} [@$interval]');
      return FeatureResult.ok(features);
    } catch (e) {
      debugPrint('❌ BinanceService: feature build error → $e');
      return FeatureResult.error('error');
    }
  }
}


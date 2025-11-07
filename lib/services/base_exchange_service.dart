import '../models/candle.dart';

/// Base interface for all exchange services (Binance, Coinbase, Kraken, etc.)
/// This ensures consistent API across all exchanges
abstract class BaseExchangeService {
  /// Exchange name identifier
  String get exchangeName;

  /// Check if API credentials are configured
  bool get hasCredentials;

  /// Get API key (if any)
  String? get apiKey;

  /// Get API secret (if any)
  String? get apiSecret;

  // ===================================
  // Credentials Management
  // ===================================

  /// Load saved API credentials from secure storage
  Future<void> loadCredentials();

  /// Save API credentials to secure storage
  Future<void> saveCredentials(String apiKey, String apiSecret);

  /// Clear saved credentials
  Future<void> clearCredentials();

  /// Test connection with provided credentials
  Future<bool> testConnection();

  // ===================================
  // Account & Portfolio
  // ===================================

  /// Get account balances for all assets
  /// Returns: Map<Asset, Amount> (e.g., {'BTC': 0.5, 'EUR': 1000.0})
  Future<Map<String, double>> getAccountBalances();

  // ===================================
  // Market Data
  // ===================================

  /// Fetch historical candlestick data (OHLCV)
  /// @param symbol - Trading pair (e.g., 'BTCEUR', 'ETHUSDT')
  /// @param interval - Time interval (e.g., '1h', '4h', '1d')
  /// @param limit - Number of candles to fetch
  /// @param endTime - Optional end time (milliseconds since epoch)
  Future<List<Candle>> fetchKlines(
    String symbol,
    String interval, {
    int limit = 500,
    int? endTime,
  });

  /// Fetch 24h ticker data
  /// Returns: {'lastPrice': 50000.0, 'priceChangePercent': 2.5}
  Future<Map<String, double>> fetchTicker24h(String symbol);

  /// Fetch 24h ticker with fallback symbols
  /// Tries multiple symbols until one succeeds
  Future<Map<String, double>> fetchTicker24hWithFallback(List<String> symbols);

  /// Get exchange info for a specific symbol or all symbols
  Future<Map<String, dynamic>> getExchangeInfo({String? symbol});

  // ===================================
  // Time Synchronization
  // ===================================

  /// Synchronize local time with exchange server
  /// Important for signed requests to avoid "timestamp out of window" errors
  Future<void> syncServerTime();

  /// Get current timestamp adjusted for server time offset
  Future<int> getSynchronizedTimestamp();
}

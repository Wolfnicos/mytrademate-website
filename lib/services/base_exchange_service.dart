import '../models/candle.dart';
import '../models/features_with_atr.dart';

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

  /// Fetch klines with fallback symbols
  /// Tries multiple symbols until one succeeds
  Future<List<Candle>> fetchKlinesWithFallback(
    List<String> symbols,
    String interval, {
    int limit = 60,
  });

  /// Fetch 24h ticker data
  /// Returns: {'lastPrice': 50000.0, 'priceChangePercent': 2.5}
  Future<Map<String, double>> fetchTicker24h(String symbol);

  /// Fetch 24h ticker with fallback symbols
  /// Tries multiple symbols until one succeeds
  Future<Map<String, double>> fetchTicker24hWithFallback(List<String> symbols);

  /// Get exchange info for a specific symbol or all symbols
  Future<Map<String, dynamic>> getExchangeInfo({String? symbol});

  /// Get volume percentile for a symbol (0.0 to 1.0)
  /// Used by ML service for volume-aware predictions
  /// @param symbol - Trading pair (e.g., 'BTCEUR', 'ETHUSDT')
  /// @param comparisonSymbols - Optional list of symbols to compare against (defaults to top coins by quote currency)
  /// @returns Volume percentile (0.0 = lowest, 1.0 = highest)
  Future<double> getVolumePercentile(String symbol, {List<String>? comparisonSymbols});

  /// Build trading pair symbol in exchange-specific format
  /// @param base - Base currency (e.g., 'BTC', 'ETH')
  /// @param quote - Quote currency (e.g., 'EUR', 'USDT')
  /// @returns Trading pair in exchange format:
  ///   - Binance: 'BTCEUR'
  ///   - Coinbase: 'BTC-EUR'
  ///   - Kraken: 'XBTEUR' (BTC → XBT)
  String buildTradingPair(String base, String quote);

  /// Get preferred quote currency for a base coin
  /// Each exchange supports different trading pairs - this method returns
  /// the best available quote currency for the given base coin.
  /// @param base - Base currency (e.g., 'BTC', 'ETH', 'TRUMP')
  /// @param desiredQuote - Desired quote currency (e.g., 'EUR', 'USD')
  /// @returns Best available quote currency (falls back to USDT/USD if desired not available)
  /// Example:
  ///   - Binance.getPreferredQuote('BTC', 'EUR') → 'EUR' (BTCEUR exists)
  ///   - Binance.getPreferredQuote('TRUMP', 'EUR') → 'USDT' (TRUMPEUR doesn't exist)
  ///   - Coinbase.getPreferredQuote('BTC', 'EUR') → 'EUR' (BTC-EUR exists)
  String getPreferredQuote(String base, String desiredQuote);

  // ===================================
  // Time Synchronization
  // ===================================

  /// Synchronize local time with exchange server
  /// Important for signed requests to avoid "timestamp out of window" errors
  Future<void> syncServerTime();

  /// Get current timestamp adjusted for server time offset
  Future<int> getSynchronizedTimestamp();

  // ===================================
  // ML Feature Engineering
  // ===================================

  /// Build ML features + ATR with symbol fallback
  /// Used by CryptoMLService for predictions
  /// @param symbol - Trading pair (e.g., 'BTCEUR', 'ETHUSDT')
  /// @param interval - Time interval (e.g., '5m', '1h', '1d')
  /// @returns FeaturesWithATR containing:
  ///   - features: 60 timesteps × 76 features for ML model
  ///   - atr: Average True Range (volatility metric, 0.0-1.0)
  ///   - currentPrice: Latest candle close price
  Future<FeaturesWithATR> getFeaturesWithATRFallback(String symbol, {String interval = '1h'});
}

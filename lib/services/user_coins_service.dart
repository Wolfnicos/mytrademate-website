import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import 'base_exchange_service.dart';

/// User Coins Service - Manages user's cryptocurrency list
///
/// Logic:
/// - If user has Exchange API connected → use coins from portfolio
/// - If user has NO API → use TOP 10 popular coins (default)
class UserCoinsService with ChangeNotifier {
  static final UserCoinsService _instance = UserCoinsService._internal();
  factory UserCoinsService() => _instance;
  UserCoinsService._internal();

  static const String _coinsKey = 'user_coins';
  static const String _sourceKey = 'coins_source'; // 'api' or 'default'

  // TOP 10 popular cryptocurrencies (default when no API connected)
  static const List<String> defaultCoins = [
    'BTC',  // Bitcoin
    'ETH',  // Ethereum
    'BNB',  // Binance Coin
    'SOL',  // Solana
    'ADA',  // Cardano
    'XRP',  // Ripple
    'DOGE', // Dogecoin
    'DOT',  // Polkadot
    'POL',  // Polygon (formerly MATIC)
    'LTC',  // Litecoin
  ];

  List<String> _cachedCoins = [];
  String _cachedSource = 'default';

  /// Get user's coin list
  /// Returns coins from API if connected, otherwise TOP 10 default
  Future<List<String>> getUserCoins() async {
    // Return cached if available
    if (_cachedCoins.isNotEmpty) {
      return _cachedCoins;
    }

    final prefs = await SharedPreferences.getInstance();

    // Load from SharedPreferences
    final savedCoins = prefs.getStringList(_coinsKey);
    final source = prefs.getString(_sourceKey) ?? 'default';

    if (savedCoins != null && savedCoins.isNotEmpty) {
      _cachedCoins = savedCoins;
      _cachedSource = source;
      debugPrint('✅ Loaded ${savedCoins.length} coins from $source');
      return savedCoins;
    }

    // No saved coins → return default
    _cachedCoins = List.from(defaultCoins);
    _cachedSource = 'default';
    await _saveCoins(_cachedCoins, 'default');
    debugPrint('✅ Using default TOP 10 coins');
    return _cachedCoins;
  }

  /// Update coins from Exchange portfolio (Binance, Coinbase, Kraken)
  /// Extracts unique coins from user's portfolio balances
  Future<void> updateCoinsFromExchange(BaseExchangeService exchange) async {
    debugPrint('🔄 UserCoinsService: updateCoinsFromExchange(${exchange.exchangeName}) called');
    try {
      // Check if API is connected
      final hasCredentials = exchange.hasCredentials;

      debugPrint('🔍 API credentials check for ${exchange.exchangeName}: hasCredentials=$hasCredentials');

      if (!hasCredentials) {
        debugPrint('⚠️  No ${exchange.exchangeName} API connected - using default coins');
        await setDefaultCoins();
        return;
      }

      debugPrint('🔄 Fetching account balances from ${exchange.exchangeName}...');
      // Fetch account balances
      final balances = await exchange.getAccountBalances();
      debugPrint('✅ Fetched ${balances.length} balances from ${exchange.exchangeName}');

      if (balances.isEmpty) {
        debugPrint('⚠️  Empty balances - using default coins');
        await setDefaultCoins();
        return;
      }

      // Extract unique coins (assets with balance > 0)
      // Exclude fiat currencies and stablecoins (quote currencies only)
      final excludedCurrencies = {'EUR', 'USD', 'GBP', 'JPY', 'CHF', 'AUD', 'CAD', 'USDT', 'USDC', 'BUSD', 'DAI', 'TUSD', 'USDP'};

      final coins = balances.entries
          .where((entry) => entry.value > 0) // Only coins with positive balance
          .map((entry) => entry.key) // Get coin symbol
          .where((coin) => !excludedCurrencies.contains(coin.toUpperCase())) // Exclude fiat & stablecoins
          .toList();

      if (coins.isEmpty) {
        debugPrint('⚠️  No valid coins in portfolio - using default coins');
        await setDefaultCoins();
        return;
      }

      // Save coins from API
      await _saveCoins(coins, 'api');
      _cachedCoins = coins;
      _cachedSource = 'api';

      debugPrint('✅ Updated coins from ${exchange.exchangeName} API: ${coins.length} coins');
      debugPrint('   Coins: ${coins.join(", ")}');

      // Notify listeners that coins changed
      notifyListeners();
    } catch (e) {
      debugPrint('❌ Error updating coins from ${exchange.exchangeName}: $e');
      // Fallback to default on error
      await setDefaultCoins();
    }
  }

  /// Update coins from Binance portfolio (deprecated - use updateCoinsFromExchange)
  @Deprecated('Use updateCoinsFromExchange(exchange) instead')
  Future<void> updateCoinsFromBinance() async {
    // This method is kept for backward compatibility
    // It will be removed in a future version
    debugPrint('⚠️  updateCoinsFromBinance is deprecated, please use updateCoinsFromExchange');
  }

  /// Set default TOP 10 coins
  Future<void> setDefaultCoins() async {
    await _saveCoins(List.from(defaultCoins), 'default');
    _cachedCoins = List.from(defaultCoins);
    _cachedSource = 'default';
    debugPrint('✅ Reset to default TOP 10 coins');

    // Notify listeners that coins changed
    notifyListeners();
  }

  /// Manually set custom coin list
  Future<void> setCustomCoins(List<String> coins) async {
    if (coins.isEmpty) {
      debugPrint('⚠️  Cannot set empty coin list');
      return;
    }

    await _saveCoins(coins, 'custom');
    _cachedCoins = coins;
    _cachedSource = 'custom';
    debugPrint('✅ Set custom coins: ${coins.join(", ")}');

    // Notify listeners that coins changed
    notifyListeners();
  }

  /// Add a coin to the list
  Future<void> addCoin(String coin) async {
    final coins = await getUserCoins();
    if (coins.contains(coin)) {
      debugPrint('⚠️  Coin $coin already in list');
      return;
    }

    coins.add(coin);
    await _saveCoins(coins, _cachedSource);
    _cachedCoins = coins;
    debugPrint('✅ Added coin: $coin');

    // Notify listeners that coins changed
    notifyListeners();
  }

  /// Remove a coin from the list
  Future<void> removeCoin(String coin) async {
    final coins = await getUserCoins();
    if (!coins.contains(coin)) {
      debugPrint('⚠️  Coin $coin not in list');
      return;
    }

    coins.remove(coin);

    // Don't allow empty list
    if (coins.isEmpty) {
      debugPrint('⚠️  Cannot remove last coin - reverting to defaults');
      await setDefaultCoins();
      return;
    }

    await _saveCoins(coins, _cachedSource);
    _cachedCoins = coins;
    debugPrint('✅ Removed coin: $coin');

    // Notify listeners that coins changed
    notifyListeners();
  }

  /// Get coins source ('api', 'default', or 'custom')
  Future<String> getCoinsSource() async {
    if (_cachedSource.isNotEmpty) {
      return _cachedSource;
    }

    final prefs = await SharedPreferences.getInstance();
    _cachedSource = prefs.getString(_sourceKey) ?? 'default';
    return _cachedSource;
  }

  /// Check if coins are from Binance API
  Future<bool> isUsingApiCoins() async {
    final source = await getCoinsSource();
    return source == 'api';
  }

  /// Clear cache (force reload on next getUserCoins call)
  void clearCache() {
    _cachedCoins = [];
    _cachedSource = '';
    debugPrint('🗑️  Coins cache cleared');
  }

  /// Save coins to SharedPreferences
  Future<void> _saveCoins(List<String> coins, String source) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_coinsKey, coins);
    await prefs.setString(_sourceKey, source);
  }

  /// Initialize service (call on app startup)
  Future<void> initialize() async {
    await getUserCoins(); // Load coins into cache
    debugPrint('✅ UserCoinsService initialized');
  }
}

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

  // TOP 10 cryptocurrencies by market cap (Nov 2025)
  // Default list shown when user has NO API connected
  // When user connects API, their actual portfolio coins (TRUMP, WLFI, etc.) will be shown
  // Fiat currencies that should NEVER be treated as tradeable coins
  static const List<String> fiatCurrencies = [
    'EUR', 'USD', 'GBP', 'JPY', 'CHF', 'CAD', 'AUD', 'NZD',
    'USDT', 'USDC', 'BUSD', // Stablecoins are also not tradeable assets
  ];

  static const List<String> defaultCoins = [
    'BTC',   // #1 Bitcoin - largest by market cap
    'ETH',   // #2 Ethereum - smart contracts
    'BNB',   // #4 Binance Coin - exchange token
    'SOL',   // #5 Solana - fast L1
    'XRP',   // #6 Ripple - payments
    'ADA',   // #8 Cardano - proof-of-stake
    'DOGE',  // #9 Dogecoin - meme coin
    'AVAX',  // #10 Avalanche - DeFi platform
    'DOT',   // Polkadot - interoperability
    'LINK',  // Chainlink - oracle network
    'MATIC', // Polygon - Ethereum L2
    'UNI',   // Uniswap - DEX token
  ];

  /// Validate that a coin is not a fiat currency
  static bool isValidCoin(String coin) {
    return !fiatCurrencies.contains(coin.toUpperCase());
  }

  /// Filter out fiat currencies from a list of coins
  static List<String> filterValidCoins(List<String> coins) {
    final filtered = coins.where((coin) => isValidCoin(coin)).toList();
    final removed = coins.where((coin) => !isValidCoin(coin)).toList();
    if (removed.isNotEmpty) {
      debugPrint('⚠️  Removed fiat currencies from coins: $removed');
    }
    return filtered;
  }

  // Exchange-specific coin exclusions
  // Some exchanges don't support certain coins due to business conflicts or listing policies
  static const Map<String, List<String>> excludedCoinsPerExchange = {
    'Coinbase': ['BNB', 'MATIC', 'UNI'],  // BNB (competitor), MATIC/UNI delisted Nov 2025
    'Kraken': ['BNB'],                     // BNB not available (competitor)
  };

  /// Get default coins filtered for specific exchange
  /// Excludes coins that are not available on the given exchange
  static List<String> getDefaultCoinsForExchange(String exchangeName) {
    final excluded = excludedCoinsPerExchange[exchangeName] ?? [];
    return defaultCoins.where((coin) => !excluded.contains(coin)).toList();
  }

  List<String> _cachedCoins = [];
  String _cachedSource = 'default';
  String? _cachedExchangeName; // Remember last exchange for filtering defaults

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
      // MIGRATION: Remove delisted/unavailable coins (ANC, UST, LUNA)
      // These coins are no longer tradeable on major exchanges
      const delistedCoins = ['ANC', 'UST', 'LUNA'];
      final hasDelistedCoins = savedCoins.any((coin) => delistedCoins.contains(coin));

      if (hasDelistedCoins && source == 'default') {
        debugPrint('🔄 Migrating: Removing delisted coins from saved list...');
        // Remove delisted coins from saved list
        final cleanedCoins = savedCoins.where((coin) => !delistedCoins.contains(coin)).toList();

        // If cleaned list is empty or too small, reset to defaults
        if (cleanedCoins.length < 3) {
          debugPrint('   Too few valid coins remaining, resetting to defaults');
          _cachedCoins = _cachedExchangeName != null
              ? getDefaultCoinsForExchange(_cachedExchangeName!)
              : List<String>.from(defaultCoins);
          await _saveCoins(_cachedCoins, 'default');
          _cachedSource = 'default';
          debugPrint('✅ Migrated to ${_cachedCoins.length} default coins: ${_cachedCoins.join(", ")}');
          return _cachedCoins;
        }

        // Save cleaned list
        _cachedCoins = cleanedCoins;
        await _saveCoins(_cachedCoins, source);
        _cachedSource = source;
        final removed = savedCoins.where((coin) => delistedCoins.contains(coin)).toList();
        debugPrint('✅ Removed delisted coins: ${removed.join(", ")}');
        debugPrint('   New coin list (${_cachedCoins.length}): ${_cachedCoins.join(", ")}');
        return _cachedCoins;
      }

      _cachedCoins = savedCoins;
      _cachedSource = source;
      debugPrint('✅ Loaded ${savedCoins.length} coins from $source');
      return savedCoins;
    }

    // No saved coins → return default
    _cachedCoins = List<String>.from(defaultCoins);
    _cachedSource = 'default';
    await _saveCoins(_cachedCoins, 'default');
    debugPrint('✅ Using default TOP 10 coins');
    return _cachedCoins;
  }

  /// Update coins from Exchange portfolio (Binance, Coinbase, Kraken)
  /// Extracts unique coins from user's portfolio balances
  Future<void> updateCoinsFromExchange(BaseExchangeService exchange) async {
    debugPrint('🔄 UserCoinsService: updateCoinsFromExchange(${exchange.exchangeName}) called');

    // Remember exchange name for future default coin filtering
    _cachedExchangeName = exchange.exchangeName;

    try {
      // Check if API is connected
      final hasCredentials = exchange.hasCredentials;

      debugPrint('🔍 API credentials check for ${exchange.exchangeName}: hasCredentials=$hasCredentials');

      if (!hasCredentials) {
        debugPrint('⚠️  No ${exchange.exchangeName} API connected - using default coins');
        await setDefaultCoins(exchangeName: exchange.exchangeName);
        return;
      }

      debugPrint('🔄 Fetching account balances from ${exchange.exchangeName}...');
      // Fetch account balances
      final balances = await exchange.getAccountBalances();
      debugPrint('✅ Fetched ${balances.length} balances from ${exchange.exchangeName}');

      if (balances.isEmpty) {
        debugPrint('⚠️  Empty balances - using default coins');
        await setDefaultCoins(exchangeName: exchange.exchangeName);
        return;
      }

      // Extract unique coins (assets with balance > 0)
      // Minimum balance threshold to filter out dust (very small amounts)
      // Strategy: Filter by relative balance size
      // Keep only coins that have meaningful balances (not tiny dust amounts)
      const minBalanceThreshold = 0.001; // Ignore balances < 0.001 (increased from 0.00001)

      final coins = balances.entries
          .where((entry) => entry.value > minBalanceThreshold) // Filter out dust balances
          .map((entry) => entry.key) // Get coin symbol
          .where((coin) => isValidCoin(coin)) // Exclude fiat currencies (EUR, USD, USDT, etc.)
          .toList();

      if (coins.isEmpty) {
        debugPrint('⚠️  No valid coins in portfolio - using default coins');
        await setDefaultCoins(exchangeName: exchange.exchangeName);
        return;
      }

      // Save coins from API
      await _saveCoins(coins, 'api');
      _cachedCoins = coins;
      _cachedSource = 'api';

      debugPrint('✅ Updated coins from ${exchange.exchangeName} API: ${coins.length} coins');
      debugPrint('   Coins: ${coins.join(", ")}');

      // Debug: Show balances for each detected coin
      for (final coin in coins) {
        final balance = balances[coin] ?? 0.0;
        debugPrint('   - $coin: $balance');
      }

      // Notify listeners that coins changed
      notifyListeners();
    } catch (e) {
      debugPrint('❌ Error updating coins from ${exchange.exchangeName}: $e');
      // Fallback to default on error
      await setDefaultCoins(exchangeName: exchange.exchangeName);
    }
  }

  /// Update coins from Binance portfolio (deprecated - use updateCoinsFromExchange)
  @Deprecated('Use updateCoinsFromExchange(exchange) instead')
  Future<void> updateCoinsFromBinance() async {
    // This method is kept for backward compatibility
    // It will be removed in a future version
    debugPrint('⚠️  updateCoinsFromBinance is deprecated, please use updateCoinsFromExchange');
  }

  /// Set default coins (filtered by exchange compatibility)
  ///
  /// If [exchangeName] is provided, returns coins filtered for that exchange
  /// (e.g., excludes BNB for Coinbase). If no exchange is provided but one was
  /// previously cached, uses the cached exchange. Otherwise returns all default coins.
  Future<void> setDefaultCoins({String? exchangeName}) async {
    // Use provided exchange, or fall back to cached exchange, or use all defaults
    final effectiveExchange = exchangeName ?? _cachedExchangeName;

    final coinsToUse = effectiveExchange != null
        ? getDefaultCoinsForExchange(effectiveExchange)
        : List<String>.from(defaultCoins);

    await _saveCoins(coinsToUse, 'default');
    _cachedCoins = coinsToUse;
    _cachedSource = 'default';

    if (effectiveExchange != null) {
      debugPrint('✅ Reset to default coins for $effectiveExchange (${coinsToUse.length} coins)');
      debugPrint('   Coins: ${coinsToUse.join(", ")}');
    } else {
      debugPrint('✅ Reset to default TOP 10 coins');
    }

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
    _cachedExchangeName = null;
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

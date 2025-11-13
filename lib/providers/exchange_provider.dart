import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/base_exchange_service.dart';
import '../services/binance_service.dart';
import '../services/coinbase_service.dart';
import '../services/kraken_service.dart';
import '../services/user_coins_service.dart';
import '../ml/crypto_ml_service.dart';

/// Provider for managing the currently selected exchange
/// Handles switching between Binance, Coinbase, and Kraken
class ExchangeProvider with ChangeNotifier {
  static const String _storageKey = 'selected_exchange';

  // Available exchanges
  String _selectedExchange = 'Binance'; // Default to Binance
  final Map<String, BaseExchangeService> _exchanges = {
    'Binance': BinanceService(),
    'Coinbase': CoinbaseService(),
    'Kraken': KrakenService(),
  };

  /// Get currently selected exchange name
  String get selectedExchange => _selectedExchange;

  /// Get list of available exchange names
  List<String> get availableExchanges => _exchanges.keys.toList();

  /// Get the current exchange service instance
  BaseExchangeService get currentExchange => _exchanges[_selectedExchange]!;

  /// Initialize provider and load saved exchange preference
  Future<void> initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_storageKey);

      if (saved != null && _exchanges.containsKey(saved)) {
        _selectedExchange = saved;
        debugPrint('[ExchangeProvider] Loaded saved exchange: $_selectedExchange');
      } else {
        debugPrint('[ExchangeProvider] Using default exchange: $_selectedExchange');
      }

      // Load credentials for current exchange
      await currentExchange.loadCredentials();
      notifyListeners();
    } catch (e) {
      debugPrint('[ExchangeProvider] Error initializing: $e');
    }
  }

  /// Switch to a different exchange
  Future<void> setExchange(String exchangeName) async {
    if (!_exchanges.containsKey(exchangeName)) {
      debugPrint('[ExchangeProvider] Invalid exchange: $exchangeName');
      return;
    }

    if (_selectedExchange == exchangeName) {
      debugPrint('[ExchangeProvider] Already using $exchangeName');
      return;
    }

    try {
      _selectedExchange = exchangeName;

      // Save preference
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_storageKey, exchangeName);

      // Load credentials for new exchange
      await currentExchange.loadCredentials();

      // Update coins based on new exchange:
      // - If exchange has API keys → load coins from portfolio
      // - If NO API keys → use default TOP 10 coins
      await UserCoinsService().updateCoinsFromExchange(currentExchange);

      // Clear ML volume cache to avoid using cached data from previous exchange
      CryptoMLService.clearVolumeCache();

      debugPrint('[ExchangeProvider] Switched to: $_selectedExchange');
      notifyListeners();
    } catch (e) {
      debugPrint('[ExchangeProvider] Error switching exchange: $e');
    }
  }

  /// Get exchange service by name (useful for settings UI)
  BaseExchangeService getExchange(String name) {
    return _exchanges[name] ?? _exchanges['Binance']!;
  }

  /// Check if current exchange has credentials configured
  bool get hasCredentials => currentExchange.hasCredentials;

  /// Get exchange icon emoji
  String getExchangeIcon(String exchangeName) {
    switch (exchangeName) {
      case 'Binance':
        return '🟡';
      case 'Coinbase':
        return '🔵';
      case 'Kraken':
        return '🟣';
      default:
        return '📊';
    }
  }

  /// Get exchange description
  String getExchangeDescription(String exchangeName) {
    switch (exchangeName) {
      case 'Binance':
        return 'World\'s largest crypto exchange';
      case 'Coinbase':
        return 'Popular in US & Europe, beginner-friendly';
      case 'Kraken':
        return 'Trusted European exchange since 2011';
      default:
        return '';
    }
  }

  /// Force refresh all listening widgets (e.g., after quote currency change)
  void refresh() {
    notifyListeners();
  }
}

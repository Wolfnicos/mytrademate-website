import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

/// Global app settings (quote currency etc.) with persistence and notifications.
class AppSettingsService extends ChangeNotifier {
  static final AppSettingsService _instance = AppSettingsService._internal();
  factory AppSettingsService() => _instance;
  AppSettingsService._internal();

  // ✅ PRODUCTION MODE: Beta testing completed
  static const bool IS_BETA_BUILD = false;

  // Allowed quote currencies (BUSD, USDC excluded - limited exchange support)
  static const List<String> allowedQuoteCurrencies = ['USDT', 'EUR', 'USD'];
  static const String defaultQuoteCurrency = 'USDT';

  static const String _kQuoteKey = 'quote_currency';
  static const String _kPermissionKey = 'api_permission_level';
  static const String _kTrialStartKey = 'trial_start_timestamp';
  static const String _kTrialDeclinedKey = 'trial_declined';

  String _quote = defaultQuoteCurrency;
  String _permissionLevel = 'read'; // 'read' | 'trading'
  DateTime? _trialStartTime;
  bool _trialDeclined = false;
  bool _loaded = false;

  String get quoteCurrency => _quote;
  String get permissionLevel => _permissionLevel;
  bool get isTradingEnabled => _permissionLevel.toLowerCase() == 'trading';

  /// Check if user is in 48-hour free trial period
  /// In BETA mode (IS_BETA_BUILD = true), always returns true for unlimited access
  bool get isInTrial {
    // BETA MODE: Grant unlimited premium access for testing
    if (IS_BETA_BUILD) return true;

    // PRODUCTION MODE: Check actual trial period
    if (_trialStartTime == null || _trialDeclined) return false;
    final now = DateTime.now();
    final diff = now.difference(_trialStartTime!);
    return diff.inHours < 48; // 48 hours = 2 days
  }

  /// Check if user needs to see trial activation dialog
  /// Returns true if trial not started and not declined
  bool get shouldShowTrialDialog {
    return _trialStartTime == null && !_trialDeclined;
  }

  /// Get remaining trial time in hours (null if not in trial)
  /// In BETA mode, returns null to hide trial banner
  int? get trialHoursRemaining {
    // BETA MODE: Don't show trial countdown
    if (IS_BETA_BUILD) return null;

    // PRODUCTION MODE: Calculate remaining hours
    if (!isInTrial) return null;
    final now = DateTime.now();
    final diff = now.difference(_trialStartTime!);
    return 48 - diff.inHours;
  }

  /// Activate trial (called when user accepts in dialog)
  Future<void> activateTrial() async {
    _trialStartTime = DateTime.now();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kTrialStartKey, _trialStartTime!.millisecondsSinceEpoch);

    // Track trial activation in RevenueCat (for analytics and debugging)
    try {
      final trialEnd = _trialStartTime!.add(const Duration(hours: 48));
      await Purchases.setAttributes({
        'trial_activated': 'true',
        'trial_start': _trialStartTime!.toIso8601String(),
        'trial_end': trialEnd.toIso8601String(),
        'trial_duration_hours': '48',
      });
      debugPrint('✅ RevenueCat: Trial tracking attributes set (48h from $_trialStartTime)');
    } catch (e) {
      debugPrint('⚠️ RevenueCat: Failed to set trial attributes: $e');
      // Continue anyway - local trial still works
    }

    debugPrint('🎁 FREE TRIAL: Activated 48-hour trial at $_trialStartTime');
    notifyListeners();
  }

  /// Decline trial (called when user clicks "Maybe Later")
  Future<void> declineTrial() async {
    _trialDeclined = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kTrialDeclinedKey, true);

    // Track trial decline in RevenueCat (for conversion analytics)
    try {
      await Purchases.setAttributes({
        'trial_activated': 'false',
        'trial_declined': 'true',
        'trial_declined_at': DateTime.now().toIso8601String(),
      });
      debugPrint('✅ RevenueCat: Trial decline tracked');
    } catch (e) {
      debugPrint('⚠️ RevenueCat: Failed to track trial decline: $e');
      // Continue anyway
    }

    debugPrint('⏭️ FREE TRIAL: User declined trial');
    notifyListeners();
  }

  /// DEBUG ONLY: Reset trial state (for testing)
  Future<void> resetTrialForTesting() async {
    _trialStartTime = null;
    _trialDeclined = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kTrialStartKey);
    await prefs.remove(_kTrialDeclinedKey);
    debugPrint('🔄 DEBUG: Trial state reset - dialog will show again');
    notifyListeners();
  }

  Future<void> load() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    final savedQuote = prefs.getString(_kQuoteKey) ?? defaultQuoteCurrency;

    // Validate and migrate quote currency
    if (!allowedQuoteCurrencies.contains(savedQuote.toUpperCase())) {
      // Invalid quote (BUSD, BUSC, typos, etc.) - migrate to default
      debugPrint('🔄 AUTO-MIGRATION: Invalid quote "$savedQuote" → $defaultQuoteCurrency');
      if (savedQuote.toUpperCase() == 'BUSD') {
        debugPrint('   (BUSD was deprecated by Binance in 2024)');
      }
      _quote = defaultQuoteCurrency;
      await prefs.setString(_kQuoteKey, defaultQuoteCurrency);
    } else {
      _quote = savedQuote.toUpperCase();
    }

    _permissionLevel = prefs.getString(_kPermissionKey) ?? 'read';

    // Load trial state
    final timestamp = prefs.getInt(_kTrialStartKey);
    _trialDeclined = prefs.getBool(_kTrialDeclinedKey) ?? false;

    if (timestamp != null) {
      _trialStartTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
      if (isInTrial) {
        debugPrint('🎁 FREE TRIAL: ${trialHoursRemaining}h remaining (started $_trialStartTime)');
      } else {
        debugPrint('⏰ FREE TRIAL: Expired (started $_trialStartTime)');
      }
    } else if (_trialDeclined) {
      debugPrint('ℹ️ FREE TRIAL: User previously declined trial');
    } else {
      debugPrint('ℹ️ FREE TRIAL: New user - will show activation dialog');
    }

    _loaded = true;
    notifyListeners();
  }

  Future<void> setQuoteCurrency(String quote) async {
    final normalized = quote.toUpperCase();

    // Validate quote currency
    if (!allowedQuoteCurrencies.contains(normalized)) {
      debugPrint('⚠️ Invalid quote currency "$quote" - using $defaultQuoteCurrency');
      _quote = defaultQuoteCurrency;
    } else {
      _quote = normalized;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kQuoteKey, _quote);
    notifyListeners();
  }

  Future<void> setPermissionLevel(String level) async {
    final normalized = (level.toLowerCase() == 'trading') ? 'trading' : 'read';
    _permissionLevel = normalized;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPermissionKey, _permissionLevel);
    notifyListeners();
  }

  static String currencyPrefix(String quote) {
    switch (quote.toUpperCase()) {
      case 'EUR':
        return '€';
      case 'USD':
      case 'USDT':
      case 'USDC':
      default:
        return r'$';
    }
  }
}



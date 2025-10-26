import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Global app settings (quote currency etc.) with persistence and notifications.
class AppSettingsService extends ChangeNotifier {
  static final AppSettingsService _instance = AppSettingsService._internal();
  factory AppSettingsService() => _instance;
  AppSettingsService._internal();

  static const String _kQuoteKey = 'quote_currency';
  static const String _kPermissionKey = 'api_permission_level';
  static const String _kTrialStartKey = 'trial_start_timestamp';
  static const String _kTrialDeclinedKey = 'trial_declined';

  String _quote = 'USDT';
  String _permissionLevel = 'read'; // 'read' | 'trading'
  DateTime? _trialStartTime;
  bool _trialDeclined = false;
  bool _loaded = false;

  String get quoteCurrency => _quote;
  String get permissionLevel => _permissionLevel;
  bool get isTradingEnabled => _permissionLevel.toLowerCase() == 'trading';

  /// Check if user is in 48-hour free trial period
  bool get isInTrial {
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
  int? get trialHoursRemaining {
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
    debugPrint('🎁 FREE TRIAL: Activated 48-hour trial at $_trialStartTime');
    notifyListeners();
  }

  /// Decline trial (called when user clicks "Maybe Later")
  Future<void> declineTrial() async {
    _trialDeclined = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kTrialDeclinedKey, true);
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
    _quote = prefs.getString(_kQuoteKey) ?? 'USDT';
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
    _quote = quote.toUpperCase();
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



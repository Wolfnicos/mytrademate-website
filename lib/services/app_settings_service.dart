import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Global app settings (quote currency etc.) with persistence and notifications.
class AppSettingsService extends ChangeNotifier {
  static final AppSettingsService _instance = AppSettingsService._internal();
  factory AppSettingsService() => _instance;
  AppSettingsService._internal();

  static const String _kQuoteKey = 'quote_currency';
  static const String _kPermissionKey = 'api_permission_level';
  static const String _kFirstLaunchKey = 'first_launch_timestamp';

  String _quote = 'USDT';
  String _permissionLevel = 'read'; // 'read' | 'trading'
  DateTime? _firstLaunchTime;
  bool _loaded = false;

  String get quoteCurrency => _quote;
  String get permissionLevel => _permissionLevel;
  bool get isTradingEnabled => _permissionLevel.toLowerCase() == 'trading';

  /// Check if user is in 48-hour free trial period
  bool get isInTrial {
    if (_firstLaunchTime == null) return false;
    final now = DateTime.now();
    final diff = now.difference(_firstLaunchTime!);
    return diff.inHours < 48; // 48 hours = 2 days
  }

  /// Get remaining trial time in hours (null if not in trial)
  int? get trialHoursRemaining {
    if (!isInTrial) return null;
    final now = DateTime.now();
    final diff = now.difference(_firstLaunchTime!);
    return 48 - diff.inHours;
  }

  Future<void> load() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    _quote = prefs.getString(_kQuoteKey) ?? 'USDT';
    _permissionLevel = prefs.getString(_kPermissionKey) ?? 'read';

    // Load or set first launch time
    final timestamp = prefs.getInt(_kFirstLaunchKey);
    if (timestamp == null) {
      // First time user - start trial
      _firstLaunchTime = DateTime.now();
      await prefs.setInt(_kFirstLaunchKey, _firstLaunchTime!.millisecondsSinceEpoch);
      debugPrint('🎁 FREE TRIAL: Started 48-hour trial at $_firstLaunchTime');
    } else {
      _firstLaunchTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
      if (isInTrial) {
        debugPrint('🎁 FREE TRIAL: ${trialHoursRemaining}h remaining (started $_firstLaunchTime)');
      } else {
        debugPrint('⏰ FREE TRIAL: Expired (started $_firstLaunchTime)');
      }
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



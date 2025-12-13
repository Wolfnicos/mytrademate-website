import 'dart:async';
import 'package:flutter/foundation.dart';

/// Rate Limiter Service - Prevents API throttling and bans
///
/// Exchange Rate Limits:
/// - Binance: 1200 requests/minute (20/second) → 50ms minimum delay
/// - Coinbase: 10 requests/second → 100ms minimum delay
/// - Kraken: 15-20 requests/second (tier-based) → 60ms minimum delay
///
/// Usage:
/// ```dart
/// await RateLimiterService().throttle('Binance');
/// final response = await http.get(...);
/// ```
class RateLimiterService {
  static final RateLimiterService _instance = RateLimiterService._internal();
  factory RateLimiterService() => _instance;
  RateLimiterService._internal();

  // Track last request timestamp per exchange
  final Map<String, DateTime> _lastRequestTime = {};

  // Minimum delay between requests (in milliseconds)
  static const Map<String, int> _minDelayMs = {
    'Binance': 50,    // 20 requests/second max
    'Coinbase': 100,  // 10 requests/second max
    'Kraken': 60,     // ~16 requests/second max (conservative)
  };

  /// Throttle requests to stay within rate limits
  ///
  /// Call this BEFORE making any API request to the exchange.
  /// It will automatically delay if needed to respect rate limits.
  ///
  /// Example:
  /// ```dart
  /// await RateLimiterService().throttle('Binance');
  /// final data = await _apiCall();
  /// ```
  Future<void> throttle(String exchangeName) async {
    final minDelay = _minDelayMs[exchangeName];
    if (minDelay == null) {
      debugPrint('⚠️  RateLimiter: Unknown exchange "$exchangeName", no rate limiting applied');
      return;
    }

    final lastRequest = _lastRequestTime[exchangeName];
    if (lastRequest == null) {
      // First request for this exchange
      _lastRequestTime[exchangeName] = DateTime.now();
      return;
    }

    // Calculate time since last request
    final timeSinceLastRequest = DateTime.now().difference(lastRequest).inMilliseconds;
    final requiredDelay = minDelay - timeSinceLastRequest;

    if (requiredDelay > 0) {
      // Need to wait before making next request
      debugPrint('⏱️  RateLimiter: Delaying $exchangeName request by ${requiredDelay}ms (rate limit protection)');
      await Future.delayed(Duration(milliseconds: requiredDelay));
    }

    // Update last request time
    _lastRequestTime[exchangeName] = DateTime.now();
  }

  /// Reset rate limiter for specific exchange (useful for testing)
  void reset(String exchangeName) {
    _lastRequestTime.remove(exchangeName);
    debugPrint('🔄 RateLimiter: Reset for $exchangeName');
  }

  /// Reset all rate limiters
  void resetAll() {
    _lastRequestTime.clear();
    debugPrint('🔄 RateLimiter: Reset all exchanges');
  }

  /// Get current delay configuration (for debugging)
  Map<String, int> getDelayConfig() {
    return Map.from(_minDelayMs);
  }

  /// Get time since last request (for debugging)
  int? getTimeSinceLastRequest(String exchangeName) {
    final lastRequest = _lastRequestTime[exchangeName];
    if (lastRequest == null) return null;
    return DateTime.now().difference(lastRequest).inMilliseconds;
  }
}

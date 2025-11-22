import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

/// Global Market Context Service
///
/// Fetches global crypto market data from CoinGecko API (free, no auth)
/// Provides total market cap, volume, and trend direction
class GlobalMarketContextService {
  static final GlobalMarketContextService _instance = GlobalMarketContextService._internal();
  factory GlobalMarketContextService() => _instance;
  GlobalMarketContextService._internal();

  static const String _apiUrl = 'https://api.coingecko.com/api/v3/global';

  // Cache (10 minute TTL - global data changes slowly)
  GlobalMarketData? _cachedData;
  DateTime? _cacheTimestamp;
  static const Duration _cacheTTL = Duration(minutes: 10);

  /// Get global market data
  Future<GlobalMarketData> getGlobalData() async {
    // Check cache
    if (_cachedData != null && _cacheTimestamp != null) {
      final age = DateTime.now().difference(_cacheTimestamp!);
      if (age < _cacheTTL) {
        debugPrint('[GlobalMarket] ⚡ Using CACHED data (age: ${age.inMinutes}m)');
        return _cachedData!;
      }
    }

    try {
      final uri = Uri.parse(_apiUrl);
      final response = await http.get(uri).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        debugPrint('[GlobalMarket] ⚠ API error: ${response.statusCode}');
        return _getFallbackData();
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final data = json['data'] as Map<String, dynamic>;

      final totalMarketCap = (data['total_market_cap'] as Map<String, dynamic>)['usd'] as num;
      final marketCapChange24h = data['market_cap_change_percentage_24h_usd'] as num;
      final totalVolume = (data['total_volume'] as Map<String, dynamic>)['usd'] as num;
      final btcDominance = data['market_cap_percentage'] != null
          ? ((data['market_cap_percentage'] as Map<String, dynamic>)['btc'] as num?) ?? 0.0
          : 0.0;

      // Determine trend based on 24h change
      String trend;
      if (marketCapChange24h > 3) {
        trend = 'bullish'; // Strong upward trend
      } else if (marketCapChange24h > 0) {
        trend = 'neutral'; // Slight upward trend
      } else if (marketCapChange24h > -3) {
        trend = 'neutral'; // Slight downward trend
      } else {
        trend = 'bearish'; // Strong downward trend
      }

      final globalData = GlobalMarketData(
        totalMarketCap: totalMarketCap.toDouble(),
        marketCapChange24h: marketCapChange24h.toDouble(),
        totalVolume: totalVolume.toDouble(),
        btcDominance: btcDominance.toDouble(),
        trend: trend,
      );

      // Cache result
      _cachedData = globalData;
      _cacheTimestamp = DateTime.now();

      debugPrint('[GlobalMarket] 🌍 Market Cap: \$${(totalMarketCap / 1e12).toStringAsFixed(2)}T (${marketCapChange24h >= 0 ? '+' : ''}${marketCapChange24h.toStringAsFixed(2)}%)');
      debugPrint('[GlobalMarket] 📊 Trend: $trend | BTC Dominance: ${btcDominance.toStringAsFixed(1)}%');

      return globalData;
    } catch (e) {
      debugPrint('[GlobalMarket] ❌ Error fetching data: $e');
      return _getFallbackData();
    }
  }

  /// Fallback to neutral data on error
  GlobalMarketData _getFallbackData() {
    return const GlobalMarketData(
      totalMarketCap: 3000000000000, // $3T fallback
      marketCapChange24h: 0.0,
      totalVolume: 100000000000, // $100B fallback
      btcDominance: 50.0,
      trend: 'neutral',
    );
  }

  /// Clear cache (useful for testing)
  void clearCache() {
    _cachedData = null;
    _cacheTimestamp = null;
  }
}

/// Global Market Data model
class GlobalMarketData {
  final double totalMarketCap; // Total crypto market cap in USD
  final double marketCapChange24h; // % change in 24h
  final double totalVolume; // Total 24h volume in USD
  final double btcDominance; // Bitcoin dominance %
  final String trend; // "bullish", "neutral", "bearish"

  const GlobalMarketData({
    required this.totalMarketCap,
    required this.marketCapChange24h,
    required this.totalVolume,
    required this.btcDominance,
    required this.trend,
  });

  /// Format market cap as human-readable string
  String get formattedMarketCap {
    if (totalMarketCap >= 1e12) {
      return '\$${(totalMarketCap / 1e12).toStringAsFixed(2)}T';
    } else if (totalMarketCap >= 1e9) {
      return '\$${(totalMarketCap / 1e9).toStringAsFixed(2)}B';
    } else {
      return '\$${(totalMarketCap / 1e6).toStringAsFixed(2)}M';
    }
  }

  /// Get emoji for trend
  String get trendEmoji {
    switch (trend) {
      case 'bullish':
        return '🚀';
      case 'bearish':
        return '📉';
      default:
        return '➡️';
    }
  }
}

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

/// Fear & Greed Index Service
///
/// Fetches crypto Fear & Greed Index from Alternative.me API (free, no auth)
/// Index range: 0-100
///   0-24: Extreme Fear
///  25-49: Fear
///  50-74: Greed
/// 75-100: Extreme Greed
class FearGreedService {
  static final FearGreedService _instance = FearGreedService._internal();
  factory FearGreedService() => _instance;
  FearGreedService._internal();

  static const String _apiUrl = 'https://api.alternative.me/fng/';

  // Cache (5 minute TTL - Fear & Greed updates daily)
  FearGreedIndex? _cachedIndex;
  DateTime? _cacheTimestamp;
  static const Duration _cacheTTL = Duration(minutes: 5);

  /// Get current Fear & Greed Index
  Future<FearGreedIndex> getCurrentIndex() async {
    // Check cache
    if (_cachedIndex != null && _cacheTimestamp != null) {
      final age = DateTime.now().difference(_cacheTimestamp!);
      if (age < _cacheTTL) {
        debugPrint('[FearGreed] ⚡ Using CACHED index (age: ${age.inMinutes}m)');
        return _cachedIndex!;
      }
    }

    try {
      final uri = Uri.parse(_apiUrl);
      final response = await http.get(uri).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        debugPrint('[FearGreed] ⚠ API error: ${response.statusCode}');
        return _getFallbackIndex();
      }

      final data = json.decode(response.body) as Map<String, dynamic>;
      final indexData = (data['data'] as List).first as Map<String, dynamic>;

      final value = int.parse(indexData['value'] as String);
      final classification = indexData['value_classification'] as String;
      final timestamp = DateTime.fromMillisecondsSinceEpoch(
        int.parse(indexData['timestamp'] as String) * 1000,
      );

      final index = FearGreedIndex(
        value: value,
        classification: classification,
        timestamp: timestamp,
      );

      // Cache result
      _cachedIndex = index;
      _cacheTimestamp = DateTime.now();

      debugPrint('[FearGreed] 📊 Index: $value/100 ($classification)');
      return index;
    } catch (e) {
      debugPrint('[FearGreed] ❌ Error fetching index: $e');
      return _getFallbackIndex();
    }
  }

  /// Fallback to neutral index on error
  FearGreedIndex _getFallbackIndex() {
    return const FearGreedIndex(
      value: 50,
      classification: 'Neutral',
      timestamp: null,
    );
  }

  /// Clear cache (useful for testing)
  void clearCache() {
    _cachedIndex = null;
    _cacheTimestamp = null;
  }
}

/// Fear & Greed Index data model
class FearGreedIndex {
  final int value; // 0-100
  final String classification; // "Extreme Fear", "Fear", "Neutral", "Greed", "Extreme Greed"
  final DateTime? timestamp;

  const FearGreedIndex({
    required this.value,
    required this.classification,
    this.timestamp,
  });

  /// Get emoji for current index
  String get emoji {
    if (value < 25) return '😱'; // Extreme Fear
    if (value < 50) return '😰'; // Fear
    if (value < 75) return '😊'; // Greed
    return '🤑'; // Extreme Greed
  }

  /// Get color for current index
  String get colorHex {
    if (value < 25) return '#FF3B30'; // Red (Extreme Fear)
    if (value < 50) return '#FF9500'; // Orange (Fear)
    if (value < 75) return '#00C853'; // Green (Greed)
    return '#4CAF50'; // Bright Green (Extreme Greed)
  }
}

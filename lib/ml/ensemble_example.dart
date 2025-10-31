import 'dart:convert';
import 'package:flutter/material.dart';
import '../services/binance_service.dart';
import 'crypto_ml_service.dart';
import 'ensemble_weights_v2.dart';
import 'confidence_threshold_filter.dart';

/// Example usage of Enhanced Ensemble Strategy with Dynamic Weights + Threshold Filtering
///
/// This demonstrates predictions for TRUMP@1h and ADA@1h using:
/// - ATR-based volatility adjustments (Phase 1)
/// - Performance-based weight boosts (Phase 1)
/// - Optimized general model penalties: 0.6x → 0.8x (Phase 1)
/// - Confidence threshold filtering: 60% for BUY/SELL, 65% for TRUMP/WLFI (Phase 2)
class EnsembleExample {
  final BinanceService _binanceService = BinanceService();
  final CryptoMLService _mlService = CryptoMLService();

  /// Get prediction for TRUMP at 1h timeframe
  /// Returns JSON: { "action": "BUY", "confidence": 0.68, "explanation": "...", "risk": "moderate" }
  Future<Map<String, dynamic>> getPredictionTRUMP() async {
    return _getPredictionForCoin('TRUMPEUR', 'TRUMP', '1h');
  }

  /// Get prediction for BTC at 1h timeframe
  /// Returns JSON: { "action": "HOLD", "confidence": 0.45, "explanation": "...", "risk": "low" }
  Future<Map<String, dynamic>> getPredictionBTC() async {
    return _getPredictionForCoin('BTCEUR', 'BTC', '1h');
  }

  /// Internal method to get prediction for any coin
  Future<Map<String, dynamic>> _getPredictionForCoin(
    String symbol,
    String coin,
    String timeframe,
  ) async {
    try {
      print('\n🚀 Getting prediction for $coin @ $timeframe...\n');

      // STEP 1: Fetch OHLCV data from Binance for ATR calculation
      print('📊 Fetching OHLCV data from Binance...');
      // Try multiple quote variants so examples work regardless of local quote settings
      final candidates = _buildSymbolCandidates(symbol);
      final candleObjects = await _binanceService.fetchKlinesWithFallback(
        candidates,
        _mapTimeframeToInterval(timeframe),
        limit: 100, // Get 100 candles for ATR calculation (need 14+)
      );

      if (candleObjects.isEmpty) {
        return {
          'action': 'ERROR',
          'confidence': 0.0,
          'explanation': 'No candle data available from Binance',
          'risk': 'unknown',
        };
      }

      print('✅ Fetched ${candleObjects.length} candles');

      // Convert Candle objects to List<List<double>> format for ATR calculation
      // Format: [timestamp, open, high, low, close, volume]
      final candles = candleObjects.map((c) => [
        c.openTime.millisecondsSinceEpoch.toDouble(),
        c.open,
        c.high,
        c.low,
        c.close,
        c.volume,
      ]).toList();

      // STEP 2: Calculate ATR (Average True Range) for volatility
      print('📈 Calculating ATR (volatility indicator)...');
      final atr = EnsembleWeightsV2.calculateATR(
        candles: candles,
        period: 14,
      );
      print('✅ ATR: ${(atr * 100).toStringAsFixed(2)}% '
          '${atr > 0.025 ? "(HIGH volatility)" : "(LOW volatility)"}');

      // STEP 3: Get ML prediction using enhanced ensemble
      print('🔮 Running ML ensemble prediction...');
      final prediction = await _mlService.getPrediction(
        coin: coin,
        symbol: symbol, // Required parameter
        timeframe: timeframe,
      );

      print('✅ Raw prediction: ${prediction.action} '
          '(confidence: ${(prediction.confidence * 100).toStringAsFixed(1)}%)');

      // STEP 4: Apply confidence threshold filtering (Phase 2)
      // Initialize threshold filter
      await ConfidenceThresholdFilter.initialize();

      // Apply threshold filter
      final filterResult = ConfidenceThresholdFilter.filter(
        action: prediction.action,
        confidence: prediction.confidence,
        coin: coin,
      );

      if (filterResult.belowThreshold) {
        print('⚠️  ${filterResult.reason}');
        print('   → Overriding to NO ACTION');
      } else {
        print('✅ Passed threshold: ${(filterResult.threshold * 100).toStringAsFixed(0)}%');
      }

      final finalAction = filterResult.action;

      // STEP 5: Calculate risk indicator
      // (In production, this would use std dev of model probabilities)
      final riskLevel = _calculateRiskLevel(atr, prediction.confidence);

      // STEP 6: Generate detailed explanation
      // Note: models_used count depends on ensemble implementation
      // For now, we estimate based on isEnsemble flag
      final modelsUsed = prediction.isEnsemble ? 3 : 1;
      final explanation = _generateExplanation(
        coin: coin,
        timeframe: timeframe,
        action: finalAction,
        confidence: prediction.confidence,
        atr: atr,
        modelsUsed: modelsUsed,
      );

      // STEP 7: Build JSON response
      final result = {
        'coin': coin,
        'timeframe': timeframe,
        'action': finalAction,
        'confidence': double.parse(prediction.confidence.toStringAsFixed(4)),
        'explanation': explanation,
        'risk': riskLevel,
        'atr': double.parse((atr * 100).toStringAsFixed(2)),
        'models_used': modelsUsed,
        'timestamp': DateTime.now().toIso8601String(),
        // Phase 2: Threshold filtering metadata
        'threshold_filter': {
          'below_threshold': filterResult.belowThreshold,
          'threshold_used': filterResult.threshold,
          'raw_action': prediction.action,
          if (filterResult.reason != null) 'filter_reason': filterResult.reason,
        },
      };

      print('\n✅ FINAL RESULT:');
      print(JsonEncoder.withIndent('  ').convert(result));

      return result;
    } catch (e, stackTrace) {
      print('❌ Error getting prediction for $coin: $e');
      print(stackTrace);
      return {
        'action': 'ERROR',
        'confidence': 0.0,
        'explanation': 'Error: $e',
        'risk': 'unknown',
      };
    }
  }

  /// Build candidate symbols: keep original + fallback to common quotes
  List<String> _buildSymbolCandidates(String symbol) {
    final upper = symbol.toUpperCase();
    final re = RegExp(r'(USDT|USDC|EUR|USD)$');
    String base = upper;
    String? quote;
    final m = re.firstMatch(upper);
    if (m != null) {
      quote = m.group(1);
      base = upper.substring(0, m.start);
    }
    return <String>[
      if (quote != null) '$base$quote' else upper,
      '${base}USDT',
      '${base}EUR',
      '${base}USDC',
      '${base}USD',
    ];
  }

  /// Map timeframe to Binance interval format
  String _mapTimeframeToInterval(String timeframe) {
    const mapping = {
      '5m': '5m',
      '15m': '15m',
      '1h': '1h',
      '4h': '4h',
      '1d': '1d',
      '7d': '1w',
    };
    return mapping[timeframe] ?? '1h';
  }

  /// Calculate risk level based on ATR and confidence
  String _calculateRiskLevel(double atr, double confidence) {
    // High volatility (ATR > 4%) = high risk
    if (atr > 0.04) return 'high';

    // Low confidence (< 55%) = moderate-high risk
    if (confidence < 0.55) return 'moderate-high';

    // Moderate volatility (2-4%) = moderate risk
    if (atr > 0.02) return 'moderate';

    // Low volatility + high confidence = low risk
    return 'low';
  }

  /// Generate detailed explanation of prediction
  String _generateExplanation({
    required String coin,
    required String timeframe,
    required String action,
    required double confidence,
    required double atr,
    required int modelsUsed,
  }) {
    final buffer = StringBuffer();

    buffer.writeln('Prediction for $coin @ $timeframe:');
    buffer.writeln('');
    buffer.writeln('Action: $action (${(confidence * 100).toStringAsFixed(1)}% confidence)');
    buffer.writeln('');
    buffer.writeln('Factors:');
    buffer.writeln('• $modelsUsed models used in ensemble');
    buffer.writeln('• Market volatility (ATR): ${(atr * 100).toStringAsFixed(2)}%');

    if (atr > 0.025) {
      buffer.writeln('  → High volatility detected → Short-term models weighted +20%');
    } else {
      buffer.writeln('  → Normal volatility → Standard timeframe weighting');
    }

    buffer.writeln('• Model performance tracking: Last 50 predictions analyzed');
    buffer.writeln('• General models penalty: Reduced to 0.8x (was 0.6x)');

    if (action == 'NO ACTION') {
      buffer.writeln('');
      buffer.writeln('⚠️  Confidence below 60% threshold → Signal filtered out');
    }

    return buffer.toString();
  }

  /// Run both examples and compare (TRUMP + BTC)
  Future<void> runBothExamples() async {
    print('\n${'=' * 80}');
    print('ENHANCED ENSEMBLE STRATEGY - EXAMPLE USAGE');
    print('=' * 80);

    final trumpResult = await getPredictionTRUMP();
    print('\n${'-' * 80}');
    final btcResult = await getPredictionBTC();

    print('\n${'=' * 80}');
    print('COMPARISON:');
    print('=' * 80);
    print('TRUMP: ${trumpResult['action']} (${trumpResult['confidence']}), '
        'Risk: ${trumpResult['risk']}, ATR: ${trumpResult['atr']}%');
    print('BTC:   ${btcResult['action']} (${btcResult['confidence']}), '
        'Risk: ${btcResult['risk']}, ATR: ${btcResult['atr']}%');
  }
}

/// Example usage in a Flutter widget
class EnsembleExampleScreen extends StatefulWidget {
  const EnsembleExampleScreen({super.key});

  @override
  State<EnsembleExampleScreen> createState() => _EnsembleExampleScreenState();
}

class _EnsembleExampleScreenState extends State<EnsembleExampleScreen> {
  final EnsembleExample _example = EnsembleExample();
  Map<String, dynamic>? _trumpResult;
  Map<String, dynamic>? _btcResult;
  bool _loading = false;

  Future<void> _runExamples() async {
    setState(() => _loading = true);

    final trump = await _example.getPredictionTRUMP();
    final btc = await _example.getPredictionBTC();

    setState(() {
      _trumpResult = trump;
      _btcResult = btc;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ensemble Strategy Example')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ElevatedButton(
              onPressed: _loading ? null : _runExamples,
              child: _loading
                  ? const CircularProgressIndicator()
                  : const Text('Run TRUMP + ADA Examples'),
            ),
            const SizedBox(height: 24),
            if (_trumpResult != null) _buildResultCard('TRUMP', _trumpResult!),
            if (_btcResult != null) _buildResultCard('BTC', _btcResult!),
          ],
        ),
      ),
    );
  }

  Widget _buildResultCard(String coin, Map<String, dynamic> result) {
    final action = result['action'] as String;
    final confidence = result['confidence'] as double;
    final risk = result['risk'] as String;
    final atr = result['atr'] as double;

    Color actionColor = Colors.grey;
    if (action == 'BUY') actionColor = Colors.green;
    if (action == 'SELL') actionColor = Colors.red;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  coin,
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: actionColor.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    action,
                    style: TextStyle(
                      color: actionColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text('Confidence: ${(confidence * 100).toStringAsFixed(1)}%'),
            Text('Risk: $risk'),
            Text('ATR: ${atr.toStringAsFixed(2)}%'),
            const SizedBox(height: 8),
            Text(
              result['explanation'] as String,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}

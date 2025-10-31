import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../ml/ml_accuracy_monitor.dart';
import '../ml/crypto_ml_service.dart';

/// ML Debug Screen
///
/// Test all coins and timeframes to verify model accuracy
class MLDebugScreen extends StatefulWidget {
  const MLDebugScreen({super.key});

  @override
  State<MLDebugScreen> createState() => _MLDebugScreenState();
}

class _MLDebugScreenState extends State<MLDebugScreen> {
  final _monitor = MLAccuracyMonitor();
  final _mlService = CryptoMLService();

  String _selectedCoin = 'BTC';
  String _selectedTimeframe = '5m';

  final List<String> _coins = ['BTC', 'ETH', 'BNB', 'SOL', 'WLFI', 'TRUMP'];
  final List<String> _timeframes = ['5m', '15m', '1h', '4h', '1d'];

  bool _isLoading = false;
  String? _predictionResult;
  AccuracyStats? _stats;
  Map<String, dynamic>? _summary;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    setState(() => _isLoading = true);
    try {
      final stats = await _monitor.getStats(coin: _selectedCoin, timeframe: _selectedTimeframe);
      final summary = await _monitor.getAccuracySummary();
      setState(() {
        _stats = stats;
        _summary = summary;
      });
    } catch (e) {
      debugPrint('Error loading stats: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _testPrediction() async {
    setState(() {
      _isLoading = true;
      _predictionResult = null;
    });

    try {
      final symbol = '${_selectedCoin}EUR'; // Use EUR pairs
      final prediction = await _mlService.getPrediction(
        coin: _selectedCoin.toLowerCase(),
        symbol: symbol,
        timeframe: _selectedTimeframe,
      );

      final result = StringBuffer();
      result.writeln('🎯 PREDICTION RESULT:');
      result.writeln('━━━━━━━━━━━━━━━━━━━━━━');
      result.writeln('Coin: $_selectedCoin');
      result.writeln('Timeframe: $_selectedTimeframe');
      result.writeln('Symbol: $symbol');
      result.writeln('');
      result.writeln('Action: ${prediction.action.toUpperCase()}');
      result.writeln('Confidence: ${(prediction.confidence * 100).toStringAsFixed(1)}%');
      result.writeln('');
      result.writeln('Probabilities:');
      prediction.probabilities.forEach((key, value) {
        result.writeln('  $key: ${(value * 100).toStringAsFixed(1)}%');
      });
      result.writeln('');
      result.writeln('Signal Strength: ${prediction.signalStrength.toStringAsFixed(1)}');
      result.writeln('Model Accuracy: ${(prediction.modelAccuracy * 100).toStringAsFixed(1)}%');
      if (prediction.atr != null) {
        result.writeln('ATR: ${(prediction.atr! * 100).toStringAsFixed(2)}%');
      }
      if (prediction.volumePercentile != null) {
        result.writeln('Volume Percentile: ${(prediction.volumePercentile! * 100).toStringAsFixed(1)}%');
      }

      setState(() => _predictionResult = result.toString());

      // Reload stats after prediction
      await _loadStats();

    } catch (e) {
      setState(() => _predictionResult = '❌ ERROR: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppTheme.background : Colors.grey[50],
      appBar: AppBar(
        title: const Text('ML Debug & Testing'),
        backgroundColor: isDark ? AppTheme.surface : Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadStats,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildTestSection(isDark),
                  const SizedBox(height: 24),
                  if (_predictionResult != null) _buildPredictionResult(isDark),
                  if (_predictionResult != null) const SizedBox(height: 24),
                  _buildStatsSection(isDark),
                  const SizedBox(height: 24),
                  _buildAccuracySummary(isDark),
                ],
              ),
            ),
    );
  }

  Widget _buildTestSection(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.surface : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? AppTheme.glassBorder : Colors.grey[300]!,
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '🧪 Test Prediction',
            style: AppTheme.headingMedium.copyWith(
              color: AppTheme.getTextPrimary(context),
            ),
          ),
          const SizedBox(height: 16),

          // Coin selector
          Text(
            'Coin',
            style: AppTheme.bodyMedium.copyWith(
              color: AppTheme.getTextSecondary(context),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: _coins.map((coin) {
              final isSelected = coin == _selectedCoin;
              return ChoiceChip(
                label: Text(coin),
                selected: isSelected,
                onSelected: (selected) {
                  setState(() => _selectedCoin = coin);
                  _loadStats();
                },
                selectedColor: AppTheme.primary,
                backgroundColor: isDark ? AppTheme.surface : Colors.grey[200],
              );
            }).toList(),
          ),

          const SizedBox(height: 16),

          // Timeframe selector
          Text(
            'Timeframe',
            style: AppTheme.bodyMedium.copyWith(
              color: AppTheme.getTextSecondary(context),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: _timeframes.map((tf) {
              final isSelected = tf == _selectedTimeframe;
              return ChoiceChip(
                label: Text(tf),
                selected: isSelected,
                onSelected: (selected) {
                  setState(() => _selectedTimeframe = tf);
                  _loadStats();
                },
                selectedColor: AppTheme.primary,
                backgroundColor: isDark ? AppTheme.surface : Colors.grey[200],
              );
            }).toList(),
          ),

          const SizedBox(height: 20),

          // Test button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _testPrediction,
              icon: const Icon(Icons.play_arrow),
              label: const Text('Run Prediction Test'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPredictionResult(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.surface : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? AppTheme.glassBorder : Colors.grey[300]!,
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.analytics, color: AppTheme.primary),
              const SizedBox(width: 8),
              Text(
                'Prediction Result',
                style: AppTheme.headingMedium.copyWith(
                  color: AppTheme.getTextPrimary(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? AppTheme.background : Colors.grey[100],
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              _predictionResult!,
              style: AppTheme.bodyMedium.copyWith(
                fontFamily: 'monospace',
                color: AppTheme.getTextPrimary(context),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsSection(bool isDark) {
    if (_stats == null) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.surface : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? AppTheme.glassBorder : Colors.grey[300]!,
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.show_chart, color: AppTheme.primary),
              const SizedBox(width: 8),
              Text(
                'Statistics: $_selectedCoin @ $_selectedTimeframe',
                style: AppTheme.headingMedium.copyWith(
                  color: AppTheme.getTextPrimary(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          _buildStatRow('Total Predictions', '${_stats!.totalPredictions}', isDark),
          _buildStatRow('Verified', '${_stats!.verifiedPredictions}', isDark),
          _buildStatRow('Correct', '${_stats!.correctPredictions}', isDark),
          _buildStatRow(
            'Accuracy',
            '${_stats!.accuracy.toStringAsFixed(1)}%',
            isDark,
            color: _stats!.accuracy >= 60
                ? AppTheme.buyGreen
                : _stats!.accuracy >= 50
                    ? AppTheme.holdYellow
                    : AppTheme.sellRed,
          ),
          _buildStatRow('Avg Confidence', '${(_stats!.avgConfidence * 100).toStringAsFixed(1)}%', isDark),
          _buildStatRow('Avg Price Change', '${_stats!.avgPriceChange.toStringAsFixed(2)}%', isDark),
          const Divider(height: 24),
          _buildStatRow('BUY predictions', '${_stats!.buyCount}', isDark, color: AppTheme.buyGreen),
          _buildStatRow('SELL predictions', '${_stats!.sellCount}', isDark, color: AppTheme.sellRed),
          _buildStatRow('HOLD predictions', '${_stats!.holdCount}', isDark, color: AppTheme.holdYellow),
        ],
      ),
    );
  }

  Widget _buildStatRow(String label, String value, bool isDark, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: AppTheme.bodyMedium.copyWith(
              color: AppTheme.getTextSecondary(context),
            ),
          ),
          Text(
            value,
            style: AppTheme.bodyMedium.copyWith(
              color: color ?? AppTheme.getTextPrimary(context),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAccuracySummary(bool isDark) {
    if (_summary == null || _summary!.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.surface : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? AppTheme.glassBorder : Colors.grey[300]!,
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.assessment, color: AppTheme.primary),
              const SizedBox(width: 8),
              Text(
                'Accuracy Summary (All Models)',
                style: AppTheme.headingMedium.copyWith(
                  color: AppTheme.getTextPrimary(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          ..._summary!.entries.map((coinEntry) {
            final coin = coinEntry.key;
            final timeframes = coinEntry.value as Map<String, dynamic>;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  coin,
                  style: AppTheme.bodyLarge.copyWith(
                    color: AppTheme.getTextPrimary(context),
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                ...timeframes.entries.map((tfEntry) {
                  final tf = tfEntry.key;
                  final data = tfEntry.value as Map<String, dynamic>;
                  final accuracy = data['accuracy'] as double;
                  final count = data['predictions'] as int;

                  return Padding(
                    padding: const EdgeInsets.only(left: 16, bottom: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          tf,
                          style: AppTheme.bodyMedium.copyWith(
                            color: AppTheme.getTextSecondary(context),
                          ),
                        ),
                        Text(
                          '${accuracy.toStringAsFixed(1)}% ($count predictions)',
                          style: AppTheme.bodyMedium.copyWith(
                            color: accuracy >= 60
                                ? AppTheme.buyGreen
                                : accuracy >= 50
                                    ? AppTheme.holdYellow
                                    : AppTheme.sellRed,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
                const SizedBox(height: 12),
              ],
            );
          }).toList(),
        ],
      ),
    );
  }
}

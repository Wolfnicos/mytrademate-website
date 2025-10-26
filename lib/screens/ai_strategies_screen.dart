import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

// Services
import '../services/app_settings_service.dart';
import '../services/binance_service.dart';

// ML
import '../ml/crypto_ml_service.dart';

// Theme & Widgets
import '../theme/app_theme.dart';
import '../widgets/glass_card.dart';
import '../widgets/risk_disclaimer.dart';
import '../widgets/upgrade_banner.dart';
import '../utils/responsive.dart';

// Providers
import '../providers/subscription_provider.dart';
import 'paywall_screen.dart';

class AiStrategiesScreen extends StatefulWidget {
  const AiStrategiesScreen({super.key});

  @override
  State<AiStrategiesScreen> createState() => _AiStrategiesScreenState();
}

class _AiStrategiesScreenState extends State<AiStrategiesScreen> {
  // AI Prediction State
  CryptoPrediction? _lastPrediction;
  bool _isRunningPrediction = false;
  String _predictionError = '';

  String _selectedSymbol = 'BTCUSDT';
  String _interval = '4h'; // Default to 4H (free tier)

  // Portfolio coins for dynamic dropdown
  List<String> _availableCoins = [];
  // bool _loadingCoins = true;

  @override
  void initState() {
    super.initState();
    final quote = AppSettingsService().quoteCurrency.toUpperCase();
    _selectedSymbol = 'BTC$quote';
    _loadAvailableCoins();
    // Auto-run first prediction
    Future.delayed(const Duration(milliseconds: 500), _runInference);
    // Listen to quote currency changes
    AppSettingsService().addListener(_onQuoteCurrencyChanged);
  }

  @override
  void dispose() {
    AppSettingsService().removeListener(_onQuoteCurrencyChanged);
    super.dispose();
  }

  void _onQuoteCurrencyChanged() async {
    // Update trading pair when quote currency changes
    final quote = AppSettingsService().quoteCurrency.toUpperCase();
    debugPrint('AI Strategies: Quote currency changed to $quote, updating pairs...');

    // Extract base asset from current pair (e.g., BTCUSDT -> BTC)
    String baseAsset = _selectedSymbol;
    for (final q in ['USDT', 'USDC', 'EUR', 'USD']) {
      baseAsset = baseAsset.replaceAll(q, '');
    }

    // Reload coins first to get the new list with updated quote
    await _loadAvailableCoins();

    // Then update selected symbol if it exists in the new list
    final newSymbol = '$baseAsset$quote';
    if (mounted) {
      setState(() {
        if (_availableCoins.contains(newSymbol)) {
          _selectedSymbol = newSymbol;
        } else if (_availableCoins.isNotEmpty) {
          // If the new symbol doesn't exist, use the first available
          _selectedSymbol = _availableCoins.first;
        }
      });
    }

    // Re-run prediction with new quote
    _runInference();
  }

  Future<void> _loadAvailableCoins() async {
    try {
      final binance = BinanceService();
      await binance.loadCredentials();
      final balances = await binance.getAccountBalances();
      final quote = AppSettingsService().quoteCurrency.toUpperCase();

      // Extract coins from portfolio (excluding quote currency and coins below $5)
      final Set<String> coins = {};
      for (final asset in balances.keys) {
        final upperAsset = asset.toUpperCase();
        if (upperAsset != quote && balances[asset]! > 0.0) {
          // Calculate value to filter out coins below $5
          try {
            final ticker = await binance.fetchTicker24hWithFallback([
              '$upperAsset$quote',
              '${upperAsset}USDT',
              '${upperAsset}EUR',
              '${upperAsset}USDC'
            ]);
            final price = ticker['lastPrice'] ?? 0.0;
            final value = balances[asset]! * price;
            if (value >= 5.0) {
              coins.add('$upperAsset$quote');
            }
          } catch (e) {
            // If price fetch fails, skip this coin
            debugPrint('AI Strategies: Could not get price for $upperAsset: $e');
          }
        }
      }

      // If no holdings, use default coins
      if (coins.isEmpty) {
        coins.addAll(['BTC', 'ETH', 'BNB', 'SOL', 'WLFI', 'TRUMP'].map((b) => '$b$quote'));
      }

      if (mounted) {
        setState(() {
          _availableCoins = coins.toList()..sort();
          // Ensure selected symbol is in the list
          if (!_availableCoins.contains(_selectedSymbol) && _availableCoins.isNotEmpty) {
            _selectedSymbol = _availableCoins.first;
          }
        });
      }
    } catch (e) {
      debugPrint('Error loading coins: $e');
      // Fall back to default coins
      final quote = AppSettingsService().quoteCurrency.toUpperCase();
      if (mounted) {
        setState(() {
          _availableCoins = ['BTC', 'ETH', 'BNB', 'SOL', 'WLFI', 'TRUMP'].map((b) => '$b$quote').toList();
          // Ensure selected symbol is in the list
          if (!_availableCoins.contains(_selectedSymbol) && _availableCoins.isNotEmpty) {
            _selectedSymbol = _availableCoins.first;
          }
        });
      }
    }
  }

  Future<void> _runInference() async {
    setState(() {
      _isRunningPrediction = true;
      _predictionError = '';
    });

    try {
      // Get coin from symbol (e.g., BTCUSDT -> BTC)
      final coin = _selectedSymbol.replaceAll(RegExp(r'(USDT|EUR|USDC)$'), '');

      debugPrint('🚀 AI Strategies: fetching CryptoML prediction for $coin @$_interval');

      // Fetch price data (60x76 features) + ATR from Binance with symbol fallback (USD -> USDT/EUR/USDC)
      final result = await BinanceService().getFeaturesWithATRFallback(_selectedSymbol, interval: _interval);

      // Use CryptoMLService multi-timeframe weighted ensemble
      final prediction = await CryptoMLService().getPrediction(
        coin: coin,
        priceData: result.features,
        timeframe: _interval,
        atr: result.atr, // Pass real ATR for Phase 3 volatility weights
      );

      // Debug-only: print final JSON-like summary for QA (no UI impact)
      // ignore: avoid_print
      print('JSON_AI_STRATEGIES: {"coin":"$coin","timeframe":"$_interval","action":"${prediction.action}","confidence":${prediction.confidence.toStringAsFixed(4)},"atr":${(result.atr * 100).toStringAsFixed(2)}}');

      debugPrint('🚀 CryptoML: ${prediction.action} (${(prediction.confidence * 100).toStringAsFixed(1)}%)');

      if (mounted) {
        setState(() {
          _lastPrediction = prediction;
          _isRunningPrediction = false;
        });
      }
    } catch (e) {
      debugPrint('❌ AI inference error: $e');
      if (mounted) {
        // Check if error is due to insufficient historical data
        String userFriendlyError = e.toString();
        if (userFriendlyError.contains('Insufficient') && userFriendlyError.contains('candles')) {
          // Extract coin name from symbol
          final coin = _selectedSymbol.replaceAll(RegExp(r'(USDT|EUR|USDC)$'), '');
          userFriendlyError = '⏰ $coin is a new cryptocurrency with limited history.\n\n'
              '📊 For $_interval predictions, we need at least 120 days of data.\n\n'
              '💡 Try a shorter timeframe (15m, 1h, or 4h) for newer coins.';
        }
        setState(() {
          _predictionError = userFriendlyError;
          _isRunningPrediction = false;
        });
      }
    }
  }

  List<String> _buildPairs() {
    if (_availableCoins.isEmpty) {
      // Fallback while loading
      final q = AppSettingsService().quoteCurrency.toUpperCase();
      return ['BTC', 'ETH', 'BNB', 'SOL', 'WLFI', 'TRUMP'].map((b) => '$b$q').toList();
    }
    return _availableCoins;
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: SafeArea(
        child: Responsive.constrainWidth(
          context,
          Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppTheme.spacing20,
                AppTheme.spacing24,
                AppTheme.spacing20,
                AppTheme.spacing16,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'AI Prediction',
                    style: AppTheme.displayLarge.copyWith(
                      color: Theme.of(context).colorScheme.onBackground,
                    ),
                  ),
                  Icon(
                    Icons.check_circle,
                    color: AppTheme.success,
                  ),
                ],
              ),
            ),

            // Upgrade Banner (only shown to free users)
            const UpgradeBanner(),

            // AI Predictions Content (no tabs)
            Expanded(
              child: _buildPredictionsTab(),
            ),
          ],
        ),
        ),
      ),
    );
  }

  // ========== PREDICTIONS TAB ==========
  Widget _buildPredictionsTab() {
    final colors = Theme.of(context).colorScheme;
    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.all(AppTheme.spacing20),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              // Risk Disclaimer
              Container(
                decoration: BoxDecoration(
                  color: colors.surfaceVariant.withOpacity(0.6),
                  borderRadius: BorderRadius.circular(AppTheme.radiusLG),
                  border: Border.all(color: colors.outlineVariant.withOpacity(0.5)),
                ),
                child: const RiskDisclaimer(),
              ),
              const SizedBox(height: AppTheme.spacing16),

              // Symbol & Interval Selector
              _buildSymbolSelector(),
              const SizedBox(height: AppTheme.spacing16),

              // AI Prediction Card
              _buildPredictionCard(),
              const SizedBox(height: AppTheme.spacing16),

              // What does this mean? - User-friendly explanation
              if (_lastPrediction != null)
                _buildWhatDoesThisMean(),
              const SizedBox(height: AppTheme.spacing16),

              // Model Contributions / AI Technical Analysis (only for short-term trading signals, not long-term trends)
              if (_lastPrediction != null && _interval != '1d' && _interval != '1w')
                _buildModelContributions(),
              
              // Upgrade to Premium CTA (FREE mode only)
              if (!AppSettingsService().isTradingEnabled) ...[
                const SizedBox(height: AppTheme.spacing16),
                _buildUpgradeToPremiumCTA(),
              ],
            ]),
          ),
        ),
      ],
    );
  }

  Widget _buildSymbolSelector() {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Trading Pair', style: AppTheme.headingMedium),
          const SizedBox(height: AppTheme.spacing12),

          // Trading Pair Dropdown
          Container(
            padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacing12),
            decoration: BoxDecoration(
              color: Theme.of(context).brightness == Brightness.dark 
                  ? AppTheme.surface 
                  : Colors.grey[100],
              borderRadius: BorderRadius.circular(AppTheme.radiusSM),
              border: Border.all(color: Theme.of(context).brightness == Brightness.dark 
                  ? AppTheme.glassBorder 
                  : Colors.grey[300]!),
            ),
            child: DropdownButton<String>(
              value: _selectedSymbol,
              isExpanded: true,
              underline: const SizedBox(),
              dropdownColor: Theme.of(context).brightness == Brightness.dark 
                  ? AppTheme.surface 
                  : Colors.white,
              style: AppTheme.bodyMedium.copyWith(
                color: Theme.of(context).brightness == Brightness.dark 
                    ? AppTheme.textPrimary 
                    : AppTheme.textPrimaryLight,
              ),
              items: _buildPairs().map((e) => DropdownMenuItem(
                value: e,
                child: Text(
                  e,
                  style: AppTheme.bodyMedium.copyWith(
                    color: Theme.of(context).brightness == Brightness.dark 
                        ? AppTheme.textPrimary 
                        : AppTheme.textPrimaryLight,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              )).toList(),
              onChanged: (v) {
                if (v == null) return;
                setState(() => _selectedSymbol = v);
                _runInference();
              },
            ),
          ),

          const SizedBox(height: AppTheme.spacing12),

          // Timeframe Selector
          Text('Timeframe', style: AppTheme.bodyMedium.copyWith(color: AppTheme.textSecondary)),
          const SizedBox(height: AppTheme.spacing8),
          Consumer<SubscriptionProvider>(
            builder: (context, subscription, _) {
              final isProUser = subscription.isProUser;
              return Wrap(
                spacing: AppTheme.spacing8,
                runSpacing: AppTheme.spacing8,
                children: [
                  {'label': isProUser ? '5M' : '5M 🔒', 'value': '5m'},
                  {'label': isProUser ? '15M' : '15M 🔒', 'value': '15m'},
                  {'label': isProUser ? '1H' : '1H 🔒', 'value': '1h'},
                  {'label': isProUser ? '4H' : '4H FREE', 'value': '4h'},
                  {'label': isProUser ? '1D' : '1D 🔒', 'value': '1d'},
                ].map((item) {
                  final bool selected = _interval == item['value'];
                  final bool isLocked = !isProUser && item['value'] != '4h';

                  return GestureDetector(
                    onTap: isLocked ? () {
                      // Show paywall for locked timeframes
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const PaywallScreen()),
                      );
                    } : () {
                      HapticFeedback.selectionClick();
                      setState(() => _interval = item['value'] as String);
                      _runInference();
                    },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppTheme.spacing16,
                    vertical: AppTheme.spacing8,
                  ),
                  decoration: BoxDecoration(
                    gradient: selected ? AppTheme.primaryGradient : null,
                    color: selected ? null : (Theme.of(context).brightness == Brightness.dark
                        ? AppTheme.glassWhite
                        : Colors.grey[100]),
                    borderRadius: BorderRadius.circular(AppTheme.radiusSM),
                    border: Border.all(
                      color: selected ? Colors.transparent : (Theme.of(context).brightness == Brightness.dark
                          ? AppTheme.glassBorder
                          : Colors.grey[300]!),
                      width: 1,
                    ),
                  ),
                  child: Text(
                    item['label'] as String,
                    style: AppTheme.bodyMedium.copyWith(
                      color: selected ? Colors.white : (Theme.of(context).brightness == Brightness.dark
                          ? AppTheme.textSecondary
                          : AppTheme.textPrimaryLight),
                      fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                ),
              );
            }).toList(),
              );
            },
          ),

          // Explanation for locked timeframes in FREE mode (wrapped in Consumer for trial support)
          Consumer<SubscriptionProvider>(
            builder: (context, subscription, _) {
              final isProUser = subscription.isProUser;

              // Don't show message if user is Pro or in trial
              if (isProUser) {
                return const SizedBox.shrink();
              }

              return Column(
                children: [
                  const SizedBox(height: AppTheme.spacing12),
                  Container(
                    padding: const EdgeInsets.all(AppTheme.spacing12),
                    decoration: BoxDecoration(
                      color: AppTheme.warning.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(AppTheme.radiusMD),
                      border: Border.all(color: AppTheme.warning.withOpacity(0.3)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline, color: AppTheme.warning, size: 18),
                        const SizedBox(width: AppTheme.spacing8),
                        Expanded(
                          child: Text(
                            '🔒 Short-term timeframes (5m-1h) and long-term (1d) are Premium only. Upgrade to unlock all signals.',
                            style: AppTheme.bodySmall.copyWith(
                              color: AppTheme.textSecondary,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildPredictionCard() {
    if (_isRunningPrediction) {
      return GlassCard(
        child: Center(
          child: Column(
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: AppTheme.spacing12),
              Text('Running AI prediction...', style: AppTheme.bodyMedium.copyWith(color: AppTheme.textSecondary)),
            ],
          ),
        ),
      );
    }

    if (_predictionError.isNotEmpty) {
      return GlassCard(
        child: Column(
          children: [
            Icon(Icons.error_outline, color: AppTheme.error, size: 48),
            const SizedBox(height: AppTheme.spacing12),
            Text('Prediction Error', style: AppTheme.headingMedium.copyWith(color: AppTheme.error)),
            const SizedBox(height: AppTheme.spacing8),
            Text(_predictionError, style: AppTheme.bodySmall.copyWith(color: AppTheme.textSecondary)),
            const SizedBox(height: AppTheme.spacing16),
            ElevatedButton.icon(
              onPressed: _runInference,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      );
    }

    if (_lastPrediction == null) {
      return GlassCard(
        child: Column(
          children: [
            Icon(Icons.psychology, color: AppTheme.primary, size: 48),
            const SizedBox(height: AppTheme.spacing12),
            Text('No prediction yet', style: AppTheme.headingMedium),
            const SizedBox(height: AppTheme.spacing8),
            Text(
              'Run AI inference to get a trading signal',
              style: AppTheme.bodyMedium.copyWith(color: AppTheme.textSecondary),
            ),
            const SizedBox(height: AppTheme.spacing16),
            ElevatedButton.icon(
              onPressed: _runInference,
              icon: const Icon(Icons.play_arrow),
              label: const Text('Run Inference'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      );
    }

    // UNIFIED STYLE for all timeframes (15m/1h/4h/1d) - Clean & Beautiful
    final prediction = _lastPrediction!;
    final action = prediction.action;

    final isBuy = action == 'BUY';
    final isSell = action == 'SELL';
    final signalColor = isBuy ? AppTheme.buyGreen : (isSell ? AppTheme.sellRed : const Color(0xFFFF9500));

    return GlassCard(
      child: Column(
        children: [
          // Signal Icon & Label
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: signalColor.withOpacity(0.2),
              shape: BoxShape.circle,
              border: Border.all(color: signalColor, width: 2),
            ),
            child: Icon(
              isBuy ? Icons.trending_up : (isSell ? Icons.trending_down : Icons.drag_handle),
              color: signalColor,
              size: 40,
            ),
          ),
          const SizedBox(height: AppTheme.spacing16),
          Text(
            action,
            style: AppTheme.displayMedium.copyWith(color: signalColor, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: AppTheme.spacing8),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppTheme.spacing16,
              vertical: AppTheme.spacing8,
            ),
            decoration: BoxDecoration(
              gradient: isBuy
                  ? AppTheme.buyGradient
                  : (isSell
                      ? AppTheme.sellGradient
                      : const LinearGradient(colors: [Color(0xFFFF9500), Color(0xFFFF7A00)])),
              borderRadius: BorderRadius.circular(AppTheme.radiusSM),
            ),
            child: Text(
              'Confidence: ${(prediction.confidence * 100).toStringAsFixed(1)}%',
              style: AppTheme.headingMedium.copyWith(color: Colors.white),
            ),
          ),
          const SizedBox(height: AppTheme.spacing16),
          Text(
            'Ensemble Prediction',
            style: AppTheme.bodySmall.copyWith(color: AppTheme.textTertiary),
          ),
          
          // PHASE 4: Market Context Badges (ATR + Volume) with animation
          if (prediction.atr != null || prediction.volumePercentile != null) ...[
            const SizedBox(height: AppTheme.spacing16),
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.0, end: 1.0),
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeOut,
              builder: (context, value, child) {
                return Opacity(
                  opacity: value,
                  child: Transform.translate(
                    offset: Offset(0, 10 * (1 - value)),
                    child: child,
                  ),
                );
              },
              child: Wrap(
                spacing: AppTheme.spacing8,
                runSpacing: AppTheme.spacing8,
                alignment: WrapAlignment.center,
                children: [
                  // ATR (Volatility) Badge
                  if (prediction.atr != null) _buildMarketBadge(
                    icon: Icons.show_chart,
                    label: 'Volatility',
                    value: '${(prediction.atr! * 100).toStringAsFixed(2)}%',
                    isHigh: prediction.atr! > 0.025,
                    context: context,
                    tooltipMessage: 'ATR (Average True Range) measures market volatility. Higher values indicate more price movement and trading opportunities.',
                  ),
                  // Volume Percentile Badge
                  if (prediction.volumePercentile != null) _buildMarketBadge(
                    icon: Icons.water_drop,
                    label: 'Liquidity',
                    value: '${(prediction.volumePercentile! * 100).toStringAsFixed(0)}%',
                    isHigh: prediction.volumePercentile! > 0.70,
                    context: context,
                    tooltipMessage: 'Liquidity rank compared to major cryptocurrencies. Higher liquidity means more reliable trading signals and better execution.',
                  ),
                ],
              ),
            ),
          ],
          
          const SizedBox(height: AppTheme.spacing16),
          ElevatedButton.icon(
            onPressed: _runInference,
            icon: const Icon(Icons.refresh),
            label: const Text('Refresh Prediction'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  /// PHASE 4: Generate dynamic HOLD explanation based on market context
  String _generateHoldExplanation({
    required String coin,
    required String timeframe,
    double? atr,
    double? volumePercentile,
    required double sellProb,
    required double buyProb,
  }) {
    final coinName = coin.replaceAll(RegExp(r'(USDT|EUR|USDC|USD)$'), '');
    final buffer = StringBuffer();
    
    // Market condition
    if (atr != null && atr > 0.025) {
      buffer.write('$coinName is in a high-volatility phase (${(atr * 100).toStringAsFixed(2)}% ATR). ');
    } else {
      buffer.write('$coinName is trading in a stable range. ');
    }
    
    // Liquidity context
    if (volumePercentile != null) {
      if (volumePercentile > 0.70) {
        buffer.write('High liquidity (${(volumePercentile * 100).toStringAsFixed(0)}% percentile) ensures reliable signals. ');
      } else if (volumePercentile < 0.30) {
        buffer.write('Low liquidity (${(volumePercentile * 100).toStringAsFixed(0)}% percentile) suggests caution on large moves. ');
      }
    }
    
    // Signal balance explanation
    final diff = (sellProb - buyProb).abs();
    if (diff < 0.15) {
      buffer.write('BUY and SELL signals are nearly balanced (${(buyProb * 100).toStringAsFixed(1)}% vs ${(sellProb * 100).toStringAsFixed(1)}%), indicating market indecision. ');
    } else if (sellProb > buyProb) {
      buffer.write('Slight bearish bias (${(sellProb * 100).toStringAsFixed(1)}% SELL vs ${(buyProb * 100).toStringAsFixed(1)}% BUY), but not strong enough for action. ');
    } else {
      buffer.write('Slight bullish bias (${(buyProb * 100).toStringAsFixed(1)}% BUY vs ${(sellProb * 100).toStringAsFixed(1)}% SELL), but confidence below threshold. ');
    }
    
    // Timeframe-specific advice
    if (timeframe == '5m' || timeframe == '15m') {
      buffer.write('Short-term consolidation detected. Await clearer momentum on $timeframe chart.');
    } else if (timeframe == '1h' || timeframe == '4h') {
      buffer.write('Mid-term range-bound trading. Wait for breakout confirmation on $timeframe timeframe.');
    } else {
      buffer.write('Long-term consolidation. Market awaiting catalyst for directional move.');
    }
    
    return buffer.toString();
  }

  /// PHASE 4: Build market context badge with descriptive labels and tooltip
  Widget _buildMarketBadge({
    required IconData icon,
    required String label,
    required String value,
    required bool isHigh,
    required BuildContext context,
    required String tooltipMessage,
  }) {
    // Parse value to get numeric part
    String displayLabel = value;
    Color color = AppTheme.textSecondary;
    Color bgColor = Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.5);
    
    // For Volatility badge
    if (label == 'Volatility') {
      final atrValue = double.tryParse(value.replaceAll('%', '')) ?? 0.0;
      if (atrValue >= 4.0) {
        displayLabel = 'High ($value)';
        color = AppTheme.sellRed;
        bgColor = AppTheme.sellRed.withOpacity(0.15);
      } else if (atrValue >= 2.5) {
        displayLabel = 'Elevated ($value)';
        color = const Color(0xFFFF9500);
        bgColor = const Color(0xFFFF9500).withOpacity(0.15);
      } else if (atrValue >= 1.5) {
        displayLabel = 'Normal ($value)';
        color = Colors.blue;
        bgColor = Colors.blue.withOpacity(0.15);
      } else {
        displayLabel = 'Calm ($value)';
        color = AppTheme.success;
        bgColor = AppTheme.success.withOpacity(0.15);
      }
    }
    // For Liquidity badge
    else if (label == 'Liquidity') {
      final volValue = double.tryParse(value.replaceAll('%', '')) ?? 0.0;
      if (volValue >= 70) {
        displayLabel = 'High ($value)';
        color = AppTheme.success;
        bgColor = AppTheme.success.withOpacity(0.15);
      } else if (volValue >= 40) {
        displayLabel = 'Medium ($value)';
        color = Colors.blue;
        bgColor = Colors.blue.withOpacity(0.15);
      } else if (volValue >= 15) {
        displayLabel = 'Low ($value)';
        color = AppTheme.textSecondary;
        bgColor = Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.5);
      } else {
        displayLabel = 'Very Low ($value)';
        color = AppTheme.textSecondary;
        bgColor = Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.5);
      }
    }
    
    return Tooltip(
      message: tooltipMessage,
      padding: const EdgeInsets.all(AppTheme.spacing12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusMD),
        border: Border.all(color: color.withOpacity(0.5)),
        boxShadow: AppTheme.glassShadow,
      ),
      textStyle: AppTheme.bodySmall.copyWith(color: AppTheme.textPrimary),
      preferBelow: false,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppTheme.spacing12,
          vertical: AppTheme.spacing8,
        ),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(AppTheme.radiusSM),
          border: Border.all(
            color: color.withOpacity(0.3),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 16),
            const SizedBox(width: AppTheme.spacing4),
            Text(
              '$label: ',
              style: AppTheme.bodySmall.copyWith(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7)),
            ),
            Text(
              displayLabel,
              style: AppTheme.bodySmall.copyWith(
                color: color,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// REMOVED - Old long-term function, now using unified style
  Widget _buildLongTermPrediction_REMOVED() {
    final prediction = _lastPrediction!;

    // Use the actual action from prediction (BUY/SELL/HOLD)
    final action = prediction.action;

    // Get colors and gradients based on action
    Color trendColor;
    Gradient trendGradient;
    IconData trendIcon;

    if (action == 'BUY') {
      trendColor = AppTheme.buyGreen;
      trendGradient = AppTheme.buyGradient;
      trendIcon = Icons.north;
    } else if (action == 'SELL') {
      trendColor = AppTheme.sellRed;
      trendGradient = AppTheme.sellGradient;
      trendIcon = Icons.south;
    } else {
      // HOLD
      trendColor = const Color(0xFFFF9500);
      trendGradient = const LinearGradient(
        colors: [Color(0xFFFF9500), Color(0xFFFF7A00)],
      );
      trendIcon = Icons.drag_handle;
    }

    final confidence = prediction.confidence;

    return GlassCard(
      child: Column(
        children: [
          // Title
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.show_chart, color: AppTheme.textSecondary, size: 20),
              const SizedBox(width: AppTheme.spacing8),
              Text(
                'Long-term Trend',
                style: AppTheme.headingMedium.copyWith(color: AppTheme.textSecondary),
              ),
            ],
          ),

          const SizedBox(height: AppTheme.spacing24),

          // Large Arrow Icon with premium design
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              gradient: trendGradient,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: trendColor.withOpacity(0.3),
                  blurRadius: 20,
                  spreadRadius: 5,
                ),
              ],
            ),
            child: Icon(
              trendIcon,
              color: Colors.white,
              size: 64,
            ),
          ),

          const SizedBox(height: AppTheme.spacing24),

          // Trend Label
          Text(
            action.toUpperCase(),
            style: AppTheme.displayLarge.copyWith(
              color: trendColor,
              fontWeight: FontWeight.bold,
              letterSpacing: 2,
            ),
          ),

          const SizedBox(height: AppTheme.spacing12),

          // Confidence Badge
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppTheme.spacing16,
              vertical: AppTheme.spacing12,
            ),
            decoration: BoxDecoration(
              gradient: trendGradient,
              borderRadius: BorderRadius.circular(AppTheme.radiusMD),
              boxShadow: [
                BoxShadow(
                  color: trendColor.withOpacity(0.2),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.analytics, color: Colors.white, size: 18),
                const SizedBox(width: AppTheme.spacing8),
                Flexible(
                  child: Text(
                    '${(confidence * 100).toStringAsFixed(1)}% Confidence',
                    style: AppTheme.headingMedium.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: AppTheme.spacing20),

          // Signal Description (why BUY/HOLD/SELL)
          Container(
            padding: const EdgeInsets.all(AppTheme.spacing16),
            decoration: BoxDecoration(
              color: trendColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(AppTheme.radiusMD),
              border: Border.all(color: trendColor.withOpacity(0.3), width: 2),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.lightbulb_outline, color: trendColor, size: 20),
                    const SizedBox(width: AppTheme.spacing8),
                    Text(
                      'Market Analysis',
                      style: AppTheme.headingSmall.copyWith(
                        color: trendColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppTheme.spacing12),
                Text(
                  action == 'BUY'
                      ? 'Bullish momentum confirmed across multiple timeframes. Technical indicators show oversold recovery, MACD golden cross, and increasing volume. Strong accumulation phase detected with higher lows forming.'
                      : action == 'SELL'
                          ? 'Bearish momentum detected with weakening support levels. RSI showing overbought conditions, negative MACD divergence, and declining volume. Distribution phase with lower highs forming.'
                          : 'Neutral market conditions with consolidation phase. Mixed signals from technical indicators suggest awaiting clear breakout confirmation. Range-bound trading with balanced buy/sell pressure.',
                  style: AppTheme.bodyMedium.copyWith(
                    color: AppTheme.textPrimary,
                    height: 1.6,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: AppTheme.spacing20),

          // Probabilities
          Container(
            padding: const EdgeInsets.all(AppTheme.spacing16),
            decoration: BoxDecoration(
              color: AppTheme.glassWhite,
              borderRadius: BorderRadius.circular(AppTheme.radiusMD),
              border: Border.all(color: AppTheme.glassBorder),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Column(
                  children: [
                    Icon(Icons.south, color: AppTheme.sellRed, size: 24),
                    const SizedBox(height: AppTheme.spacing4),
                    Text(
                      'SELL',
                      style: AppTheme.bodySmall.copyWith(color: AppTheme.textSecondary),
                    ),
                    Text(
                      '${((prediction.probabilities['SELL'] ?? 0.0) * 100).toStringAsFixed(1)}%',
                      style: AppTheme.headingMedium.copyWith(
                        color: AppTheme.sellRed,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                Container(
                  width: 1,
                  height: 60,
                  color: AppTheme.glassBorder,
                ),
                Column(
                  children: [
                    Icon(Icons.drag_handle, color: const Color(0xFFFF9500), size: 24),
                    const SizedBox(height: AppTheme.spacing4),
                    Text(
                      'HOLD',
                      style: AppTheme.bodySmall.copyWith(color: AppTheme.textSecondary),
                    ),
                    Text(
                      '${((prediction.probabilities['HOLD'] ?? 0.0) * 100).toStringAsFixed(1)}%',
                      style: AppTheme.headingMedium.copyWith(
                        color: const Color(0xFFFF9500),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                Container(
                  width: 1,
                  height: 60,
                  color: AppTheme.glassBorder,
                ),
                Column(
                  children: [
                    Icon(Icons.north, color: AppTheme.buyGreen, size: 24),
                    const SizedBox(height: AppTheme.spacing4),
                    Text(
                      'BUY',
                      style: AppTheme.bodySmall.copyWith(color: AppTheme.textSecondary),
                    ),
                    Text(
                      '${((prediction.probabilities['BUY'] ?? 0.0) * 100).toStringAsFixed(1)}%',
                      style: AppTheme.headingMedium.copyWith(
                        color: AppTheme.buyGreen,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: AppTheme.spacing20),

          // Timeframe Info
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppTheme.spacing12,
              vertical: AppTheme.spacing8,
            ),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(AppTheme.radiusSM),
              border: Border.all(color: AppTheme.glassBorder),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.schedule, color: AppTheme.textTertiary, size: 16),
                const SizedBox(width: AppTheme.spacing8),
                Text(
                  '1-Day Forecast',
                  style: AppTheme.bodySmall.copyWith(color: AppTheme.textTertiary),
                ),
              ],
            ),
          ),

          const SizedBox(height: AppTheme.spacing16),

          // Refresh Button
          ElevatedButton.icon(
            onPressed: _runInference,
            icon: const Icon(Icons.refresh),
            label: const Text('Refresh Prediction'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(
                horizontal: AppTheme.spacing20,
                vertical: AppTheme.spacing12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModelContributions() {
    final prediction = _lastPrediction!;

    // Determine which signal to show based on prediction label
    final isBuy = prediction.action == 'BUY';
    final isSell = prediction.action == 'SELL';

    // CryptoPrediction uses Map<String, double> for probabilities
    final sellProb = prediction.probabilities['SELL'] ?? 0.0;
    final holdProb = prediction.probabilities['HOLD'] ?? 0.0;
    final buyProb = prediction.probabilities['BUY'] ?? 0.0;

    String signalLabel;
    double signalProb;
    Color signalColor;
    IconData signalIcon;
    String signalDescription;

    if (isBuy) {
      signalLabel = 'BUY SIGNAL';
      signalProb = buyProb;
      signalColor = AppTheme.buyGreen;
      signalIcon = Icons.trending_up;
      signalDescription = 'Bullish momentum confirmed. RSI oversold recovery, MACD golden cross, volume surge. Multiple technical indicators align for upward movement.';
    } else if (isSell) {
      signalLabel = 'SELL SIGNAL';
      signalProb = sellProb;
      signalColor = AppTheme.sellRed;
      signalIcon = Icons.trending_down;
      signalDescription = 'Bearish momentum detected. RSI overbought, MACD divergence, declining volume. Technical indicators suggest downward pressure.';
    } else {
      signalLabel = 'HOLD SIGNAL';
      signalProb = holdProb;
      signalColor = AppTheme.holdYellow;
      signalIcon = Icons.pause;
      // PHASE 4: Dynamic HOLD explanation based on coin + ATR + volume
      signalDescription = _generateHoldExplanation(
        coin: _selectedSymbol,
        timeframe: _interval,
        atr: prediction.atr,
        volumePercentile: prediction.volumePercentile,
        sellProb: sellProb,
        buyProb: buyProb,
      );
    }

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.insights, color: AppTheme.primary, size: 20),
              const SizedBox(width: AppTheme.spacing8),
              Expanded(
                child: Text('AI Technical Analysis', style: AppTheme.headingMedium),
              ),
            ],
          ),
          const SizedBox(height: AppTheme.spacing8),
          Text(
            'Advanced deep learning model analyzes 76 technical indicators across multiple timeframes',
            style: AppTheme.bodySmall.copyWith(color: AppTheme.textTertiary),
          ),
          const SizedBox(height: AppTheme.spacing20),

          // Show only the active signal
          _buildSignalCard(
            signalLabel,
            signalProb,
            signalColor,
            signalIcon,
            signalDescription,
          ),
        ],
      ),
    );
  }

  Widget _buildSignalCard(String label, double probability, Color color, IconData icon, String description) {
    return Container(
      padding: const EdgeInsets.all(AppTheme.spacing12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(AppTheme.radiusMD),
        border: Border.all(
          color: color.withOpacity(0.3),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(icon, color: color, size: 20),
                  const SizedBox(width: AppTheme.spacing8),
                  Text(
                    label,
                    style: AppTheme.bodyLarge.copyWith(
                      color: color,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppTheme.spacing12,
                  vertical: AppTheme.spacing4,
                ),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(AppTheme.radiusSM),
                ),
                child: Text(
                  '${(probability * 100).toStringAsFixed(1)}%',
                  style: AppTheme.bodyMedium.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTheme.spacing8),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppTheme.radiusSM),
            child: LinearProgressIndicator(
              value: probability,
              backgroundColor: AppTheme.surface,
              valueColor: AlwaysStoppedAnimation<Color>(color),
              minHeight: 6,
            ),
          ),
          const SizedBox(height: AppTheme.spacing8),
          Text(
            description,
            style: AppTheme.bodySmall.copyWith(
              color: AppTheme.textSecondary,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
  
  /// Build "What does this mean?" section
  Widget _buildWhatDoesThisMean() {
    final prediction = _lastPrediction!;
    final action = prediction.action;
    final isBuy = action == 'BUY';
    final isSell = action == 'SELL';
    final signalColor = isBuy ? AppTheme.buyGreen : (isSell ? AppTheme.sellRed : const Color(0xFFFF9500));
    
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.lightbulb_outline, color: signalColor, size: 20),
              const SizedBox(width: AppTheme.spacing8),
              Flexible(
                child: Text(
                  'What does this mean?',
                  style: AppTheme.headingMedium.copyWith(
                    color: signalColor,
                    fontWeight: FontWeight.bold,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTheme.spacing12),
          Text(
            _getActionExplanation(action, _selectedSymbol, _interval),
            style: AppTheme.bodyMedium.copyWith(
              color: AppTheme.textSecondary,
              height: 1.5,
            ),
          ),
          const SizedBox(height: AppTheme.spacing12),
          
          // Action instruction based on mode
          if (!AppSettingsService().isTradingEnabled) ...[
            // FREE mode - show upgrade message
            Container(
              padding: const EdgeInsets.all(AppTheme.spacing12),
              decoration: BoxDecoration(
                color: AppTheme.warning.withOpacity(0.1),
                borderRadius: BorderRadius.circular(AppTheme.radiusSM),
                border: Border.all(color: AppTheme.warning.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.lock_outline, color: AppTheme.warning, size: 18),
                  const SizedBox(width: AppTheme.spacing8),
                  Expanded(
                    child: Text(
                      '💡 To act on this signal, upgrade to Premium and enable trading in Settings.',
                      style: AppTheme.bodySmall.copyWith(
                        color: AppTheme.warning,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[
            // PREMIUM mode - show action instruction
            Container(
              padding: const EdgeInsets.all(AppTheme.spacing12),
              decoration: BoxDecoration(
                color: signalColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(AppTheme.radiusSM),
                border: Border.all(color: signalColor.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.touch_app, color: signalColor, size: 18),
                  const SizedBox(width: AppTheme.spacing8),
                  Expanded(
                    child: Text(
                      action == 'HOLD' 
                        ? '💡 Wait for a clearer signal before trading.'
                        : '💡 Go to Orders tab to manually place a ${action.toLowerCase()} order.',
                      style: AppTheme.bodySmall.copyWith(
                        color: signalColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
  
  /// Build "Upgrade to Premium" CTA
  Widget _buildUpgradeToPremiumCTA() {
    return GlassCard(
      child: Container(
        padding: const EdgeInsets.all(AppTheme.spacing16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppTheme.primary.withOpacity(0.1),
              AppTheme.secondary.withOpacity(0.1),
            ],
          ),
          borderRadius: BorderRadius.circular(AppTheme.radiusMD),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Icon(Icons.auto_awesome, color: AppTheme.primary, size: 20),
                const SizedBox(width: AppTheme.spacing8),
                Expanded(
                  child: Text(
                    'Want more AI predictions?',
                    style: AppTheme.headingSmall.copyWith(
                      color: AppTheme.primary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppTheme.spacing8),
            Text(
              'Upgrade to Premium for:\n'
              '• 5m, 15m, 1h predictions (day trading)\n'
              '• 1d predictions (swing trading)\n'
              '• Volatility & liquidity indicators\n'
              '• Model contributions breakdown\n'
              '• Trading capabilities',
              style: AppTheme.bodySmall.copyWith(
                color: AppTheme.textSecondary,
                height: 1.5,
              ),
            ),
            const SizedBox(height: AppTheme.spacing12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pushNamed(context, '/settings');
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Upgrade to Premium'),
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  /// Generate user-friendly explanation of AI recommendation
  String _getActionExplanation(String action, String symbol, String timeframe) {
    final coin = symbol.replaceAll(RegExp(r'(USDT|EUR|USDC|USD)'), '');
    final tfDisplay = timeframe == '5m' ? '5-minute' :
                      timeframe == '15m' ? '15-minute' :
                      timeframe == '1h' ? '1-hour' :
                      timeframe == '4h' ? '4-hour' :
                      timeframe == '1d' ? 'daily' : timeframe;
    
    switch (action) {
      case 'BUY':
        return 'AI analysis suggests $coin is in an uptrend on the $tfDisplay timeframe. '
               'This means the price is likely to increase in the coming ${_getTimeHorizon(timeframe)}. '
               'Consider buying $coin now and holding for potential gains.\n\n'
               '⚠️ Always do your own research and only invest what you can afford to lose.';
      
      case 'SELL':
        return 'AI analysis suggests $coin is in a downtrend on the $tfDisplay timeframe. '
               'This means the price is likely to decrease in the coming ${_getTimeHorizon(timeframe)}. '
               'If you own $coin, consider selling to protect your capital.\n\n'
               '⚠️ Always do your own research and only invest what you can afford to lose.';
      
      case 'HOLD':
        return 'AI analysis suggests $coin is in a consolidation phase on the $tfDisplay timeframe. '
               'This means the price is moving sideways without clear direction. '
               'Wait for a clearer signal before buying or selling.\n\n'
               '💡 Check back later or try a different timeframe for more insights.';
      
      default:
        return 'AI is analyzing market conditions for $coin. Check back soon for updated signals.';
    }
  }
  
  /// Get time horizon description based on timeframe
  String _getTimeHorizon(String timeframe) {
    switch (timeframe) {
      case '5m':
      case '15m':
        return 'minutes to hours';
      case '1h':
        return 'hours';
      case '4h':
        return 'hours to days';
      case '1d':
        return 'days to weeks';
      default:
        return 'period';
    }
  }
}

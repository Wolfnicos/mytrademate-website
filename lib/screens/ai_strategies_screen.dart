import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

// Services
import '../services/app_settings_service.dart';
import '../services/binance_service.dart';
import '../services/user_coins_service.dart';

// ML
import '../ml/crypto_ml_service.dart';

// Theme & Widgets
import '../theme/app_theme.dart';
import '../widgets/glass_card.dart';
import '../widgets/upgrade_banner.dart';
import '../utils/responsive.dart';

// Providers
import '../providers/subscription_provider.dart';
import '../providers/exchange_provider.dart';
import 'paywall_screen.dart';

// Market Intelligence
import 'package:mytrademate/models/market_intelligence_boost.dart';
import 'package:mytrademate/services/market_intelligence_aggregator.dart';

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
  DateTime? _lastUpdateTime; // Track when prediction was last updated
  double? _previousAtr; // Track previous ATR to show trend
  double? _previousPrice; // Track previous price to show change

  String _selectedSymbol = 'BTCUSDT';
  String _interval = '4h'; // Default to 4H (free tier)

  // Market Intelligence State
  MarketIntelligenceBoost? _marketIntelligence;

  // Portfolio coins for dynamic dropdown
  List<String> _availableCoins = [];
  // bool _loadingCoins = true;

  // Auto-refresh timer (Phase 4 Quick Win)
  Timer? _autoRefreshTimer;

  @override
  void initState() {
    super.initState();
    debugPrint('📍 Insight: initState() - adding UserCoinsService listener');
    final quote = AppSettingsService().quoteCurrency.toUpperCase();
    _selectedSymbol = 'BTC$quote';
    _loadAvailableCoins();
    // Auto-run first prediction
    Future.delayed(const Duration(milliseconds: 500), _runInference);
    // Listen to quote currency changes
    AppSettingsService().addListener(_onQuoteCurrencyChanged);
    // Listen to UserCoinsService changes (when API added/removed in Settings)
    UserCoinsService().addListener(_onCoinsChanged);
    debugPrint('✅ Insight: UserCoinsService listener added');
    // Start auto-refresh timer (30 seconds)
    _startAutoRefresh();
  }

  /// Called when UserCoinsService notifies that coins changed
  void _onCoinsChanged() {
    debugPrint('📢 Insight: Coins changed, reloading...');
    _loadAvailableCoins();
  }

  /// Start auto-refresh timer to update predictions every 3 minutes (SILENT)
  void _startAutoRefresh() {
    _autoRefreshTimer?.cancel(); // Cancel existing timer if any
    _autoRefreshTimer = Timer.periodic(const Duration(minutes: 3), (_) {
      debugPrint('🔄 Auto-refresh triggered (SILENT) for $_selectedSymbol @ $_interval');
      if (mounted && !_isRunningPrediction) {
        _runInferenceSilent();  // Use silent refresh (no UI indicators)
      }
    });
  }

  /// Stop auto-refresh timer
  void _stopAutoRefresh() {
    _autoRefreshTimer?.cancel();
    _autoRefreshTimer = null;
  }

  @override
  void dispose() {
    _stopAutoRefresh(); // Cancel timer before disposing
    AppSettingsService().removeListener(_onQuoteCurrencyChanged);
    UserCoinsService().removeListener(_onCoinsChanged);
    super.dispose();
  }

  void _onQuoteCurrencyChanged() async {
    // Update trading pair when quote currency changes
    final quote = AppSettingsService().quoteCurrency.toUpperCase();
    debugPrint('AI Strategies: Quote currency changed to $quote, updating pairs...');

    // Extract base asset from current pair (e.g., BTCUSDT -> BTC, BTC-USD -> BTC)
    String baseAsset = _selectedSymbol.replaceAll('-', ''); // Remove Coinbase hyphens
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
      final exchangeProvider = Provider.of<ExchangeProvider>(context, listen: false);
      final exchange = exchangeProvider.currentExchange;

      await exchange.loadCredentials();
      final balances = await exchange.getAccountBalances();
      final quote = AppSettingsService().quoteCurrency.toUpperCase();

      // Extract coins from portfolio (excluding quote currency, fiat currencies, and coins below $5)
      final Set<String> coins = {};
      for (final asset in balances.keys) {
        final upperAsset = asset.toUpperCase();
        // Skip quote currency and fiat currencies (EUR, USD, GBP, etc.)
        if (upperAsset == quote || !UserCoinsService.isValidCoin(upperAsset)) {
          continue;
        }
        if (balances[asset]! > 0.0) {
          // Calculate value to filter out coins below $5
          try {
            final ticker = await exchange.fetchTicker24hWithFallback([
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

      // If no holdings, use UserCoinsService (TOP 10 default or API coins)
      if (coins.isEmpty) {
        final userCoins = await UserCoinsService().getUserCoins();
        coins.addAll(userCoins.map((b) => '$b$quote'));
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
      // Fall back to UserCoinsService (TOP 10 default or API coins)
      final quote = AppSettingsService().quoteCurrency.toUpperCase();
      final userCoins = await UserCoinsService().getUserCoins();
      if (mounted) {
        setState(() {
          _availableCoins = userCoins.map((b) => '$b$quote').toList();
          // Ensure selected symbol is in the list
          if (!_availableCoins.contains(_selectedSymbol) && _availableCoins.isNotEmpty) {
            _selectedSymbol = _availableCoins.first;
          }
        });
      }
    }
  }

  Future<void> _runInference() async {
    if (!mounted) return;
    setState(() {
      _isRunningPrediction = true;
      _predictionError = '';
    });

    try {
      // Get coin from symbol (e.g., BTCUSDT -> BTC, BTC-USD -> BTC)
      // Remove Coinbase hyphens first, then extract base currency
      final cleanSymbol = _selectedSymbol.replaceAll('-', '');
      final coin = cleanSymbol.replaceAll(RegExp(r'(USDT|USDC|BUSD|USD|EUR|BTC)$'), '');

      debugPrint('🚀 AI Strategies: fetching CryptoML prediction for $coin @$_interval');

      // NEW: CryptoMLService now fetches candles for EACH model's timeframe!
      // We just pass the symbol and let the service handle multi-timeframe fetching
      final exchangeProvider = Provider.of<ExchangeProvider>(context, listen: false);
      // 🆕 V2 PRO MODELS: For 4h/1d + BTC/ETH/SOL/BNB, CryptoMLService now uses V2 (150 features) automatically!
      final prediction = await CryptoMLService().getPrediction(
        coin: coin,
        symbol: _selectedSymbol,
        timeframe: _interval,
        exchangeService: exchangeProvider.currentExchange,
        userCoins: _availableCoins,  // Pass user's portfolio coins for volume percentile
      );

      // Get current price for price change tracking
      final currentPriceResult = await BinanceService().getFeaturesWithATRFallback(_selectedSymbol, interval: _interval);
      final currentPrice = currentPriceResult.currentPrice;

      // Calculate price change from previous prediction
      final priceChange = _previousPrice != null ? currentPrice - _previousPrice! : 0.0;
      final priceChangePercent = _previousPrice != null && _previousPrice! > 0
          ? (priceChange / _previousPrice!) * 100
          : 0.0;

      if (_previousPrice != null) {
        debugPrint('💹 Price change: ${priceChange >= 0 ? '+' : ''}${priceChange.toStringAsFixed(2)} (${priceChangePercent >= 0 ? '+' : ''}${priceChangePercent.toStringAsFixed(3)}%)');
      }

      // Use configured quote currency (not extracted from symbol to avoid BUSD)
      final quoteCurrency = AppSettingsService().quoteCurrency;

      // Debug-only: print final JSON-like summary for QA (no UI impact)
      // ignore: avoid_print
      print('JSON_AI_STRATEGIES: {"coin":"$coin","timeframe":"$_interval","action":"${prediction.action}","confidence":${prediction.confidence.toStringAsFixed(4)},"atr":${(currentPriceResult.atr * 100).toStringAsFixed(2)},"quote_currency":"$quoteCurrency"}');

      debugPrint('🚀 CryptoML: ${prediction.action} (${(prediction.confidence * 100).toStringAsFixed(1)}%)');

      if (mounted) {
        setState(() {
          // Store previous values before updating prediction
          _previousAtr = _lastPrediction?.atr;
          _previousPrice = currentPrice;
          _lastPrediction = prediction;
          _lastUpdateTime = DateTime.now();
          _isRunningPrediction = false;
        });
        // Load market intelligence after prediction completes
        _loadMarketIntelligence();
      }
    } catch (e) {
      debugPrint('❌ AI inference error: $e');
      if (mounted) {
        // Check if error is due to insufficient historical data
        String userFriendlyError = e.toString();

        // Handle various "not enough data" errors
        if ((userFriendlyError.contains('Insufficient') && userFriendlyError.contains('candles')) ||
            (userFriendlyError.contains('Need at least') && userFriendlyError.contains('candles')) ||
            userFriendlyError.contains('sliding window')) {
          // Extract coin name from symbol
          final coin = _selectedSymbol.replaceAll(RegExp(r'(USDT|USDC|BUSD|USD|EUR|BTC)$'), '');

          // Friendly message for new coins with limited history
          if (_interval == '1d') {
            userFriendlyError = '🪙 $coin is a new cryptocurrency!\n\n'
                '📊 Daily (1D) predictions need at least 4 months of data.\n\n'
                '✅ Try a shorter timeframe:\n'
                '   • 4H (most recommended)\n'
                '   • 1H or 15M (for scalping)';
          } else {
            userFriendlyError = '⏰ $coin is a new cryptocurrency with limited history.\n\n'
                '📊 For $_interval predictions, we need more historical data.\n\n'
                '💡 Try a shorter timeframe (15m, 1h, or 4h) for newer coins.';
          }
        }
        setState(() {
          _predictionError = userFriendlyError;
          _isRunningPrediction = false;
        });
      }
    }
  }

  /// Silent refresh (no UI indicators) - used by auto-refresh timer
  Future<void> _runInferenceSilent() async {
    if (!mounted) return;
    // DO NOT set _isRunningPrediction = true (no UI spinner/text)

    try {
      // Get coin from symbol (e.g., BTCUSDT -> BTC, BTC-USD -> BTC)
      // Remove Coinbase hyphens first, then extract base currency
      final cleanSymbol = _selectedSymbol.replaceAll('-', '');
      final coin = cleanSymbol.replaceAll(RegExp(r'(USDT|USDC|BUSD|USD|EUR|BTC)$'), '');

      debugPrint('🔄 AI Strategies (SILENT): fetching CryptoML prediction for $coin @$_interval');

      // Fetch prediction with silent flag (reduced logging)
      final exchangeProvider = Provider.of<ExchangeProvider>(context, listen: false);
      final prediction = await CryptoMLService().getPrediction(
        coin: coin,
        symbol: _selectedSymbol,
        timeframe: _interval,
        silent: true,  // Silent mode: no verbose logging
        exchangeService: exchangeProvider.currentExchange,
        userCoins: _availableCoins,  // Pass user's portfolio coins for volume percentile
      );

      // Get current price for price change tracking
      final currentPriceResult = await BinanceService().getFeaturesWithATRFallback(_selectedSymbol, interval: _interval);
      final currentPrice = currentPriceResult.currentPrice;

      // Calculate price change from previous prediction
      final priceChange = _previousPrice != null ? currentPrice - _previousPrice! : 0.0;
      final priceChangePercent = _previousPrice != null && _previousPrice! > 0
          ? (priceChange / _previousPrice!) * 100
          : 0.0;

      if (_previousPrice != null && priceChangePercent.abs() > 0.5) {
        // Only log significant price changes (>0.5%)
        debugPrint('💹 Price change: ${priceChange >= 0 ? '+' : ''}${priceChange.toStringAsFixed(2)} (${priceChangePercent >= 0 ? '+' : ''}${priceChangePercent.toStringAsFixed(3)}%)');
      }

      debugPrint('🔄 CryptoML (SILENT): ${prediction.action} (${(prediction.confidence * 100).toStringAsFixed(1)}%)');

      if (mounted) {
        setState(() {
          // Update state WITHOUT showing loading indicators
          _previousAtr = _lastPrediction?.atr;
          _previousPrice = currentPrice;
          _lastPrediction = prediction;
          _lastUpdateTime = DateTime.now();
          // DO NOT set _isRunningPrediction = false (it was never true)
        });
      }
    } catch (e) {
      debugPrint('❌ AI inference error (SILENT): $e');
      // Don't update UI with error on silent refresh (user didn't initiate it)
      // Just log the error and keep previous prediction
    }
  }

  Future<void> _loadMarketIntelligence() async {
    if (_lastPrediction == null) return;

    try {
      final aggregator = MarketIntelligenceAggregator();
      final boost = await aggregator.getBoost(
        symbol: _selectedSymbol,
        mlDirection: _lastPrediction!.action,
        mlConfidence: _lastPrediction!.confidence,
        priceChange24h: _lastPrediction!.atr != null ? _lastPrediction!.atr! * 100 : null,
        volumeChange24h: null,
      );

      if (mounted) {
        setState(() {
          _marketIntelligence = boost;
        });
      }
    } catch (e) {
      debugPrint('Error loading market intelligence: $e');
    }
  }

  List<String> _buildPairs() {
    if (_availableCoins.isEmpty) {
      // Fallback while loading - use TOP 10 from UserCoinsService
      final q = AppSettingsService().quoteCurrency.toUpperCase();
      return UserCoinsService.defaultCoins.map((b) => '$b$q').toList();
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
                      color: Theme.of(context).colorScheme.onSurface,
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
      physics: const ClampingScrollPhysics(),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.all(AppTheme.spacing20),
          sliver: SliverList(
            delegate: SliverChildListDelegate([

              // Symbol & Interval Selector
              _buildSymbolSelector(),
              const SizedBox(height: AppTheme.spacing16),

              // AI Prediction Card
              _buildPredictionCard(),
              const SizedBox(height: AppTheme.spacing16),


              // Model Contributions / AI Technical Analysis
              if (_lastPrediction != null && _interval != '1w')
                _buildModelContributions(),

              // Market Intelligence Card
              _buildMarketIntelligenceCard(),

              // Upgrade to Premium CTA (FREE mode only, NOT during trial)
              Consumer<SubscriptionProvider>(
                builder: (context, subscription, _) {
                  // Only show if user is NOT pro AND NOT in trial
                  if (!subscription.isProUser) {
                    return Column(
                      children: [
                        const SizedBox(height: AppTheme.spacing16),
                        _buildUpgradeToPremiumCTA(),
                      ],
                    );
                  }
                  return const SizedBox.shrink();
                },
              ),
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
              value: _buildPairs().contains(_selectedSymbol)
                  ? _selectedSymbol
                  : (_buildPairs().isNotEmpty ? _buildPairs().first : 'BTCUSDT'),
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
                setState(() {
                  _selectedSymbol = v;
                  // Reset price tracking when switching symbols to avoid -100% error
                  _previousPrice = null;
                  _previousAtr = null;
                });
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
                  {'label': isProUser ? '4H' : '4H 🔒', 'value': '4h'},
                  {'label': isProUser ? '1D' : '1D 🔒', 'value': '1d'},
                ].map((item) {
                  final bool selected = _interval == item['value'];
                  final bool isLocked = !isProUser;

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
                      color: AppTheme.warning.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(AppTheme.radiusMD),
                      border: Border.all(color: AppTheme.warning.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline, color: AppTheme.warning, size: 18),
                        const SizedBox(width: AppTheme.spacing8),
                        Expanded(
                          child: Text(
                            '🔒 AI Predictions require Premium subscription. Upgrade to unlock all timeframes and get intelligent market insights.',
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

    // Apply Market Intelligence boost to confidence (if available)
    final finalConfidence = _marketIntelligence != null
        ? _marketIntelligence!.applyBoost(prediction.confidence)
        : prediction.confidence;

    // Convert trading terminology to educational/market sentiment terminology
    final displayAction = action == 'BUY' ? 'BULLISH' : (action == 'SELL' ? 'BEARISH' : 'NEUTRAL');

    final isBullish = action == 'BUY';
    final isBearish = action == 'SELL';
    final signalColor = isBullish ? AppTheme.buyGreen : (isBearish ? AppTheme.sellRed : const Color(0xFFFF9500));

    return GlassCard(
      child: Column(
        children: [
          // Signal Icon & Label
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: signalColor.withValues(alpha: 0.2),
              shape: BoxShape.circle,
              border: Border.all(color: signalColor, width: 2),
            ),
            child: Icon(
              isBullish ? Icons.trending_up : (isBearish ? Icons.trending_down : Icons.drag_handle),
              color: signalColor,
              size: 40,
            ),
          ),
          const SizedBox(height: AppTheme.spacing16),
          Text(
            displayAction,
            style: AppTheme.displayMedium.copyWith(color: signalColor, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: AppTheme.spacing8),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppTheme.spacing16,
              vertical: AppTheme.spacing8,
            ),
            decoration: BoxDecoration(
              gradient: isBullish
                  ? AppTheme.buyGradient
                  : (isBearish
                      ? AppTheme.sellGradient
                      : const LinearGradient(colors: [Color(0xFFFF9500), Color(0xFFFF7A00)])),
              borderRadius: BorderRadius.circular(AppTheme.radiusSM),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Confidence: ${(finalConfidence * 100).toStringAsFixed(1)}%',
                  style: AppTheme.headingMedium.copyWith(color: Colors.white),
                ),
                // Show boost indicator if Market Intelligence enhanced the confidence
                if (_marketIntelligence != null && _marketIntelligence!.confidenceBoost != 0) ...[
                  const SizedBox(width: AppTheme.spacing8),
                  Icon(
                    Icons.auto_awesome,
                    size: 18,
                    color: Colors.white.withValues(alpha: 0.9),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: AppTheme.spacing16),

          // Last Updated timestamp with live indicator and ATR trend
          _buildLiveUpdateIndicator(prediction),

          const SizedBox(height: AppTheme.spacing12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'AI Analysis',
                style: AppTheme.bodySmall.copyWith(color: AppTheme.textTertiary),
              ),
              if (prediction.atr != null && prediction.volumePercentile != null) ...[
                const SizedBox(width: AppTheme.spacing8),
                _buildMarketActivityIndicator(
                  atr: prediction.atr!,
                  volumePercentile: prediction.volumePercentile!,
                ),
              ],
            ],
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

          // Decision Reason (Phase 4)
          if (prediction.decisionReason != null) ...[
            const SizedBox(height: AppTheme.spacing16),
            Container(
              padding: const EdgeInsets.all(AppTheme.spacing12),
              decoration: BoxDecoration(
                color: (Theme.of(context).brightness == Brightness.dark
                    ? AppTheme.glassWhite
                    : Colors.grey[100]),
                borderRadius: BorderRadius.circular(AppTheme.radiusSM),
                border: Border.all(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? AppTheme.glassBorder
                      : Colors.grey[300]!,
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.lightbulb_outline,
                    size: 16,
                    color: AppTheme.primary.withValues(alpha: 0.8),
                  ),
                  const SizedBox(width: AppTheme.spacing8),
                  Expanded(
                    child: Text(
                      prediction.decisionReason!,
                      style: AppTheme.bodySmall.copyWith(
                        color: AppTheme.textSecondary,
                        fontStyle: FontStyle.italic,
                        height: 1.4,
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

  /// Build live update indicator with timestamp and ATR trend
  Widget _buildLiveUpdateIndicator(CryptoPrediction prediction) {
    if (_lastUpdateTime == null) return const SizedBox.shrink();

    // Calculate time since last update
    final now = DateTime.now();
    final diff = now.difference(_lastUpdateTime!);
    String timeAgo;
    if (diff.inSeconds < 60) {
      timeAgo = 'Just now';
    } else if (diff.inMinutes < 60) {
      timeAgo = '${diff.inMinutes}m ago';
    } else if (diff.inHours < 24) {
      timeAgo = '${diff.inHours}h ago';
    } else {
      timeAgo = '${diff.inDays}d ago';
    }

    // Determine ATR trend
    String atrTrend = '';
    Color? atrTrendColor;
    IconData? atrTrendIcon;
    if (prediction.atr != null && _previousAtr != null) {
      final atrChange = prediction.atr! - _previousAtr!;
      final atrChangePercent = (atrChange / _previousAtr!) * 100;

      if (atrChangePercent.abs() > 5) { // Only show if change > 5%
        if (atrChange > 0) {
          atrTrend = '+${atrChangePercent.toStringAsFixed(1)}%';
          atrTrendColor = AppTheme.sellRed; // Higher volatility = red
          atrTrendIcon = Icons.trending_up;
        } else {
          atrTrend = '${atrChangePercent.toStringAsFixed(1)}%';
          atrTrendColor = AppTheme.buyGreen; // Lower volatility = green (calmer)
          atrTrendIcon = Icons.trending_down;
        }
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacing12,
        vertical: AppTheme.spacing8,
      ),
      decoration: BoxDecoration(
        color: AppTheme.glassWhite,
        borderRadius: BorderRadius.circular(AppTheme.radiusSM),
        border: Border.all(color: AppTheme.glassBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Pulsing live indicator
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.3, end: 1.0),
            duration: const Duration(milliseconds: 1500),
            curve: Curves.easeInOut,
            builder: (context, value, child) {
              return Opacity(
                opacity: value,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: AppTheme.success,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.success.withValues(alpha: 0.5),
                        blurRadius: 4,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                ),
              );
            },
            onEnd: () {
              // Restart animation if mounted
              if (mounted) {
                setState(() {});
              }
            },
          ),
          const SizedBox(width: AppTheme.spacing8),
          Icon(Icons.schedule, size: 14, color: AppTheme.textTertiary),
          const SizedBox(width: AppTheme.spacing4),
          Flexible(
            child: Text(
              'Updated $timeAgo',
              style: AppTheme.bodySmall.copyWith(
                color: AppTheme.textTertiary,
                fontSize: 12,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),

          // ATR trend indicator (if significant change)
          if (atrTrend.isNotEmpty) ...[
            const SizedBox(width: AppTheme.spacing4),
            Flexible(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppTheme.spacing8,
                  vertical: AppTheme.spacing4,
                ),
                decoration: BoxDecoration(
                  color: atrTrendColor!.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(AppTheme.radiusSM),
                  border: Border.all(color: atrTrendColor.withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(atrTrendIcon, size: 12, color: atrTrendColor),
                    const SizedBox(width: AppTheme.spacing4),
                    Flexible(
                      child: Text(
                        'Vol $atrTrend',
                        style: AppTheme.bodySmall.copyWith(
                          color: atrTrendColor,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Build market activity indicator based on ATR and volume
  Widget _buildMarketActivityIndicator({required double atr, required double volumePercentile}) {
    // Determine market activity level
    String activityLabel;
    Color activityColor;
    IconData activityIcon;

    // High activity: high volatility OR high volume
    // Normal activity: medium volatility AND medium volume
    // Quiet activity: low volatility AND low volume
    if (atr > 0.025 || volumePercentile > 0.70) {
      activityLabel = 'Active';
      activityColor = AppTheme.success;
      activityIcon = Icons.whatshot;
    } else if (atr < 0.015 && volumePercentile < 0.30) {
      activityLabel = 'Quiet';
      activityColor = AppTheme.textTertiary;
      activityIcon = Icons.bedtime;
    } else {
      activityLabel = 'Normal';
      activityColor = Colors.blue;
      activityIcon = Icons.wb_sunny_outlined;
    }

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacing8,
        vertical: AppTheme.spacing4,
      ),
      decoration: BoxDecoration(
        color: activityColor.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(AppTheme.radiusSM),
        border: Border.all(color: activityColor.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(activityIcon, size: 12, color: activityColor),
          const SizedBox(width: AppTheme.spacing4),
          Text(
            activityLabel,
            style: AppTheme.bodySmall.copyWith(
              color: activityColor,
              fontSize: 11,
              fontWeight: FontWeight.w600,
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
    final coinName = coin.replaceAll(RegExp(r'(USDT|USDC|BUSD|USD|EUR|BTC)$'), '');
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
      buffer.write('Bullish and bearish indicators are nearly balanced (${(buyProb * 100).toStringAsFixed(1)}% vs ${(sellProb * 100).toStringAsFixed(1)}%), indicating market indecision. ');
    } else if (sellProb > buyProb) {
      buffer.write('Slight bearish bias observed (${(sellProb * 100).toStringAsFixed(1)}% vs ${(buyProb * 100).toStringAsFixed(1)}% bullish), but not strong enough for clear directional signal. ');
    } else {
      buffer.write('Slight bullish bias observed (${(buyProb * 100).toStringAsFixed(1)}% vs ${(sellProb * 100).toStringAsFixed(1)}% bearish), but confidence remains below threshold. ');
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
    Color bgColor = Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5);
    
    // For Volatility badge
    if (label == 'Volatility') {
      final atrValue = double.tryParse(value.replaceAll('%', '')) ?? 0.0;
      if (atrValue >= 4.0) {
        displayLabel = 'High ($value)';
        color = AppTheme.sellRed;
        bgColor = AppTheme.sellRed.withValues(alpha: 0.15);
      } else if (atrValue >= 2.5) {
        displayLabel = 'Elevated ($value)';
        color = const Color(0xFFFF9500);
        bgColor = const Color(0xFFFF9500).withValues(alpha: 0.15);
      } else if (atrValue >= 1.5) {
        displayLabel = 'Normal ($value)';
        color = Colors.blue;
        bgColor = Colors.blue.withValues(alpha: 0.15);
      } else {
        displayLabel = 'Calm ($value)';
        color = AppTheme.success;
        bgColor = AppTheme.success.withValues(alpha: 0.15);
      }
    }
    // For Liquidity badge
    else if (label == 'Liquidity') {
      final volValue = double.tryParse(value.replaceAll('%', '')) ?? 0.0;
      if (volValue >= 70) {
        displayLabel = 'High ($value)';
        color = AppTheme.success;
        bgColor = AppTheme.success.withValues(alpha: 0.15);
      } else if (volValue >= 40) {
        displayLabel = 'Medium ($value)';
        color = Colors.blue;
        bgColor = Colors.blue.withValues(alpha: 0.15);
      } else if (volValue >= 15) {
        displayLabel = 'Low ($value)';
        color = AppTheme.textSecondary;
        bgColor = Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5);
      } else {
        displayLabel = 'Very Low ($value)';
        color = AppTheme.textSecondary;
        bgColor = Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5);
      }
    }
    
    return Tooltip(
      message: tooltipMessage,
      padding: const EdgeInsets.all(AppTheme.spacing12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusMD),
        border: Border.all(color: color.withValues(alpha: 0.5)),
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
            color: color.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 16),
            const SizedBox(width: AppTheme.spacing4),
            Flexible(
              child: Text(
                '$label: ',
                style: AppTheme.bodySmall.copyWith(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7)),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Flexible(
              child: Text(
                displayLabel,
                style: AppTheme.bodySmall.copyWith(
                  color: color,
                  fontWeight: FontWeight.bold,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }


  Widget _buildModelContributions() {
    final prediction = _lastPrediction!;

    // Determine which signal to show based on prediction label
    final isBullish = prediction.action == 'BUY';
    final isBearish = prediction.action == 'SELL';

    // CryptoPrediction uses Map<String, double> for probabilities
    final bearishProb = prediction.probabilities['SELL'] ?? 0.0;
    final neutralProb = prediction.probabilities['HOLD'] ?? 0.0;
    final bullishProb = prediction.probabilities['BUY'] ?? 0.0;

    // FIXED: Use overall confidence (not individual probability)
    final overallConfidence = prediction.confidence;

    String signalLabel;
    Color signalColor;
    IconData signalIcon;
    String signalDescription;

    if (isBullish) {
      signalLabel = 'Bullish Momentum';
      signalColor = AppTheme.buyGreen;
      signalIcon = Icons.trending_up;
      signalDescription = _buildBullishExplanation(bullishProb, bearishProb, neutralProb, overallConfidence);
    } else if (isBearish) {
      signalLabel = 'Bearish Momentum';
      signalColor = AppTheme.sellRed;
      signalIcon = Icons.trending_down;
      signalDescription = _buildBearishExplanation(bearishProb, bullishProb, neutralProb, overallConfidence);
    } else {
      signalLabel = 'Neutral Market';
      signalColor = AppTheme.holdYellow;
      signalIcon = Icons.pause;
      // PHASE 4: Dynamic HOLD explanation based on coin + ATR + volume
      signalDescription = _generateHoldExplanation(
        coin: _selectedSymbol,
        timeframe: _interval,
        atr: prediction.atr,
        volumePercentile: prediction.volumePercentile,
        sellProb: bearishProb,
        buyProb: bullishProb,
      );
    }

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.psychology_outlined, color: AppTheme.primary, size: 20),
              const SizedBox(width: AppTheme.spacing8),
              Expanded(
                child: Text('🤖 Ensemble AI Engine', style: AppTheme.headingMedium),
              ),
            ],
          ),
          const SizedBox(height: AppTheme.spacing12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.auto_awesome, color: AppTheme.primary.withValues(alpha: 0.8), size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Multi-timeframe deep learning analysis across 76+ technical features',
                      style: AppTheme.bodySmall.copyWith(
                        color: AppTheme.textSecondary,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppTheme.spacing8),
              Row(
                children: [
                  Icon(Icons.flash_on, color: AppTheme.primary.withValues(alpha: 0.8), size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Real-time pattern detection: candlesticks, momentum, and volume analysis',
                      style: AppTheme.bodySmall.copyWith(
                        color: AppTheme.textSecondary,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppTheme.spacing8),
              Row(
                children: [
                  Icon(Icons.hub_outlined, color: AppTheme.primary.withValues(alpha: 0.8), size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Smart decision fusion: combines 5 specialized models with dynamic weighting',
                      style: AppTheme.bodySmall.copyWith(
                        color: AppTheme.textSecondary,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: AppTheme.spacing20),

          // Show only the active signal with OVERALL CONFIDENCE
          _buildSignalCard(
            signalLabel,
            overallConfidence, // FIXED: Use overall confidence
            signalColor,
            signalIcon,
            signalDescription,
          ),
        ],
      ),
    );
  }

  /// Build explanation for BULLISH signal with probability breakdown
  String _buildBullishExplanation(double bullishProb, double bearishProb, double neutralProb, double confidence) {
    final buffer = StringBuffer();
    buffer.write('Technical analysis shows positive momentum. ');
    buffer.write('AI model assigns ${(bullishProb * 100).toStringAsFixed(1)}% bullish, ');
    buffer.write('${(bearishProb * 100).toStringAsFixed(1)}% bearish, ');
    buffer.write('${(neutralProb * 100).toStringAsFixed(1)}% neutral probability. ');
    buffer.write('After analyzing RSI recovery, MACD golden cross pattern, volume trends, and ${(76 - 3)} other indicators, ');
    buffer.write('the model reaches ${(confidence * 100).toStringAsFixed(1)}% confidence in this bullish signal.');
    return buffer.toString();
  }

  /// Build explanation for BEARISH signal with probability breakdown
  String _buildBearishExplanation(double bearishProb, double bullishProb, double neutralProb, double confidence) {
    final buffer = StringBuffer();
    buffer.write('Technical analysis shows negative momentum. ');
    buffer.write('AI model assigns ${(bearishProb * 100).toStringAsFixed(1)}% bearish, ');
    buffer.write('${(bullishProb * 100).toStringAsFixed(1)}% bullish, ');
    buffer.write('${(neutralProb * 100).toStringAsFixed(1)}% neutral probability. ');
    buffer.write('After analyzing RSI divergence, MACD downturn, volume decline, and ${(76 - 3)} other indicators, ');
    buffer.write('the model reaches ${(confidence * 100).toStringAsFixed(1)}% confidence in this bearish signal.');
    return buffer.toString();
  }

  Widget _buildSignalCard(String label, double probability, Color color, IconData icon, String description) {
    return Container(
      padding: const EdgeInsets.all(AppTheme.spacing12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppTheme.radiusMD),
        border: Border.all(
          color: color.withValues(alpha: 0.3),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, color: color, size: 20),
                    const SizedBox(width: AppTheme.spacing8),
                    Flexible(
                      child: Text(
                        label,
                        style: AppTheme.bodyLarge.copyWith(
                          color: color,
                          fontWeight: FontWeight.bold,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppTheme.spacing8),
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
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.white
                        : (color == AppTheme.holdYellow ? Colors.black : Colors.white),
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
              color: AppTheme.getTextSecondary(context),
              height: 1.4,
            ),
          ),
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
              AppTheme.primary.withValues(alpha: 0.1),
              AppTheme.secondary.withValues(alpha: 0.1),
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

  Widget _buildMarketIntelligenceCard() {
    if (_marketIntelligence == null) return const SizedBox.shrink();

    final boost = _marketIntelligence!;

    // Determine boost color
    final boostColor = boost.confidenceBoost > 0
        ? AppTheme.buyGreen
        : boost.confidenceBoost < 0
            ? AppTheme.sellRed
            : AppTheme.textSecondary;

    // Fear & Greed color
    final fearGreedColor = boost.fearGreedValue < 25
        ? AppTheme.sellRed
        : boost.fearGreedValue > 75
            ? AppTheme.buyGreen
            : AppTheme.holdYellow;

    return GlassCard(
      padding: const EdgeInsets.all(AppTheme.spacing20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with boost badge
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(AppTheme.spacing8),
                    decoration: BoxDecoration(
                      gradient: AppTheme.primaryGradient,
                      borderRadius: BorderRadius.circular(AppTheme.radiusSM),
                    ),
                    child: const Icon(
                      Icons.insights,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: AppTheme.spacing12),
                  Text(
                    'Market Intelligence',
                    style: AppTheme.headingSmall.copyWith(
                      color: AppTheme.getTextPrimary(context),
                    ),
                  ),
                ],
              ),
              if (boost.confidenceBoost != 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppTheme.spacing12,
                    vertical: AppTheme.spacing4,
                  ),
                  decoration: BoxDecoration(
                    color: boostColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(AppTheme.radiusFull),
                    border: Border.all(
                      color: boostColor.withValues(alpha: 0.3),
                      width: 1,
                    ),
                  ),
                  child: Text(
                    '${boost.confidenceBoost > 0 ? '+' : ''}${boost.confidenceBoost}%',
                    style: AppTheme.labelMedium.copyWith(
                      color: boostColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),

          const SizedBox(height: AppTheme.spacing20),

          // Metrics Grid
          _buildMetricRow(
            context,
            icon: Icons.psychology,
            iconColor: fearGreedColor,
            label: 'Fear & Greed Index',
            value: '${boost.fearGreedValue}/100',
            subtitle: boost.fearGreedLevel,
          ),

          const SizedBox(height: AppTheme.spacing16),

          _buildMetricRow(
            context,
            icon: Icons.article_outlined,
            iconColor: boost.newsSentiment == 'Bullish'
                ? AppTheme.buyGreen
                : boost.newsSentiment == 'Bearish'
                    ? AppTheme.sellRed
                    : AppTheme.textSecondary,
            label: 'News Sentiment',
            value: boost.newsSentiment,
            subtitle: '${(boost.newsSentimentScore * 100).toStringAsFixed(1)}% score',
          ),

          const SizedBox(height: AppTheme.spacing16),

          _buildMetricRow(
            context,
            icon: Icons.public,
            iconColor: boost.globalMarketTrend == 'bullish'
                ? AppTheme.buyGreen
                : boost.globalMarketTrend == 'bearish'
                    ? AppTheme.sellRed
                    : AppTheme.textSecondary,
            label: 'Global Market',
            value: '\$${(boost.globalMarketCap / 1e12).toStringAsFixed(2)}T',
            subtitle: '${boost.globalMarketCapChange24h >= 0 ? '+' : ''}${boost.globalMarketCapChange24h.toStringAsFixed(2)}% (${boost.globalMarketTrend})',
          ),

          // Multi-Exchange Section
          if (boost.multiExchangePrices.isNotEmpty) ...[
            const SizedBox(height: AppTheme.spacing16),
            _buildMetricRow(
              context,
              icon: Icons.compare_arrows,
              iconColor: AppTheme.info,
              label: 'Price Spread',
              value: '${(boost.priceSpread * 100).toStringAsFixed(3)}%',
              subtitle: '${boost.multiExchangePrices.length} exchanges',
            ),
          ],

          // Analysis Section
          if (boost.reasonsForBoost.isNotEmpty) ...[
            const SizedBox(height: AppTheme.spacing20),
            const Divider(height: 1),
            const SizedBox(height: AppTheme.spacing16),

            Row(
              children: [
                Icon(
                  Icons.lightbulb_outline,
                  size: 16,
                  color: AppTheme.getTextSecondary(context),
                ),
                const SizedBox(width: AppTheme.spacing8),
                Text(
                  'Analysis',
                  style: AppTheme.labelLarge.copyWith(
                    color: AppTheme.getTextPrimary(context),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppTheme.spacing12),
            ...boost.reasonsForBoost.map((reason) => Padding(
              padding: const EdgeInsets.only(bottom: AppTheme.spacing8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '• ',
                    style: AppTheme.bodySmall.copyWith(
                      color: AppTheme.getTextSecondary(context),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      reason,
                      style: AppTheme.bodySmall.copyWith(
                        color: AppTheme.getTextSecondary(context),
                      ),
                    ),
                  ),
                ],
              ),
            )),
          ],

          // Enhanced Confidence Section
          if (_lastPrediction != null && boost.confidenceBoost != 0) ...[
            const SizedBox(height: AppTheme.spacing16),
            const Divider(height: 1),
            const SizedBox(height: AppTheme.spacing16),

            Container(
              padding: const EdgeInsets.all(AppTheme.spacing12),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    boostColor.withValues(alpha: 0.1),
                    boostColor.withValues(alpha: 0.05),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(AppTheme.radiusMD),
                border: Border.all(
                  color: boostColor.withValues(alpha: 0.2),
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Original Confidence',
                        style: AppTheme.labelSmall.copyWith(
                          color: AppTheme.getTextTertiary(context),
                        ),
                      ),
                      const SizedBox(height: AppTheme.spacing4),
                      Text(
                        '${(_lastPrediction!.confidence * 100).toStringAsFixed(1)}%',
                        style: AppTheme.labelLarge.copyWith(
                          color: AppTheme.getTextPrimary(context),
                        ),
                      ),
                    ],
                  ),
                  Icon(
                    Icons.arrow_forward,
                    size: 20,
                    color: AppTheme.getTextTertiary(context),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Row(
                        children: [
                          Text(
                            'Enhanced',
                            style: AppTheme.labelSmall.copyWith(
                              color: AppTheme.getTextTertiary(context),
                            ),
                          ),
                          const SizedBox(width: AppTheme.spacing4),
                          Icon(
                            Icons.auto_awesome,
                            size: 12,
                            color: boostColor,
                          ),
                        ],
                      ),
                      const SizedBox(height: AppTheme.spacing4),
                      Text(
                        '${(boost.applyBoost(_lastPrediction!.confidence) * 100).toStringAsFixed(1)}%',
                        style: AppTheme.labelLarge.copyWith(
                          color: boostColor,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMetricRow(
    BuildContext context, {
    required IconData icon,
    required Color iconColor,
    required String label,
    required String value,
    String? subtitle,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(AppTheme.spacing8),
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(AppTheme.radiusSM),
          ),
          child: Icon(
            icon,
            size: 18,
            color: iconColor,
          ),
        ),
        const SizedBox(width: AppTheme.spacing12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: AppTheme.labelSmall.copyWith(
                  color: AppTheme.getTextTertiary(context),
                ),
              ),
              const SizedBox(height: AppTheme.spacing4),
              Text(
                value,
                style: AppTheme.bodyMedium.copyWith(
                  color: AppTheme.getTextPrimary(context),
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: AppTheme.spacing4),
                Text(
                  subtitle,
                  style: AppTheme.bodySmall.copyWith(
                    color: AppTheme.getTextSecondary(context),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

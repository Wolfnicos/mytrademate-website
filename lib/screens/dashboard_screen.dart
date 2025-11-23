import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/app_settings_service.dart';
import '../services/user_coins_service.dart';
import '../providers/subscription_provider.dart';
import '../providers/exchange_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_card.dart';
import '../widgets/ai_indicator.dart';
import '../widgets/crypto_avatar.dart';
import '../widgets/trial_banner.dart';
import '../widgets/trial_activation_dialog.dart';
import '../ml/ensemble_predictor.dart';
import '../utils/responsive.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  @override
  void initState() {
    super.initState();
    // Show trial dialog on first app launch (48h free trial)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeShowTrialDialog();
    });
    // Listen to quote currency changes and rebuild all tiles
    AppSettingsService().addListener(_onSettingsChanged);

    // Listen to exchange changes and rebuild dashboard
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        Provider.of<ExchangeProvider>(context, listen: false).addListener(_onExchangeChanged);
      }
    });
  }

  @override
  void dispose() {
    AppSettingsService().removeListener(_onSettingsChanged);
    try {
      Provider.of<ExchangeProvider>(context, listen: false).removeListener(_onExchangeChanged);
    } catch (e) {
      // Ignore if provider not available
    }
    super.dispose();
  }

  void _onSettingsChanged() {
    // Rebuild dashboard when quote currency changes
    debugPrint('Dashboard: Quote currency changed, rebuilding tiles...');
    if (mounted) {
      setState(() {
        // Force rebuild of all dashboard tiles with new quote currency
      });
    }
  }

  void _onExchangeChanged() {
    // Rebuild dashboard when exchange changes
    debugPrint('Dashboard: Exchange changed, rebuilding dashboard...');
    if (mounted) {
      setState(() {
        // Force rebuild of all dashboard tiles with new exchange
      });
    }
  }

  Future<void> _maybeShowTrialDialog() async {
    if (!mounted) return;

    final settings = AppSettingsService();
    if (settings.shouldShowTrialDialog) {
      final accepted = await TrialActivationDialog.show(context);
      if (accepted) {
        await settings.activateTrial();
        // Notify SubscriptionProvider to rebuild UI (hide upgrade banners)
        if (mounted) {
          Provider.of<SubscriptionProvider>(context, listen: false).notifyListeners();
        }
      } else {
        await settings.declineTrial();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: SafeArea(
        child: Responsive.constrainWidth(
          context,
          CustomScrollView(
          physics: const ClampingScrollPhysics(),
          slivers: [
            // Header
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppTheme.spacing20,
                  AppTheme.spacing24,
                  AppTheme.spacing20,
                  AppTheme.spacing16,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Title with AI Indicator
                    Row(
                      children: [
                        Text(
                          'Dashboard',
                          style: AppTheme.displayLarge.copyWith(
                            color: Theme.of(context).colorScheme.onBackground,
                          ),
                        ),
                        const SizedBox(width: AppTheme.spacing12),
                        AIIndicator(
                          isActive: globalEnsemblePredictor.isLoaded,
                          isLoading: !globalEnsemblePredictor.isLoaded,
                          label: 'AI Active',
                        ),
                      ],
                    ),
                    const SizedBox(height: AppTheme.spacing8),
                    Text(
                      'Welcome back to MyTradeMate',
                      style: AppTheme.bodyMedium.copyWith(
                        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.75),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Trial Banner (shows only if in trial)
            const SliverToBoxAdapter(
              child: TrialBanner(),
            ),

            // Content
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacing20),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  const SizedBox(height: AppTheme.spacing16),

                  // Portfolio Overview Card
                  Consumer<ExchangeProvider>(
                    builder: (context, exchangeProvider, _) => RepaintBoundary(
                      key: ValueKey('portfolio_${exchangeProvider.selectedExchange}_${AppSettingsService().quoteCurrency}'),
                      child: PortfolioOverviewCard(),
                    ),
                  ),

                  const SizedBox(height: AppTheme.spacing16),

                  // AI Models Status Card
                  RepaintBoundary(
                    key: ValueKey('ai_models_${AppSettingsService().quoteCurrency}'),
                    child: const AIModelsStatusCard(),
                  ),

                  const SizedBox(height: AppTheme.spacing16),

                  // P&L Today Section
                  RepaintBoundary(
                    key: ValueKey('pnl_${AppSettingsService().quoteCurrency}'),
                    child: const PnLTodaySection(),
                  ),

                  const SizedBox(height: AppTheme.spacing32),
                ]),
              ),
            ),
          ],
        ),
        ),
      ),
    );
  }
}

class PortfolioOverviewCard extends StatefulWidget {
  const PortfolioOverviewCard({super.key});

  @override
  State<PortfolioOverviewCard> createState() => _PortfolioOverviewCardState();
}

class _PortfolioOverviewCardState extends State<PortfolioOverviewCard> {
  // bool _isLoading = false; // Unused - commented out
  double _totalValue = 0.0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadCachedValue();
    _loadPortfolio();

    // Listen to exchange changes and reload portfolio (same as Portfolio screen)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        Provider.of<ExchangeProvider>(context, listen: false).addListener(_onExchangeChanged);
      }
    });
  }

  @override
  void dispose() {
    try {
      Provider.of<ExchangeProvider>(context, listen: false).removeListener(_onExchangeChanged);
    } catch (e) {
      // Ignore if provider not available
    }
    super.dispose();
  }

  void _onExchangeChanged() {
    // Exchange changed - load new exchange's cached value and reload
    debugPrint('[PortfolioOverview] 📢 Exchange changed listener triggered');
    debugPrint('[PortfolioOverview] 🔄 Reloading portfolio overview...');
    if (mounted) {
      setState(() {
        _totalValue = 0.0; // Clear old cached value immediately
        // _isLoading = true; // Unused - commented out
      });
      _loadCachedValue(); // Load cached value for new exchange
      _loadPortfolio(); // Then load fresh data
    } else {
      debugPrint('[PortfolioOverview] ⚠️  Widget not mounted, skipping reload');
    }
  }

  Future<void> _loadCachedValue() async {
    // Load cached value immediately for instant display
    // Include exchange name in cache key to avoid showing wrong exchange data
    final exchangeProvider = Provider.of<ExchangeProvider>(context, listen: false);
    final exchangeName = exchangeProvider.selectedExchange;

    final prefs = await SharedPreferences.getInstance();
    final cacheKey = 'portfolio_total_value_$exchangeName';
    final cachedValue = prefs.getDouble(cacheKey);

    if (cachedValue != null && mounted) {
      setState(() {
        _totalValue = cachedValue;
      });
    }
  }

  Future<void> _loadPortfolio() async {
    // Don't show loading state, just update in background
    _error = null;

    try {
      final exchangeProvider = Provider.of<ExchangeProvider>(context, listen: false);
      final exchange = exchangeProvider.currentExchange;

      await exchange.loadCredentials();
      final balances = await exchange.getAccountBalances();
      final quote = AppSettingsService().quoteCurrency.toUpperCase();

      double total = 0.0;

      // Add quote currency balance directly (EUR, USD, USDT, USDC)
      total += balances[quote] ?? 0.0;

      // Convert other assets to quote currency
      for (final entry in balances.entries) {
        final asset = entry.key;
        final amount = entry.value;

        if (asset == quote) continue; // Already added

        try {
          // Try to get price for this asset in quote currency
          final ticker = await exchange.fetchTicker24hWithFallback([
            '$asset$quote',
            '${asset}USDT',
            '${asset}EUR',
            '${asset}USDC'
          ]);
          final price = ticker['lastPrice'] ?? 0.0;
          total += amount * price;
        } catch (e) {
          debugPrint('[PortfolioOverview] Could not get price for $asset: $e');
        }
      }

      if (mounted) {
        setState(() {
          _totalValue = total;
          // _isLoading = false; // Unused - commented out
        });

        // Cache the value for instant display next time
        // Include exchange name in cache key to avoid mixing data between exchanges
        final cacheKey = 'portfolio_total_value_${exchange.exchangeName}';
        final prefs = await SharedPreferences.getInstance();
        await prefs.setDouble(cacheKey, total);
      }
    } catch (e) {
      debugPrint('[PortfolioOverview] Error loading portfolio: $e');
      if (mounted) {
        setState(() {
          _error = 'Failed to load portfolio';
          // _isLoading = false; // Unused - commented out
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(AppTheme.spacing8),
                decoration: BoxDecoration(
                  gradient: AppTheme.primaryGradient,
                  borderRadius: BorderRadius.circular(AppTheme.radiusMD),
                ),
                child: const Icon(
                  Icons.account_balance_wallet,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: AppTheme.spacing12),
              Text(
                'Portfolio Overview',
                style: AppTheme.headingMedium,
              ),
            ],
          ),

          const SizedBox(height: AppTheme.spacing20),

          // Total Value
          Text(
            'Total Value',
            style: AppTheme.bodySmall.copyWith(
              color: AppTheme.textTertiary,
              textBaseline: TextBaseline.alphabetic,
            ),
          ),
          const SizedBox(height: AppTheme.spacing4),

          if (_error != null)
            Text(
              _error!,
              style: AppTheme.bodyMedium.copyWith(color: AppTheme.error),
            )
          else
            Text(
              '${AppSettingsService.currencyPrefix(AppSettingsService().quoteCurrency)}${_totalValue.toStringAsFixed(2)}',
              style: AppTheme.monoLarge,
            ),

          const SizedBox(height: AppTheme.spacing16),

          // Daily P&L - Hidden for now (requires historical data)
          Container(
            padding: const EdgeInsets.all(AppTheme.spacing12),
            decoration: BoxDecoration(
              color: AppTheme.glassWhite,
              borderRadius: BorderRadius.circular(AppTheme.radiusMD),
              border: Border.all(
                color: AppTheme.glassBorder,
                width: 1,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.info_outline,
                  color: AppTheme.textTertiary,
                  size: 16,
                ),
                const SizedBox(width: AppTheme.spacing8),
                Text(
                  'Live portfolio value',
                  style: AppTheme.bodySmall.copyWith(
                    color: AppTheme.textTertiary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// AI Neural Engine - Modern 2025 Design
class AIModelsStatusCard extends StatefulWidget {
  const AIModelsStatusCard({super.key});

  @override
  State<AIModelsStatusCard> createState() => _AIModelsStatusCardState();
}

class _AIModelsStatusCardState extends State<AIModelsStatusCard> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _pulseAnimation;
  int _progressKey = 0;
  // bool _hasLoadedOnce = false;  // Unused - commented out
  bool _isLoaded = false;

  @override
  void initState() {
    super.initState();

    // Pulsing animation for brain icon
    _controller = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.8, end: 1.2).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );

    // Check if models are loaded periodically
    _checkModelsLoaded();
  }

  void _checkModelsLoaded() {
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        final isLoaded = globalEnsemblePredictor.isLoaded;
        if (isLoaded != _isLoaded) {
          setState(() {
            _isLoaded = isLoaded;
          });
        }
        if (!isLoaded) {
          _checkModelsLoaded();
        }
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isActive = _isLoaded;

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Neural Engine Header with animated brain
          Row(
            children: [
              // Animated brain icon with gradient glow
              AnimatedBuilder(
                animation: _pulseAnimation,
                builder: (context, child) {
                  return Container(
                    padding: const EdgeInsets.all(AppTheme.spacing12),
                    decoration: BoxDecoration(
                      gradient: isActive
                          ? LinearGradient(
                              colors: [
                                AppTheme.primary.withOpacity(0.9),
                                AppTheme.secondary.withOpacity(0.9),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            )
                          : LinearGradient(
                              colors: [
                                AppTheme.textTertiary.withOpacity(0.5),
                                AppTheme.textTertiary.withOpacity(0.3),
                              ],
                            ),
                      borderRadius: BorderRadius.circular(AppTheme.radiusLG),
                      boxShadow: isActive
                          ? [
                              BoxShadow(
                                color: AppTheme.primary.withOpacity(0.4 * _pulseAnimation.value),
                                blurRadius: 16,
                                spreadRadius: 2,
                              ),
                            ]
                          : null,
                    ),
                    child: Transform.scale(
                      scale: isActive ? _pulseAnimation.value : 1.0,
                      child: const Icon(
                        Icons.psychology,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(width: AppTheme.spacing16),

              // Title and subtitle
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            'Neural Engine',
                            style: AppTheme.headingMedium.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: AppTheme.spacing8),
                        if (isActive)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppTheme.spacing8,
                              vertical: AppTheme.spacing4,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.success.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(AppTheme.radiusSM),
                              border: Border.all(
                                color: AppTheme.success,
                                width: 1,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 6,
                                  height: 6,
                                  decoration: BoxDecoration(
                                    color: AppTheme.success,
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: AppTheme.success,
                                        blurRadius: 4,
                                        spreadRadius: 1,
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: AppTheme.spacing4),
                                Text(
                                  'LIVE',
                                  style: AppTheme.bodySmall.copyWith(
                                    color: AppTheme.success,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 10,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: AppTheme.spacing4),
                    Text(
                      'Deep learning • 76 indicators',
                      style: AppTheme.bodySmall.copyWith(
                        color: AppTheme.textTertiary,
                        fontSize: 12,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: AppTheme.spacing20),

          // AI Processing Visualization
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppTheme.spacing16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isActive
                    ? [
                        AppTheme.primary.withOpacity(0.1),
                        AppTheme.secondary.withOpacity(0.05),
                      ]
                    : [
                        AppTheme.glassWhite,
                        AppTheme.glassWhite,
                      ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(AppTheme.radiusMD),
              border: Border.all(
                color: isActive
                    ? AppTheme.primary.withOpacity(0.3)
                    : AppTheme.glassBorder,
                width: 1.5,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isActive) ...[
                  // Neural Network Visualization Grid
                  Row(
                    children: [
                      Expanded(
                        child: _buildAIStatBox(
                          label: 'AI Models',
                          value: '26',
                          icon: Icons.memory,
                          color: AppTheme.primary,
                        ),
                      ),
                      const SizedBox(width: AppTheme.spacing12),
                      Expanded(
                        child: _buildAIStatBox(
                          label: 'Indicators',
                          value: '76',
                          icon: Icons.show_chart,
                          color: AppTheme.secondary,
                        ),
                      ),
                      const SizedBox(width: AppTheme.spacing12),
                      Expanded(
                        child: _buildAIStatBox(
                          label: 'Timeframes',
                          value: '5',
                          icon: Icons.access_time,
                          color: AppTheme.success,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppTheme.spacing16),

                  // Animated processing bar
                  TweenAnimationBuilder<double>(
                    key: ValueKey(_progressKey),
                    duration: const Duration(milliseconds: 2000),
                    curve: Curves.easeInOut,
                    tween: Tween<double>(begin: 0.0, end: 1.0),
                    onEnd: () {
                      if (mounted) {
                        setState(() {
                          _progressKey++;
                        });
                      }
                    },
                    builder: (context, value, _) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Processing market data...',
                                style: AppTheme.bodySmall.copyWith(
                                  color: AppTheme.textSecondary,
                                  fontSize: 11,
                                ),
                              ),
                              Text(
                                '${(value * 100).toInt()}%',
                                style: AppTheme.bodySmall.copyWith(
                                  color: AppTheme.primary,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: AppTheme.spacing8),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(AppTheme.radiusSM),
                            child: LinearProgressIndicator(
                              value: value,
                              backgroundColor: AppTheme.glassBorder,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                AppTheme.primary,
                              ),
                              minHeight: 4,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ] else ...[
                  Center(
                    child: Column(
                      children: [
                        CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation<Color>(
                            AppTheme.primary.withOpacity(0.5),
                          ),
                        ),
                        const SizedBox(height: AppTheme.spacing12),
                        Text(
                          'Initializing AI models...',
                          style: AppTheme.bodySmall.copyWith(
                            color: AppTheme.textTertiary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Widget _buildStatChip({ // UNUSED - commented out
  //   required IconData icon,
  //   required String label,
  //   required Color color,
  // }) {
  //   return Container(
  //     padding: const EdgeInsets.symmetric(
  //       horizontal: AppTheme.spacing8,
  //       vertical: AppTheme.spacing4,
  //     ),
  //     decoration: BoxDecoration(
  //       color: color.withOpacity(0.15),
  //       borderRadius: BorderRadius.circular(AppTheme.radiusSM),
  //     ),
  //     child: Row(
  //       mainAxisSize: MainAxisSize.min,
  //       children: [
  //         Icon(icon, size: 12, color: color),
  //         const SizedBox(width: AppTheme.spacing4),
  //         Text(
  //           label,
  //           style: AppTheme.bodySmall.copyWith(
  //             color: color,
  //             fontSize: 10,
  //             fontWeight: FontWeight.w600,
  //           ),
  //         ),
  //       ],
  //     ),
  //   );
  // }

  Widget _buildAIStatBox({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
  }) {
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
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: AppTheme.spacing8),
          Text(
            value,
            style: AppTheme.headingLarge.copyWith(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 24,
            ),
          ),
          const SizedBox(height: AppTheme.spacing4),
          Text(
            label,
            style: AppTheme.bodySmall.copyWith(
              color: AppTheme.textSecondary,
              fontSize: 11,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class PnLTodaySection extends StatefulWidget {
  const PnLTodaySection({super.key});

  @override
  State<PnLTodaySection> createState() => _PnLTodaySectionState();
}

class _PnLTodaySectionState extends State<PnLTodaySection> {
  List<String> _userCoins = []; // Dynamic coins from UserCoinsService
  Map<String, Map<String, double>> _tickers = {}; // Coin -> ticker data
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    debugPrint('📍 Dashboard: initState() - adding UserCoinsService listener');
    _loadUserCoinsAndRefresh();

    // Listen to UserCoinsService changes (when API added/removed in Settings)
    UserCoinsService().addListener(_onCoinsChanged);
    debugPrint('✅ Dashboard: UserCoinsService listener added');
  }

  @override
  void dispose() {
    // Remove listener to prevent memory leaks
    UserCoinsService().removeListener(_onCoinsChanged);
    super.dispose();
  }

  /// Called when UserCoinsService notifies that coins changed
  void _onCoinsChanged() {
    debugPrint('📢 Dashboard: Coins changed, reloading...');
    _loadUserCoinsAndRefresh();
  }

  Future<void> _loadUserCoinsAndRefresh() async {
    // Clear cache to get fresh coins (in case API was added/removed)
    UserCoinsService().clearCache();

    // Load user coins first
    final coins = await UserCoinsService().getUserCoins();
    if (mounted) {
      setState(() => _userCoins = coins);
      _refresh();
    }
  }

  Future<void> _refresh() async {
    setState(() => _isLoading = true);
    try {
      final exchangeProvider = Provider.of<ExchangeProvider>(context, listen: false);
      final exchange = exchangeProvider.currentExchange;
      final quote = AppSettingsService().quoteCurrency.toUpperCase();

      // Fetch tickers for all user coins dynamically
      for (final coin in _userCoins) {
        try {
          final ticker = await exchange.fetchTicker24hWithFallback([
            '$coin$quote',
            '${coin}USDT',
            '${coin}EUR',
            '${coin}USDC',
          ]);
          _tickers[coin] = ticker;
        } catch (e) {
          print('Dashboard: Error fetching $coin: $e');
        }
      }
    } catch (e) {
      print('Dashboard: Error fetching market data: $e');
    }
    if (mounted) setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(AppTheme.spacing8),
                      decoration: BoxDecoration(
                        gradient: AppTheme.primaryGradient,
                        borderRadius: BorderRadius.circular(AppTheme.radiusMD),
                      ),
                      child: const Icon(
                        Icons.trending_up,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: AppTheme.spacing12),
                    Flexible(
                      child: Text(
                        'Market',
                        style: AppTheme.headingMedium,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh, size: 20),
                onPressed: _isLoading ? null : _refresh,
                color: AppTheme.textSecondary,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),

          const SizedBox(height: AppTheme.spacing16),

          // Coin list - dynamically display all coins from UserCoinsService
          if (_isLoading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(AppTheme.spacing20),
                child: CircularProgressIndicator(),
              ),
            )
          else if (_tickers.isEmpty)
            Padding(
              padding: const EdgeInsets.all(AppTheme.spacing20),
              child: Center(
                child: Text(
                  'No market data available',
                  style: AppTheme.bodyMedium.copyWith(color: AppTheme.textTertiary),
                ),
              ),
            )
          else
            ...() {
              final entries = _tickers.entries.toList();
              final widgets = <Widget>[];
              for (var i = 0; i < entries.length; i++) {
                final entry = entries[i];
                widgets.add(_buildPnLRow(entry.key, entry.value));
                if (i < entries.length - 1) {
                  widgets.add(_buildDivider());
                }
              }
              return widgets;
            }(),
        ],
      ),
    );
  }

  Widget _buildDivider() {
    return const Divider(
      height: 1,
      thickness: 1,
      color: AppTheme.glassBorder,
    );
  }

  Widget _buildPnLRow(String coin, Map<String, double>? t) {
    final double chg = t?['priceChangePercent'] ?? 0.0;
    final double price = t?['lastPrice'] ?? 0.0;
    final bool isGain = chg >= 0;
    final color = isGain ? AppTheme.buyGreen : AppTheme.sellRed;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppTheme.spacing12),
      child: Row(
        children: [
          // Coin avatar with CoinGecko logo
          CryptoAvatar(symbol: coin, size: 40),

          const SizedBox(width: AppTheme.spacing12),

          // Coin name & price
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  coin,
                  style: AppTheme.bodyLarge.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${AppSettingsService.currencyPrefix(AppSettingsService().quoteCurrency)}${price.toStringAsFixed(price >= 100 ? 0 : 2)}',
                  style: AppTheme.bodySmall.copyWith(
                    color: AppTheme.textTertiary,
                  ),
                ),
              ],
            ),
          ),

          // Change percentage
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppTheme.spacing12,
              vertical: AppTheme.spacing8,
            ),
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(AppTheme.radiusSM),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isGain ? Icons.arrow_upward : Icons.arrow_downward,
                  color: color,
                  size: 16,
                ),
                const SizedBox(width: AppTheme.spacing4),
                Text(
                  '${isGain ? '+' : ''}${chg.toStringAsFixed(2)}%',
                  style: AppTheme.monoMedium.copyWith(
                    color: color,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}


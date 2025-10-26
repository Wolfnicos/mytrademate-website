import 'package:flutter/material.dart';
import '../services/binance_service.dart';
import '../services/app_settings_service.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_card.dart';
import '../widgets/ai_indicator.dart';
import '../widgets/crypto_avatar.dart';
import '../widgets/trial_banner.dart';
import '../ml/ensemble_predictor.dart';
import '../utils/responsive.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: SafeArea(
        child: Responsive.constrainWidth(
          context,
          CustomScrollView(
          physics: const BouncingScrollPhysics(),
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
                  const RepaintBoundary(
                    child: PortfolioOverviewCard(),
                  ),

                  const SizedBox(height: AppTheme.spacing16),

                  // AI Models Status Card
                  const RepaintBoundary(
                    child: AIModelsStatusCard(),
                  ),

                  const SizedBox(height: AppTheme.spacing16),

                  // P&L Today Section
                  const RepaintBoundary(
                    child: PnLTodaySection(),
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
  final BinanceService _binance = BinanceService();
  bool _isLoading = true;
  double _totalValue = 0.0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadPortfolio();
  }

  Future<void> _loadPortfolio() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      await _binance.loadCredentials();
      final balances = await _binance.getAccountBalances();
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
          final ticker = await _binance.fetchTicker24hWithFallback([
            '$asset$quote',
            '${asset}USDT',
            '${asset}EUR',
            '${asset}USDC'
          ]);
          final price = ticker['lastPrice'] ?? 0.0;
          total += amount * price;
        } catch (e) {
          print('Portfolio: Could not get price for $asset: $e');
        }
      }

      if (mounted) {
        setState(() {
          _totalValue = total;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Portfolio: Error loading portfolio: $e');
      if (mounted) {
        setState(() {
          _error = 'Failed to load portfolio';
          _isLoading = false;
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

          if (_isLoading)
            const CircularProgressIndicator()
          else if (_error != null)
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
  int _activityIndex = 0;
  int _progressKey = 0;

  final List<String> _activities = [
    'Analyzing market patterns',
    'Processing technical indicators',
    'Evaluating price movements',
    'Detecting trend reversals',
    'Calculating risk factors',
    'Monitoring volatility signals',
  ];

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

    // Cycle through activities every 5 seconds
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 5));
      if (mounted) {
        setState(() {
          _activityIndex = (_activityIndex + 1) % _activities.length;
        });
        return true;
      }
      return false;
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isActive = globalEnsemblePredictor.isLoaded;

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

          // AI Activity Display
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
                Row(
                  children: [
                    Icon(
                      Icons.data_usage,
                      color: isActive ? AppTheme.primary : AppTheme.textTertiary,
                      size: 18,
                    ),
                    const SizedBox(width: AppTheme.spacing8),
                    Expanded(
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 800),
                        transitionBuilder: (Widget child, Animation<double> animation) {
                          return FadeTransition(
                            opacity: animation,
                            child: SlideTransition(
                              position: Tween<Offset>(
                                begin: const Offset(0, 0.2),
                                end: Offset.zero,
                              ).animate(animation),
                              child: child,
                            ),
                          );
                        },
                        child: Text(
                          isActive ? _activities[_activityIndex] : 'Initializing neural engine...',
                          key: ValueKey<String>(isActive ? _activities[_activityIndex] : 'loading'),
                          style: AppTheme.bodyMedium.copyWith(
                            color: isActive ? AppTheme.textPrimary : AppTheme.textTertiary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),

                if (isActive) ...[
                  const SizedBox(height: AppTheme.spacing12),

                  // Processing bar animation (slower)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppTheme.radiusSM),
                    child: TweenAnimationBuilder<double>(
                      key: ValueKey<int>(_progressKey),
                      duration: const Duration(seconds: 3),
                      curve: Curves.easeInOut,
                      tween: Tween<double>(
                        begin: 0.0,
                        end: 1.0,
                      ),
                      onEnd: () {
                        // Restart animation when it ends
                        if (mounted) {
                          setState(() {
                            _progressKey++;
                          });
                        }
                      },
                      builder: (context, value, _) {
                        return LinearProgressIndicator(
                          value: value,
                          backgroundColor: AppTheme.glassBorder,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            AppTheme.primary.withOpacity(0.8),
                          ),
                          minHeight: 3,
                        );
                      },
                    ),
                  ),

                  const SizedBox(height: AppTheme.spacing12),

                  // Real-time stats
                  Wrap(
                    spacing: AppTheme.spacing8,
                    runSpacing: AppTheme.spacing8,
                    alignment: WrapAlignment.spaceBetween,
                    children: [
                      _buildStatChip(
                        icon: Icons.speed,
                        label: 'Real-time',
                        color: AppTheme.primary,
                      ),
                      _buildStatChip(
                        icon: Icons.layers,
                        label: 'Multi-layer',
                        color: AppTheme.secondary,
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatChip({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacing8,
        vertical: AppTheme.spacing4,
      ),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(AppTheme.radiusSM),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: AppTheme.spacing4),
          Text(
            label,
            style: AppTheme.bodySmall.copyWith(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
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
  final BinanceService _binance = BinanceService();
  Map<String, double>? _btc;
  Map<String, double>? _eth;
  Map<String, double>? _bnb;
  Map<String, double>? _sol;
  Map<String, double>? _wif;
  Map<String, double>? _trump;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _isLoading = true);
    try {
      final quote = AppSettingsService().quoteCurrency.toUpperCase();

      // Use fallback lists for all coins to support EUR, USD, USDT, USDC
      _btc = await _binance.fetchTicker24hWithFallback(['BTC$quote', 'BTCUSDT', 'BTCEUR', 'BTCUSDC']);
      _eth = await _binance.fetchTicker24hWithFallback(['ETH$quote', 'ETHUSDT', 'ETHEUR', 'ETHUSDC']);
      _bnb = await _binance.fetchTicker24hWithFallback(['BNB$quote', 'BNBUSDT', 'BNBEUR', 'BNBUSDC']);
      _sol = await _binance.fetchTicker24hWithFallback(['SOL$quote', 'SOLUSDT', 'SOLEUR', 'SOLUSDC']);
      _wif = await _binance.fetchTicker24hWithFallback(['WLFI$quote', 'WLFIUSDT', 'WLFIEUR', 'WLFIUSDC']);
      _trump = await _binance.fetchTicker24hWithFallback(['TRUMP$quote', 'TRUMPUSDT', 'DJTUSDT']);
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

          // Coin list
          if (_isLoading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(AppTheme.spacing20),
                child: CircularProgressIndicator(),
              ),
            )
          else ...[
            if (_btc != null) ...[
              _buildPnLRow('BTC', _btc),
              if (_eth != null || _bnb != null || _sol != null || _wif != null || _trump != null) _buildDivider(),
            ],
            if (_eth != null) ...[
              _buildPnLRow('ETH', _eth),
              if (_bnb != null || _sol != null || _wif != null || _trump != null) _buildDivider(),
            ],
            if (_bnb != null) ...[
              _buildPnLRow('BNB', _bnb),
              if (_sol != null || _wif != null || _trump != null) _buildDivider(),
            ],
            if (_sol != null) ...[
              _buildPnLRow('SOL', _sol),
              if (_wif != null || _trump != null) _buildDivider(),
            ],
            if (_wif != null) ...[
              _buildPnLRow('WLFI', _wif),
              if (_trump != null) _buildDivider(),
            ],
            if (_trump != null) _buildPnLRow('TRUMP', _trump),
            if (_btc == null && _eth == null && _bnb == null && _sol == null && _wif == null && _trump == null)
              Padding(
                padding: const EdgeInsets.all(AppTheme.spacing20),
                child: Center(
                  child: Text(
                    'No market data available',
                    style: AppTheme.bodyMedium.copyWith(color: AppTheme.textTertiary),
                  ),
                ),
              ),
          ],
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


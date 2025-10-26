import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:provider/provider.dart';
import '../models/candle.dart';
import '../services/binance_service.dart';
import '../services/app_settings_service.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_card.dart';
import '../widgets/crypto_avatar.dart';
import '../widgets/upgrade_banner.dart';
import '../utils/responsive.dart';
import '../providers/subscription_provider.dart';
import 'paywall_screen.dart';

class MarketScreen extends StatefulWidget {
  const MarketScreen({super.key});

  @override
  State<MarketScreen> createState() => _MarketScreenState();
}

class _MarketScreenState extends State<MarketScreen> {
  final BinanceService _binance = BinanceService();
  final Map<String, Map<String, double>> _tickers = {};
  String _interval = '4h'; // Default to 4H (free tier)
  String _selectedSymbol = 'BTCUSDT';
  List<CandleData> _candles = <CandleData>[];
  bool _loadingChart = true;
  bool _loadingTickers = true;
  String _chartError = '';

  List<List<String>> get _symbols {
    final q = AppSettingsService().quoteCurrency.toUpperCase();
    return [
      ['BTC$q', 'BTCUSDT', 'BTCEUR', 'BTCUSDC'],
      ['ETH$q', 'ETHUSDT', 'ETHEUR', 'ETHUSDC'],
      ['BNB$q', 'BNBUSDT', 'BNBEUR', 'BNBUSDC'],
      ['SOL$q', 'SOLUSDT', 'SOLEUR', 'SOLUSDC'],
      ['WLFI$q', 'WLFIUSDT', 'WLFIEUR', 'WLFIUSDC'],
      ['TRUMP$q', 'TRUMPUSDT', 'DJTUSDT'],
    ];
  }

  @override
  void initState() {
    super.initState();
    final q = AppSettingsService().quoteCurrency.toUpperCase();
    _selectedSymbol = 'BTC$q';
    _refreshTickers();
    _loadChart();
    // Listen to quote currency changes and reload data
    AppSettingsService().addListener(_onSettingsChanged);
  }

  @override
  void dispose() {
    AppSettingsService().removeListener(_onSettingsChanged);
    super.dispose();
  }

  void _onSettingsChanged() {
    // Reload tickers and chart when quote currency changes
    final q = AppSettingsService().quoteCurrency.toUpperCase();
    debugPrint('Market: Quote currency changed to $q, reloading data...');
    setState(() {
      _selectedSymbol = 'BTC$q';
      _loadingTickers = true;
      _loadingChart = true;
    });
    _refreshTickers();
    _loadChart();
  }

  Future<void> _refreshTickers() async {
    setState(() => _loadingTickers = true);
    for (final List<String> symbolList in _symbols) {
      try {
        final Map<String, double> t = await _binance.fetchTicker24hWithFallback(symbolList);
        if (mounted) {
          setState(() => _tickers[symbolList.first] = t);
        }
      } catch (e) {
        print('Market: Failed to fetch ticker for ${symbolList.first}: $e');
      }
    }
    if (mounted) {
      setState(() => _loadingTickers = false);
    }
  }

  Future<void> _loadChart() async {
    setState(() {
      _loadingChart = true;
      _chartError = '';
    });
    try {
      // Use different limits based on timeframe to avoid too much historical data
      int limit;
      if (_interval == '1d') {
        limit = 30;  // 30 days = 1 month
      } else if (_interval == '4h') {
        limit = 42;  // 42 x 4h = 7 days
      } else if (_interval == '5m') {
        limit = 100;  // 5m x 100 = ~8 hours
      } else {
        limit = 60;  // 15m/1h: 60 candles
      }

      // Find the symbol list for fallback (try multiple quote currencies)
      final List<String> symbolListForFallback = _symbols.firstWhere(
        (list) => list.first == _selectedSymbol,
        orElse: () => [_selectedSymbol], // Fallback to just the symbol itself
      );

      final List<Candle> klines = await _binance.fetchKlinesWithFallback(
        symbolListForFallback,
        _interval,
        limit: limit,
      );
      final List<CandleData> data = <CandleData>[];
      for (int i = 0; i < klines.length; i++) {
        final Candle c = klines[i];
        data.add(CandleData(
          x: i.toDouble(),
          open: c.open,
          high: c.high,
          low: c.low,
          close: c.close,
        ));
      }
      if (mounted) {
        setState(() {
          _candles = data;
          _loadingChart = false;
        });
      }
    } catch (e) {
      print('Market: Failed to load chart: $e');
      if (mounted) {
        setState(() {
          _chartError = 'Failed to load chart';
          _loadingChart = false;
        });
      }
    }
  }

  String _labelForSymbol(String symbol) {
    if (symbol.endsWith('USDT')) return symbol.replaceAll('USDT', '/USDT');
    if (symbol.endsWith('USDC')) return symbol.replaceAll('USDC', '/USDC');
    if (symbol.endsWith('USD')) return symbol.replaceAll('USD', '/USD');
    if (symbol.endsWith('EUR')) return symbol.replaceAll('EUR', '/EUR');
    return symbol;
  }

  @override
  Widget build(BuildContext context) {
    final quote = AppSettingsService().quoteCurrency;
    final prefix = AppSettingsService.currencyPrefix(quote);

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
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Market',
                      style: AppTheme.displayLarge.copyWith(
                        color: Theme.of(context).colorScheme.onBackground,
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.refresh,
                        color: AppTheme.textSecondary,
                      ),
                      onPressed: _loadingTickers ? null : () {
                        _refreshTickers();
                        _loadChart();
                      },
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
              ),
            ),

            // Upgrade Banner
            const SliverToBoxAdapter(
              child: UpgradeBanner(),
            ),

            // Coin Carousel
            SliverToBoxAdapter(
              child: SizedBox(
                height: 125,
                child: _loadingTickers
                    ? const Center(child: CircularProgressIndicator())
                    : Container(
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.5),
                          borderRadius: BorderRadius.circular(AppTheme.radiusLG),
                          border: Border.all(color: Theme.of(context).colorScheme.outlineVariant.withOpacity(0.5)),
                        ),
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacing20),
                          children: _buildTickerCards(quote, prefix),
                        ),
                      ),
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: AppTheme.spacing20)),

            // Chart Card
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacing20),
              sliver: SliverToBoxAdapter(
                child: GlassCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Chart Header
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _labelForSymbol(_selectedSymbol),
                                style: AppTheme.headingLarge,
                              ),
                              const SizedBox(height: AppTheme.spacing4),
                              if (_candles.isNotEmpty)
                                Text(
                                  prefix + (_candles.last.close >= 100
                                      ? _candles.last.close.toStringAsFixed(0)
                                      : _candles.last.close.toStringAsFixed(4)),
                                  style: AppTheme.monoLarge.copyWith(
                                    color: _candles.last.close > _candles.last.open
                                        ? AppTheme.buyGreen
                                        : AppTheme.sellRed,
                                  ),
                                ),
                            ],
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppTheme.spacing12,
                              vertical: AppTheme.spacing8,
                            ),
                            decoration: BoxDecoration(
                              gradient: AppTheme.secondaryGradient,
                              borderRadius: BorderRadius.circular(AppTheme.radiusSM),
                            ),
                            child: Text(
                              _interval.toUpperCase(),
                              style: AppTheme.bodyMedium.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: AppTheme.spacing20),

                      // Chart
                      SizedBox(
                        height: 300,
                        child: _loadingChart
                            ? const Center(child: CircularProgressIndicator())
                            : _chartError.isNotEmpty
                                ? Center(
                                    child: Text(
                                      _chartError,
                                      style: AppTheme.bodyMedium.copyWith(
                                        color: AppTheme.error,
                                      ),
                                    ),
                                  )
                                : CandlestickChart(
                                    data: _candles,
                                    bullColor: AppTheme.buyGreen,
                                    bearColor: AppTheme.sellRed,
                                  ),
                      ),

                      const SizedBox(height: AppTheme.spacing20),

                      // Interval Selector
                      Consumer<SubscriptionProvider>(
                        builder: (context, subscription, _) {
                          final isProUser = subscription.isProUser;
                          return Wrap(
                            spacing: AppTheme.spacing8,
                            runSpacing: AppTheme.spacing8,
                            children: [
                              _buildIntervalChip(isProUser ? '5M' : '5M 🔒', '5m', isProUser),
                              _buildIntervalChip(isProUser ? '15M' : '15M 🔒', '15m', isProUser),
                              _buildIntervalChip(isProUser ? '1H' : '1H 🔒', '1h', isProUser),
                              _buildIntervalChip(isProUser ? '4H' : '4H FREE', '4h', true),
                              _buildIntervalChip(isProUser ? '1D' : '1D 🔒', '1d', isProUser),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: AppTheme.spacing32)),
          ],
        ),
        ),
      ),
    );
  }

  Widget _buildIntervalChip(String label, String value, bool isUnlocked) {
    final bool selected = _interval == value;
    final isLocked = !isUnlocked && ['5m', '15m', '1h', '4h'].contains(value);

    return GestureDetector(
      onTap: () {
        if (isLocked) {
          // Show paywall for locked timeframes
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const PaywallScreen()),
          );
        } else {
          setState(() => _interval = value);
          _loadChart();
        }
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
          label,
          style: AppTheme.bodyMedium.copyWith(
            color: selected ? Colors.white : (Theme.of(context).brightness == Brightness.dark 
                ? AppTheme.textSecondary 
                : AppTheme.textPrimaryLight),
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  List<Widget> _buildTickerCards(String quote, String prefix) {
    final q = quote.toUpperCase();

    Widget buildCard(String base, String key) {
      final t = _tickers[key];
      final double price = t?['lastPrice'] ?? 0.0;
      final double chg = t?['priceChangePercent'] ?? 0.0;
      final bool isGain = chg >= 0;
      final symbol = key;
      final bool isSelected = _selectedSymbol == symbol;

      return GestureDetector(
        onTap: () {
          setState(() => _selectedSymbol = symbol);
          _loadChart();
        },
        child: Container(
          width: 140,
          height: 115,
          margin: const EdgeInsets.only(right: AppTheme.spacing12),
          padding: const EdgeInsets.all(AppTheme.spacing12),
          decoration: BoxDecoration(
            gradient: isSelected ? AppTheme.primaryGradient : null,
            color: isSelected ? null : (Theme.of(context).brightness == Brightness.dark 
                ? AppTheme.glassWhite 
                : Colors.grey[100]),
            borderRadius: BorderRadius.circular(AppTheme.radiusMD),
            border: Border.all(
              color: isSelected ? Colors.transparent : (Theme.of(context).brightness == Brightness.dark 
                  ? AppTheme.glassBorder 
                  : Colors.grey[300]!),
              width: 1.5,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Coin name with logo
              Row(
                children: [
                  CryptoAvatar(
                    symbol: base,
                    size: 28,
                    showBorder: true,
                  ),
                  const SizedBox(width: AppTheme.spacing8),
                  Expanded(
                    child: Text(
                      base,
                      style: AppTheme.bodyMedium.copyWith(
                        color: isSelected ? Colors.white : (Theme.of(context).brightness == Brightness.dark 
                            ? AppTheme.textPrimary 
                            : AppTheme.textPrimaryLight),
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: AppTheme.spacing4),

              // Price
              Text(
                price > 0 ? prefix + (price >= 100 ? price.toStringAsFixed(0) : price.toStringAsFixed(4)) : '—',
                style: AppTheme.monoMedium.copyWith(
                  color: isSelected ? Colors.white : (Theme.of(context).brightness == Brightness.dark 
                      ? AppTheme.textPrimary 
                      : AppTheme.textPrimaryLight),
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),

              const SizedBox(height: AppTheme.spacing4),

              // Change %
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppTheme.spacing8,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: isSelected
                      ? Colors.white.withOpacity(0.2)
                      : (isGain ? AppTheme.buyGreen : AppTheme.sellRed).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(AppTheme.radiusSM),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isGain ? Icons.arrow_upward : Icons.arrow_downward,
                      color: isSelected
                          ? Colors.white
                          : (isGain ? AppTheme.buyGreen : AppTheme.sellRed),
                      size: 10,
                    ),
                    const SizedBox(width: 2),
                    Text(
                      '${isGain ? '+' : ''}${chg.toStringAsFixed(2)}%',
                      style: AppTheme.bodySmall.copyWith(
                        color: isSelected
                            ? Colors.white
                            : (isGain ? AppTheme.buyGreen : AppTheme.sellRed),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return [
      buildCard('BTC', 'BTC$q'),
      buildCard('ETH', 'ETH$q'),
      buildCard('BNB', 'BNB$q'),
      buildCard('SOL', 'SOL$q'),
      buildCard('WLFI', 'WLFI$q'),
      buildCard('TRUMP', 'TRUMP$q'),
    ];
  }
}

// CandleData and CandlestickChart remain the same
class CandleData {
  final double x;
  final double open;
  final double high;
  final double low;
  final double close;

  CandleData({
    required this.x,
    required this.open,
    required this.high,
    required this.low,
    required this.close,
  });

  bool get isBullish => close > open;
}

class CandlestickChart extends StatelessWidget {
  final List<CandleData> data;
  final Color bullColor;
  final Color bearColor;

  const CandlestickChart({
    super.key,
    required this.data,
    required this.bullColor,
    required this.bearColor,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    if (data.isEmpty) {
      return Center(
        child: Text(
          'No data available',
          style: AppTheme.bodyMedium.copyWith(color: colors.onSurface.withOpacity(0.7)),
        ),
      );
    }

    final double maxPrice = data.map((e) => e.high).reduce((a, b) => a > b ? a : b);
    final double minPrice = data.map((e) => e.low).reduce((a, b) => a < b ? a : b);
    final double range = maxPrice - minPrice;

    // Calculate smart interval - aim for 4-5 labels
    double interval = range / 4;

    // Round interval to nice numbers
    if (interval > 1000) {
      interval = (interval / 1000).ceilToDouble() * 1000;
    } else if (interval > 100) {
      interval = (interval / 100).ceilToDouble() * 100;
    } else if (interval > 10) {
      interval = (interval / 10).ceilToDouble() * 10;
    } else if (interval > 1) {
      interval = interval.ceilToDouble();
    }

    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceBetween,
        maxY: maxPrice * 1.03,
        minY: minPrice * 0.97,
        groupsSpace: 6,
        barTouchData: BarTouchData(
          enabled: true,
          handleBuiltInTouches: true,
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (group) => AppTheme.surface,
            tooltipPadding: const EdgeInsets.all(AppTheme.spacing8),
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              final candle = data[group.x.toInt()];
              return BarTooltipItem(
                'O: ${candle.open.toStringAsFixed(4)}\n'
                'H: ${candle.high.toStringAsFixed(4)}\n'
                'L: ${candle.low.toStringAsFixed(4)}\n'
                'C: ${candle.close.toStringAsFixed(4)}',
                AppTheme.bodySmall.copyWith(
                  color: AppTheme.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              );
            },
          ),
          touchCallback: (event, response) {},
        ),
        titlesData: FlTitlesData(
          show: true,
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 70,
              interval: interval > 0 ? interval : null,
              getTitlesWidget: (value, meta) {
                final double absValue = value.abs();
                final int decimals = absValue >= 100
                    ? 0
                    : absValue >= 1
                        ? 2
                        : 4;
                return Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Text(
                    '\$${value.toStringAsFixed(decimals)}',
                    style: AppTheme.bodySmall.copyWith(
                      color: colors.onSurface.withOpacity(0.6),
                      fontSize: 9,
                    ),
                    textAlign: TextAlign.right,
                    maxLines: 1,
                    overflow: TextOverflow.visible,
                  ),
                );
              },
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                if (value.toInt() % 10 == 0) {
                  return Text(
                    value.toInt().toString(),
                    style: AppTheme.bodySmall.copyWith(
                      color: colors.onSurface.withOpacity(0.6),
                    ),
                  );
                }
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        barGroups: data.asMap().entries.map((entry) {
          final candle = entry.value;
          final isBullish = candle.isBullish;
          final color = isBullish ? bullColor : bearColor;

          return BarChartGroupData(
            x: entry.key,
            barRods: [
              BarChartRodData(
                fromY: candle.low,
                toY: candle.high,
                width: 2.4,
                color: color.withOpacity(0.9),
                rodStackItems: [
                  BarChartRodStackItem(
                    candle.low,
                    candle.open < candle.close ? candle.open : candle.close,
                    color.withOpacity(0.4),
                  ),
                  BarChartRodStackItem(
                    candle.open < candle.close ? candle.open : candle.close,
                    candle.open > candle.close ? candle.open : candle.close,
                    color.withOpacity(0.95),
                  ),
                  BarChartRodStackItem(
                    candle.open > candle.close ? candle.open : candle.close,
                    candle.high,
                    color.withOpacity(0.4),
                  ),
                ],
              ),
            ],
          );
        }).toList(),
      ),
    );
  }
}

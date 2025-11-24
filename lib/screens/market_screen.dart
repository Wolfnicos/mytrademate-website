import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import '../models/candle.dart';
import '../services/app_settings_service.dart';
import '../services/user_coins_service.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_card.dart';
import '../widgets/crypto_avatar.dart';
import '../widgets/upgrade_banner.dart';
import '../utils/responsive.dart';
import '../providers/subscription_provider.dart';
import '../providers/exchange_provider.dart';
import 'paywall_screen.dart';

class MarketScreen extends StatefulWidget {
  const MarketScreen({super.key});

  @override
  State<MarketScreen> createState() => _MarketScreenState();
}

class _MarketScreenState extends State<MarketScreen> {
  final Map<String, Map<String, double>> _tickers = {};
  String _interval = '4h'; // Default to 4H (free tier)
  String _selectedSymbol = 'BTCUSDT';
  List<CandleData> _candles = <CandleData>[];
  bool _loadingChart = true;
  bool _loadingTickers = true;
  String _chartError = '';
  List<String> _userCoins = []; // Dynamic coin list from UserCoinsService

  List<List<String>> get _symbols {
    final exchangeProvider = Provider.of<ExchangeProvider>(context, listen: false);
    final exchange = exchangeProvider.currentExchange;
    final q = AppSettingsService().quoteCurrency.toUpperCase();

    // Use UserCoinsService coins or fallback to default TOP 10
    final coins = _userCoins.isNotEmpty ? _userCoins : UserCoinsService.defaultCoins;

    // Build trading pairs using exchange-specific format
    // Use getPreferredQuote to get the best available quote currency for each coin
    return coins.map((coin) => [
      exchange.buildTradingPair(coin, exchange.getPreferredQuote(coin, q)),
      exchange.buildTradingPair(coin, 'USDT'),
      exchange.buildTradingPair(coin, 'EUR'),
      exchange.buildTradingPair(coin, 'USD'),
      exchange.buildTradingPair(coin, 'USDC'),
    ]).toList();
  }

  @override
  void initState() {
    super.initState();
    debugPrint('📍 Market: initState() - adding UserCoinsService listener');

    _loadUserCoins();

    // Listen to quote currency changes and reload data
    AppSettingsService().addListener(_onSettingsChanged);

    // Listen to UserCoinsService changes (when API added/removed in Settings)
    UserCoinsService().addListener(_onCoinsChanged);
    debugPrint('✅ Market: UserCoinsService listener added');

    // Initialize selected symbol with correct exchange format
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final exchangeProvider = Provider.of<ExchangeProvider>(context, listen: false);
        final exchange = exchangeProvider.currentExchange;
        final q = AppSettingsService().quoteCurrency.toUpperCase();
        setState(() {
          _selectedSymbol = exchange.buildTradingPair('BTC', exchange.getPreferredQuote('BTC', q));
        });

        // Listen to exchange changes and reload data
        exchangeProvider.addListener(_onExchangeChanged);
      }
    });
  }

  /// Called when UserCoinsService notifies that coins changed
  void _onCoinsChanged() {
    debugPrint('📢 Market: Coins changed, reloading...');
    _loadUserCoins();
  }

  /// Called when ExchangeProvider notifies that exchange changed
  void _onExchangeChanged() {
    debugPrint('Market: Exchange changed, reloading data...');
    final exchangeProvider = Provider.of<ExchangeProvider>(context, listen: false);
    final exchange = exchangeProvider.currentExchange;
    final q = AppSettingsService().quoteCurrency.toUpperCase();

    setState(() {
      _selectedSymbol = exchange.buildTradingPair('BTC', q);
      _loadingTickers = true;
      _loadingChart = true;
      _candles = []; // Clear old candles to prevent showing stale data
      _tickers.clear(); // Clear old tickers
    });
    _refreshTickers();
    _loadChart();
  }

  Future<void> _loadUserCoins() async {
    // Clear cache to get fresh coins (in case API was added/removed)
    UserCoinsService().clearCache();

    final coins = await UserCoinsService().getUserCoins();

    // FILTER OUT DELISTED COINS (ANC, UST, LUNA)
    // These coins are no longer tradeable on major exchanges
    const delistedCoins = ['ANC', 'UST', 'LUNA'];
    final validCoins = coins.where((coin) => !delistedCoins.contains(coin)).toList();

    if (validCoins.length < coins.length) {
      final removed = coins.where((coin) => delistedCoins.contains(coin)).toList();
      debugPrint('⚠️  Market: Filtered out delisted coins: ${removed.join(", ")}');
    }

    if (mounted) {
      setState(() => _userCoins = validCoins);
      // AFTER coins are loaded, refresh tickers and chart
      _refreshTickers();
      _loadChart();
    }
  }

  @override
  void dispose() {
    AppSettingsService().removeListener(_onSettingsChanged);
    UserCoinsService().removeListener(_onCoinsChanged);
    try {
      Provider.of<ExchangeProvider>(context, listen: false).removeListener(_onExchangeChanged);
    } catch (e) {
      // Ignore if provider not available
    }
    super.dispose();
  }

  void _onSettingsChanged() {
    // Reload tickers and chart when quote currency changes
    final exchangeProvider = Provider.of<ExchangeProvider>(context, listen: false);
    final exchange = exchangeProvider.currentExchange;
    final q = AppSettingsService().quoteCurrency.toUpperCase();
    debugPrint('Market: Quote currency changed to $q, reloading data...');
    setState(() {
      _selectedSymbol = exchange.buildTradingPair('BTC', q);
      _loadingTickers = true;
      _loadingChart = true;
      _candles = []; // Clear old candles to prevent showing stale data
      _tickers.clear(); // Clear old tickers
    });
    _refreshTickers();
    _loadChart();
  }

  Future<void> _refreshTickers() async {
    final exchangeProvider = Provider.of<ExchangeProvider>(context, listen: false);
    final exchange = exchangeProvider.currentExchange;
    final q = AppSettingsService().quoteCurrency.toUpperCase();

    setState(() => _loadingTickers = true);

    // Use _userCoins to match with _symbols
    final coins = _userCoins.isNotEmpty ? _userCoins : UserCoinsService.defaultCoins;

    for (int i = 0; i < _symbols.length; i++) {
      final symbolList = _symbols[i];
      final coin = coins[i]; // Get corresponding coin

      try {
        debugPrint('Market: Fetching ticker for ${symbolList.first} (fallbacks: ${symbolList.join(", ")})');
        final Map<String, double> t = await exchange.fetchTicker24hWithFallback(symbolList);
        if (mounted) {
          // Save ticker using the same key that _buildTickerCards uses: exchange.buildTradingPair(coin, q)
          final tickerKey = exchange.buildTradingPair(coin, q);

          // Detect if price needs conversion (e.g., USDT → EUR)
          // If first symbol in fallback list doesn't match user's quote currency, we need conversion
          final primarySymbol = symbolList.first;
          final needsConversion = q == 'EUR' && !primarySymbol.endsWith('EUR') && t['lastPrice'] != null && t['lastPrice']! > 0;

          if (needsConversion) {
            // Fetch EUR/USDT conversion rate (inverse)
            try {
              final eurUsdtTicker = await exchange.fetchTicker24hWithFallback([
                exchange.buildTradingPair('EUR', 'USDT'),
                'EURUSDT',
              ]);

              // EURUSDT gives EUR price in USDT (e.g., 1 EUR = 1.08 USDT)
              // To convert USDT → EUR, we need to divide by this rate
              final eurInUsdt = eurUsdtTicker['lastPrice'] ?? 1.08; // Fallback: 1 EUR = 1.08 USDT
              final conversionRate = 1.0 / eurInUsdt; // e.g., 1/1.08 = 0.926 (USDT → EUR)

              final convertedPrice = t['lastPrice']! * conversionRate;
              final convertedChange = t['priceChangePercent'] ?? 0.0; // % stays same

              setState(() => _tickers[tickerKey] = {
                'lastPrice': convertedPrice,
                'priceChangePercent': convertedChange,
              });
              debugPrint('Market: ✅ Ticker loaded for $tickerKey (coin: $coin) - price: €${convertedPrice.toStringAsFixed(4)} (converted from \$${t['lastPrice']} USDT, 1 EUR = $eurInUsdt USDT)');
            } catch (e) {
              debugPrint('Market: ⚠️  Failed to convert USDT→EUR for $coin: $e');
              // Use fallback rate
              const fallbackRate = 0.926; // ~1/1.08
              final convertedPrice = t['lastPrice']! * fallbackRate;
              setState(() => _tickers[tickerKey] = {
                'lastPrice': convertedPrice,
                'priceChangePercent': t['priceChangePercent'] ?? 0.0,
              });
              debugPrint('Market: ⚠️  Using fallback rate 0.926 for $coin → €${convertedPrice.toStringAsFixed(4)}');
            }
          } else {
            setState(() => _tickers[tickerKey] = t);
            debugPrint('Market: ✅ Ticker loaded for $tickerKey (coin: $coin) - price: ${t['lastPrice']} (no conversion needed)');
          }
        }
      } catch (e) {
        debugPrint('Market: ❌ Failed to fetch ticker for ${symbolList.first}: $e');
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
      // Fewer candles = larger, more visible candles on chart
      int limit;
      if (_interval == '1d') {
        limit = 30;  // 30 days = 1 month
      } else if (_interval == '4h') {
        limit = 42;  // 42 x 4h = 7 days
      } else if (_interval == '1h') {
        limit = 48;  // 48 hours = 2 days
      } else if (_interval == '15m') {
        limit = 48;  // 15m x 48 = 12 hours
      } else if (_interval == '5m') {
        limit = 48;  // 5m x 48 = 4 hours (more visible candles!)
      } else {
        limit = 60;  // Default fallback
      }

      final exchangeProvider = Provider.of<ExchangeProvider>(context, listen: false);
      final exchange = exchangeProvider.currentExchange;

      // Find the symbol list for fallback (try multiple quote currencies)
      final List<String> symbolListForFallback = _symbols.firstWhere(
        (list) => list.first == _selectedSymbol,
        orElse: () => [_selectedSymbol], // Fallback to just the symbol itself
      );

      List<Candle> klines = await exchange.fetchKlinesWithFallback(
        symbolListForFallback,
        _interval,
        limit: limit,
      );

      // CRITICAL: Sort candles by time (ascending) to ensure proper order
      // Some exchanges may return candles in descending order
      klines.sort((a, b) => a.openTime.compareTo(b.openTime));

      // DEBUG: Log the candle data received
      if (klines.isNotEmpty) {
        debugPrint('📊 [Market] Loaded ${klines.length} candles for $_interval');
        debugPrint('📊 [Market] First candle: open=${klines.first.open}, close=${klines.first.close}, time=${klines.first.openTime}');
        debugPrint('📊 [Market] Last candle: open=${klines.last.open}, close=${klines.last.close}, time=${klines.last.openTime}');
      }

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
                              Builder(
                                builder: (context) {
                                  // Get price from candles if available, otherwise from ticker
                                  final double price = _candles.length >= 2
                                      ? _candles[_candles.length - 2].close
                                      : (_tickers[_selectedSymbol]?['lastPrice'] ?? 0.0);

                                  if (price == 0.0) {
                                    return Text(
                                      '${prefix}—.——',
                                      style: AppTheme.monoLarge.copyWith(color: AppTheme.textSecondary),
                                    );
                                  }

                                  final priceText = prefix + (price >= 100
                                      ? price.toStringAsFixed(0)
                                      : price.toStringAsFixed(4));
                                  debugPrint('💰 [Market] Displaying price: $priceText for $_selectedSymbol');

                                  // Determine color from candles if available, otherwise neutral
                                  final color = _candles.length >= 2
                                      ? (_candles[_candles.length - 2].close > _candles[_candles.length - 2].open
                                          ? AppTheme.buyGreen
                                          : AppTheme.sellRed)
                                      : AppTheme.textPrimary;

                                  return Text(
                                    priceText,
                                    style: AppTheme.monoLarge.copyWith(color: color),
                                  );
                                },
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
                                    key: ValueKey('${_selectedSymbol}_$_interval'),
                                    data: _candles,
                                    bullColor: AppTheme.buyGreen,
                                    bearColor: AppTheme.sellRed,
                                    symbol: _selectedSymbol,
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
                              _buildIntervalChip(isProUser ? '4H' : '4H 🔒', '4h', isProUser),
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
          debugPrint('🔄 [Market] User changed timeframe to $value (old: $_interval)');
          setState(() {
            _interval = value;
            _candles = []; // Clear old candles when changing timeframe
            _loadingChart = true;
          });
          debugPrint('🔄 [Market] Cleared _candles, now length=${_candles.length}');
          debugPrint('🔄 [Market] Calling _loadChart() for $_interval');
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
    final exchangeProvider = Provider.of<ExchangeProvider>(context, listen: false);
    final exchange = exchangeProvider.currentExchange;

    Widget buildCard(String base, String key) {
      final t = _tickers[key];
      final double price = t?['lastPrice'] ?? 0.0;
      final double chg = t?['priceChangePercent'] ?? 0.0;
      final bool isGain = chg >= 0;
      final symbol = key;
      final bool isSelected = _selectedSymbol == symbol;

      return GestureDetector(
        onTap: () {
          setState(() {
            _selectedSymbol = symbol;
            _candles = []; // Clear old candles to prevent showing stale BTC price
          });
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

    // Use _userCoins dynamically (TOP 10 default or user's coins from API)
    final coins = _userCoins.isNotEmpty ? _userCoins : UserCoinsService.defaultCoins;
    // Use exchange-specific format for ticker lookup key (e.g., BTC-EUR for Coinbase, XBTEUR for Kraken)
    return coins.map((coin) => buildCard(coin, exchange.buildTradingPair(coin, q))).toList();
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
  final String symbol;

  const CandlestickChart({
    super.key,
    required this.data,
    required this.bullColor,
    required this.bearColor,
    required this.symbol,
  });

  // Detect quote currency from symbol
  String _getQuoteCurrency() {
    if (symbol.endsWith('EUR')) return 'EUR';
    if (symbol.endsWith('USD')) return 'USD';
    if (symbol.endsWith('USDT')) return 'USDT';
    if (symbol.endsWith('USDC')) return 'USDC';
    return 'USD'; // fallback
  }

  // Get currency prefix (€ for EUR, $ for others)
  String _getCurrencyPrefix() {
    final quote = _getQuoteCurrency();
    return quote == 'EUR' ? '€' : '\$';
  }

  // Get optimal decimal places based on price
  int _getDecimals(double price) {
    if (price >= 100) return 0;      // BTC, ETH: €95000 → €95000
    if (price >= 10) return 2;       // BNB, SOL, TRUMP: €171 → €171.00, €6.13 → €6.13
    if (price >= 1) return 2;        // Mid-range: €5.97 → €5.97
    if (price >= 0.01) return 2;     // WLFI: €0.1254 → €0.13 (2 decimale!)
    return 2;                        // Very small prices - 2 decimale peste tot!
  }

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

    // Get current price from LAST CLOSED candle (second-to-last in array)
    // The last candle might be incomplete/current, so we use the penultimate one
    final double currentPrice = data.length >= 2 ? data[data.length - 2].close : data.last.close;
    final String currencyPrefix = _getCurrencyPrefix();

    return SfCartesianChart(
      plotAreaBorderWidth: 0,
      // Trackball for current price line (like TradingView)
      trackballBehavior: TrackballBehavior(
        enable: true,
        activationMode: ActivationMode.singleTap,
        lineType: TrackballLineType.vertical,
        lineColor: AppTheme.primary.withOpacity(0.5),
        lineWidth: 1,
        lineDashArray: const [5, 5],
        tooltipSettings: InteractiveTooltip(
          enable: true,
          color: AppTheme.surface,
          textStyle: AppTheme.bodySmall.copyWith(
            color: AppTheme.textPrimary,
            fontWeight: FontWeight.w600,
          ),
          borderColor: AppTheme.glassBorder,
          borderWidth: 1,
          format: 'O: point.open\nH: point.high\nL: point.low\nC: point.close',
        ),
      ),
      // Primary X-Axis (candle index)
      primaryXAxis: NumericAxis(
        isVisible: false,
        majorGridLines: const MajorGridLines(width: 0),
      ),
      // Primary Y-Axis (price)
      primaryYAxis: NumericAxis(
        opposedPosition: false,
        // Let Syncfusion auto-calculate optimal intervals to prevent crowding
        desiredIntervals: 5,
        labelStyle: TextStyle(
          color: colors.onSurface.withOpacity(0.6),
          fontSize: 10,
          fontFamily: 'monospace',
        ),
        majorGridLines: MajorGridLines(
          width: 0.5,
          color: colors.onSurface.withOpacity(0.1),
          dashArray: const [5, 5],
        ),
        axisLine: const AxisLine(width: 0),
        labelAlignment: LabelAlignment.end,
        // Custom label formatting with correct currency and decimals
        axisLabelFormatter: (AxisLabelRenderDetails details) {
          final double value = details.value.toDouble();
          final int decimals = _getDecimals(value);
          return ChartAxisLabel(
            '$currencyPrefix${value.toStringAsFixed(decimals)}',
            TextStyle(
              color: colors.onSurface.withOpacity(0.6),
              fontSize: 10,
              fontFamily: 'monospace',
            ),
          );
        },
      ),
      // Candlestick series
      series: <CandleSeries<CandleData, num>>[
        CandleSeries<CandleData, num>(
          dataSource: data,
          xValueMapper: (CandleData candle, _) => candle.x,
          lowValueMapper: (CandleData candle, _) => candle.low,
          highValueMapper: (CandleData candle, _) => candle.high,
          openValueMapper: (CandleData candle, _) => candle.open,
          closeValueMapper: (CandleData candle, _) => candle.close,
          // Candle colors
          bullColor: bullColor,
          bearColor: bearColor,
          enableSolidCandles: true,
          // Candle width - Syncfusion auto-optimizes based on data points
          spacing: 0.1, // 10% spacing = fatter candles (more visible!)
          borderWidth: 2, // Thicker borders for better visibility
          // Show indication for same values (makes wicks more visible!)
          showIndicationForSameValues: true,
          // Show current value indicator (price line on right side)
          dataLabelSettings: const DataLabelSettings(
            isVisible: false,
          ),
        ),
      ],
      // Plot area customization
      margin: const EdgeInsets.only(right: 10, top: 10, bottom: 5),
      // Zooming and panning
      zoomPanBehavior: ZoomPanBehavior(
        enablePinching: true,
        enablePanning: true,
        zoomMode: ZoomMode.x,
      ),
      // Annotations for current price line (using last CLOSED candle)
      annotations: <CartesianChartAnnotation>[
        CartesianChartAnnotation(
          widget: Container(
            decoration: BoxDecoration(
              color: data.length >= 2
                ? (data[data.length - 2].close > data[data.length - 2].open ? bullColor : bearColor)
                : (data.last.close > data.last.open ? bullColor : bearColor),
              borderRadius: BorderRadius.circular(4),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            child: Text(
              '$currencyPrefix${currentPrice.toStringAsFixed(_getDecimals(currentPrice))}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 9,
                fontWeight: FontWeight.bold,
                fontFamily: 'monospace',
              ),
            ),
          ),
          coordinateUnit: CoordinateUnit.point,
          x: data.length >= 2 ? data.length - 2 : data.length - 1,
          y: currentPrice,
          horizontalAlignment: ChartAlignment.far,
          verticalAlignment: ChartAlignment.center,
        ),
        // Horizontal line at current price (like TradingView)
        CartesianChartAnnotation(
          widget: Container(
            height: 1,
            color: (data.length >= 2
              ? (data[data.length - 2].close > data[data.length - 2].open ? bullColor : bearColor)
              : (data.last.close > data.last.open ? bullColor : bearColor)).withOpacity(0.5),
          ),
          coordinateUnit: CoordinateUnit.point,
          region: AnnotationRegion.plotArea,
          x: 0,
          y: currentPrice,
        ),
      ],
    );
  }
}

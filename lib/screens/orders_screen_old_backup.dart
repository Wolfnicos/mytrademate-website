import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../backtest/backtester.dart';
import '../services/paper_broker.dart';
import '../services/binance_service.dart';
import '../services/hybrid_strategies_service.dart';
import '../ml/ml_service.dart';
import 'dart:async';
import '../theme/app_theme.dart';
import '../widgets/glass_card.dart';
import '../widgets/crypto_avatar.dart';
import '../services/app_settings_service.dart';
import '../widgets/orders/achievement_toast.dart';
import '../widgets/orders/open_orders_card.dart';
import '../utils/responsive.dart';

enum OrderType { market, limit, stopLimit, stopMarket }

class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key});

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> with SingleTickerProviderStateMixin {
  bool isBuy = true;
  OrderType _orderType = OrderType.market;
  String _selectedPair = 'BTCUSDT';
  List<Map<String, String>> _pairs = <Map<String, String>>[];
  bool _loadingPairs = true;
  final TextEditingController _amountCtrl = TextEditingController();
  final TextEditingController _priceCtrl = TextEditingController();
  final TextEditingController _totalCtrl = TextEditingController();
  final TextEditingController _limitPriceCtrl = TextEditingController();
  final TextEditingController _stopPriceCtrl = TextEditingController();
  bool _updatingFields = false;
  final String _aiInterval = '1h';
  final bool _ocoEnabled = false;
  final double _stopLossPct = 3.0;
  final double _takeProfitPct = 6.0;
  StreamSubscription<List<StrategySignal>>? _hybridSub;
  Timer? _aiTimer;

  @override
  void initState() {
    super.initState();
    // Set initial pair based on quote currency
    final quote = AppSettingsService().quoteCurrency.toUpperCase();
    _selectedPair = 'BTC$quote';
    
    // Load last order type preference
    _loadSavedOrderType();
    _loadPairs();
    
    // Listen for quote currency changes
    AppSettingsService().addListener(_onQuoteCurrencyChanged);
  }
  
  void _onQuoteCurrencyChanged() {
    // Reload pairs when quote currency changes
    final quote = AppSettingsService().quoteCurrency.toUpperCase();
    setState(() {
      _selectedPair = 'BTC$quote';
      _loadingPairs = true;
    });
    _loadPairs();
    _loadCurrentPrice();
  }

  Future<void> _loadSavedOrderType() async {
    final prefs = await SharedPreferences.getInstance();
    final String? saved = prefs.getString('order_type');
    if (saved != null) {
      setState(() {
        switch (saved) {
          case 'market':
            _orderType = OrderType.market;
            break;
          case 'limit':
            _orderType = OrderType.limit;
            break;
          case 'stop_limit':
            _orderType = OrderType.stopLimit;
            break;
          case 'stop_market':
            _orderType = OrderType.stopMarket;
            break;
          default:
            _orderType = OrderType.market;
        }
      });
    }
  }

  Future<void> _loadPairs() async {
    if (!mounted) return;
    setState(() => _loadingPairs = true);
    
    try {
      final binance = BinanceService();

      // Get user's portfolio balances from Binance
      await binance.loadCredentials();
      final balances = await binance.getAccountBalances();
      
      debugPrint('Orders: Loaded ${balances.length} balances');

      // Get all available trading pairs
      final all = await binance.fetchTradingPairs();
      final String selectedQuote = AppSettingsService().quoteCurrency.toUpperCase();

      // Extract base currencies from user's portfolio (excluding quote currency and coins below $5)
      final Set<String> allowedBases = <String>{};
      for (final asset in balances.keys) {
        final upperAsset = asset.toUpperCase();
        if (upperAsset != selectedQuote && balances[asset]! > 0.0) {
          // Calculate value to filter out coins below $5
          try {
            final ticker = await binance.fetchTicker24hWithFallback([
              '$upperAsset$selectedQuote',
              '${upperAsset}USDT',
              '${upperAsset}EUR',
              '${upperAsset}USDC'
            ]);
            final price = ticker['lastPrice'] ?? 0.0;
            final value = balances[asset]! * price;
            if (value >= 5.0) {
              allowedBases.add(upperAsset);
            }
          } catch (e) {
            // If price fetch fails, skip this coin
            debugPrint('Orders: Could not get price for $upperAsset: $e');
          }
        }
      }

      // If user has no holdings, fall back to default coins
      if (allowedBases.isEmpty) {
        allowedBases.addAll({'BTC', 'ETH', 'BNB', 'SOL', 'WLFI', 'TRUMP'});
      }

      // Filter trading pairs to only include user's coins
      final List<Map<String, String>> filtered = <Map<String, String>>[];
      final Set<String> seen = <String>{};
      for (final m in all) {
        final base = (m['base'] ?? '').toUpperCase();
        final quote = (m['quote'] ?? '').toUpperCase();
        if (quote == selectedQuote && allowedBases.contains(base)) {
          final sym = (m['symbol'] ?? '').toUpperCase();
          if (!seen.contains(sym)) {
            seen.add(sym);
            filtered.add({'symbol': sym, 'base': base, 'quote': quote});
          }
        }
      }
      filtered.sort((a, b) => (a['base'] ?? '').compareTo(b['base'] ?? ''));
      
      debugPrint('Orders: Filtered ${filtered.length} pairs for quote $selectedQuote');
      
      if (!mounted) return;
      setState(() {
        _pairs = filtered;
        _loadingPairs = false;
        // default selected to first if current not in list
        if (_pairs.isNotEmpty && !_pairs.any((p) => (p['symbol'] ?? '') == _selectedPair)) {
          _selectedPair = _pairs.first['symbol'] ?? _selectedPair;
        }
      });
      // Load current price after pairs are loaded
      _loadCurrentPrice();
    } catch (e) {
      debugPrint('Orders: Error loading pairs: $e');
      if (!mounted) return;
      setState(() {
        _pairs = [];
        _loadingPairs = false;
      });
    }
  }

  Future<void> _loadCurrentPrice() async {
    try {
      final binance = BinanceService();
      final ticker = await binance.fetchTicker24h(_selectedPair);
      final price = ticker['lastPrice'] ?? 0.0;
      if (mounted) {
        setState(() {
          _priceCtrl.text = price.toString();
        });
      }
    } catch (e) {
      debugPrint('Error loading current price: $e');
    }
  }

  @override
  void dispose() {
    _hybridSub?.cancel();
    _aiTimer?.cancel();
    AppSettingsService().removeListener(_onQuoteCurrencyChanged);
    _amountCtrl.dispose();
    _priceCtrl.dispose();
    _totalCtrl.dispose();
    _limitPriceCtrl.dispose();
    _stopPriceCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final activeColor = isBuy ? AppTheme.buyGreen : AppTheme.sellRed;
    final bool tradingEnabled = AppSettingsService().isTradingEnabled;

    return Scaffold(
      body: SafeArea(
        child: Responsive.constrainWidth(
          context,
          GestureDetector(
            onTap: () => FocusScope.of(context).unfocus(),
            child: CustomScrollView(
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
                  child: Text(
                    'Orders',
                    style: AppTheme.displayLarge.copyWith(
                      color: Theme.of(context).colorScheme.onBackground,
                    ),
                  ),
                ),
              ),

              // Content
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacing20),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                        // BUY/SELL Toggle - SUPER CLEAR
                        RepaintBoundary(
                          child: GlassCard(
                            padding: const EdgeInsets.all(AppTheme.spacing12),
                            child: Row(
                              children: [
                                Expanded(
                                  child: GestureDetector(
                                    onTap: () {
                                      HapticFeedback.selectionClick();
                                      setState(() => isBuy = true);
                                    },
                                    child: AnimatedContainer(
                                      duration: AppTheme.animationNormal,
                                      curve: Curves.easeInOut,
                                      padding: const EdgeInsets.symmetric(vertical: AppTheme.spacing16),
                                      decoration: BoxDecoration(
                                        gradient: isBuy ? AppTheme.buyGradient : null,
                                        color: isBuy ? null : Colors.transparent,
                                        borderRadius: BorderRadius.circular(AppTheme.radiusMD),
                                        boxShadow: isBuy ? AppTheme.glassShadow : null,
                                      ),
                                      child: Center(
                                        child: Text(
                                          'BUY',
                                          style: AppTheme.labelLarge.copyWith(
                                            color: isBuy ? Colors.white : AppTheme.textSecondary,
                                            fontSize: 16,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: AppTheme.spacing12),
                                Expanded(
                                  child: GestureDetector(
                                    onTap: () {
                                      HapticFeedback.selectionClick();
                                      setState(() => isBuy = false);
                                    },
                                    child: AnimatedContainer(
                                      duration: AppTheme.animationNormal,
                                      curve: Curves.easeInOut,
                                      padding: const EdgeInsets.symmetric(vertical: AppTheme.spacing16),
                                      decoration: BoxDecoration(
                                        gradient: !isBuy ? AppTheme.sellGradient : null,
                                        color: !isBuy ? null : Colors.transparent,
                                        borderRadius: BorderRadius.circular(AppTheme.radiusMD),
                                        boxShadow: !isBuy ? AppTheme.glassShadow : null,
                                      ),
                                      child: Center(
                                        child: Text(
                                          'SELL',
                                          style: AppTheme.labelLarge.copyWith(
                                            color: !isBuy ? Colors.white : AppTheme.textSecondary,
                                            fontSize: 16,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: AppTheme.spacing16),
                        
                        // Order Type Selector (only in PREMIUM mode)
                        if (AppSettingsService().isTradingEnabled)
                          RepaintBoundary(
                            child: GlassCard(
                              padding: const EdgeInsets.all(AppTheme.spacing16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Order Type',
                                    style: AppTheme.labelMedium.copyWith(
                                      color: AppTheme.textTertiary,
                                    ),
                                  ),
                                  const SizedBox(height: AppTheme.spacing12),
                                  Wrap(
                                    spacing: AppTheme.spacing8,
                                    runSpacing: AppTheme.spacing8,
                                    children: [
                                      _buildOrderTypeChip('Market', OrderType.market),
                                      _buildOrderTypeChip('Limit', OrderType.limit),
                                      _buildOrderTypeChip('Stop-Limit', OrderType.stopLimit),
                                      _buildOrderTypeChip('Stop-Market', OrderType.stopMarket),
                                    ],
                                  ),
                                  const SizedBox(height: AppTheme.spacing12),
                                  // Order Type Explanation
                                  Container(
                                    padding: const EdgeInsets.all(AppTheme.spacing12),
                                    decoration: BoxDecoration(
                                      color: AppTheme.primary.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(AppTheme.radiusMD),
                                      border: Border.all(color: AppTheme.primary.withOpacity(0.3)),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(Icons.info_outline, color: AppTheme.primary, size: 18),
                                        const SizedBox(width: AppTheme.spacing8),
                                        Expanded(
                                          child: Text(
                                            _getOrderTypeExplanation(_orderType),
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
                              ),
                            ),
                          ),
                        const SizedBox(height: AppTheme.spacing16),
                        
                        FutureBuilder<SharedPreferences>(
                          future: SharedPreferences.getInstance(),
                          builder: (context, snap) {
                            final paper = (snap.data?.getBool('paper_trading') ?? false);
                            return OpenOrdersCard(symbol: _selectedPair, paperMode: paper);
                          },
                        ),
                        const SizedBox(height: AppTheme.spacing16),

                        // Main Order Card - gated by permission (Read vs Trading)
                        if (tradingEnabled)
                          GlassCard(
                          padding: const EdgeInsets.all(AppTheme.spacing20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Pair Selector
                              Text(
                                'Trading Pair',
                                style: AppTheme.labelMedium.copyWith(
                                  color: AppTheme.textTertiary,
                                ),
                              ),
                              const SizedBox(height: AppTheme.spacing8),
                              _buildPairSelector(context),

                              const SizedBox(height: AppTheme.spacing20),

                              // Amount Input
                              Text(
                                'Amount',
                                style: AppTheme.labelMedium.copyWith(
                                  color: AppTheme.textTertiary,
                                ),
                              ),
                              const SizedBox(height: AppTheme.spacing8),
                              TextField(
                                controller: _amountCtrl,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                style: AppTheme.bodyLarge,
                                decoration: InputDecoration(
                                  hintText: '0.00',
                                  hintStyle: AppTheme.bodyLarge.copyWith(
                                    color: AppTheme.textDisabled,
                                  ),
                                  filled: true,
                                  fillColor: AppTheme.surfaceVariant,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(AppTheme.radiusMD),
                                    borderSide: BorderSide.none,
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: AppTheme.spacing16,
                                    vertical: AppTheme.spacing16,
                                  ),
                                  suffixText: _selectedPair.replaceAll('USDT', '').replaceAll('EUR', '').replaceAll('USD', ''),
                                  suffixStyle: AppTheme.bodyMedium.copyWith(
                                    color: AppTheme.textSecondary,
                                  ),
                                ),
                                onChanged: (v) {
                                  if (!_updatingFields) {
                                    setState(() {
                                      _updatingFields = true;
                                      final amt = double.tryParse(v) ?? 0.0;
                                      final price = double.tryParse(_priceCtrl.text) ?? 0.0;
                                      _totalCtrl.text = (amt * price).toStringAsFixed(2);
                                      _updatingFields = false;
                                    });
                                  }
                                },
                              ),

                              const SizedBox(height: AppTheme.spacing20),

                              // Limit Price (for Limit and Stop-Limit orders)
                              if (_orderType == OrderType.limit || _orderType == OrderType.stopLimit) ...[
                                Text(
                                  'Limit Price',
                                  style: AppTheme.labelMedium.copyWith(
                                    color: AppTheme.textTertiary,
                                  ),
                                ),
                                const SizedBox(height: AppTheme.spacing8),
                                TextField(
                                  controller: _limitPriceCtrl,
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                  style: AppTheme.bodyLarge,
                                  decoration: InputDecoration(
                                    hintText: 'Enter limit price',
                                    hintStyle: AppTheme.bodyLarge.copyWith(
                                      color: AppTheme.textDisabled,
                                    ),
                                    filled: true,
                                    fillColor: AppTheme.surfaceVariant,
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(AppTheme.radiusMD),
                                      borderSide: BorderSide.none,
                                    ),
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: AppTheme.spacing16,
                                      vertical: AppTheme.spacing16,
                                    ),
                                    prefixText: AppSettingsService.currencyPrefix(AppSettingsService().quoteCurrency),
                                    prefixStyle: AppTheme.bodyMedium.copyWith(
                                      color: AppTheme.textSecondary,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: AppTheme.spacing20),
                              ],

                              // Stop Price (for Stop-Limit and Stop-Market orders)
                              if (_orderType == OrderType.stopLimit || _orderType == OrderType.stopMarket) ...[
                                Text(
                                  'Stop Price',
                                  style: AppTheme.labelMedium.copyWith(
                                    color: AppTheme.textTertiary,
                                  ),
                                ),
                                const SizedBox(height: AppTheme.spacing8),
                                TextField(
                                  controller: _stopPriceCtrl,
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                  style: AppTheme.bodyLarge,
                                  decoration: InputDecoration(
                                    hintText: 'Enter stop price',
                                    hintStyle: AppTheme.bodyLarge.copyWith(
                                      color: AppTheme.textDisabled,
                                    ),
                                    filled: true,
                                    fillColor: AppTheme.surfaceVariant,
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(AppTheme.radiusMD),
                                      borderSide: BorderSide.none,
                                    ),
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: AppTheme.spacing16,
                                      vertical: AppTheme.spacing16,
                                    ),
                                    prefixText: AppSettingsService.currencyPrefix(AppSettingsService().quoteCurrency),
                                    prefixStyle: AppTheme.bodyMedium.copyWith(
                                      color: AppTheme.textSecondary,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: AppTheme.spacing20),
                              ],

                              // Current Price Display
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'Current Price',
                                    style: AppTheme.labelMedium.copyWith(
                                      color: AppTheme.textTertiary,
                                    ),
                                  ),
                                  Text(
                                    _priceCtrl.text.isEmpty ? 'Loading...' : '${AppSettingsService.currencyPrefix(AppSettingsService().quoteCurrency)}${double.tryParse(_priceCtrl.text)?.toStringAsFixed(2) ?? '0.00'}',
                                    style: AppTheme.monoMedium.copyWith(
                                      color: AppTheme.textPrimary,
                                    ),
                                  ),
                                ],
                              ),

                              const SizedBox(height: AppTheme.spacing12),

                              // Total Display
                              Container(
                                padding: const EdgeInsets.all(AppTheme.spacing16),
                                decoration: BoxDecoration(
                                  color: (isBuy ? AppTheme.buyGreen : AppTheme.sellRed).withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(AppTheme.radiusMD),
                                  border: Border.all(
                                    color: (isBuy ? AppTheme.buyGreen : AppTheme.sellRed).withOpacity(0.3),
                                    width: 1.5,
                                  ),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      'Total',
                                      style: AppTheme.labelLarge.copyWith(
                                        color: isBuy ? AppTheme.buyGreen : AppTheme.sellRed,
                                      ),
                                    ),
                                    Text(
                                      '${AppSettingsService.currencyPrefix(AppSettingsService().quoteCurrency)}${_totalCtrl.text.isEmpty ? '0.00' : _totalCtrl.text}',
                                      style: AppTheme.monoMedium.copyWith(
                                        color: isBuy ? AppTheme.buyGreen : AppTheme.sellRed,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        )
                        else
                          GlassCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(AppTheme.spacing8),
                                      decoration: BoxDecoration(
                                        color: AppTheme.warning.withOpacity(0.15),
                                        borderRadius: BorderRadius.circular(AppTheme.radiusSM),
                                        border: Border.all(color: AppTheme.warning.withOpacity(0.3)),
                                      ),
                                      child: const Icon(Icons.lock_outline, color: AppTheme.warning, size: 20),
                                    ),
                                    const SizedBox(width: AppTheme.spacing12),
                                    Expanded(
                                      child: Text(
                                        'Trading disabled (Read‑only mode)',
                                        style: AppTheme.headingMedium,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: AppTheme.spacing12),
                                Text(
                                  'You can view portfolio, market data and AI insights. Trading actions are disabled when API permission is Read Only.',
                                  style: AppTheme.bodyMedium.copyWith(color: AppTheme.textSecondary, height: 1.4),
                                ),
                                const SizedBox(height: AppTheme.spacing12),
                                OutlinedButton.icon(
                                  onPressed: () {
                                    Navigator.of(context).pushNamed('/welcome');
                                  },
                                  icon: const Icon(Icons.info_outline),
                                  label: const Text('Learn more'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: AppTheme.primary,
                                    side: const BorderSide(color: AppTheme.primary),
                                  ),
                                ),
                              ],
                            ),
                          ),

                        const SizedBox(height: AppTheme.spacing24),

                        // Execute Button - SUPER CLEAR (only when trading enabled)
                        if (tradingEnabled)
                          RepaintBoundary(
                          child: Container(
                            width: double.infinity,
                            height: 60,
                            decoration: BoxDecoration(
                              gradient: isBuy ? AppTheme.buyGradient : AppTheme.sellGradient,
                              borderRadius: BorderRadius.circular(AppTheme.radiusMD),
                              boxShadow: AppTheme.glowShadow,
                            ),
                            child: ElevatedButton(
                              onPressed: () async {
                              // Show confirmation dialog first
                              final confirmed = await _confirmOrder();
                              if (!confirmed) return;
                              
                              final prefs = await SharedPreferences.getInstance();
                              final bool paper = prefs.getBool('paper_trading') ?? false;
                              if (!tradingEnabled) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Trading disabled (Read Only). Enable Trading in Settings.')));
                                }
                                return;
                              }
                              if (_orderType == OrderType.market) {
                                if (paper) {
                                  final price = double.tryParse(_priceCtrl.text) ?? 0.0;
                                  final qty = double.tryParse(_amountCtrl.text) ?? 0.0;
                                  PaperBroker().execute(Trade(time: DateTime.now(), side: isBuy ? 'BUY' : 'SELL', price: price, quantity: qty));
                                  AchievementToast.show(context, 'first_paper_trade', 'Achievement unlocked: First Paper Trade!');
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Market order (Paper) executed')));
                                  }
                                } else {
                                  try {
                                    final double? qty = double.tryParse(_amountCtrl.text);
                                    final double? total = double.tryParse(_totalCtrl.text);
                                    final res = await BinanceService().placeMarketOrder(
                                      symbol: _selectedPair,
                                      side: isBuy ? 'BUY' : 'SELL',
                                      quantity: (qty != null && qty > 0) ? qty : null,
                                      quoteOrderQty: (total != null && total > 0) ? total : null,
                                    );
                                    // If protection enabled and BUY, place OCO (SELL) with TP/SL based on last price
                                    if (_ocoEnabled && isBuy) {
                                      final lastPrice = double.tryParse(_priceCtrl.text);
                                      final usePrice = lastPrice ?? (res['fills'] != null && (res['fills'] as List).isNotEmpty ? double.tryParse(((res['fills'] as List).first as Map)['price']?.toString() ?? '') : null);
                                      final double? filledQty = double.tryParse(res['executedQty']?.toString() ?? '') ?? qty;
                                      if (usePrice != null && filledQty != null && filledQty > 0) {
                                        final tp = usePrice * (1 + _takeProfitPct / 100.0);
                                        final sl = usePrice * (1 - _stopLossPct / 100.0);
                                        try {
                                          await BinanceService().placeOcoOrder(
                                            symbol: _selectedPair,
                                            side: 'SELL',
                                            quantity: filledQty,
                                            price: tp,
                                            stopPrice: sl,
                                          );
                                          if (context.mounted) {
                                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Protection OCO placed')));
                                          }
                                        } catch (e) {
                                          if (context.mounted) {
                                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('OCO error: $e')));
                                          }
                                        }
                                      }
                                    }
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text('Order sent: ${res['status']?.toString() ?? 'OK'}')),
                                      );
                                    }
                                  } catch (e) {
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text('Order error: $e')),
                                      );
                                    }
                                  }
                                }
                              } else if (_orderType == OrderType.limit) {
                                // LIMIT ORDER
                                try {
                                  final double? qty = double.tryParse(_amountCtrl.text);
                                  final double? limitPrice = double.tryParse(_limitPriceCtrl.text);
                                  
                                  if (qty == null || qty <= 0) {
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text('Please enter a valid amount')),
                                      );
                                    }
                                    return;
                                  }
                                  
                                  if (limitPrice == null || limitPrice <= 0) {
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text('Please enter a valid limit price')),
                                      );
                                    }
                                    return;
                                  }
                                  
                                  final res = await BinanceService().placeLimitOrder(
                                    symbol: _selectedPair,
                                    side: isBuy ? 'BUY' : 'SELL',
                                    quantity: qty,
                                    price: limitPrice,
                                  );
                                  
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('Limit order placed: ${res['status']?.toString() ?? 'OK'}')),
                                    );
                                  }
                                } catch (e) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('Limit order error: $e')),
                                    );
                                  }
                                }
                              } else if (_orderType == OrderType.stopLimit) {
                                // STOP-LIMIT ORDER
                                try {
                                  final double? qty = double.tryParse(_amountCtrl.text);
                                  final double? limitPrice = double.tryParse(_limitPriceCtrl.text);
                                  final double? stopPrice = double.tryParse(_stopPriceCtrl.text);
                                  
                                  if (qty == null || qty <= 0) {
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text('Please enter a valid amount')),
                                      );
                                    }
                                    return;
                                  }
                                  
                                  if (limitPrice == null || limitPrice <= 0) {
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text('Please enter a valid limit price')),
                                      );
                                    }
                                    return;
                                  }
                                  
                                  if (stopPrice == null || stopPrice <= 0) {
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text('Please enter a valid stop price')),
                                      );
                                    }
                                    return;
                                  }
                                  
                                  final res = await BinanceService().placeStopLimitOrder(
                                    symbol: _selectedPair,
                                    side: isBuy ? 'BUY' : 'SELL',
                                    quantity: qty,
                                    price: limitPrice,
                                    stopPrice: stopPrice,
                                  );
                                  
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('Stop-Limit order placed: ${res['status']?.toString() ?? 'OK'}')),
                                    );
                                  }
                                } catch (e) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('Stop-Limit order error: $e')),
                                    );
                                  }
                                }
                              } else if (_orderType == OrderType.stopMarket) {
                                // STOP-MARKET ORDER
                                try {
                                  final double? qty = double.tryParse(_amountCtrl.text);
                                  final double? stopPrice = double.tryParse(_stopPriceCtrl.text);
                                  
                                  if (qty == null || qty <= 0) {
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text('Please enter a valid amount')),
                                      );
                                    }
                                    return;
                                  }
                                  
                                  if (stopPrice == null || stopPrice <= 0) {
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text('Please enter a valid stop price')),
                                      );
                                    }
                                    return;
                                  }
                                  
                                  final res = await BinanceService().placeStopMarketOrder(
                                    symbol: _selectedPair,
                                    side: isBuy ? 'BUY' : 'SELL',
                                    quantity: qty,
                                    stopPrice: stopPrice,
                                  );
                                  
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('Stop-Market order placed: ${res['status']?.toString() ?? 'OK'}')),
                                    );
                                  }
                                } catch (e) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('Stop-Market order error: $e')),
                                    );
                                  }
                                }
                              }
                            },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.transparent,
                                shadowColor: Colors.transparent,
                                padding: EdgeInsets.zero,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(AppTheme.radiusMD),
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    isBuy ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                                    color: Colors.white,
                                    size: 24,
                                  ),
                                  const SizedBox(width: AppTheme.spacing8),
                                  Text(
                                    '${isBuy ? 'BUY' : 'SELL'} ${_formatPairLabel(_selectedPair).split('/').first}',
                                    style: AppTheme.headingMedium.copyWith(
                                      color: Colors.white,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: AppTheme.spacing32),
                      ]),
                ),
              ),
            ],
          ),
        ),
        ),
      ),
    );
  }

  // Removed unused _buildTextField

  Widget _buildAmountField() {
    final String base = _selectedPair.replaceAll(RegExp(r'(USDT|USDC|EUR)$'), '');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Amount', style: AppTheme.headingSmall),
        const SizedBox(height: AppTheme.spacing8),
        TextField(
          controller: _amountCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: AppTheme.bodyLarge,
          decoration: InputDecoration(
            hintText: '0.0',
            hintStyle: AppTheme.bodyLarge.copyWith(color: AppTheme.textTertiary),
            filled: true,
            fillColor: AppTheme.surfaceVariant,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppTheme.radiusMD),
              borderSide: BorderSide.none,
            ),
            suffixText: base,
            suffixStyle: AppTheme.bodyMedium.copyWith(color: AppTheme.textSecondary),
          ),
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => FocusScope.of(context).unfocus(),
          onChanged: (_) {
            if (_updatingFields) return;
            _updatingFields = true;
            final qty = double.tryParse(_amountCtrl.text) ?? 0.0;
            final price = double.tryParse(_priceCtrl.text) ?? 0.0;
            final total = qty * price;
            _totalCtrl.text = total > 0 ? total.toStringAsFixed(2) : '';
            _updatingFields = false;
            setState(() {});
          },
        ),
      ],
    );
  }

  Widget _buildLimitPriceField() {
    final String quote = _selectedPair.endsWith('USDT')
        ? 'USDT'
        : _selectedPair.endsWith('USDC')
            ? 'USDC'
            : 'EUR';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Limit Price', style: AppTheme.headingSmall),
        const SizedBox(height: AppTheme.spacing8),
        TextField(
          controller: _priceCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: AppTheme.bodyLarge,
          decoration: InputDecoration(
            hintText: '0.00',
            hintStyle: AppTheme.bodyLarge.copyWith(color: AppTheme.textTertiary),
            filled: true,
            fillColor: AppTheme.surfaceVariant,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppTheme.radiusMD),
              borderSide: BorderSide.none,
            ),
            prefixText: quote == 'EUR' ? '€ ' : (quote == 'USDC' || quote == 'USDT') ? '\$ ' : '',
            prefixStyle: AppTheme.bodyMedium.copyWith(color: AppTheme.textSecondary),
            suffixText: quote,
            suffixStyle: AppTheme.bodyMedium.copyWith(color: AppTheme.textSecondary),
          ),
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => FocusScope.of(context).unfocus(),
          onChanged: (_) {
            if (_updatingFields) return;
            _updatingFields = true;
            final qty = double.tryParse(_amountCtrl.text) ?? 0.0;
            final price = double.tryParse(_priceCtrl.text) ?? 0.0;
            final total = qty * price;
            _totalCtrl.text = total > 0 ? total.toStringAsFixed(2) : '';
            _updatingFields = false;
            setState(() {});
          },
        ),
      ],
    );
  }

  Widget _buildAmountSummary() {
    if (_amountCtrl.text.isEmpty || _priceCtrl.text.isEmpty) return const SizedBox.shrink();
    final double qty = double.tryParse(_amountCtrl.text) ?? 0.0;
    final double price = double.tryParse(_priceCtrl.text) ?? 0.0;
    final double total = qty * price;
    final String quote = _selectedPair.endsWith('USDT')
        ? 'USDT'
        : _selectedPair.endsWith('USDC')
            ? 'USDC'
            : 'EUR';
    return Padding(
      padding: const EdgeInsets.only(top: 8.0),
      child: Align(
        alignment: Alignment.centerRight,
        child: Text('Total: ${total.toStringAsFixed(2)} $quote'),
      ),
    );
  }

  Widget _buildTotalFiatField() {
    final String quote = _selectedPair.endsWith('USDT')
        ? 'USDT'
        : _selectedPair.endsWith('USDC')
            ? 'USDC'
            : 'EUR';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Total ($quote)', style: AppTheme.headingSmall),
        const SizedBox(height: AppTheme.spacing8),
        TextField(
          controller: _totalCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: AppTheme.bodyLarge,
          decoration: InputDecoration(
            hintText: '0.00',
            hintStyle: AppTheme.bodyLarge.copyWith(color: AppTheme.textTertiary),
            filled: true,
            fillColor: AppTheme.surfaceVariant,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppTheme.radiusMD),
              borderSide: BorderSide.none,
            ),
            prefixText: quote == 'EUR' ? '€ ' : (quote == 'USDC' || quote == 'USDT') ? '\$ ' : '',
            prefixStyle: AppTheme.bodyMedium.copyWith(color: AppTheme.textSecondary),
            suffixText: quote,
            suffixStyle: AppTheme.bodyMedium.copyWith(color: AppTheme.textSecondary),
          ),
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => FocusScope.of(context).unfocus(),
          onChanged: (_) {
            if (_updatingFields) return;
            _updatingFields = true;
            final total = double.tryParse(_totalCtrl.text) ?? 0.0;
            final price = double.tryParse(_priceCtrl.text) ?? 0.0;
            if (price > 0) {
              final qty = total / price;
              _amountCtrl.text = qty > 0 ? qty.toStringAsFixed(8) : '';
            }
            _updatingFields = false;
            setState(() {});
          },
        ),
      ],
    );
  }

  // Removed unused _buildAiIntervalChips

  String _orderTypeLabel(OrderType t) {
    switch (t) {
      case OrderType.market:
        return 'Market';
      case OrderType.limit:
        return 'Limit';
      case OrderType.stopLimit:
        return 'Stop-Limit';
      case OrderType.stopMarket:
        return 'Stop-Market';
    }
  }

  IconData _orderTypeIcon(OrderType t) {
    switch (t) {
      case OrderType.market:
        return Icons.flash_on;
      case OrderType.limit:
        return Icons.price_check;
      case OrderType.stopLimit:
        return Icons.stop_circle;
      case OrderType.stopMarket:
        return Icons.stop;
    }
  }

  Future<void> _pickOrderType() async {
    final theme = Theme.of(context);
    final OrderType? selected = await showModalBottomSheet<OrderType>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        Widget tile(OrderType t, String title, String subtitle) {
          final bool isSel = _orderType == t;
          return ListTile(
            leading: Icon(_orderTypeIcon(t), color: isSel ? theme.colorScheme.primary : null),
            title: Text(title, style: TextStyle(fontWeight: isSel ? FontWeight.bold : FontWeight.w500)),
            subtitle: Text(subtitle),
            trailing: isSel ? Icon(Icons.check, color: theme.colorScheme.primary) : null,
            onTap: () => Navigator.of(context).pop(t),
          );
        }

        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              tile(OrderType.market, 'Market', 'Executes immediately at current price'),
              tile(OrderType.limit, 'Limit', 'Executes at your specified price or better'),
              tile(OrderType.stopLimit, 'Stop-Limit', 'Activates limit order at stop price'),
              tile(OrderType.stopMarket, 'Stop-Market', 'Activates market order at stop price'),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );

    if (selected != null) {
      setState(() => _orderType = selected);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('order_type', _orderType.name);
    }
  }

  Widget _buildOrderTypeBanner(BuildContext context) {
    return InkWell(
      onTap: _pickOrderType,
      child: Container(
        padding: const EdgeInsets.all(AppTheme.spacing16),
        decoration: BoxDecoration(
          color: AppTheme.surfaceVariant,
          borderRadius: BorderRadius.circular(AppTheme.radiusMD),
          border: Border.all(
            color: AppTheme.glassBorder,
            width: 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(AppTheme.spacing8),
              decoration: BoxDecoration(
                gradient: AppTheme.primaryGradient,
                borderRadius: BorderRadius.circular(AppTheme.radiusSM),
              ),
              child: Icon(
                _orderTypeIcon(_orderType),
                color: Colors.white,
                size: 20,
              ),
            ),
            const SizedBox(width: AppTheme.spacing12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Order Type', style: AppTheme.bodySmall.copyWith(color: AppTheme.textTertiary)),
                  const SizedBox(height: 2),
                  Text(_orderTypeLabel(_orderType), style: AppTheme.bodyLarge.copyWith(fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            Icon(Icons.keyboard_arrow_down_rounded, color: AppTheme.textSecondary),
          ],
        ),
      ),
    );
  }

  Widget _buildPairSelector(BuildContext context) {
    return InkWell(
      onTap: () async {
        await showModalBottomSheet<void>(
          context: context,
          showDragHandle: true,
          isScrollControlled: true,
          backgroundColor: AppTheme.surface,
          builder: (context) {
            return SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(AppTheme.spacing16),
                    child: Text('Select Pair', style: AppTheme.headingLarge),
                  ),
                  SizedBox(
                    height: MediaQuery.of(context).size.height * 0.6,
                    child: _loadingPairs
                        ? const Center(child: CircularProgressIndicator())
                        : _pairs.isEmpty
                            ? Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(AppTheme.spacing24),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.info_outline, size: 48, color: AppTheme.textTertiary),
                                      const SizedBox(height: AppTheme.spacing16),
                                      Text(
                                        'No trading pairs available',
                                        style: AppTheme.headingMedium,
                                        textAlign: TextAlign.center,
                                      ),
                                      const SizedBox(height: AppTheme.spacing8),
                                      Text(
                                        'Make sure you have coins in your portfolio (>\$5 value)',
                                        style: AppTheme.bodyMedium.copyWith(color: AppTheme.textSecondary),
                                        textAlign: TextAlign.center,
                                      ),
                                    ],
                                  ),
                                ),
                              )
                            : ListView.builder(
                                itemCount: _pairs.length,
                                itemBuilder: (context, index) {
                                  final m = _pairs[index];
                                  final sym = m['symbol'] ?? '';
                                  final base = m['base'] ?? '';
                                  final quote = m['quote'] ?? '';
                                  return ListTile(
                                    title: Text('$base/$quote', style: AppTheme.bodyLarge),
                                    subtitle: Text(sym, style: AppTheme.bodySmall),
                                    onTap: () {
                                      setState(() => _selectedPair = sym);
                                      Navigator.of(context).pop();
                                      _loadCurrentPrice();
                                    },
                                  );
                                },
                              ),
                  ),
                ],
              ),
            );
          },
        );
      },
      child: Container(
        padding: const EdgeInsets.all(AppTheme.spacing16),
        decoration: BoxDecoration(
          color: Theme.of(context).brightness == Brightness.dark 
              ? AppTheme.surfaceVariant 
              : Colors.grey[100],
          borderRadius: BorderRadius.circular(AppTheme.radiusMD),
          border: Border.all(
            color: Theme.of(context).brightness == Brightness.dark 
                ? AppTheme.glassBorder 
                : Colors.grey[300]!,
            width: 1,
          ),
        ),
        child: Row(
          children: [
            CryptoAvatar(
              symbol: _selectedPair.replaceAll('USDT', '').replaceAll('EUR', '').replaceAll('USDC', ''),
              size: 36,
              showBorder: true,
            ),
            const SizedBox(width: AppTheme.spacing12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Coin/Pair', style: AppTheme.bodySmall.copyWith(
                    color: Theme.of(context).brightness == Brightness.dark 
                        ? AppTheme.textTertiary 
                        : AppTheme.textTertiaryLight,
                  )),
                  const SizedBox(height: 2),
                  Text(_formatPairLabel(_selectedPair), style: AppTheme.bodyLarge.copyWith(
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).brightness == Brightness.dark 
                        ? AppTheme.textPrimary 
                        : AppTheme.textPrimaryLight,
                  )),
                ],
              ),
            ),
            Icon(Icons.keyboard_arrow_down_rounded, color: Theme.of(context).brightness == Brightness.dark 
                ? AppTheme.textSecondary 
                : AppTheme.textSecondaryLight),
          ],
        ),
      ),
    );
  }

  String _formatPairLabel(String sym) {
    if (sym.endsWith('USDT')) return sym.replaceAll('USDT', '/USDT');
    if (sym.endsWith('USDC')) return sym.replaceAll('USDC', '/USDC');
    if (sym.endsWith('EUR')) return sym.replaceAll('EUR', '/EUR');
    return sym;
  }
  
  /// Build Order Type chip
  Widget _buildOrderTypeChip(String label, OrderType type) {
    final bool selected = _orderType == type;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() {
          _orderType = type;
          debugPrint('Orders: Order type changed to: ${type.name}');
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppTheme.spacing16,
          vertical: AppTheme.spacing8,
        ),
        decoration: BoxDecoration(
          gradient: selected ? AppTheme.primaryGradient : null,
          color: selected ? null : AppTheme.glassWhite,
          borderRadius: BorderRadius.circular(AppTheme.radiusSM),
          border: Border.all(
            color: selected ? Colors.transparent : AppTheme.glassBorder,
          ),
        ),
        child: Text(
          label,
          style: AppTheme.bodyMedium.copyWith(
            color: selected ? Colors.white : AppTheme.textSecondary,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }
  
  /// Get explanation for each order type
  String _getOrderTypeExplanation(OrderType type) {
    switch (type) {
      case OrderType.market:
        return 'Market order executes immediately at current market price. Best for quick trades.';
      case OrderType.limit:
        return 'Limit order executes only at your specified price or better. Good for getting exact entry price.';
      case OrderType.stopLimit:
        return 'Stop-Limit activates a limit order when price reaches stop price. Used for stop-loss or breakout entries.';
      case OrderType.stopMarket:
        return 'Stop-Market activates a market order when price reaches stop price. Guarantees execution but not price.';
    }
  }
  
  /// Show order confirmation dialog before executing trade
  Future<bool> _confirmOrder() async {
    final amount = _amountCtrl.text;
    final price = _priceCtrl.text;
    final total = _totalCtrl.text;
    final action = isBuy ? 'BUY' : 'SELL';
    final baseCurrency = _selectedPair.replaceAll('USDT', '').replaceAll('EUR', '').replaceAll('USDC', '');
    final quoteCurrency = AppSettingsService().quoteCurrency.toUpperCase();
    
    return await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusLG),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(AppTheme.spacing8),
              decoration: BoxDecoration(
                gradient: isBuy ? AppTheme.buyGradient : AppTheme.sellGradient,
                borderRadius: BorderRadius.circular(AppTheme.radiusSM),
              ),
              child: Icon(
                isBuy ? Icons.arrow_upward : Icons.arrow_downward,
                color: Colors.white,
                size: 20,
              ),
            ),
            const SizedBox(width: AppTheme.spacing12),
            Expanded(
              child: Text(
                'Confirm $action Order',
                style: AppTheme.headingLarge,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'You are about to $action:',
              style: AppTheme.bodyMedium.copyWith(color: AppTheme.textSecondary),
            ),
            const SizedBox(height: AppTheme.spacing16),
            Container(
              padding: const EdgeInsets.all(AppTheme.spacing16),
              decoration: BoxDecoration(
                color: (isBuy ? AppTheme.buyGreen : AppTheme.sellRed).withOpacity(0.1),
                borderRadius: BorderRadius.circular(AppTheme.radiusMD),
                border: Border.all(
                  color: (isBuy ? AppTheme.buyGreen : AppTheme.sellRed).withOpacity(0.3),
                  width: 1.5,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Amount:',
                        style: AppTheme.bodyMedium.copyWith(color: AppTheme.textSecondary),
                      ),
                      Text(
                        '$amount $baseCurrency',
                        style: AppTheme.monoMedium.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppTheme.spacing8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Price:',
                        style: AppTheme.bodyMedium.copyWith(color: AppTheme.textSecondary),
                      ),
                      Text(
                        '~${AppSettingsService.currencyPrefix(quoteCurrency)}$price',
                        style: AppTheme.monoMedium.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                  const Divider(height: AppTheme.spacing16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Total:',
                        style: AppTheme.bodyMedium.copyWith(
                          color: AppTheme.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        '${AppSettingsService.currencyPrefix(quoteCurrency)}$total',
                        style: AppTheme.monoLarge.copyWith(
                          fontWeight: FontWeight.w700,
                          color: isBuy ? AppTheme.buyGreen : AppTheme.sellRed,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppTheme.spacing16),
            Container(
              padding: const EdgeInsets.all(AppTheme.spacing12),
              decoration: BoxDecoration(
                color: AppTheme.warning.withOpacity(0.1),
                borderRadius: BorderRadius.circular(AppTheme.radiusMD),
                border: Border.all(
                  color: AppTheme.warning.withOpacity(0.3),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: AppTheme.warning, size: 20),
                  const SizedBox(width: AppTheme.spacing8),
                  Expanded(
                    child: Text(
                      'This action cannot be undone',
                      style: AppTheme.bodySmall.copyWith(
                        color: AppTheme.warning,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              'Cancel',
              style: AppTheme.bodyMedium.copyWith(color: AppTheme.textSecondary),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: isBuy ? AppTheme.buyGreen : AppTheme.sellRed,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(
                horizontal: AppTheme.spacing24,
                vertical: AppTheme.spacing12,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppTheme.radiusMD),
              ),
            ),
            child: Text(
              'Confirm $action',
              style: AppTheme.bodyMedium.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    ) ?? false;
  }
}


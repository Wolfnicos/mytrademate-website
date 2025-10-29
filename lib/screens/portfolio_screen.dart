import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_card.dart';
import '../widgets/crypto_avatar.dart';
import '../services/binance_service.dart';
import '../services/app_settings_service.dart';
import '../utils/responsive.dart';

class PortfolioScreen extends StatefulWidget {
  const PortfolioScreen({super.key});

  @override
  State<PortfolioScreen> createState() => _PortfolioScreenState();
}

class _PortfolioScreenState extends State<PortfolioScreen> {
  final BinanceService _binance = BinanceService();
  bool _isLoading = true;
  Map<String, double> _balances = {};
  Map<String, double> _prices = {};
  double _totalValue = 0.0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadPortfolio();
    // Listen to quote currency changes and reload portfolio
    AppSettingsService().addListener(_onSettingsChanged);
  }

  @override
  void dispose() {
    AppSettingsService().removeListener(_onSettingsChanged);
    super.dispose();
  }

  void _onSettingsChanged() {
    // Reload portfolio when quote currency changes
    debugPrint('Portfolio: Quote currency changed, reloading portfolio...');
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
      final prices = <String, double>{};

      // Add quote currency balance directly (EUR, USD, USDT, USDC)
      total += balances[quote] ?? 0.0;
      prices[quote] = 1.0; // Quote currency is always 1:1

      // Convert other assets to quote currency
      for (final entry in balances.entries) {
        final asset = entry.key;
        final amount = entry.value;

        if (asset == quote || amount <= 0.0) continue;

        try {
          // Try to get price for this asset in quote currency
          final ticker = await _binance.fetchTicker24hWithFallback([
            '$asset$quote',
            '${asset}USDT',
            '${asset}EUR',
            '${asset}USDC'
          ]);
          final price = ticker['lastPrice'] ?? 0.0;
          prices[asset] = price;
          total += amount * price;
        } catch (e) {
          debugPrint('Portfolio: Could not get price for $asset: $e');
          prices[asset] = 0.0;
        }
      }

      if (mounted) {
        setState(() {
          _balances = balances;
          _prices = prices;
          _totalValue = total;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Portfolio: Error loading portfolio: $e');
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
    return Scaffold(
      body: SafeArea(
        child: Responsive.constrainWidth(
            context,
            NestedScrollView(
            headerSliverBuilder: (context, innerBoxIsScrolled) {
              return [
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
                      'Portfolio',
                      style: AppTheme.displayLarge.copyWith(
                        color: Theme.of(context).colorScheme.onBackground,
                      ),
                    ),
                  ),
                ),

                // Portfolio Value Card - Scrollable
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacing20),
                    child: _PortfolioValueCard(
                      isLoading: _isLoading,
                      error: _error,
                      totalValue: _totalValue,
                      onRefresh: _loadPortfolio,
                    ),
                  ),
                ),

                SliverToBoxAdapter(
                  child: const SizedBox(height: AppTheme.spacing8),
                ),

                // Holdings Section Header
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppTheme.spacing20,
                      AppTheme.spacing12,
                      AppTheme.spacing20,
                      AppTheme.spacing12,
                    ),
                    child: Text(
                      'Holdings',
                      style: AppTheme.headingLarge.copyWith(
                        color: AppTheme.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ];
            },
            body: _HoldingsList(
              isLoading: _isLoading,
              balances: _balances,
              prices: _prices,
              error: _error,
              onRefresh: _loadPortfolio,
            ),
          ),
        ),
      ),
    );
  }

}

class _PortfolioValueCard extends StatelessWidget {
  final bool isLoading;
  final String? error;
  final double totalValue;
  final VoidCallback onRefresh;

  const _PortfolioValueCard({
    required this.isLoading,
    required this.error,
    required this.totalValue,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final quote = AppSettingsService().quoteCurrency;
    final prefix = AppSettingsService.currencyPrefix(quote);

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(AppTheme.spacing12),
                decoration: BoxDecoration(
                  gradient: AppTheme.primaryGradient,
                  borderRadius: BorderRadius.circular(AppTheme.radiusMD),
                ),
                child: const Icon(
                  Icons.account_balance_wallet,
                  color: Colors.white,
                  size: 24,
                ),
              ),
              const SizedBox(width: AppTheme.spacing12),
              Expanded(
                child: Text(
                  'Total Portfolio Value',
                  style: AppTheme.headingMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: onRefresh,
                color: AppTheme.textSecondary,
              ),
            ],
          ),
          const SizedBox(height: AppTheme.spacing20),

          if (isLoading)
            const Center(child: CircularProgressIndicator())
          else if (error != null)
            Text(
              error!,
              style: AppTheme.bodyMedium.copyWith(color: AppTheme.error),
            )
          else
            Text(
              '$prefix${totalValue.toStringAsFixed(2)}',
              style: AppTheme.displayLarge.copyWith(
                fontSize: 40,
                fontWeight: FontWeight.w700,
              ),
            ),

          const SizedBox(height: AppTheme.spacing12),

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
                  'Live portfolio value from Binance',
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

class _HoldingsList extends StatelessWidget {
  final bool isLoading;
  final Map<String, double> balances;
  final Map<String, double> prices;
  final String? error;
  final VoidCallback onRefresh;

  const _HoldingsList({
    required this.isLoading,
    required this.balances,
    required this.prices,
    required this.error,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: AppTheme.error),
            const SizedBox(height: AppTheme.spacing16),
            Text(
              error!,
              style: AppTheme.headingMedium.copyWith(color: AppTheme.error),
            ),
            const SizedBox(height: AppTheme.spacing16),
            ElevatedButton.icon(
              onPressed: onRefresh,
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

    // Filter out zero balances and holdings below $5, then sort by value (descending)
    final holdings = balances.entries
        .where((e) => e.value > 0.0)
        .map((e) {
          final asset = e.key;
          final amount = e.value;
          final price = prices[asset] ?? 0.0;
          final value = amount * price;
          return MapEntry(asset, {'amount': amount, 'price': price, 'value': value});
        })
        .where((e) => (e.value['value'] as double) >= 5.0) // Hide coins below $5
        .toList()
      ..sort((a, b) => (b.value['value'] as double).compareTo(a.value['value'] as double));

    if (holdings.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.account_balance_wallet, size: 64, color: AppTheme.textTertiary),
            const SizedBox(height: AppTheme.spacing16),
            Text(
              'No Holdings',
              style: AppTheme.headingLarge.copyWith(color: AppTheme.textSecondary),
            ),
            const SizedBox(height: AppTheme.spacing8),
            Text(
              'Your crypto holdings will appear here',
              style: AppTheme.bodyMedium.copyWith(color: AppTheme.textTertiary),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(AppTheme.spacing20),
      itemCount: holdings.length,
      itemBuilder: (context, index) {
        final entry = holdings[index];
        final asset = entry.key;
        final data = entry.value;
        final amount = data['amount'] as double;
        final price = data['price'] as double;
        final value = data['value'] as double;

        return Padding(
          padding: const EdgeInsets.only(bottom: AppTheme.spacing12),
          child: _HoldingCard(
            asset: asset,
            amount: amount,
            price: price,
            value: value,
          ),
        );
      },
    );
  }
}

class _HoldingCard extends StatelessWidget {
  final String asset;
  final double amount;
  final double price;
  final double value;

  const _HoldingCard({
    required this.asset,
    required this.amount,
    required this.price,
    required this.value,
  });

  IconData _getIcon(String asset) {
    switch (asset.toUpperCase()) {
      case 'BTC':
        return Icons.currency_bitcoin;
      case 'ETH':
        return Icons.diamond_outlined;
      case 'BNB':
        return Icons.attach_money;
      case 'SOL':
        return Icons.sunny;
      case 'WLFI':
        return Icons.account_balance;
      case 'TRUMP':
        return Icons.person;
      case 'EUR':
      case 'USD':
      case 'USDT':
      case 'USDC':
        return Icons.euro_symbol;
      default:
        return Icons.monetization_on;
    }
  }

  String _getDisplayName(String asset) {
    switch (asset.toUpperCase()) {
      case 'BTC':
        return 'Bitcoin';
      case 'ETH':
        return 'Ethereum';
      case 'BNB':
        return 'BNB';
      case 'SOL':
        return 'Solana';
      case 'WLFI':
        return 'WLFI';
      case 'TRUMP':
        return 'TRUMP';
      case 'USDT':
        return 'Tether';
      case 'USDC':
        return 'USD Coin';
      default:
        return asset;
    }
  }

  @override
  Widget build(BuildContext context) {
    final quote = AppSettingsService().quoteCurrency;
    final prefix = AppSettingsService.currencyPrefix(quote);

    return GlassCard(
      child: Row(
        children: [
          // Crypto logo from CoinGecko
          CryptoAvatar(symbol: asset, size: 48),
          const SizedBox(width: AppTheme.spacing16),

          // Name & Amount
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _getDisplayName(asset),
                  style: AppTheme.headingMedium,
                ),
                const SizedBox(height: AppTheme.spacing4),
                Text(
                  '$amount $asset',
                  style: AppTheme.bodyMedium.copyWith(color: AppTheme.textSecondary),
                ),
              ],
            ),
          ),

          // Value & Price
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '$prefix${value.toStringAsFixed(2)}',
                style: AppTheme.headingMedium.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: AppTheme.spacing4),
              Text(
                price > 0 ? '$prefix${price.toStringAsFixed(2)}' : '-',
                style: AppTheme.bodySmall.copyWith(
                  color: AppTheme.textTertiary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

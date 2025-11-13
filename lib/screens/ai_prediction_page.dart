import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../ml/crypto_ml_service.dart';
import '../services/app_settings_service.dart';
import '../widgets/premium_card.dart';
import '../widgets/upgrade_banner.dart';
import '../providers/subscription_provider.dart';
import 'paywall_screen.dart';

class AiPredictionPage extends StatefulWidget {
  const AiPredictionPage({super.key});

  @override
  State<AiPredictionPage> createState() => _AiPredictionPageState();
}

class _AiPredictionPageState extends State<AiPredictionPage> {
  String _action = 'HOLD';
  List<double> _probabilities = <double>[0.33, 0.34, 0.33];
  bool _isLoading = true;
  bool _isModelReady = false;
  bool _isFetchingData = false;
  String _errorMessage = '';
  String _selectedSymbol = 'BTCUSDT';
  String _interval = '4h'; // Default to 4H (free tier)

  // final BinanceService _binanceService = BinanceService();
  final List<String> _bases = const ['BTC','ETH','BNB','SOL','WLFI','TRUMP'];

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    setState(() => _isLoading = true);
    await CryptoMLService().initialize();
    // Load saved quote and base selection if any
    final quote = AppSettingsService().quoteCurrency;
    final opts = _buildPairOptions(quote);
    if (!opts.contains(_selectedSymbol)) {
      _selectedSymbol = opts.first;
    }
    setState(() {
      _isLoading = false;
      _isModelReady = true;
    });
    if (mounted && _isModelReady) {
      // Auto-run once to populate UI
      await _runPrediction();
    }
  }

  Future<void> _runPrediction() async {
    if (!_isModelReady) return;

    // Check if timeframe is locked
    final subscription = Provider.of<SubscriptionProvider>(context, listen: false);
    final isProUser = subscription.isProUser;
    final isLockedTimeframe = ['5m', '15m', '1h', '1d'].contains(_interval);

    if (isLockedTimeframe && !isProUser) {
      // Show paywall instead of running prediction
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const PaywallScreen()),
        );
      }
      return;
    }

    setState(() {
      _isFetchingData = true;
      _errorMessage = '';
    });

    try {
      // Get coin from symbol (e.g., BTCUSDT -> BTC)
      final coin = _selectedSymbol.replaceAll(RegExp(r'(USDT|EUR|USDC)$'), '');

      debugPrint('▶️ AIPage: fetching ML prediction for $coin @$_interval');

      // NEW: CryptoMLService now fetches candles for EACH model's timeframe!
      final res = await CryptoMLService().getPrediction(
        coin: coin,
        symbol: _selectedSymbol,
        timeframe: _interval,
      );

      debugPrint('ℹ️ AIPage: CryptoML result action=${res.action} conf=${res.confidence.toStringAsFixed(3)}');

      setState(() {
        _action = res.action;
        _probabilities = [
          res.probabilities['SELL'] ?? 0.0,
          res.probabilities['HOLD'] ?? 0.0,
          res.probabilities['BUY'] ?? 0.0,
        ];
        _isFetchingData = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Error: $e';
        _isFetchingData = false;
      });
    }
  }

  Widget _buildSignalWidget() {
    final maxProb = _probabilities.reduce((a, b) => a > b ? a : b);
    return SignalIndicator(
      signal: _action,
      confidence: maxProb,
    );
  }

  Widget _buildProbabilityBar(String label, double value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
            Text(
              '${(value * 100).toStringAsFixed(1)}%',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: value,
            minHeight: 8,
            backgroundColor: color.withOpacity(0.15),
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final quote = AppSettingsService().quoteCurrency;
    final options = _buildPairOptions(quote);
    final selected = options.contains(_selectedSymbol) ? _selectedSymbol : options.first;
    if (_selectedSymbol != selected) {
      // keep state coherent with available items
      _selectedSymbol = selected;
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Motor de Decizie AI')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : !_isModelReady
              ? const Center(child: Text('Eroare la încărcarea modelului.', style: TextStyle(color: Colors.red)))
              : SafeArea(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Upgrade Banner (for free users)
                        const UpgradeBanner(),

                        // Symbol Selector - Premium Design
                        PremiumCard(
                          useGradient: true,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Icon(
                                      Icons.currency_bitcoin,
                                      color: Theme.of(context).colorScheme.primary,
                                      size: 24,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Text(
                                    'Select Trading Pair',
                                    style: Theme.of(context).textTheme.titleLarge,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16),
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: DropdownButton<String>(
                                  value: selected,
                                  isExpanded: true,
                                  underline: const SizedBox(),
                                  icon: const Icon(Icons.keyboard_arrow_down_rounded),
                                  style: Theme.of(context).textTheme.titleMedium,
                                  items: options.map((symbol) {
                                    return DropdownMenuItem(
                                      value: symbol,
                                      child: Row(
                                        children: [
                                          Container(
                                            width: 8,
                                            height: 8,
                                            decoration: BoxDecoration(
                                              color: Theme.of(context).colorScheme.primary,
                                              shape: BoxShape.circle,
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Text(symbol, style: const TextStyle(fontWeight: FontWeight.w600)),
                                        ],
                                      ),
                                    );
                                  }).toList(),
                                  onChanged: (value) {
                                    if (value != null) {
                                      setState(() => _selectedSymbol = value);
                                    }
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),

                        // Signal Display - Premium with Animation
                        Center(child: _buildSignalWidget()),
                        const SizedBox(height: 24),

                        // Interval selector
                        Consumer<SubscriptionProvider>(
                          builder: (context, subscription, _) {
                            final isProUser = subscription.isProUser;
                            return Wrap(
                              alignment: WrapAlignment.center,
                              spacing: 8,
                              children: [
                                {'label': isProUser ? '5m' : '5m 🔒 Pro', 'value': '5m'},
                                {'label': isProUser ? '15m' : '15m 🔒 Pro', 'value': '15m'},
                                {'label': isProUser ? '1H' : '1H 🔒 Pro', 'value': '1h'},
                                {'label': isProUser ? '4H' : '4H FREE', 'value': '4h'},
                                {'label': isProUser ? '1D' : '1D 🔒 Pro', 'value': '1d'},
                              ].map((item) {
                                final bool isSel = _interval == item['value'];
                                final isLocked = !isProUser && ['5m', '15m', '1h', '1d'].contains(item['value']);
                                return GestureDetector(
                                  onTap: isLocked ? () {
                                    // Show paywall when tapping locked timeframe
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(builder: (context) => const PaywallScreen()),
                                    );
                                  } : null,
                                  child: ChoiceChip(
                                    label: Text(item['label'] as String),
                                    selected: isSel,
                                    onSelected: isLocked ? null : (_) {
                                      setState(() => _interval = item['value'] as String);
                                    },
                                    backgroundColor: isLocked ? Colors.grey.withOpacity(0.2) : null,
                                  ),
                                );
                              }).toList(),
                            );
                          },
                        ),
                        const SizedBox(height: 16),

                        // Probabilities - Modern Cards
                        PremiumCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Probability Distribution',
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              const SizedBox(height: 20),
                              _buildProbabilityBar('SELL', _probabilities[0], const Color(0xFFFF3B30)),
                              const SizedBox(height: 12),
                              _buildProbabilityBar('HOLD', _probabilities[1], const Color(0xFFFF9500)),
                              const SizedBox(height: 12),
                              _buildProbabilityBar('BUY', _probabilities[2], const Color(0xFF00C853)),
                            ],
                          ),
                        ),

                        // Error Message - Premium Style
                        if (_errorMessage.isNotEmpty) ...[
                          const SizedBox(height: 20),
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFF3B30).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: const Color(0xFFFF3B30).withOpacity(0.3),
                                width: 2,
                              ),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.error_outline, color: Color(0xFFFF3B30)),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    _errorMessage,
                                    style: const TextStyle(color: Color(0xFFFF3B30)),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],

                        const SizedBox(height: 24),

                        // Predict Button - Gradient Premium
                        GradientButton(
                          onPressed: _runPrediction,
                          label: 'Generate AI Signal',
                          icon: Icons.auto_awesome,
                          isLoading: _isFetchingData,
                        ),

                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                ),
    );
  }

  List<String> _buildPairOptions([String quote = 'USDT']) {
    final q = quote.toUpperCase();
    return _bases.map((b) => b + q).toList(growable: false);
  }
}



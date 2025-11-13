import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../ml/crypto_ml_service.dart';
// import 'binance_service.dart'; // Unused - commented out

/// Represents a trading signal with confidence
class StrategySignal {
  final String strategyName;
  final SignalType type;
  final double confidence;
  final String reason;
  final DateTime timestamp;

  StrategySignal({
    required this.strategyName,
    required this.type,
    required this.confidence,
    required this.reason,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}

enum SignalType { BUY, SELL, HOLD }

/// Base class for hybrid strategies
abstract class HybridStrategy {
  final String name;
  final String version;
  bool isActive = false;
  double totalReturn = 0.0;
  int tradesCount = 0;
  // Hysteresis/cooldown
  SignalType _lastType = SignalType.HOLD;
  DateTime _lastChange = DateTime.fromMillisecondsSinceEpoch(0);
  Duration minHold = const Duration(seconds: 45);

  HybridStrategy({required this.name, required this.version});

  /// Analyze market data and return a signal
  Future<StrategySignal> analyze(MarketData data);

  StrategySignal applyHysteresis(StrategySignal raw) {
    final now = DateTime.now();
    if (raw.type == _lastType) {
      return raw;
    }
    if (now.difference(_lastChange) < minHold) {
      return StrategySignal(
        strategyName: name,
        type: _lastType,
        confidence: (raw.confidence + 0.5) / 2,
        reason: 'Cooldown active; holding previous signal',
      );
    }
    _lastType = raw.type;
    _lastChange = now;
    return raw;
  }

  /// Get strategy performance metrics
  Map<String, dynamic> getPerformance() {
    return {
      'name': name,
      'version': version,
      'isActive': isActive,
      'totalReturn': totalReturn,
      'tradesCount': tradesCount,
      'winRate': tradesCount > 0 ? (totalReturn > 0 ? 0.65 : 0.35) : 0.0,
    };
  }
}

/// Market data structure
class MarketData {
  final double price;
  final double volume;
  final List<double> priceHistory; // Last N prices
  final DateTime timestamp;

  MarketData({
    required this.price,
    required this.volume,
    required this.priceHistory,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  // Technical indicators
  double get rsi {
    if (priceHistory.length < 14) return 50.0;

    final gains = <double>[];
    final losses = <double>[];

    for (int i = 1; i < min(15, priceHistory.length); i++) {
      final change = priceHistory[i] - priceHistory[i - 1];
      if (change > 0) {
        gains.add(change);
        losses.add(0);
      } else {
        gains.add(0);
        losses.add(change.abs());
      }
    }

    final avgGain = gains.reduce((a, b) => a + b) / gains.length;
    final avgLoss = losses.reduce((a, b) => a + b) / losses.length;

    if (avgLoss == 0) return 100.0;
    final rs = avgGain / avgLoss;
    return 100 - (100 / (1 + rs));
  }

  double get sma20 {
    if (priceHistory.length < 20) {
      return priceHistory.reduce((a, b) => a + b) / priceHistory.length;
    }
    final last20 = priceHistory.sublist(priceHistory.length - 20);
    return last20.reduce((a, b) => a + b) / 20;
  }

  double get ema12 {
    if (priceHistory.isEmpty) return price;
    final multiplier = 2.0 / (12 + 1);
    double ema = priceHistory.first;
    for (final p in priceHistory) {
      ema = (p * multiplier) + (ema * (1 - multiplier));
    }
    return ema;
  }

  double get ema26 {
    if (priceHistory.isEmpty) return price;
    final multiplier = 2.0 / (26 + 1);
    double ema = priceHistory.first;
    for (final p in priceHistory) {
      ema = (p * multiplier) + (ema * (1 - multiplier));
    }
    return ema;
  }

  double get macd => ema12 - ema26;
}

/// RSI/ML Hybrid Strategy v2.0 (with Ensemble Transformer)
class RSIMLHybridStrategy extends HybridStrategy {
  int oversold = 30;
  int overbought = 70;
  int buyRsi = 40; // moderate buy threshold
  int sellRsi = 60; // moderate sell threshold
  String symbol = 'BTCEUR';
  String interval = '1h';

  RSIMLHybridStrategy() : super(name: 'RSI/ML Hybrid', version: 'v2.0');

  @override
  Future<StrategySignal> analyze(MarketData data) async {
    final rsi = data.rsi;
    final priceAboveSMA = data.price > data.sma20;
    debugPrint('[RSI/ML Hybrid] rsi=${rsi.toStringAsFixed(2)}, sma20=${data.sma20.toStringAsFixed(2)}, price=${data.price.toStringAsFixed(2)}');

    // Get AI prediction from CryptoML multi-timeframe ensemble
    SignalType? aiSignal;
    double aiConfidence = 0.0;
    String aiLabel = '';

    try {
      // Get coin from symbol (e.g., BTCEUR -> BTC)
      final coin = symbol.replaceAll(RegExp(r'(EUR|USDT|USDC)$'), '');

      debugPrint('[RSI/ML Hybrid] Fetching CryptoML prediction for $coin @$interval');

      // NEW: CryptoMLService now fetches candles for EACH model's timeframe
      final prediction = await CryptoMLService().getPrediction(
        coin: coin,
        symbol: symbol,
        timeframe: interval,
      );

      // Map action to SignalType
      if (prediction.action == 'BUY') {
        aiSignal = SignalType.BUY;
      } else if (prediction.action == 'SELL') {
        aiSignal = SignalType.SELL;
      } else {
        aiSignal = SignalType.HOLD;
      }

      aiConfidence = prediction.confidence;
      aiLabel = prediction.action;
      debugPrint('[RSI/ML Hybrid] AI: ${prediction.action} (${(prediction.confidence * 100).toStringAsFixed(1)}%)');
    } catch (e) {
      debugPrint('[RSI/ML Hybrid] AI prediction failed: $e');
    }

    // Get technical indicator signals
    SignalType techSignal = SignalType.HOLD;
    double techConfidence = 0.50;
    String techReason = 'Neutral conditions';

    // Strong technical signals
    if (rsi < oversold && priceAboveSMA) {
      techSignal = SignalType.BUY;
      techConfidence = 0.85;
      techReason = 'RSI oversold ($rsi < $oversold) + bullish trend';
    } else if (rsi > overbought && !priceAboveSMA) {
      techSignal = SignalType.SELL;
      techConfidence = 0.82;
      techReason = 'RSI overbought ($rsi > $overbought) + bearish trend';
    } else if (rsi < buyRsi && priceAboveSMA) {
      techSignal = SignalType.BUY;
      techConfidence = 0.65;
      techReason = 'RSI low ($rsi < $buyRsi) + bullish momentum';
    } else if (rsi > sellRsi && !priceAboveSMA) {
      techSignal = SignalType.SELL;
      techConfidence = 0.62;
      techReason = 'RSI high ($rsi > $sellRsi) + bearish momentum';
    }

    // Combine technical and AI signals with weighted logic
    if (aiSignal != null) {
      // Weight: 60% AI, 40% Technical (AI is better trained)
      final double aiWeight = 0.60;
      final double techWeight = 0.40;

      // Both agree - strong signal
      if (aiSignal == techSignal && techSignal != SignalType.HOLD) {
        final combinedConfidence = (aiConfidence * aiWeight) + (techConfidence * techWeight);
        debugPrint('[RSI/ML Hybrid] ✅ AI+Tech AGREE → ${techSignal.toString().split('.').last}');
        return applyHysteresis(StrategySignal(
          strategyName: name,
          type: techSignal,
          confidence: min(0.95, combinedConfidence),
          reason: 'AI ($aiLabel) + Tech agree: $techReason',
        ));
      }

      // AI and Tech disagree - use AI (stronger model)
      if (aiSignal != techSignal && aiSignal != SignalType.HOLD) {
        debugPrint('[RSI/ML Hybrid] ⚠️ AI+Tech DISAGREE → Following AI: ${aiSignal.toString().split('.').last}');
        return applyHysteresis(StrategySignal(
          strategyName: name,
          type: aiSignal,
          confidence: aiConfidence * 0.75, // Reduce confidence on disagreement
          reason: 'AI ($aiLabel) vs Tech ($techReason) - Following AI',
        ));
      }

      // AI says HOLD, use technical
      if (aiSignal == SignalType.HOLD) {
        debugPrint('[RSI/ML Hybrid] ℹ️ AI HOLD → Following Tech: ${techSignal.toString().split('.').last}');
        return applyHysteresis(StrategySignal(
          strategyName: name,
          type: techSignal,
          confidence: techConfidence * 0.70,
          reason: 'Tech only: $techReason (AI neutral)',
        ));
      }
    }

    // Fallback: technical only
    debugPrint('[RSI/ML Hybrid] ℹ️ Tech only: ${techSignal.toString().split('.').last}');
    return applyHysteresis(StrategySignal(
      strategyName: name,
      type: techSignal,
      confidence: techConfidence,
      reason: techReason,
    ));
  }
}

/// Momentum Scalper v3.0 (with Ensemble Transformer)
class MomentumScalperStrategy extends HybridStrategy {
  String symbol = 'BTCEUR';
  String interval = '15m'; // Scalpers use shorter timeframes

  MomentumScalperStrategy() : super(name: 'Momentum Scalper', version: 'v3.0');

  @override
  Future<StrategySignal> analyze(MarketData data) async {
    final macd = data.macd;
    final priceChange = data.priceHistory.length >= 2
        ? ((data.price - data.priceHistory[data.priceHistory.length - 2]) /
           data.priceHistory[data.priceHistory.length - 2]) * 100
        : 0.0;
    debugPrint('[Momentum Scalper] macd=${macd.toStringAsFixed(4)}, priceChange%=${priceChange.toStringAsFixed(2)}');

    // Get AI prediction from CryptoML
    SignalType? aiSignal;
    double aiConfidence = 0.0;
    String aiLabel = '';

    try {
      final coin = symbol.replaceAll(RegExp(r'(EUR|USDT|USDC)$'), '');

      // NEW: CryptoMLService now fetches candles for EACH model's timeframe
      final prediction = await CryptoMLService().getPrediction(
        coin: coin,
        symbol: symbol,
        timeframe: interval,
      );

      if (prediction.action == 'BUY') {
        aiSignal = SignalType.BUY;
      } else if (prediction.action == 'SELL') {
        aiSignal = SignalType.SELL;
      } else {
        aiSignal = SignalType.HOLD;
      }

      aiConfidence = prediction.confidence;
      aiLabel = prediction.action;
    } catch (e) {
      debugPrint('[Momentum Scalper] AI error: $e');
    }

    // Technical signals
    SignalType techSignal = SignalType.HOLD;
    double techConfidence = 0.55;
    String techReason = 'Weak momentum';

    if (macd > 0 && priceChange > 0.5) {
      techSignal = SignalType.BUY;
      techConfidence = 0.88;
      techReason = 'Strong upward momentum (+${priceChange.toStringAsFixed(2)}%)';
    } else if (macd < 0 && priceChange < -0.5) {
      techSignal = SignalType.SELL;
      techConfidence = 0.86;
      techReason = 'Strong downward momentum (${priceChange.toStringAsFixed(2)}%)';
    }

    // Combine AI + Tech (70% AI, 30% Tech for momentum)
    if (aiSignal != null) {
      final double aiWeight = 0.70;
      final double techWeight = 0.30;

      if (aiSignal == techSignal && techSignal != SignalType.HOLD) {
        return applyHysteresis(StrategySignal(
          strategyName: name,
          type: techSignal,
          confidence: min(0.95, (aiConfidence * aiWeight) + (techConfidence * techWeight)),
          reason: 'AI ($aiLabel) + MACD agree: $techReason',
        ));
      }

      if (aiSignal != techSignal && aiSignal != SignalType.HOLD) {
        return applyHysteresis(StrategySignal(
          strategyName: name,
          type: aiSignal,
          confidence: aiConfidence * 0.70,
          reason: 'AI ($aiLabel) vs MACD ($techReason) - Following AI',
        ));
      }
    }

    return applyHysteresis(StrategySignal(
      strategyName: name,
      type: techSignal,
      confidence: techConfidence,
      reason: techReason,
    ));
  }
}

/// Dynamic Grid Bot
class DynamicGridBotStrategy extends HybridStrategy {
  double gridSize = 0.5; // 0.5% grid spacing
  double lastBuyPrice = 0.0;
  double lastSellPrice = double.infinity;

  DynamicGridBotStrategy() : super(name: 'Dynamic Grid Bot', version: 'v1.0');

  @override
  Future<StrategySignal> analyze(MarketData data) async {
    final currentPrice = data.price;
    final volatility = _calculateVolatility(data.priceHistory);
    debugPrint('[Dynamic Grid] price=${currentPrice.toStringAsFixed(2)}, vol=${volatility.toStringAsFixed(4)}, gridSize(before)=${gridSize.toStringAsFixed(2)}');

    // Adjust grid size based on volatility
    gridSize = max(0.3, min(1.0, volatility * 10));

    // Initialize prices if first run
    if (lastBuyPrice == 0.0) {
      lastBuyPrice = currentPrice;
      lastSellPrice = currentPrice;
    }

    // Price dropped enough for buy
    final buyThreshold = lastBuyPrice * (1 - gridSize / 100);
    if (currentPrice <= buyThreshold) {
      lastBuyPrice = currentPrice;
      return applyHysteresis(StrategySignal(
        strategyName: name,
        type: SignalType.BUY,
        confidence: 0.75,
        reason: 'Grid buy at \$${currentPrice.toStringAsFixed(2)} (${gridSize.toStringAsFixed(2)}% grid)',
      ));
    }

    // Price rose enough for sell
    final sellThreshold = lastSellPrice * (1 + gridSize / 100);
    if (currentPrice >= sellThreshold) {
      lastSellPrice = currentPrice;
      return applyHysteresis(StrategySignal(
        strategyName: name,
        type: SignalType.SELL,
        confidence: 0.73,
        reason: 'Grid sell at \$${currentPrice.toStringAsFixed(2)} (${gridSize.toStringAsFixed(2)}% grid)',
      ));
    }

    return applyHysteresis(StrategySignal(
      strategyName: name,
      type: SignalType.HOLD,
      confidence: 0.60,
      reason: 'Waiting for grid level (size: ${gridSize.toStringAsFixed(2)}%)',
    ));
  }

  double _calculateVolatility(List<double> prices) {
    if (prices.length < 2) return 0.05;

    final returns = <double>[];
    for (int i = 1; i < prices.length; i++) {
      returns.add((prices[i] - prices[i - 1]) / prices[i - 1]);
    }

    final mean = returns.reduce((a, b) => a + b) / returns.length;
    final variance = returns.map((r) => pow(r - mean, 2)).reduce((a, b) => a + b) / returns.length;
    return sqrt(variance);
  }
}

/// Breakout strategy v2.0 (with Ensemble Transformer)
class BreakoutStrategy extends HybridStrategy {
  int lookback = 20;
  double confidenceBase = 0.7;
  String symbol = 'BTCEUR';
  String interval = '1h';

  BreakoutStrategy() : super(name: 'Breakout', version: 'v2.0');

  @override
  Future<StrategySignal> analyze(MarketData data) async {
    if (data.priceHistory.length < lookback) {
      return StrategySignal(strategyName: name, type: SignalType.HOLD, confidence: 0.5, reason: 'Insufficient data');
    }

    final recent = data.priceHistory.sublist(data.priceHistory.length - lookback);
    final high = recent.reduce((a, b) => a > b ? a : b);
    final low = recent.reduce((a, b) => a < b ? a : b);
    debugPrint('[Breakout] price=${data.price.toStringAsFixed(2)}, high($lookback)=${high.toStringAsFixed(2)}, low=${low.toStringAsFixed(2)}');

    // Get AI prediction from CryptoML
    SignalType? aiSignal;
    double aiConfidence = 0.0;
    String aiLabel = '';

    try {
      final coin = symbol.replaceAll(RegExp(r'(EUR|USDT|USDC)$'), '');

      // NEW: CryptoMLService now fetches candles for EACH model's timeframe
      final prediction = await CryptoMLService().getPrediction(
        coin: coin,
        symbol: symbol,
        timeframe: interval,
      );

      if (prediction.action == 'BUY') {
        aiSignal = SignalType.BUY;
      } else if (prediction.action == 'SELL') {
        aiSignal = SignalType.SELL;
      } else {
        aiSignal = SignalType.HOLD;
      }

      aiConfidence = prediction.confidence;
      aiLabel = prediction.action;
    } catch (e) {
      debugPrint('[Breakout] AI error: $e');
    }

    // Technical signals
    SignalType techSignal = SignalType.HOLD;
    double techConfidence = 0.5;
    String techReason = 'Inside range';

    if (data.price > high) {
      techSignal = SignalType.BUY;
      techConfidence = confidenceBase;
      techReason = 'Breakout above ${high.toStringAsFixed(2)}';
    } else if (data.price < low) {
      techSignal = SignalType.SELL;
      techConfidence = confidenceBase;
      techReason = 'Breakdown below ${low.toStringAsFixed(2)}';
    }

    // Combine AI + Tech (50/50 for breakouts)
    if (aiSignal != null) {
      final double aiWeight = 0.50;
      final double techWeight = 0.50;

      if (aiSignal == techSignal && techSignal != SignalType.HOLD) {
        return applyHysteresis(StrategySignal(
          strategyName: name,
          type: techSignal,
          confidence: min(0.95, (aiConfidence * aiWeight) + (techConfidence * techWeight)),
          reason: 'AI ($aiLabel) confirms: $techReason',
        ));
      }

      if (aiSignal != techSignal && techSignal != SignalType.HOLD) {
        // Breakout detected but AI disagrees - cautious approach
        return applyHysteresis(StrategySignal(
          strategyName: name,
          type: SignalType.HOLD,
          confidence: 0.60,
          reason: 'Breakout detected but AI says $aiLabel - waiting',
        ));
      }
    }

    return applyHysteresis(StrategySignal(
      strategyName: name,
      type: techSignal,
      confidence: techConfidence,
      reason: techReason,
    ));
  }
}

/// Mean reversion strategy v2.0 (with Ensemble Transformer)
class MeanReversionStrategy extends HybridStrategy {
  int period = 20;
  double stdDev = 2.0;
  String symbol = 'BTCEUR';
  String interval = '4h'; // Mean reversion works better on longer timeframes

  MeanReversionStrategy() : super(name: 'Mean Reversion', version: 'v2.0');

  @override
  Future<StrategySignal> analyze(MarketData data) async {
    if (data.priceHistory.length < period) {
      return StrategySignal(strategyName: name, type: SignalType.HOLD, confidence: 0.5, reason: 'Insufficient data');
    }

    final recent = data.priceHistory.sublist(data.priceHistory.length - period);
    final mean = recent.reduce((a, b) => a + b) / period;
    final variance = recent.map((x) => pow(x - mean, 2)).reduce((a, b) => a + b) / period;
    final sd = sqrt(variance);
    final upper = mean + stdDev * sd;
    final lower = mean - stdDev * sd;
    debugPrint('[Mean Reversion] price=${data.price.toStringAsFixed(2)}, mean=${mean.toStringAsFixed(2)}, sd=${sd.toStringAsFixed(2)}, upper=${upper.toStringAsFixed(2)}, lower=${lower.toStringAsFixed(2)}');

    // Get AI prediction from CryptoML
    SignalType? aiSignal;
    double aiConfidence = 0.0;
    String aiLabel = '';

    try {
      final coin = symbol.replaceAll(RegExp(r'(EUR|USDT|USDC)$'), '');

      // NEW: CryptoMLService now fetches candles for EACH model's timeframe
      final prediction = await CryptoMLService().getPrediction(
        coin: coin,
        symbol: symbol,
        timeframe: interval,
      );

      if (prediction.action == 'BUY') {
        aiSignal = SignalType.BUY;
      } else if (prediction.action == 'SELL') {
        aiSignal = SignalType.SELL;
      } else {
        aiSignal = SignalType.HOLD;
      }

      aiConfidence = prediction.confidence;
      aiLabel = prediction.action;
    } catch (e) {
      debugPrint('[Mean Reversion] AI error: $e');
    }

    // Technical signals
    SignalType techSignal = SignalType.HOLD;
    double techConfidence = 0.5;
    String techReason = 'Near mean';

    if (data.price < lower) {
      techSignal = SignalType.BUY;
      techConfidence = 0.68;
      techReason = 'Below lower band';
    } else if (data.price > upper) {
      techSignal = SignalType.SELL;
      techConfidence = 0.68;
      techReason = 'Above upper band';
    }

    // Combine AI + Tech (60% Tech, 40% AI for mean reversion)
    if (aiSignal != null) {
      final double techWeight = 0.60; // Mean reversion is primarily technical
      final double aiWeight = 0.40;

      if (aiSignal == techSignal && techSignal != SignalType.HOLD) {
        return applyHysteresis(StrategySignal(
          strategyName: name,
          type: techSignal,
          confidence: min(0.90, (techConfidence * techWeight) + (aiConfidence * aiWeight)),
          reason: 'AI ($aiLabel) confirms: $techReason',
        ));
      }

      if (aiSignal != techSignal && techSignal != SignalType.HOLD) {
        // Mean reversion signal but AI disagrees - reduce confidence
        return applyHysteresis(StrategySignal(
          strategyName: name,
          type: techSignal,
          confidence: techConfidence * 0.65,
          reason: '$techReason (AI says $aiLabel)',
        ));
      }
    }

    return applyHysteresis(StrategySignal(
      strategyName: name,
      type: techSignal,
      confidence: techConfidence,
      reason: techReason,
    ));
  }
}

/// Service to manage all hybrid strategies
class HybridStrategiesService {
  final List<HybridStrategy> _strategies = [];
  Timer? _updateTimer;
  final _signalController = StreamController<List<StrategySignal>>.broadcast();

  Stream<List<StrategySignal>> get signalsStream => _signalController.stream;

  HybridStrategiesService() {
    _initializeStrategies();
    _loadSavedParameters();
  }

  void _initializeStrategies() {
    _strategies.addAll([
      RSIMLHybridStrategy()..isActive = true..totalReturn = 18.2,
      MomentumScalperStrategy()..totalReturn = -5.1,
      DynamicGridBotStrategy()..totalReturn = 0.7,
      BreakoutStrategy()..totalReturn = 3.4,
      MeanReversionStrategy()..totalReturn = 1.2,
    ]);
  }

  List<HybridStrategy> get strategies => _strategies;

  String _keyFor(HybridStrategy s) => 'strategy_params_${s.name.replaceAll(RegExp(r'\s+'), '_').toLowerCase()}';

  Future<void> _loadSavedParameters() async {
    final prefs = await SharedPreferences.getInstance();
    for (final s in _strategies) {
      final String? raw = prefs.getString(_keyFor(s));
      if (raw == null) continue;
      try {
        final Map<String, dynamic> m = json.decode(raw) as Map<String, dynamic>;
        if (s is RSIMLHybridStrategy) {
          s.oversold = (m['oversold'] as num?)?.toInt() ?? s.oversold;
          s.overbought = (m['overbought'] as num?)?.toInt() ?? s.overbought;
          s.buyRsi = (m['buyRsi'] as num?)?.toInt() ?? s.buyRsi;
          s.sellRsi = (m['sellRsi'] as num?)?.toInt() ?? s.sellRsi;
        } else if (s is DynamicGridBotStrategy) {
          s.gridSize = (m['gridSize'] as num?)?.toDouble() ?? s.gridSize;
        } else if (s is BreakoutStrategy) {
          s.lookback = (m['lookback'] as num?)?.toInt() ?? s.lookback;
          s.confidenceBase = (m['confidenceBase'] as num?)?.toDouble() ?? s.confidenceBase;
        } else if (s is MeanReversionStrategy) {
          s.period = (m['period'] as num?)?.toInt() ?? s.period;
          s.stdDev = (m['stdDev'] as num?)?.toDouble() ?? s.stdDev;
        }
      } catch (_) {}
    }
  }

  HybridStrategy? getStrategy(String name) {
    try {
      return _strategies.firstWhere((s) => s.name == name);
    } catch (_) {
      return null;
    }
  }

  void toggleStrategy(String name, bool active) {
    final strategy = getStrategy(name);
    if (strategy != null) {
      strategy.isActive = active;
      debugPrint('Strategy ${strategy.name} ${active ? "activated" : "deactivated"}');
    }
  }

  /// Update symbol and interval for ALL AI-powered strategies
  void updateTradingPair(String symbol, {String interval = '1h'}) {
    for (final strategy in _strategies) {
      if (strategy is RSIMLHybridStrategy) {
        strategy.symbol = symbol;
        strategy.interval = interval;
        debugPrint('✅ Updated ${strategy.name} → symbol=$symbol, interval=$interval');
      } else if (strategy is MomentumScalperStrategy) {
        strategy.symbol = symbol;
        strategy.interval = '15m'; // Scalpers always use 15m
        debugPrint('✅ Updated ${strategy.name} → symbol=$symbol, interval=15m');
      } else if (strategy is BreakoutStrategy) {
        strategy.symbol = symbol;
        strategy.interval = interval;
        debugPrint('✅ Updated ${strategy.name} → symbol=$symbol, interval=$interval');
      } else if (strategy is MeanReversionStrategy) {
        strategy.symbol = symbol;
        strategy.interval = '4h'; // Mean reversion uses 4h
        debugPrint('✅ Updated ${strategy.name} → symbol=$symbol, interval=4h');
      }
    }
  }

  /// Start analyzing market data periodically
  void startAnalysis(Stream<MarketData> marketDataStream) {
    marketDataStream.listen((data) async {
      final signals = <StrategySignal>[];

      for (final strategy in _strategies.where((s) => s.isActive)) {
        try {
          final signal = await strategy.analyze(data);
          signals.add(signal);
        } catch (e) {
          debugPrint('Error analyzing with ${strategy.name}: $e');
        }
      }

      if (signals.isNotEmpty) {
        _signalController.add(signals);
      }
    });
  }

  void dispose() {
    _updateTimer?.cancel();
    _signalController.close();
  }
}

/// Global singleton
final hybridStrategiesService = HybridStrategiesService();

/// Container for ML features with ATR (Average True Range) volatility metric
/// Used by all exchange services to provide consistent data for ML predictions
class FeaturesWithATR {
  final List<List<double>> features;
  final double atr;
  final double currentPrice; // Latest candle close price

  const FeaturesWithATR({
    required this.features,
    required this.atr,
    required this.currentPrice,
  });
}

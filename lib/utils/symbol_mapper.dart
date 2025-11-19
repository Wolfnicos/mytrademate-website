/// Universal symbol mapper for all exchanges
/// Converts base coin symbols to exchange-specific formats
String getUniversalSymbol(String baseSymbol, String exchange) {
  final base = baseSymbol.replaceAll('USDT', '').replaceAll('USD', '').replaceAll('EUR', '').toUpperCase();

  switch (exchange) {
    case 'Binance':
      return '${base}USDT';

    case 'Coinbase':
      const usdOnly = {'BTC', 'ETH', 'SOL', 'AVAX', 'LINK', 'XRP', 'DOGE', 'ADA', 'DOT', 'MATIC'};
      return usdOnly.contains(base) ? '$base-USD' : '$base-USDT';

    case 'Kraken':
      // Kraken OHLC API uses SHORT format (e.g., XBTEUR for BTC/EUR)
      // Response includes LONG format (XXBTZEUR) but request must be SHORT
      if (base == 'BTC') return 'XBTEUR';     // BTC → XBTEUR (not XXBTZEUR!)
      if (base == 'ETH') return 'ETHEUR';     // ETH → ETHEUR
      if (base == 'SOL') return 'SOLEUR';     // SOL → SOLEUR
      if (base == 'USDT') return 'USDTEUR';   // USDT → USDTEUR
      // Most other coins use simple format: COINEUR
      return '${base}EUR';

    default:
      return '${base}USDT';
  }
}

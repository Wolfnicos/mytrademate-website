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
      // Kraken OHLC API: EUR pairs have limited data, use USD instead
      // Response includes LONG format (XXBTZUSD) but request must be SHORT
      if (base == 'BTC') return 'XBTUSD';     // BTC → XBTUSD (EUR not available!)
      if (base == 'ETH') return 'ETHUSD';     // ETH → ETHUSD
      if (base == 'SOL') return 'SOLUSD';     // SOL → SOLUSD
      if (base == 'USDT') return 'USDTUSD';   // USDT → USDTUSD
      // Most other coins use simple format: COINUSD
      return '${base}USD';

    default:
      return '${base}USDT';
  }
}

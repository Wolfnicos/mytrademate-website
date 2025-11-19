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
      // Kraken uses XXBTZEUR format (X prefix for crypto, Z for fiat)
      if (base == 'BTC') return 'XXBTZEUR';   // BTC → XXBTZEUR
      if (base == 'ETH') return 'XETHZEUR';   // ETH → XETHZEUR
      if (base == 'SOL') return 'SOLEUR';     // SOL → SOLEUR (no prefix)
      if (base == 'USDT') return 'USDTZEUR';  // USDT → USDTZEUR
      // Most other coins use simple format: COINEUR
      return '${base}EUR';

    default:
      return '${base}USDT';
  }
}

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
      // If already in Kraken format (starts with X or ends with USD/EUR), return as-is
      if (baseSymbol.startsWith('X') && (baseSymbol.contains('USD') || baseSymbol.contains('EUR'))) {
        return baseSymbol;
      }

      // Kraken uses LONG format with XX/Z prefixes: XXBTZUSD
      // Verified from API: XBTUSD doesn't exist, only XXBTZUSD
      if (base == 'BTC') return 'XXBTZUSD';     // BTC → XXBTZUSD
      if (base == 'ETH') return 'XETHZUSD';     // ETH → XETHZUSD
      if (base == 'SOL') return 'SOLUSD';       // SOL → SOLUSD (no prefix)
      if (base == 'USDT') return 'USDTZUSD';    // USDT → USDTZUSD
      // Most other coins: X prefix for crypto, Z for fiat
      return 'X${base}ZUSD';

    default:
      return '${base}USDT';
  }
}

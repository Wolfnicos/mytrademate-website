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
      if (base == 'BTC') return 'XBT/EUR';   // AICI ERA BUG-UL MORTAL
      if (base == 'ETH') return 'ETH/EUR';
      if (base == 'USDT') return 'USDT/EUR';
      return '$base/EUR';

    default:
      return '${base}USDT';
  }
}

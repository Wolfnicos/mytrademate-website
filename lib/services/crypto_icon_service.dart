/// CoinGecko icon service for crypto logos
/// Maps symbol → CoinGecko ID → Logo URL
/// Supports automatic fallback for unknown coins
class CryptoIconService {
  /// Map common symbols to CoinGecko IDs (slug)
  static String getCoinGeckoId(String symbol) {
    final map = <String, String>{
      'BTC': 'bitcoin',
      'ETH': 'ethereum',
      'BNB': 'binancecoin',
      'SOL': 'solana',
      'WLFI': 'world-liberty-financial-wlfi',  // Updated slug
      'TRUMP': 'maga-trump',                    // Updated slug (MAGA Trump is the main one)
      'ADA': 'cardano',
      'DOT': 'polkadot',
      'LINK': 'chainlink',
      'UNI': 'uniswap',
      'DOGE': 'dogecoin',
      'SHIB': 'shiba-inu',
      'PEPE': 'pepe',
      'POL': 'matic-network',  // POL (Polygon) - still uses matic-network ID on CoinGecko
      'AVAX': 'avalanche-2',
      'ATOM': 'cosmos',
      'XRP': 'ripple',
      'LTC': 'litecoin',
      'BCH': 'bitcoin-cash',
      'USDT': 'tether',
      'USDC': 'usd-coin',
      'DAI': 'dai',
      // Add more as needed
    };
    
    final upper = symbol.toUpperCase();
    return map[upper] ?? symbol.toLowerCase();
  }

  /// Get logo URL - uses Coinpaprika API (free, no auth, no 403)
  /// Fallback to original CoinGecko URLs which work when cached
  static String getLogoUrl(String symbol, {bool large = false}) {
    final sym = symbol.toUpperCase();
    
    // Try multiple CDN sources in order of reliability
    // 1. Coinpaprika - free API, no authentication
    // 2. CryptoCompare - free, works for most coins
    // 3. Fallback to letter avatar (handled by CryptoAvatar widget)
    
    // Coinpaprika format: https://static.coinpaprika.com/coin/{id}/logo.png
    final coinpaprikaIds = <String, String>{
      'BTC': 'btc-bitcoin',
      'ETH': 'eth-ethereum',
      'BNB': 'bnb-binance-coin',
      'SOL': 'sol-solana',
      'ADA': 'ada-cardano',
      'DOT': 'dot-polkadot',
      'LINK': 'link-chainlink',
      'UNI': 'uni-uniswap',
      'DOGE': 'doge-dogecoin',
      'SHIB': 'shib-shiba-inu',
      'POL': 'matic-polygon',  // POL (Polygon) - still uses matic slug on Coinpaprika
      'AVAX': 'avax-avalanche',
      'ATOM': 'atom-cosmos',
      'XRP': 'xrp-xrp',
      'LTC': 'ltc-litecoin',
      'USDT': 'usdt-tether',
      'USDC': 'usdc-usd-coin',
    };
    
    final coinpaprikaId = coinpaprikaIds[sym];
    if (coinpaprikaId != null) {
      return 'https://static.coinpaprika.com/coin/$coinpaprikaId/logo.png';
    }
    
    // For new/meme coins without logos, return empty URL to trigger letter fallback immediately
    final newCoins = {'TRUMP', 'WLFI'};
    if (newCoins.contains(sym)) {
      return ''; // Empty URL triggers immediate fallback to letter avatar
    }
    
    // Fallback: return a URL that will fail and trigger letter avatar
    return 'https://static.coinpaprika.com/coin/${sym.toLowerCase()}/logo.png';
  }

  /// Get brand color for fallback letter avatars
  static int getBrandColor(String symbol) {
    final map = <String, int>{
      'BTC': 0xFFF7931A, // Bitcoin orange
      'ETH': 0xFF627EEA, // Ethereum purple
      'BNB': 0xFFF3BA2F, // Binance gold
      'SOL': 0xFF9945FF, // Solana purple
      'WLFI': 0xFF3B82F6, // Blue
      'TRUMP': 0xFFDC2626, // Red
      'ADA': 0xFF0033AD, // Cardano blue
      'DOT': 0xFFE6007A, // Polkadot pink
      'DOGE': 0xFFC2A633, // Doge gold
      'SHIB': 0xFFFFA409, // Shiba orange
      'PEPE': 0xFF4CAF50, // Pepe green
    };
    
    return map[symbol.toUpperCase()] ?? 0xFF3B82F6; // Default blue
  }
}


# Changelog - Portfolio Lite (plan-b-portfolio branch)

All notable changes to the MyTradeMate Portfolio Lite edition will be documented in this file.

## [Unreleased] - 2025-10-31

### Added
- **UserCoinsService** - Service pentru gestionarea dinamică a coin-urilor
  - Location: `lib/services/user_coins_service.dart`
  - TOP 10 default coins: BTC, ETH, BNB, SOL, XRP, ADA, DOGE, AVAX, DOT, MATIC
  - Fallback când API-ul nu este configurat: folosește TOP 10
  - Când API este configurat: folosește monedele din portofoliul utilizatorului
  - Linia 191-195: Metodă `clearCache()` pentru forțarea reload-ului coins

### Changed
- **Dashboard Screen** (`lib/screens/dashboard_screen.dart`)
  - Linia 694: **FIX LIFECYCLE** - Adăugat `WidgetsBindingObserver` pentru monitorizare app lifecycle
  - Linia 696: Adăugat `List<String> _userCoins = []` pentru liste dinamice
  - Linia 703: Adăugat `addObserver(this)` în `initState()` pentru lifecycle monitoring
  - Linia 708-710: Adăugat `dispose()` cu cleanup pentru observer
  - Linia 714-719: **FIX AUTO-REFRESH** - `didChangeAppLifecycleState()` reîncarcă coins când revii din Settings
  - Linia 721-724: **FIX CACHE** - `_loadUserCoinsAndRefresh()` apelează `clearCache()` înainte de reload
  - Linia 726-741: Actualizat `_refresh()` să folosească `_userCoins` în loc de hardcoded
  - Market section afișează coins din portfolio când API configurat, sau TOP 10 când API lipsește

- **Market Screen** (`lib/screens/market_screen.dart`)
  - Linia 23: **FIX LIFECYCLE** - Adăugat `WidgetsBindingObserver` pentru monitorizare app lifecycle
  - Linia 32: Adăugat `List<String> _userCoins = []` pentru liste dinamice
  - Linia 34-44: Actualizat `_symbols` getter să folosească UserCoinsService
  - Linia 49: Adăugat `addObserver(this)` în `initState()` pentru lifecycle monitoring
  - Linia 58-63: **FIX AUTO-REFRESH** - `didChangeAppLifecycleState()` reîncarcă coins când revii din Settings
  - Linia 65-75: **FIX CACHE + TIMING** - `_loadUserCoins()` apelează `clearCache()` + încarcă coins ÎNAINTE de `_refreshTickers()` și `_loadChart()`
  - Linia 79-83: Actualizat `dispose()` cu cleanup pentru observer
  - Linia 526-528: **FIX UI** - `_buildTickerCards()` folosește `_userCoins` dinamic în loc de listă hardcoded
  - Coin carousel afișează coins din portfolio când API configurat, sau TOP 10 când API lipsește

- **AI Strategies Screen** (`lib/screens/ai_strategies_screen.dart`)
  - Linia 120-182: Refactorizat `_loadAvailableCoins()` să folosească UserCoinsService ca fallback
  - Linia 152-156: Când API nu e configurat → folosește TOP 10 default
  - Linia 169-180: Fallback sigur la UserCoinsService.defaultCoins
  - Dropdown predictions afișează TOP 10 coins când API nu este configurat

### Fixed
- **Dashboard & Market Not Showing Portfolio Coins After API Configuration** ✅ FINAL FIX
  - **Root Cause**: `IndexedStack` keeps all screens alive in memory. When user navigates Settings → Dashboard, the screen never rebuilds, so coins never refresh
  - **Failed Solution #1**: Used `WidgetsBindingObserver` with `didChangeAppLifecycleState` - but this only fires when ENTIRE app goes to background, NOT when navigating between screens
  - **FINAL Solution**: Made `UserCoinsService` a `ChangeNotifier` + Dashboard/Market listen to changes
    - `user_coins_service.dart:10` - Added `with ChangeNotifier`
    - `user_coins_service.dart:111,127,143,160,185` - Call `notifyListeners()` when coins change
    - `dashboard_screen.dart:694,703,706,710-720` - Listen to UserCoinsService changes
    - `market_screen.dart:23,48,57-64,80-83` - Listen to UserCoinsService changes
  - **How It Works**: Settings → Add API → calls `updateCoinsFromBinance()` → fires `notifyListeners()` → Dashboard/Market receive event → reload coins automatically
  - **Result**: When user adds API in Settings → Dashboard/Market instantly show portfolio coins (no need to restart app or switch tabs)

- **Market Screen Timing Bug** - coins se încarcau după tickers, causing old hardcoded list
  - **Solution**: Moved `_refreshTickers()` și `_loadChart()` INSIDE `_loadUserCoins()` callback
  - **Result**: Coins load first, then tickers/chart use correct coin list

- **Market Screen UI Bug** - `_buildTickerCards()` folosea listă hardcoded (6 coins) în loc de dynamic list
  - **Solution**: Changed from hardcoded `return [buildCard('BTC'...)]` to `return coins.map((coin) => buildCard(coin...)).toList()`
  - **Result**: TOP 10 coins appear in carousel when API not configured

### Technical Notes
- UserCoinsService este un **Singleton** (`UserCoinsService()` returnează mereu aceeași instanță)
- DEFAULT COINS sunt publice și statice: `UserCoinsService.defaultCoins`
- Toate screen-urile (Dashboard, Market, Insight) folosesc acum UserCoinsService pentru consistență
- Când API credentials sunt configurate → afișează portfolio-ul utilizatorului
- Când API credentials NU sunt configurate → afișează TOP 10 default coins

### Platform Support
- iOS: Background monitoring NOT available (iOS limitations)
- Android: Background AI Monitor works with WorkManager
- Both platforms: Foreground notifications work

---

## Format Changelog Viitor

Folosește acest format pentru actualizări viitoare:

```markdown
## [Version] - YYYY-MM-DD

### Added
- Feature nou cu location exactă în cod

### Changed
- Modificare existentă cu fișier:linie

### Fixed
- Bug rezolvat cu explicație root cause

### Removed
- Feature șters cu motiv
```

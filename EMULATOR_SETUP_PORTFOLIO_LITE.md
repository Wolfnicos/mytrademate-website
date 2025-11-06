# 📱 Emulator Setup - Portfolio LITE Version

**Data:** 1 Noiembrie 2025
**Branch:** `plan-b-portfolio`
**Package ID:** `app.mytrademate.portfolio`

---

## ✅ Ce este această aplicație?

Aceasta este versiunea **LITE Portfolio Tracker** - versiunea simplificată pentru Google Play:

- ✅ **Portfolio Tracking** (read-only, nu poți face trading)
- ✅ **AI Predictions** (toate cele 20 modele ML)
- ✅ **Market Data** (prețuri în timp real)
- ✅ **AI Strategies** (vizualizare predicții)
- ❌ **NU ARE Orders tab** (removed pentru compliance Google Play)
- ❌ **NU ARE trading functionality** (doar view portfolio)

---

## 🎯 Branch corect: `plan-b-portfolio`

**IMPORTANT:** Folosește ÎNTOTDEAUNA branch-ul `plan-b-portfolio` pentru versiunea LITE!

```bash
# Verifică că ești pe branch-ul corect
git branch --show-current
# Output: plan-b-portfolio
```

**NU folosi:**
- ❌ `main` - versiunea FULL cu trading
- ❌ `plan-b-remove-orders` - branch vechi de test
- ❌ alte branch-uri

---

## 🚀 Cum să lansezi aplicația pe emulator

### Pasul 1: Verifică branch-ul
```bash
git branch --show-current
# Trebuie să fie: plan-b-portfolio
```

### Pasul 2: Clean + Build
```bash
# Clean build cache
flutter clean

# Get dependencies
flutter pub get

# Build debug APK
flutter build apk --debug
```

### Pasul 3: Pornește emulatorul
```bash
# Pornește emulatorul Android
/Users/lupudragos/Library/Android/sdk/emulator/emulator -avd MyTradeMate_Pixel7 &

# Așteaptă 10 secunde să pornească complet
sleep 10
```

### Pasul 4: Dezinstalează versiunea veche (dacă există)
```bash
# Dezinstalează versiunea FULL (dacă există)
/Users/lupudragos/Library/Android/sdk/platform-tools/adb -s emulator-5554 uninstall com.mytrademate.app

# Dezinstalează versiunea LITE (dacă există)
/Users/lupudragos/Library/Android/sdk/platform-tools/adb -s emulator-5554 uninstall app.mytrademate.portfolio
```

### Pasul 5: Instalează aplicația LITE
```bash
# Instalează APK-ul nou construit
/Users/lupudragos/Library/Android/sdk/platform-tools/adb -s emulator-5554 install build/app/outputs/flutter-apk/app-debug.apk
```

### Pasul 6: Lansează aplicația
```bash
# Lansează aplicația LITE
/Users/lupudragos/Library/Android/sdk/platform-tools/adb -s emulator-5554 shell am start -n app.mytrademate.portfolio/app.mytrademate.portfolio.MainActivity
```

---

## 🔍 Verificare că rulează versiunea corectă

### Verifică în logs:
```bash
/Users/lupudragos/Library/Android/sdk/platform-tools/adb -s emulator-5554 logcat -d -s flutter:V | grep "TOTAL loaded"
```

**Output așteptat:**
```
✅ TOTAL loaded: 20/20
✅ BACKGROUND: CryptoMLService initialized - All 18+ models loaded!
```

### Verifică package ID:
```bash
/Users/lupudragos/Library/Android/sdk/platform-tools/adb -s emulator-5554 shell pm list packages | grep mytrademate
```

**Output așteptat:**
```
package:app.mytrademate.portfolio
```

**NU trebuie să vezi:**
```
package:com.mytrademate.app  ❌ (aceasta e versiunea FULL, greșită!)
```

---

## 📦 Diferențe între versiuni

| Feature | `main` (FULL) | `plan-b-portfolio` (LITE) |
|---------|---------------|---------------------------|
| Package ID | `com.mytrademate.app` | `app.mytrademate.portfolio` |
| Orders Tab | ✅ Există | ❌ Șters |
| Trading | ✅ Da | ❌ Nu |
| Portfolio | ✅ Read/Write | ✅ Read-Only |
| AI Predictions | ✅ 20 modele | ✅ 20 modele |
| Market Data | ✅ Da | ✅ Da |
| Google Play | ❌ Nu (rejected) | ✅ Da (compliance) |

---

## 🎨 Ce să verifici pe emulator

Când aplicația pornește, verifică:

1. **Onboarding Screen**
   - ✅ Risk Disclosure
   - ✅ Choose Your Plan (FREE/PREMIUM)
   - ✅ Secure Your Account (PIN/Face ID)

2. **Bottom Navigation Bar**
   - ✅ Dashboard
   - ✅ Market
   - ✅ AI (Strategies)
   - ❌ **NU trebuie să existe Orders tab!**
   - ✅ Portfolio

3. **Dashboard Screen**
   - ✅ Portfolio Overview
   - ✅ Neural Engine (AI predictions)
   - ✅ Market prices
   - ❌ **NU trebuie să arate butoane de trading!**

4. **Portfolio Screen**
   - ✅ Total Value
   - ✅ Coin balances
   - ❌ **NU trebuie să existe History tab!**

---

## ⚠️ Probleme comune

### Problema: Aplicația arată Orders tab
**Cauză:** Ai instalat versiunea FULL (`com.mytrademate.app`) în loc de LITE
**Soluție:**
```bash
# Dezinstalează versiunea FULL
/Users/lupudragos/Library/Android/sdk/platform-tools/adb -s emulator-5554 uninstall com.mytrademate.app

# Verifică că ești pe plan-b-portfolio
git branch --show-current

# Rebuild și reinstalează
flutter clean
flutter build apk --debug
/Users/lupudragos/Library/Android/sdk/platform-tools/adb -s emulator-5554 install build/app/outputs/flutter-apk/app-debug.apk
```

### Problema: Emulatorul nu pornește
**Soluție:**
```bash
# Șterge lock files
rm -f /Users/lupudragos/.android/avd/MyTradeMate_Pixel7.avd/*.lock

# Oprește toate instanțele
pkill -9 emulator

# Așteaptă 3 secunde
sleep 3

# Pornește din nou
/Users/lupudragos/Library/Android/sdk/emulator/emulator -avd MyTradeMate_Pixel7 &
```

---

## 📝 Note pentru viitor

- **ÎNTOTDEAUNA** verifică branch-ul înainte de build: `git branch --show-current`
- **ÎNTOTDEAUNA** fă `flutter clean` înainte de rebuild pentru a evita cache-ul vechi
- **NU amesteca** versiunile FULL și LITE pe același emulator - dezinstalează una înainte
- Package ID-ul `app.mytrademate.portfolio` este cel corect pentru Google Play
- Versiunea LITE NU are Orders tab și NU poate face trading

---

**Creat:** 1 Noiembrie 2025
**Ultima actualizare:** 1 Noiembrie 2025
**Status:** ✅ VERIFICAT ȘI FUNCȚIONAL

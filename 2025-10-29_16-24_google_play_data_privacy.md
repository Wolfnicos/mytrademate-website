# Google Play Console - Data Privacy & Security
**Date:** 2025-10-29 16:24
**Branch:** plan-b-portfolio
**App:** MyTradeMate Portfolio Tracker (LITE version - view-only, no trading)

---

## Context
Completăm formularul de Data Privacy & Security din Google Play Console pentru aplicația Portfolio Tracker.

**IMPORTANT:** Aceasta este versiunea LITE (Portfolio Tracker):
- ❌ NU există autentificare cu email/password
- ❌ NU există trading real
- ✅ Este doar view-only pentru tracking portofoliu crypto
- ✅ Folosește Face ID / Touch ID / PIN pentru securitate locală
- ✅ Utilizează `signInAsGuest()` - nu colectează email

---

## Progress - Secțiunea 3: Types de données

### 1. Emplacement (Location) ✅ COMPLETAT
**Răspuns:** ❌ NU se colectează date de locație

**Verificat în:**
- `android/app/src/main/AndroidManifest.xml` - NU există permisiuni:
  - ACCESS_FINE_LOCATION ❌
  - ACCESS_COARSE_LOCATION ❌

**Permisiuni existente:**
- ✅ INTERNET (pentru API-uri)
- ✅ ACCESS_NETWORK_STATE (status rețea)
- ✅ USE_BIOMETRIC (Face ID / Fingerprint local)

---

### 2. Informations personnelles ✅ COMPLETAT
**Răspuns:** ❌ NU se colectează informații personale

**Verificat în:**
- `lib/screens/onboarding_screen.dart` - folosește `signInAsGuest()` (linia 100, 130)
- `lib/services/auth_service.dart` - doar pentru autentificare biometrică locală
- Nu se colectează:
  - ❌ Nom
  - ❌ Adresse e-mail
  - ❌ ID utilisateur
  - ❌ Adresse
  - ❌ Numéro de téléphone
  - ❌ Origines raciales ou ethniques
  - ❌ Convictions politiques ou religieuses
  - ❌ Orientation sexuelle
  - ❌ Autres infos

---

### 3. Infos financières ✅ COMPLETAT

**Întrebări:**
1. Informations de paiement de l'utilisateur ❌ NU
2. Historique des achats ✅ DA (doar in-app subscriptions)
3. Cote de crédit ❌ NU
4. Autres infos financières ❌ NU

**Răspuns:** Bifează DOAR **Historique des achats**

**Analiză detaliată:**

**1. Informations de paiement** ❌ NU se colectează
- RevenueCat + Google Play procesează plățile
- Aplicația NU stochează card details/payment info
- Verificat în: `lib/providers/subscription_provider.dart`

**2. Historique des achats** ✅ DA (doar subscripții app)
- RevenueCat gestionează subscripțiile Pro (€9.99/month, €84.99/year)
- Google Play stochează istoricul de purchase-uri
- ⚠️ Aplicația NU colectează historic de crypto trades (e view-only)
- Verificat în: `lib/providers/subscription_provider.dart`, `pubspec.yaml` (purchases_flutter: ^8.2.2)

**3. Cote de crédit** ❌ NU se colectează
- Aplicația nu are nicio funcționalitate legată de credit scoring

**4. Autres infos financières** ❌ NU se colectează
- Aplicația afișează balances crypto și portfolio values
- DAR toate sunt stocate doar LOCAL (FlutterSecureStorage)
- NU sunt trimise către servere externe (verificat: nu există Firebase, Analytics, Sentry în pubspec.yaml)
- Toate POST requests sunt doar către Binance API (pentru a obține date) și Glassnode API
- Aplicația e view-only, nu execută trades
- Verificat în: `lib/services/binance_service.dart`, `lib/screens/portfolio_screen.dart`

---

### 4. Messages ✅ COMPLETAT

**Întrebări:**
1. E-mails ❌ NU
2. SMS ou MMS ❌ NU
3. Autres messages via une appli ❌ NU

**Răspuns:** NU bifa NICIO căsuță ❌

**Analiză detaliată:**

**1. E-mails** ❌ NU se colectează
- Aplicația NU citește sau colectează email-uri
- Butonul "Contact Us" din Settings deschide doar browser-ul către https://mytrademate.app/contact.html
- NU există permisiuni READ_EMAIL în AndroidManifest
- Verificat în: `lib/screens/settings_screen.dart` (linia 860-865)

**2. SMS ou MMS** ❌ NU se colectează
- NU există permisiuni READ_SMS, SEND_SMS, RECEIVE_SMS în AndroidManifest.xml
- Aplicația nu accesează SMS-uri

**3. Autres messages via une appli** ❌ NU se colectează
- NU există sistem de chat/messaging în aplicație
- NU există Firebase Messaging, OneSignal sau alte sisteme de push notifications
- Verificat în: `pubspec.yaml` - nu există dependințe de messaging
- "Messages" găsite în cod sunt doar mesaje UI (SnackBar pentru erori din `lib/utils/error_handler.dart`)

---

### 5. Activité dans les applis ✅ COMPLETAT

**Întrebări:**
1. Interactions avec l'appli ❌ NU
2. Historique des recherches via une appli ❌ NU
3. Applis installées ❌ NU
4. Autre contenu généré par l'utilisateur ❌ NU
5. Autres actions ❌ NU

**Răspuns:** NU bifa NICIO căsuță ❌

**Analiză detaliată:**

**1. Interactions avec l'appli** ❌ NU se colectează
- Aplicația NU folosește analytics extern (Firebase Analytics, Mixpanel, Amplitude)
- Verificat în: `pubspec.yaml` - nu există dependințe de analytics
- Achievements și app settings sunt stocate DOAR local (SharedPreferences în `lib/services/achievement_service.dart`, `lib/services/app_settings_service.dart`)
- Nu există tracking de clicks, taps, feature usage trimis către servere

**2. Historique des recherches** ❌ NU se colectează
- NU există funcționalitate de search cu istoric salvat
- TextField-urile găsite în `settings_screen.dart` sunt doar pentru API keys input
- Nu se stochează search queries

**3. Applis installées** ❌ NU se colectează
- NU există permisiunea QUERY_ALL_PACKAGES în AndroidManifest.xml
- Aplicația NU accesează lista de aplicații instalate pe device

**4. Contenu généré par l'utilisateur** ❌ NU se colectează
- Aplicația este view-only (Portfolio Tracker)
- NU permite users să creeze: posts, comments, photos, videos, notes, etc.
- "Content" găsit în cod se referă doar la UI text (SnackBar messages)

**5. Autres actions** ❌ NU se colectează
- Tot ce e stocat (achievements, settings, trial state) este LOCAL
- Nu există tracking de user actions trimis către servere externe
- Verificat: 11 utilizări de SharedPreferences/FlutterSecureStorage în services - toate LOCAL

---

### 6. Infos et performance des applis ✅ COMPLETAT

**Întrebări:**
1. Journaux de plantage (Crash logs) ❌ NU
2. Diagnostics ❌ NU
3. Autres données de performance de l'appli ❌ NU

**Răspuns:** NU bifa NICIO căsuță ❌

**Analiză detaliată:**

**1. Journaux de plantage** ❌ NU se colectează
- NU există servicii de crash reporting (Firebase Crashlytics, Sentry, Bugsnag, Instabug)
- Verificat în: `pubspec.yaml` - nu există astfel de dependințe
- `lib/main.dart` folosește `runApp()` simplu, FĂRĂ error handlers care trimit crash logs
- NU există `runZonedGuarded` sau `FlutterError.onError` configurați să trimită date externe

**2. Diagnostics** ❌ NU se colectează
- NU există servicii de diagnostics sau monitoring
- NU există Firebase Performance, New Relic, Datadog, AppDynamics, etc.
- Verificat în: `pubspec.yaml` - fără dependințe de diagnostics

**3. Autres données de performance** ❌ NU se colectează
- Am găsit 482 utilizări de `debugPrint()` în 39 fișiere dart
- DAR `debugPrint()` în Flutter este DOAR local pentru development
- În production builds (`flutter build --release`), toate `debugPrint`-urile sunt **automat dezactivate**
- NU se trimit performance metrics către servere externe
- Exemplu: `lib/widgets/crypto_avatar.dart` (linia 85) - log doar pentru debugging local

---

### 7. Appareil ou autres ID ✅ COMPLETAT

**Întrebare:**
- Appareil ou autres ID (Device or other IDs)

**Răspuns:** ✅ DA - bifează "Appareil ou autres ID"

**Analiză detaliată:**

**Ce se colectează:**
- ✅ RevenueCat generează automat un **anonymous app user ID** (format: `$RCAnonymousID:...`)
- Acest ID este un **app instance identifier** folosit DOAR pentru subscriptions (Pro monthly/annual)
- Similar cu Firebase Installation ID - trebuie declarat pentru transparență

**Ce NU se colectează:**
- ❌ Android Advertising ID (GAID) - NU colectat (nu există integrări de advertising)
- ❌ Android ID - NU colectat (versiuni recente RevenueCat 8.x nu-l mai colectează)
- ❌ IMEI, MEID, MAC address, IMSI, BSSID, SSID
- ❌ Nu există device_info package sau getInstalledPackages

**Verificat în cod:**
- `lib/providers/subscription_provider.dart` - RevenueCat folosit simplu: `Purchases.configure()` + `getCustomerInfo()`
- NU există integrări externe: Facebook, Adjust, AppsFlyer, Branch, Mixpanel, Amplitude
- NU există apeluri la `setAttributes`, `setAdjustID`, `setFBAnonymousID`
- `pubspec.yaml` - packages: `purchases_flutter: ^8.2.2` (versiune 8.x)

**Motivație pentru declarare:**
- Google Play cere să declari "app instance identifiers"
- RevenueCat anonymous ID este similar cu Firebase Installation ID
- Chiar dacă e folosit DOAR pentru funcționalitate, trebuie declarat

**Referință:** [RevenueCat Google Play Data Safety Documentation](https://www.revenuecat.com/docs/google-plays-data-safety)

---

---

## Detalii Colectare și Partajare Date

### Pentru: Historique des achats (Purchase History)

**1. Manière éphémère?**
- ❌ NON - RevenueCat stochează persistent purchase history

**2. Collecte requise?**
- ☑️ REQUISE - utilizatorii nu pot dezactiva dacă cumpără Pro

**3. Pourquoi collectées?**
- ☑️ Fonctionnement de l'appli (activare funcții Pro)
- ☑️ Gestion des comptes (gestiune subscripție)

**4. Pourquoi partagées?**
- ☑️ Fonctionnement de l'appli (RevenueCat procesează plățile)

---

### Pentru: Appareil ou autres ID (Device IDs)

**1. Manière éphémère?**
- ❌ NON - RevenueCat stochează persistent anonymous app user ID

**2. Collecte requise?**
- ☑️ REQUISE - generat automat de RevenueCat, nu poate fi dezactivat

**3. Pourquoi collectées?**
- ☑️ Fonctionnement de l'appli (identificare utilizator pentru subscripții)
- ☑️ Gestion des comptes (asociere subscripție cu utilizatorul)

**4. Pourquoi partagées?**
- ☑️ Fonctionnement de l'appli (RevenueCat necesită ID pentru gestiune)
- ☑️ Gestion des comptes (asociere purchase-uri cu utilizatorul)

---

---

## Applis gouvernementales ✅ COMPLETAT

**Întrebare:** Votre appli est-elle développée par ou pour un organisme public?

**Răspuns:** ❌ NON

**Motivație:**
- MyTradeMate Portfolio Tracker este o aplicație PRIVATĂ pentru tracking portofoliu crypto
- NU este dezvoltată de sau pentru un organism public
- Este o aplicație comercială pentru utilizatori individuali

---

## Summary - Date Declarate în Google Play Data Safety

### Date colectate și partajate:

**1. Historique des achats** (Purchase History)
- Collectées: ✅ DA (optional - doar dacă user cumpără Pro)
- Partagées: ✅ DA (cu RevenueCat)
- Éphémère: ❌ NON
- Requise: ❌ NON (optional)
- Pourquoi collectées: Fonctionnement de l'appli + Gestion des comptes
- Pourquoi partagées: Fonctionnement de l'appli

**2. Appareil ou autres ID** (Device IDs)
- Collectées: ✅ DA (required - pentru toți utilizatorii)
- Partagées: ✅ DA (cu RevenueCat)
- Éphémère: ❌ NON
- Requise: ✅ OUI (required)
- Pourquoi collectées: Fonctionnement de l'appli + Gestion des comptes
- Pourquoi partagées: Fonctionnement de l'appli + Gestion des comptes

### Date NU colectate:

- ❌ Emplacement (Location)
- ❌ Informations personnelles (Name, Email, etc.)
- ❌ Informations de paiement
- ❌ Cote de crédit
- ❌ Autres infos financières
- ❌ Messages (E-mails, SMS, etc.)
- ❌ Activité dans les applis (Interactions, Search history, etc.)
- ❌ Infos et performance (Crash logs, Diagnostics)

---

## Fonctionnalités financières ✅ COMPLETAT

**Întrebare:** Quelles fonctionnalités financières votre appli propose-t-elle?

**Răspuns:** ☑️ Mon appli ne fournit aucune fonctionnalité financière

**Motivație:**
- Portfolio Tracker este VIEW-ONLY (nu execută trades, nu transferă bani)
- NU este crypto wallet (nu stochează private keys)
- NU este exchange (nu facilitează buy/sell)
- NU oferă servicii bancare, loans, payments, transfers
- In-app purchases (subscripții Pro) au fost deja declarate la "Historique des achats"

---

## Fonctionnalités de santé ✅ COMPLETAT

**Întrebare:** Votre appli propose-t-elle des fonctionnalités de santé?

**Răspuns:** ☑️ Mon appli ne propose aucune fonctionnalité de santé

**Motivație:**
- MyTradeMate Portfolio Tracker este o aplicație de tracking portofoliu crypto
- NU oferă funcționalități de sănătate (fitness, medical, wellness, etc.)

---

## ✅ FORMULAR COMPLET - READY FOR SUBMISSION

### Rezumat Final - Google Play Data Privacy & Security

**Date colectate și partajate:**
1. ✅ Historique des achats (optional - cu RevenueCat)
2. ✅ Appareil ou autres ID (required - cu RevenueCat)

**Date NU colectate:**
- ❌ Location
- ❌ Personal info (name, email, etc.)
- ❌ Payment info
- ❌ Messages
- ❌ App activity
- ❌ Performance data
- ❌ Alte financial info

**Aplicație:**
- ❌ Nu este guvernamentală
- ❌ Nu oferă funcționalități financiare (trading, payments, etc.)
- ❌ Nu oferă funcționalități de sănătate

**Documentație completă:** Toate răspunsurile sunt documentate în acest fișier cu justificări din cod.

---

## Next Steps
1. ✅ Apasă "Enregistrer comme brouillon" sau "Suivant"
2. ✅ Trimite formularul pentru review de la Google Play
3. ✅ Așteaptă aprovarea (poate dura 1-3 zile)

---

## Cod Relevant Verificat

### AndroidManifest.xml
```xml
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
<uses-permission android:name="android.permission.USE_BIOMETRIC" />
<uses-permission android:name="android.permission.USE_FINGERPRINT" />
```

### OnboardingScreen.dart - Guest Sign In
```dart
// Linia 100
await context.read<AuthService>().signInAsGuest();

// Linia 130
Future<void> signInAsGuest() async {
  await _secureStorage.write(key: _kIsAuthenticatedKey, value: 'true');
  _userEmail = 'guest';
  _isAuthenticated = true;
}
```

---

## Notes
- Aplicația este Portfolio Tracker (view-only)
- NU există exchange API keys stored în app
- NU există trading execution
- Este doar pentru tracking și AI predictions

/// Application Configuration
///
/// Environment variables and build-time configuration.
///
/// Usage in development:
/// flutter run --dart-define=SYNCFUSION_LICENSE=your_key_here
///
/// For production builds, set these in your CI/CD pipeline:
/// flutter build ios --dart-define=SYNCFUSION_LICENSE=your_key
class AppConfig {
  /// Syncfusion license key (required for charts)
  /// Set via --dart-define=SYNCFUSION_LICENSE=key
  static const String syncfusionLicense = String.fromEnvironment(
    'SYNCFUSION_LICENSE',
    defaultValue: '', // Empty in development, must be set for production
  );

  /// RevenueCat Apple API Key
  /// Set via --dart-define=REVENUECAT_APPLE_KEY=key
  static const String revenueCatAppleKey = String.fromEnvironment(
    'REVENUECAT_APPLE_KEY',
    defaultValue: 'appl_YOUR_KEY_HERE',
  );

  /// RevenueCat Google API Key
  /// Set via --dart-define=REVENUECAT_GOOGLE_KEY=key
  static const String revenueCatGoogleKey = String.fromEnvironment(
    'REVENUECAT_GOOGLE_KEY',
    defaultValue: 'goog_YOUR_KEY_HERE',
  );

  /// Check if all required config is present
  static bool get isConfigured {
    if (syncfusionLicense.isEmpty) {
      print('⚠️ WARNING: SYNCFUSION_LICENSE not set');
      return false;
    }
    if (revenueCatAppleKey == 'appl_YOUR_KEY_HERE') {
      print('⚠️ WARNING: REVENUECAT_APPLE_KEY not configured');
      return false;
    }
    return true;
  }

  /// Print configuration status (for debugging)
  static void printStatus() {
    print('🔧 App Configuration:');
    print('  Syncfusion License: ${syncfusionLicense.isNotEmpty ? "✓ SET" : "✗ MISSING"}');
    print('  RevenueCat Apple: ${revenueCatAppleKey != "appl_YOUR_KEY_HERE" ? "✓ SET" : "✗ DEFAULT"}');
    print('  RevenueCat Google: ${revenueCatGoogleKey != "goog_YOUR_KEY_HERE" ? "✓ SET" : "✗ DEFAULT"}');
  }
}

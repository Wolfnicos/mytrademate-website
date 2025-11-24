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
  /// For production, MUST be set via --dart-define
  static const String syncfusionLicense = String.fromEnvironment(
    'SYNCFUSION_LICENSE',
    // Development fallback (expires yearly - renew at syncfusion.com)
    defaultValue: 'Ngo9BigBOggjHTQxAR8/V1JFaF5cXGRCf1FpRmJGdld5fUVHYVZUTXxaS00DNHVRdkdmWH9ceXVVRmBZVUZxXEBWYEg=',
  );

  /// RevenueCat Apple API Key
  /// Set via --dart-define=REVENUECAT_APPLE_KEY=key
  /// For production, MUST be set via --dart-define
  static const String revenueCatAppleKey = String.fromEnvironment(
    'REVENUECAT_APPLE_KEY',
    // Development fallback - replace with your production key
    defaultValue: 'appl_vVgBtEaVpppbqhilxwiMvBrJZEX',
  );

  /// RevenueCat Google API Key
  /// Set via --dart-define=REVENUECAT_GOOGLE_KEY=key
  /// For production, MUST be set via --dart-define
  static const String revenueCatGoogleKey = String.fromEnvironment(
    'REVENUECAT_GOOGLE_KEY',
    // Development fallback - add your Google Play key
    defaultValue: 'goog_YOUR_GOOGLE_KEY',
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

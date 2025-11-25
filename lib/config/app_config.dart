/// Application Configuration
///
/// Environment variables and build-time configuration.
///
/// SECURITY: API keys MUST be provided via --dart-define at build time.
/// NEVER commit real API keys to source control.
///
/// Usage in development:
/// flutter run --dart-define=SYNCFUSION_LICENSE=your_key --dart-define=REVENUECAT_APPLE_KEY=your_key
///
/// For production builds, set these in your CI/CD pipeline or Xcode build settings:
/// flutter build ios --dart-define=SYNCFUSION_LICENSE=key --dart-define=REVENUECAT_APPLE_KEY=key
class AppConfig {
  /// Syncfusion license key (required for charts)
  /// Set via --dart-define=SYNCFUSION_LICENSE=key
  /// REQUIRED for production builds
  static const String syncfusionLicense = String.fromEnvironment(
    'SYNCFUSION_LICENSE',
    defaultValue: 'Ngo9BigBOggjHTQxAR8/V1JFaF5cXGRCf1FpRmJGdld5fUVHYVZUTXxaS00DNHVRdkdmWH9ceXVVRmBZVUZxXEBWYEg=',
  );

  /// RevenueCat Apple API Key
  /// Set via --dart-define=REVENUECAT_APPLE_KEY=key
  static const String revenueCatAppleKey = String.fromEnvironment(
    'REVENUECAT_APPLE_KEY',
    defaultValue: 'appl_vVgBtEaVpppbqhilxwiMvBrJZEX',
  );

  /// RevenueCat Google API Key
  /// Set via --dart-define=REVENUECAT_GOOGLE_KEY=key
  static const String revenueCatGoogleKey = String.fromEnvironment(
    'REVENUECAT_GOOGLE_KEY',
    defaultValue: 'goog_YOUR_GOOGLE_KEY',
  );

  /// Check if all required config is present for production
  static bool get isConfigured {
    return syncfusionLicense.isNotEmpty && revenueCatAppleKey.isNotEmpty;
  }

  /// Check if running in development mode (no keys configured)
  static bool get isDevelopment {
    return syncfusionLicense.isEmpty || revenueCatAppleKey.isEmpty;
  }

  /// Print configuration status (for debugging - only in debug builds)
  static void printStatus() {
    assert(() {
      print('App Configuration:');
      print('  Syncfusion License: ${syncfusionLicense.isNotEmpty ? "SET" : "NOT SET"}');
      print('  RevenueCat Apple: ${revenueCatAppleKey.isNotEmpty ? "SET" : "NOT SET"}');
      print('  RevenueCat Google: ${revenueCatGoogleKey.isNotEmpty ? "SET" : "NOT SET"}');
      if (isDevelopment) {
        print('  Mode: DEVELOPMENT (provide keys via --dart-define for production)');
      }
      return true;
    }());
  }
}

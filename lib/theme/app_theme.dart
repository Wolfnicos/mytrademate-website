import 'package:flutter/material.dart';

/// Premium Design System for MyTradeMate
///
/// Features:
/// - Dark mode optimized (Material 3)
/// - Glassmorphism colors
/// - Trading-specific colors (BUY green, SELL red)
/// - Typography hierarchy
/// - Spacing system
class AppTheme {
  // ============ COLORS ============

  // Background
  static const Color background = Color(0xFF0A0E1A); // Deep navy
  static const Color surface = Color(0xFF131827); // Card background
  static const Color surfaceVariant = Color(0xFF1A1F2E); // Elevated cards

  // Trading Colors
  static const Color buyGreen = Color(0xFF00D9A3); // Bright teal
  static const Color buyGreenDark = Color(0xFF00A87E);
  static const Color sellRed = Color(0xFFFF5C5C); // Bright red
  static const Color sellRedDark = Color(0xFFE63946);
  static const Color holdYellow = Color(0xFFFFC107); // Warning amber

  // Accent & Brand
  static const Color primary = Color(0xFF3B82F6); // Blue
  static const Color primaryDark = Color(0xFF2563EB);
  static const Color secondary = Color(0xFF8B5CF6); // Purple
  static const Color secondaryDark = Color(0xFF7C3AED);

  // Text Colors - Dark Mode
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFFB4B8C5);
  static const Color textTertiary = Color(0xFF6B7280);
  static const Color textDisabled = Color(0xFF4B5563);

  // Text Colors - Light Mode (HIGH CONTRAST for WCAG AA compliance)
  static const Color textPrimaryLight = Color(0xFF000000); // Pure black for maximum contrast
  static const Color textSecondaryLight = Color(0xFF374151); // Dark gray (was too light #4B5563)
  static const Color textTertiaryLight = Color(0xFF6B7280); // Medium gray (was too light #9CA3AF)
  static const Color textDisabledLight = Color(0xFFD1D5DB);

  // Semantic Colors
  static const Color success = buyGreen;
  static const Color error = sellRed;
  static const Color warning = holdYellow;
  static const Color info = primary;

  // Glassmorphism
  static const Color glassWhite = Color(0x14FFFFFF); // 8% white
  static const Color glassBorder = Color(0x1AFFFFFF); // 10% white

  // Charts
  static const Color chartGreen = buyGreen;
  static const Color chartRed = sellRed;

  // ============ ADAPTIVE COLORS ============
  
  /// Get text color based on theme brightness
  static Color getTextPrimary(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark 
        ? textPrimary 
        : textPrimaryLight;
  }
  
  static Color getTextSecondary(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark 
        ? textSecondary 
        : textSecondaryLight;
  }
  
  static Color getTextTertiary(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark 
        ? textTertiary 
        : textTertiaryLight;
  }
  
  static Color getSurface(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark 
        ? surface 
        : Colors.white;
  }
  
  static Color getBackground(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark 
        ? background 
        : Colors.grey[50]!;
  }
  static const Color chartBlue = primary;
  static const Color chartPurple = secondary;
  static const Color chartGrid = Color(0x0AFFFFFF); // 4% white

  // ============ GRADIENTS ============

  static const LinearGradient buyGradient = LinearGradient(
    colors: [buyGreen, buyGreenDark],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient sellGradient = LinearGradient(
    colors: [sellRed, sellRedDark],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient primaryGradient = LinearGradient(
    colors: [primary, primaryDark],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient secondaryGradient = LinearGradient(
    colors: [secondary, secondaryDark],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // Premium gold (for PRO badges) - tuned for Light & Dark
  static const Color premiumGoldStart = Color(0xFFFFD54F);
  static const Color premiumGoldEnd = Color(0xFFFFA000);
  static const LinearGradient premiumGoldGradient = LinearGradient(
    colors: [premiumGoldStart, premiumGoldEnd],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient glassGradient = LinearGradient(
    colors: [Color(0x1AFFFFFF), Color(0x0AFFFFFF)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // ============ SHADOWS ============

  static const List<BoxShadow> cardShadow = [
    BoxShadow(
      color: Color(0x1A000000),
      blurRadius: 20,
      offset: Offset(0, 8),
    ),
  ];

  static const List<BoxShadow> glassShadow = [
    BoxShadow(
      color: Color(0x14000000),
      blurRadius: 16,
      offset: Offset(0, 4),
    ),
  ];

  static const List<BoxShadow> glowShadow = [
    BoxShadow(
      color: Color(0x33000000),
      blurRadius: 24,
      offset: Offset(0, 12),
    ),
  ];

  // ============ BORDER RADIUS ============

  static const double radiusXS = 4.0;
  static const double radiusSM = 8.0;
  static const double radiusMD = 12.0;
  static const double radiusLG = 16.0;
  static const double radiusXL = 20.0;
  static const double radius2XL = 24.0;
  static const double radiusFull = 999.0;

  // ============ SPACING ============

  static const double spacing4 = 4.0;
  static const double spacing8 = 8.0;
  static const double spacing12 = 12.0;
  static const double spacing16 = 16.0;
  static const double spacing20 = 20.0;
  static const double spacing24 = 24.0;
  static const double spacing32 = 32.0;
  static const double spacing40 = 40.0;
  static const double spacing48 = 48.0;

  // ============ TYPOGRAPHY ============

  // Display (Hero text)
  static const TextStyle displayLarge = TextStyle(
    fontSize: 32,
    fontWeight: FontWeight.w700,
    height: 1.2,
    letterSpacing: -0.5,
  );

  static const TextStyle displayMedium = TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.w700,
    height: 1.3,
    letterSpacing: -0.3,
  );

  // Headings
  static const TextStyle headingLarge = TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.w600,
    height: 1.3,
    letterSpacing: -0.3,
  );

  static const TextStyle headingMedium = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w600,
    height: 1.4,
    letterSpacing: -0.2,
  );

  static const TextStyle headingSmall = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w600,
    height: 1.4,
    letterSpacing: -0.1,
  );

  // Body
  static const TextStyle bodyLarge = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w400,
    height: 1.5,
    letterSpacing: 0,
  );

  static const TextStyle bodyMedium = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 1.5,
    letterSpacing: 0,
  );

  static const TextStyle bodySmall = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    height: 1.5,
    letterSpacing: 0,
  );

  // Labels
  static const TextStyle labelLarge = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    height: 1.4,
    letterSpacing: 0.1,
  );

  static const TextStyle labelMedium = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w600,
    height: 1.4,
    letterSpacing: 0.1,
  );

  static const TextStyle labelSmall = TextStyle(
    fontSize: 10,
    fontWeight: FontWeight.w600,
    height: 1.4,
    letterSpacing: 0.5,
  );

  // Mono (for prices)
  static const TextStyle monoLarge = TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.w700,
    height: 1.2,
    letterSpacing: -0.5,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  static const TextStyle monoMedium = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    height: 1.4,
    letterSpacing: 0,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  // ============ ANIMATION DURATIONS ============

  static const Duration animationFast = Duration(milliseconds: 150);
  static const Duration animationNormal = Duration(milliseconds: 300);
  static const Duration animationSlow = Duration(milliseconds: 500);

  // ============ THEME DATA ============

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: Colors.grey[50],

      colorScheme: ColorScheme.light(
        primary: primary,
        secondary: secondary,
        surface: Colors.white,
        background: Colors.grey[50]!,
        error: error,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: textPrimaryLight,
        onBackground: textPrimaryLight,
        onError: Colors.white,
        outline: textTertiaryLight,
        outlineVariant: textDisabledLight,
      ),

      appBarTheme: AppBarTheme(
        backgroundColor: Colors.grey[50],
        elevation: 0,
        centerTitle: true,
        titleTextStyle: headingMedium.copyWith(color: Colors.grey[900]),
        iconTheme: const IconThemeData(color: Colors.black87),
        surfaceTintColor: Colors.transparent,
      ),

      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusLG),
        ),
        surfaceTintColor: Colors.transparent,
      ),

      textTheme: TextTheme(
        displayLarge: displayLarge.copyWith(color: textPrimaryLight),
        displayMedium: displayMedium.copyWith(color: textPrimaryLight),
        headlineLarge: headingLarge.copyWith(color: textPrimaryLight),
        headlineMedium: headingMedium.copyWith(color: textPrimaryLight),
        headlineSmall: headingSmall.copyWith(color: textPrimaryLight),
        bodyLarge: bodyLarge.copyWith(color: textSecondaryLight), // Dark gray for readability
        bodyMedium: bodyMedium.copyWith(color: textSecondaryLight),
        bodySmall: bodySmall.copyWith(color: textTertiaryLight),
        labelLarge: labelLarge.copyWith(color: textPrimaryLight),
        labelMedium: labelMedium.copyWith(color: textSecondaryLight),
        labelSmall: labelSmall.copyWith(color: textTertiaryLight),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: spacing24, vertical: spacing16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusMD),
          ),
          textStyle: labelLarge,
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: spacing16, vertical: spacing12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusSM),
          ),
          textStyle: labelLarge,
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.grey[100],
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMD),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMD),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMD),
          borderSide: const BorderSide(color: primary, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: spacing16, vertical: spacing16),
      ),
    );
  }

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: background,

      colorScheme: const ColorScheme.dark(
        primary: primary,
        secondary: secondary,
        surface: surface,
        error: error,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: textPrimary,
        onError: Colors.white,
      ),

      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: headingMedium,
        iconTheme: IconThemeData(color: textPrimary),
      ),

      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusLG),
        ),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: spacing24, vertical: spacing16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusMD),
          ),
          textStyle: labelLarge,
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: spacing16, vertical: spacing12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusSM),
          ),
          textStyle: labelLarge,
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceVariant,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMD),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMD),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMD),
          borderSide: const BorderSide(color: primary, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: spacing16, vertical: spacing16),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:local_auth/local_auth.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../widgets/pin_dialog.dart';

/// Premium Onboarding Flow (3 pages)
/// Page 1: Welcome + All Features
/// Page 2: FREE vs PREMIUM
/// Page 3: Disclaimer + Face ID/PIN setup
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  final LocalAuthentication _localAuth = LocalAuthentication();

  int _currentPage = 0;
  bool _agreedToRisks = false;
  bool _canCheckBiometrics = false;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _checkBiometricSupport();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _checkBiometricSupport() async {
    try {
      final canCheck = await _localAuth.canCheckBiometrics;
      final isDeviceSupported = await _localAuth.isDeviceSupported();

      // IMPORTANT: Also check if any biometrics are actually enrolled
      final availableBiometrics = await _localAuth.getAvailableBiometrics();
      final hasEnrolledBiometrics = availableBiometrics.isNotEmpty;

      if (mounted) {
        setState(() {
          _canCheckBiometrics = canCheck && isDeviceSupported && hasEnrolledBiometrics;
        });
      }
    } catch (e) {
      debugPrint('Error checking biometric support: $e');
    }
  }

  void _nextPage() {
    if (_currentPage < 2) {
      _pageController.nextPage(
        duration: AppTheme.animationNormal,
        curve: Curves.easeInOut,
      );
    }
  }

  void _previousPage() {
    if (_currentPage > 0) {
      _pageController.previousPage(
        duration: AppTheme.animationNormal,
        curve: Curves.easeInOut,
      );
    }
  }

  Future<void> _setupBiometric() async {
    setState(() => _isLoading = true);

    try {
      final authService = context.read<AuthService>();
      final success = await authService.authenticateWithBiometrics();

      if (!mounted) return;

      if (success) {
        await authService.signInAsGuest();
        Navigator.of(context).pushReplacementNamed('/home');
      } else {
        _showError('Biometric authentication failed');
      }
    } catch (e) {
      if (mounted) {
        _showError('Biometric authentication unavailable');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _setupPIN() async {
    setState(() => _isLoading = true);

    try {
      final authService = context.read<AuthService>();

      // Check if PIN is already set
      final hasPIN = await authService.hasPIN();

      if (hasPIN) {
        // User has PIN - VERIFY it
        final pin = await PINDialog.showVerify(context);

        if (!mounted) return;

        if (pin == null) {
          setState(() => _isLoading = false);
          return;
        }

        // Check if user clicked "Forgot PIN?"
        if (pin == 'FORGOT_PIN') {
          setState(() => _isLoading = false);
          await _showForgotPINDialog();
          return;
        }

        // Verify PIN
        final isValid = await authService.verifyPIN(pin);

        if (!mounted) return;

        if (isValid) {
          setState(() => _isLoading = false);
          Navigator.of(context).pushReplacementNamed('/home');
        } else {
          setState(() => _isLoading = false);
          _showError('Invalid PIN code');
        }
      } else {
        // User doesn't have PIN - SET it
        final pin = await PINDialog.showSetup(context);

        if (!mounted) return;

        // If user cancelled, just sign in as guest
        if (pin == null) {
          await authService.signInAsGuest();
          if (!mounted) return;
          setState(() => _isLoading = false);
          Navigator.of(context).pushReplacementNamed('/home');
          return;
        }

        // Save PIN and sign in
        final success = await authService.setPIN(pin);

        if (!mounted) return;

        if (success) {
          // Sign in as guest (user has PIN but no account)
          await authService.signInAsGuest();
          if (!mounted) return;
          setState(() => _isLoading = false);
          Navigator.of(context).pushReplacementNamed('/home');
        } else {
          setState(() => _isLoading = false);
          _showError('Failed to set PIN. Please try again.');
        }
      }
    } catch (e) {
      debugPrint('Error with PIN: $e');
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showError('An error occurred. Please try again.');
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppTheme.error,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Future<void> _showForgotPINDialog() async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).brightness == Brightness.dark
            ? AppTheme.surface
            : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusLG),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(AppTheme.spacing8),
              decoration: BoxDecoration(
                color: AppTheme.error.withOpacity(0.1),
                borderRadius: BorderRadius.circular(AppTheme.radiusSM),
              ),
              child: const Icon(Icons.warning_amber, color: AppTheme.error, size: 24),
            ),
            const SizedBox(width: AppTheme.spacing12),
            const Expanded(
              child: Text(
                'Reset App?',
                style: AppTheme.headingLarge,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'This will delete ALL app data including:',
              style: AppTheme.bodyMedium.copyWith(
                color: AppTheme.getTextPrimary(context),
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: AppTheme.spacing12),
            _buildResetItem('Your PIN code'),
            _buildResetItem('API credentials'),
            _buildResetItem('All settings and preferences'),
            const SizedBox(height: AppTheme.spacing16),
            Text(
              'You will need to set up the app again from scratch.',
              style: AppTheme.bodySmall.copyWith(
                color: AppTheme.getTextSecondary(context),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(
              'Cancel',
              style: TextStyle(color: AppTheme.getTextSecondary(context)),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.error,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppTheme.radiusMD),
              ),
            ),
            child: const Text('Reset App'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      setState(() => _isLoading = true);
      final authService = context.read<AuthService>();
      await authService.deleteAccount();
      if (!mounted) return;
      setState(() => _isLoading = false);
      // Stay on onboarding screen, user can start fresh
      _showError('App data cleared. You can now set up a new PIN.');
    }
  }

  Widget _buildResetItem(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTheme.spacing8),
      child: Row(
        children: [
          const Icon(Icons.close, color: AppTheme.error, size: 16),
          const SizedBox(width: AppTheme.spacing8),
          Text(
            text,
            style: AppTheme.bodyMedium.copyWith(
              color: AppTheme.getTextSecondary(context),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isTablet = screenWidth > 600;
    final maxContentWidth = isTablet ? 600.0 : double.infinity;

    return Scaffold(
      backgroundColor: AppTheme.getBackground(context),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxContentWidth),
            child: Column(
              children: [
                // Progress indicator
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: List.generate(3, (index) {
                      return Expanded(
                        child: Container(
                          height: 4,
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          decoration: BoxDecoration(
                            color: _currentPage >= index
                                ? AppTheme.primary
                                : AppTheme.glassBorder,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      );
                    }),
                  ),
                ),

                // PageView
                Expanded(
                  child: PageView(
                    controller: _pageController,
                    onPageChanged: (index) {
                      setState(() => _currentPage = index);
                    },
                    children: [
                      _buildPage1Welcome(),
                      _buildPage2FreePremium(),
                      _buildPage3Security(),
                    ],
                  ),
                ),

                // Bottom buttons
                Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: _buildBottomButtons(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // PAGE 1: Welcome + All Features
  Widget _buildPage1Welcome() {
    final screenWidth = MediaQuery.of(context).size.width;
    final isTablet = screenWidth > 600;
    final logoSize = isTablet ? 160.0 : 120.0;
    final titleSize = isTablet ? 42.0 : 32.0;
    final subtitleSize = isTablet ? 22.0 : 18.0;

    return SingleChildScrollView(
      physics: const ClampingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 32.0),
      child: Column(
        children: [
          SizedBox(height: isTablet ? 40 : 20),

          // Logo
          Image.asset(
            'assets/logo/mytrademate-logo.png',
            width: logoSize,
            height: logoSize,
            fit: BoxFit.contain,
          ),

          SizedBox(height: isTablet ? 32 : 20),

          // Title
          Text(
            'MyTradeMate',
            style: AppTheme.displayLarge.copyWith(
              fontSize: titleSize,
              fontWeight: FontWeight.bold,
              color: const Color(0xFFFFC837),
            ),
          ),

          const SizedBox(height: 12),

          Text(
            'AI-Powered Crypto Tracking',
            style: AppTheme.headingMedium.copyWith(
              fontSize: subtitleSize,
              fontWeight: FontWeight.w600,
              color: AppTheme.getTextPrimary(context),
            ),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: 8),

          Text(
            'Your intelligent portfolio assistant with advanced market insights',
            style: AppTheme.bodyMedium.copyWith(
              fontSize: isTablet ? 17.0 : 14.0,
              color: AppTheme.getTextSecondary(context),
            ),
            textAlign: TextAlign.center,
          ),

          SizedBox(height: isTablet ? 48 : 32),

          // Feature 1
          _buildFeatureCard(
            icon: Icons.psychology_outlined,
            iconColor: const Color(0xFF0A84FF),
            title: 'Advanced Market Analysis',
            description: '5 timeframes • 76 indicators • Ensemble models',
            isTablet: isTablet,
          ),

          SizedBox(height: isTablet ? 16 : 12),

          // Feature 2
          _buildFeatureCard(
            icon: Icons.show_chart_rounded,
            iconColor: const Color(0xFF34C759),
            title: 'Multi-Timeframe Analysis',
            description: '5 timeframes • 7-day free trial',
            isTablet: isTablet,
          ),

          SizedBox(height: isTablet ? 16 : 12),

          // Feature 3
          _buildFeatureCard(
            icon: Icons.account_balance_wallet_outlined,
            iconColor: const Color(0xFFAF52DE),
            title: 'Portfolio Tracking',
            description: 'Real-time balances • P&L • Performance analytics',
            isTablet: isTablet,
          ),

          SizedBox(height: isTablet ? 16 : 12),

          // Feature 4
          _buildFeatureCard(
            icon: Icons.shield_outlined,
            iconColor: const Color(0xFF34C759),
            title: 'Secure & Private',
            description: 'Read-only access • Encrypted storage • No trade execution',
            isTablet: isTablet,
          ),

          const SizedBox(height: 40),
        ],
      ),
    );
  }

  // PAGE 2: FREE vs PREMIUM
  Widget _buildPage2FreePremium() {
    return SingleChildScrollView(
      physics: const ClampingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 28.0),
      child: Column(
        children: [
          const SizedBox(height: 32),

          Text(
            '7-Day Free Trial',
            style: AppTheme.displayLarge.copyWith(
              fontSize: 32,
              fontWeight: FontWeight.bold,
              color: AppTheme.getTextPrimary(context),
            ),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: 16),

          Text(
            'Full access for 7 days, then €6.99/month or €67.99/year',
            style: AppTheme.bodyLarge.copyWith(
              fontSize: 17,
              color: AppTheme.getTextSecondary(context),
            ),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: 40),

          // FREE Plan
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: AppTheme.glassGradient,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: AppTheme.glassBorder,
                width: 2,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.check_circle, color: AppTheme.success, size: 28),
                    const SizedBox(width: 12),
                    Text(
                      'Free Trial (7 Days)',
                      style: AppTheme.headingLarge.copyWith(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.getTextPrimary(context),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                _buildFeature('✓ All market insights (5m, 15m, 1h, 4h, 1d)', fontSize: 15),
                _buildFeature('✓ Portfolio view (read-only)', fontSize: 15),
                _buildFeature('✓ Real-time price data', fontSize: 15),
                _buildFeature('✓ Candlestick charts', fontSize: 15),
                _buildFeature('✓ Full access for 7 days', fontSize: 15),
                const SizedBox(height: 8),
                Text(
                  'Then subscription required',
                  style: AppTheme.labelSmall.copyWith(
                    fontSize: 12,
                    color: AppTheme.getTextSecondary(context),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // PREMIUM Plan
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppTheme.primary.withOpacity(0.2),
                  AppTheme.secondary.withOpacity(0.2),
                ],
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: AppTheme.primary.withOpacity(0.6),
                width: 2.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.primary.withOpacity(0.3),
                  blurRadius: 20,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.star, color: AppTheme.primary, size: 28),
                    const SizedBox(width: 12),
                    Text(
                      'Pro',
                      style: AppTheme.headingLarge.copyWith(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.primary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                _buildFeature('✓ All features unlocked', fontSize: 15),
                _buildFeature('✓ Market insights on all timeframes', fontSize: 15),
                _buildFeature('✓ Portfolio tracking', fontSize: 15),
                _buildFeature('✓ Real-time market data', fontSize: 15),
                const SizedBox(height: 16),
                Text(
                  '€6.99/month or €67.99/year (save 19%)',
                  style: AppTheme.labelMedium.copyWith(
                    fontSize: 13,
                    color: AppTheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 40),
        ],
      ),
    );
  }

  // PAGE 3: Disclaimer + Security Setup
  Widget _buildPage3Security() {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: constraints.maxHeight,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32.0),
              child: Column(
                children: [
                  const SizedBox(height: 20),

          // Disclaimer box
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppTheme.error.withOpacity(0.1),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: const Color(0xFFFFC837),
                width: 2,
              ),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.warning_amber_rounded,
                      color: Color(0xFFFFC837),
                      size: 28,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Important Risk Disclaimer',
                        style: AppTheme.headingMedium.copyWith(
                          color: const Color(0xFFFFC837),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                _buildDisclaimerItem(
                  icon: Icons.warning_rounded,
                  text: 'Cryptocurrency markets are volatile and risky',
                ),
                _buildDisclaimerItem(
                  icon: Icons.bar_chart_rounded,
                  text: 'Market insights are not financial advice',
                ),
                _buildDisclaimerItem(
                  icon: Icons.visibility_outlined,
                  text: 'This app is view-only and does not execute trades',
                ),
                _buildDisclaimerItem(
                  icon: Icons.school_outlined,
                  text: 'Always do your own research (DYOR)',
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Checkbox
          GestureDetector(
            onTap: () {
              setState(() => _agreedToRisks = !_agreedToRisks);
            },
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.surface.withOpacity(0.5),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _agreedToRisks
                      ? AppTheme.primary
                      : AppTheme.glassBorder,
                  width: 2,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: _agreedToRisks
                          ? AppTheme.primary
                          : Colors.transparent,
                      border: Border.all(
                        color: _agreedToRisks
                            ? AppTheme.primary
                            : AppTheme.textTertiary,
                        width: 2,
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: _agreedToRisks
                        ? const Icon(
                            Icons.check,
                            size: 20,
                            color: Colors.white,
                          )
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'I understand and accept the risks',
                      style: AppTheme.bodyLarge.copyWith(
                        fontWeight: FontWeight.w600,
                        color: AppTheme.getTextPrimary(context),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 32),

          // Security setup section
          if (_agreedToRisks) ...[
            Divider(color: AppTheme.glassBorder, height: 40),

            Text(
              'Secure Your Account',
              style: AppTheme.headingLarge.copyWith(
                fontWeight: FontWeight.bold,
                color: AppTheme.getTextPrimary(context),
              ),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 8),

            Text(
              'Choose how to protect your trading account',
              style: AppTheme.bodyMedium.copyWith(
                color: AppTheme.getTextSecondary(context),
              ),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 24),

            // Face ID button
            if (_canCheckBiometrics)
              _buildSecurityButton(
                icon: Icons.fingerprint_rounded,
                title: 'Use Face ID / Touch ID',
                description: 'Quick and secure biometric authentication',
                onTap: _isLoading ? null : _setupBiometric,
                isPrimary: true,
              ),

            if (_canCheckBiometrics) const SizedBox(height: 12),

            // PIN button
            _buildSecurityButton(
              icon: Icons.lock_outline_rounded,
              title: 'Use PIN Code',
              description: '4-digit security code',
              onTap: _isLoading ? null : _setupPIN,
              isPrimary: !_canCheckBiometrics,
            ),

            const SizedBox(height: 12),
          ],

                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildFeatureCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String description,
    bool isTablet = false,
  }) {
    final iconBoxSize = isTablet ? 56.0 : 48.0;
    final iconSize = isTablet ? 28.0 : 24.0;
    final titleSize = isTablet ? 18.0 : 16.0;
    final descSize = isTablet ? 15.0 : 13.0;

    return Container(
      padding: EdgeInsets.all(isTablet ? 20 : 16),
      decoration: BoxDecoration(
        gradient: AppTheme.glassGradient,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppTheme.glassBorder,
          width: 1.5,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: iconBoxSize,
            height: iconBoxSize,
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: iconColor, size: iconSize),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTheme.bodyLarge.copyWith(
                    fontSize: titleSize,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.getTextPrimary(context),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: AppTheme.bodySmall.copyWith(
                    fontSize: descSize,
                    color: AppTheme.getTextSecondary(context),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeature(String text, {bool isDisabled = false, double fontSize = 14}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10.0),
      child: Builder(
        builder: (context) => Text(
          text,
          style: AppTheme.bodyMedium.copyWith(
            fontSize: fontSize,
            color: isDisabled ? AppTheme.getTextTertiary(context) : AppTheme.getTextSecondary(context),
            decoration: isDisabled ? TextDecoration.lineThrough : null,
          ),
        ),
      ),
    );
  }

  Widget _buildDisclaimerItem({
    required IconData icon,
    required String text,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Builder(
        builder: (context) => Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              icon,
              color: AppTheme.getTextSecondary(context),
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                text,
                style: AppTheme.bodyMedium.copyWith(
                  color: AppTheme.getTextSecondary(context),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSecurityButton({
    required IconData icon,
    required String title,
    required String description,
    required VoidCallback? onTap,
    required bool isPrimary,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: isPrimary
              ? LinearGradient(
                  colors: [
                    AppTheme.primary.withOpacity(0.15),
                    AppTheme.secondary.withOpacity(0.15),
                  ],
                )
              : AppTheme.glassGradient,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isPrimary
                ? AppTheme.primary.withOpacity(0.5)
                : AppTheme.glassBorder,
            width: isPrimary ? 2 : 1.5,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: isPrimary
                    ? AppTheme.primary.withOpacity(0.2)
                    : AppTheme.glassBorder.withOpacity(0.1),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: AppTheme.primary, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppTheme.bodyLarge.copyWith(
                      fontWeight: FontWeight.w600,
                      color: AppTheme.getTextPrimary(context),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: AppTheme.bodySmall.copyWith(
                      color: AppTheme.getTextSecondary(context),
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios_rounded,
              color: AppTheme.textTertiary,
              size: 16,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomButtons() {
    if (_currentPage == 0 || _currentPage == 1) {
      return Row(
        children: [
          // Back button (only on page 2)
          if (_currentPage == 1)
            Expanded(
              flex: 1,
              child: SizedBox(
                height: 56,
                child: OutlinedButton(
                  onPressed: _previousPage,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.textPrimary,
                    side: BorderSide(
                      color: AppTheme.glassBorder,
                      width: 1.5,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: const Text('Back'),
                ),
              ),
            ),
          if (_currentPage == 1) const SizedBox(width: 12),
          // Next button
          Expanded(
            flex: _currentPage == 0 ? 1 : 2,
            child: SizedBox(
              height: 56,
              child: ElevatedButton(
                onPressed: _nextPage,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shadowColor: Colors.transparent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Continue',
                      style: AppTheme.bodyLarge.copyWith(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.arrow_forward, size: 20),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    }

    // Page 3 - Back button (Face ID/PIN appear only after accepting risks)
    return SizedBox(
      height: 56,
      child: OutlinedButton(
        onPressed: _previousPage,
        style: OutlinedButton.styleFrom(
          foregroundColor: AppTheme.textPrimary,
          side: BorderSide(
            color: AppTheme.glassBorder,
            width: 1.5,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: const Text('Back'),
      ),
    );
  }
}

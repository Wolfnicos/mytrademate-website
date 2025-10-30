import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_card.dart';
import '../widgets/risk_disclaimer_dialog.dart';
import '../services/auth_service.dart';
import 'package:provider/provider.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  int _currentPage = 0;
  final PageController _pageController = PageController();

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PageView(
        controller: _pageController,
        onPageChanged: (index) => setState(() => _currentPage = index),
        children: const [
          _PremiumIntroPage(),
          _AuthPage(),
        ],
      ),
      bottomNavigationBar: _BottomIndicator(
        currentPage: _currentPage,
        pageController: _pageController,
        totalPages: 2,
      ),
    );
  }
}

// Page 1: Premium Introduction with Features & Disclaimer
class _PremiumIntroPage extends StatefulWidget {
  const _PremiumIntroPage();

  @override
  State<_PremiumIntroPage> createState() => _PremiumIntroPageState();
}

class _PremiumIntroPageState extends State<_PremiumIntroPage> {
  bool _disclaimerAccepted = false;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppTheme.spacing24),
        child: Column(
          children: [
            const SizedBox(height: AppTheme.spacing32),
          
          // Premium Hero Section
          Container(
            width: 140,
            height: 140,
            decoration: BoxDecoration(
              gradient: AppTheme.premiumGoldGradient,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: AppTheme.warning.withOpacity(0.5),
                  blurRadius: 60,
                  spreadRadius: 10,
                ),
              ],
            ),
            child: const Icon(
              Icons.auto_awesome,
              size: 72,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: AppTheme.spacing24),

          // App Title with Premium Badge
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: ShaderMask(
                  shaderCallback: (bounds) => AppTheme.premiumGoldGradient.createShader(bounds),
                  child: Text(
                    'MyTradeMate',
                    style: AppTheme.displayLarge.copyWith(
                      fontSize: 36,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              const SizedBox(width: AppTheme.spacing8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppTheme.spacing8,
                  vertical: AppTheme.spacing4,
                ),
                decoration: BoxDecoration(
                  gradient: AppTheme.premiumGoldGradient,
                  borderRadius: BorderRadius.circular(AppTheme.radiusSM),
                ),
                child: Text(
                  'PRO',
                  style: AppTheme.labelSmall.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTheme.spacing12),

          // Tagline
          Text(
            'AI-Powered Portfolio Tracker',
            style: AppTheme.headingLarge.copyWith(
              fontSize: 24,
              fontWeight: FontWeight.w700,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppTheme.spacing8),
          Text(
            'Your intelligent trading assistant with advanced AI predictions and automated strategies',
            style: AppTheme.bodyMedium.copyWith(
              color: AppTheme.textSecondary,
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppTheme.spacing40),

          // Premium Features
          _buildPremiumFeature(
            icon: Icons.psychology,
            gradient: AppTheme.primaryGradient,
            title: 'Advanced AI Predictions',
            description: '6 timeframes • 76 indicators • Ensemble models',
          ),
          const SizedBox(height: AppTheme.spacing16),
          _buildPremiumFeature(
            icon: Icons.trending_up,
            gradient: AppTheme.buyGradient,
            title: '4 Order Types',
            description: 'Market, Limit, Stop-Limit, Stop-Market',
          ),
          const SizedBox(height: AppTheme.spacing16),
          _buildPremiumFeature(
            icon: Icons.account_balance_wallet,
            gradient: AppTheme.secondaryGradient,
            title: 'Portfolio Tracking',
            description: 'Real-time balances • P&L • Performance analytics',
          ),
          const SizedBox(height: AppTheme.spacing16),
          _buildPremiumFeature(
            icon: Icons.shield_outlined,
            gradient: LinearGradient(
              colors: [AppTheme.success, AppTheme.success.withOpacity(0.6)],
            ),
            title: 'Secure & Private',
            description: 'Biometric auth • Encrypted storage • Your keys',
          ),
          
          const SizedBox(height: AppTheme.spacing40),
          
          // Risk Disclaimer Section
          Container(
            padding: const EdgeInsets.all(AppTheme.spacing20),
            decoration: BoxDecoration(
              color: AppTheme.warning.withOpacity(0.1),
              borderRadius: BorderRadius.circular(AppTheme.radiusLG),
              border: Border.all(
                color: AppTheme.warning.withOpacity(0.3),
                width: 2,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, color: AppTheme.warning, size: 24),
                    const SizedBox(width: AppTheme.spacing12),
                    Expanded(
                      child: Text(
                        'Important Risk Disclaimer',
                        style: AppTheme.headingMedium.copyWith(
                          color: AppTheme.warning,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppTheme.spacing16),
                _buildDisclaimerPoint('⚠️', 'Crypto trading involves substantial risk of loss'),
                _buildDisclaimerPoint('📊', 'Not financial advice - AI predictions may be inaccurate'),
                _buildDisclaimerPoint('🔞', 'You must be 18+ to use this app'),
                _buildDisclaimerPoint('💼', 'Always do your own research (DYOR)'),
                const SizedBox(height: AppTheme.spacing16),
                
                // Accept Checkbox
                GestureDetector(
                  onTap: () => setState(() => _disclaimerAccepted = !_disclaimerAccepted),
                  child: Container(
                    padding: const EdgeInsets.all(AppTheme.spacing12),
                    decoration: BoxDecoration(
                      color: _disclaimerAccepted 
                          ? AppTheme.success.withOpacity(0.1)
                          : AppTheme.surfaceVariant,
                      borderRadius: BorderRadius.circular(AppTheme.radiusMD),
                      border: Border.all(
                        color: _disclaimerAccepted 
                            ? AppTheme.success
                            : AppTheme.glassBorder,
                        width: 2,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _disclaimerAccepted 
                              ? Icons.check_circle
                              : Icons.circle_outlined,
                          color: _disclaimerAccepted 
                              ? AppTheme.success
                              : AppTheme.textTertiary,
                          size: 24,
                        ),
                        const SizedBox(width: AppTheme.spacing12),
                        Expanded(
                          child: Text(
                            'I understand and accept the risks',
                            style: AppTheme.bodyMedium.copyWith(
                              color: _disclaimerAccepted 
                                  ? AppTheme.success
                                  : AppTheme.textPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: AppTheme.spacing32),
          
          // Get Started Button
          SizedBox(
            width: double.infinity,
            height: 60,
            child: ElevatedButton(
              onPressed: _disclaimerAccepted
                  ? () {
                      // Save disclaimer acceptance
                      RiskDisclaimerDialog.markAccepted();
                      // Go to auth page
                      final pageController = context.findAncestorStateOfType<_WelcomeScreenState>()?._pageController;
                      pageController?.nextPage(
                        duration: AppTheme.animationNormal,
                        curve: Curves.easeInOut,
                      );
                    }
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: _disclaimerAccepted ? AppTheme.primary : AppTheme.textDisabled,
                foregroundColor: Colors.white,
                disabledBackgroundColor: AppTheme.textDisabled,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppTheme.radiusMD),
                ),
                elevation: _disclaimerAccepted ? 8 : 0,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Get Started',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: AppTheme.spacing8),
                  const Icon(Icons.arrow_forward, color: Colors.white, size: 20),
                ],
              ),
            ),
          ),
          const SizedBox(height: 100), // Space for bottom navigation bar
        ],
      ),
    ),
    );
  }
  
  Widget _buildPremiumFeature({
    required IconData icon,
    required Gradient gradient,
    required String title,
    required String description,
  }) {
    return Container(
      padding: const EdgeInsets.all(AppTheme.spacing16),
      decoration: BoxDecoration(
        gradient: AppTheme.glassGradient,
        borderRadius: BorderRadius.circular(AppTheme.radiusLG),
        border: Border.all(color: AppTheme.glassBorder),
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              gradient: gradient,
              borderRadius: BorderRadius.circular(AppTheme.radiusMD),
            ),
            child: Icon(icon, color: Colors.white, size: 28),
          ),
          const SizedBox(width: AppTheme.spacing16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTheme.headingSmall.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: AppTheme.spacing4),
                Text(
                  description,
                  style: AppTheme.bodySmall.copyWith(
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildDisclaimerPoint(String emoji, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTheme.spacing8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 16)),
          const SizedBox(width: AppTheme.spacing8),
          Expanded(
            child: Text(
              text,
              style: AppTheme.bodySmall.copyWith(
                color: AppTheme.textSecondary,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// OLD Page 1: App Introduction (REMOVED)
class _IntroPage extends StatelessWidget {
  const _IntroPage();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.all(AppTheme.spacing24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Animated AI Icon
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              gradient: AppTheme.primaryGradient,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: AppTheme.primary.withOpacity(0.4),
                  blurRadius: 40,
                  spreadRadius: 4,
                ),
              ],
            ),
            child: const Icon(
              Icons.smart_toy,
              size: 64,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: AppTheme.spacing32),

          // App Title
          ShaderMask(
            shaderCallback: (bounds) => AppTheme.primaryGradient.createShader(bounds),
            child: Text(
              'MyTradeMate',
              style: AppTheme.displayLarge.copyWith(
                fontSize: 48,
                fontWeight: FontWeight.w900,
                color: Colors.white,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: AppTheme.spacing16),

          // Subtitle
          Text(
            'Your premium AI-powered crypto trading assistant',
            style: (textTheme.titleLarge ?? AppTheme.headingLarge).copyWith(
              color: colors.onBackground.withOpacity(0.75),
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppTheme.spacing48),

          // Feature Pills
          GlassCard(
            child: Column(
              children: [
                _FeaturePill(
                  icon: Icons.auto_graph,
                  title: 'Smart AI Analysis',
                  description: 'Advanced machine learning models analyze market trends in real-time',
                ),
                const Divider(color: AppTheme.glassBorder, height: 24),
                _FeaturePill(
                  icon: Icons.security,
                  title: 'Secure & Private',
                  description: 'Your data is encrypted and stored locally on your device',
                ),
                const Divider(color: AppTheme.glassBorder, height: 24),
                _FeaturePill(
                  icon: Icons.wallet,
                  title: 'Portfolio Tracking',
                  description: 'Monitor your crypto holdings and performance',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FeaturePill extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;

  const _FeaturePill({
    required this.icon,
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Row(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            gradient: AppTheme.primaryGradient,
            borderRadius: BorderRadius.circular(AppTheme.radiusMD),
          ),
          child: Icon(icon, color: Colors.white, size: 24),
        ),
        const SizedBox(width: AppTheme.spacing16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: (textTheme.titleMedium ?? AppTheme.headingSmall).copyWith(color: colors.onBackground)),
              const SizedBox(height: AppTheme.spacing4),
              Text(
                description,
                style: (textTheme.bodySmall ?? AppTheme.bodySmall).copyWith(color: colors.onBackground.withOpacity(0.6)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// Page 2: Feature Tiers (Free vs Premium)
class _FeatureTiersPage extends StatelessWidget {
  const _FeatureTiersPage();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppTheme.spacing24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Title
          Text(
            'Choose Your Plan',
            style: AppTheme.displayLarge.copyWith(fontSize: 32),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppTheme.spacing8),
          Text(
            'Start free, upgrade anytime',
            style: AppTheme.bodyLarge.copyWith(color: AppTheme.textSecondary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppTheme.spacing32),

          // FREE Tier Card
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            AppTheme.primary.withOpacity(0.3),
                            AppTheme.secondary.withOpacity(0.3),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(AppTheme.radiusMD),
                      ),
                      child: const Icon(Icons.visibility, color: AppTheme.primary, size: 24),
                    ),
                    const SizedBox(width: AppTheme.spacing12),
                    Expanded(
                      child: Text('READ ONLY', style: AppTheme.headingLarge),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppTheme.spacing12,
                        vertical: AppTheme.spacing4,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.success.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(AppTheme.radiusSM),
                      ),
                      child: Text(
                        'FREE',
                        style: AppTheme.labelSmall.copyWith(
                          color: AppTheme.success,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppTheme.spacing16),
                _TierFeature(icon: Icons.bar_chart, text: 'View portfolio & market data'),
                _TierFeature(icon: Icons.lightbulb_outline, text: 'Get AI trading recommendations'),
                _TierFeature(icon: Icons.analytics_outlined, text: 'Real-time market analysis'),
                _TierFeature(icon: Icons.lock_outline, text: 'Safe & secure (read-only API)'),
              ],
            ),
          ),
          const SizedBox(height: AppTheme.spacing16),

          // PREMIUM Tier Card
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            AppTheme.warning.withOpacity(0.3),
                            AppTheme.warning.withOpacity(0.5),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(AppTheme.radiusMD),
                      ),
                      child: const Icon(Icons.auto_awesome, color: AppTheme.warning, size: 24),
                    ),
                    const SizedBox(width: AppTheme.spacing12),
                    Flexible(
                      child: Text(
                        'TRADING ENABLED',
                        style: AppTheme.headingLarge,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: AppTheme.spacing8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppTheme.spacing12,
                        vertical: AppTheme.spacing4,
                      ),
                      decoration: BoxDecoration(
                        gradient: AppTheme.premiumGoldGradient,
                        borderRadius: BorderRadius.circular(AppTheme.radiusSM),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.12),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Text(
                        'PRO',
                        style: AppTheme.labelSmall.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppTheme.spacing16),
                _TierFeature(icon: Icons.check_circle, text: 'Everything in FREE'),
                _TierFeature(icon: Icons.rocket_launch, text: 'AI executes trades automatically'),
                _TierFeature(icon: Icons.trending_up, text: 'Advanced trading strategies'),
                _TierFeature(icon: Icons.shield, text: 'Risk management & stop-loss'),
                const SizedBox(height: AppTheme.spacing12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(AppTheme.spacing12),
                  decoration: BoxDecoration(
                    gradient: AppTheme.primaryGradient,
                    borderRadius: BorderRadius.circular(AppTheme.radiusMD),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.info_outline, color: Colors.white, size: 16),
                      const SizedBox(width: AppTheme.spacing8),
                      Text(
                        'Can be enabled later in Settings',
                        style: AppTheme.bodySmall.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TierFeature extends StatelessWidget {
  final IconData icon;
  final String text;

  const _TierFeature({
    required this.icon,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTheme.spacing8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppTheme.primary),
          const SizedBox(width: AppTheme.spacing8),
          Expanded(
            child: Text(
              text,
              style: AppTheme.bodyMedium.copyWith(color: AppTheme.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

// Page 3: Authentication (Email/Password + Biometrics)
class _AuthPage extends StatefulWidget {
  const _AuthPage();

  @override
  State<_AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<_AuthPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _canUseBiometrics = false;
  List<BiometricType> _availableBiometrics = [];
  bool _showPassword = false;

  @override
  void initState() {
    super.initState();
    _checkBiometrics();
    _prefillFromStorage();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _checkBiometrics() async {
    final authService = context.read<AuthService>();
    final canUse = await authService.canUseBiometrics();
    final available = await authService.getAvailableBiometrics();
    setState(() {
      _canUseBiometrics = canUse;
      _availableBiometrics = available;
    });
    // If biometrics enabled, auto-attempt quick login
    if (authService.biometricsEnabled && canUse && mounted) {
      await _signInWithBiometrics();
    }
  }

  Future<void> _prefillFromStorage() async {
    final authService = context.read<AuthService>();
    await authService.load();
    if (!mounted) return;
    setState(() {
      _emailController.text = authService.userEmail ?? '';
    });
  }

  Future<void> _signIn() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      _showError('Please enter email and password');
      return;
    }

    if (!email.contains('@')) {
      _showError('Please enter a valid email');
      return;
    }

    setState(() => _isLoading = true);

    final authService = context.read<AuthService>();
    final success = await authService.signInWithEmailPassword(email, password);

    if (!mounted) return;

    setState(() => _isLoading = false);

    if (success) {
      Navigator.of(context).pushReplacementNamed('/home');
    } else {
      _showError('Invalid email or password');
    }
  }

  Future<void> _register() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      _showError('Please enter email and password');
      return;
    }

    if (!email.contains('@')) {
      _showError('Please enter a valid email');
      return;
    }

    if (password.length < 6) {
      _showError('Password must be at least 6 characters');
      return;
    }

    setState(() => _isLoading = true);

    final authService = context.read<AuthService>();
    final success = await authService.register(email, password);

    if (!mounted) return;

    setState(() => _isLoading = false);

    if (success) {
      // Optionally offer to enable biometrics
      if (_canUseBiometrics) {
        _offerBiometrics();
      } else {
        Navigator.of(context).pushReplacementNamed('/home');
      }
    } else {
      _showError('Failed to create account');
    }
  }

  Future<void> _signInWithBiometrics() async {
    setState(() => _isLoading = true);

    final authService = context.read<AuthService>();
    final success = await authService.authenticateWithBiometrics();

    if (!mounted) return;

    setState(() => _isLoading = false);

    if (success) {
      Navigator.of(context).pushReplacementNamed('/home');
    } else {
      _showError('Biometric authentication failed');
    }
  }

  void _offerBiometrics() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: Text('Enable Biometric Login?', style: AppTheme.headingLarge),
        content: Text(
          'Use Face ID / Touch ID for quick and secure access',
          style: AppTheme.bodyMedium.copyWith(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.of(context).pushReplacementNamed('/home');
            },
            child: const Text('Not Now'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(context).pop();
              final authService = context.read<AuthService>();
              final enabled = await authService.enableBiometrics();
              if (enabled && mounted) {
                Navigator.of(context).pushReplacementNamed('/home');
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
            ),
            child: const Text('Enable'),
          ),
        ],
      ),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppTheme.error,
      ),
    );
  }

  String get _biometricLabel {
    if (_availableBiometrics.contains(BiometricType.face)) {
      return 'Face ID';
    } else if (_availableBiometrics.contains(BiometricType.fingerprint)) {
      return 'Touch ID';
    }
    return 'Biometric';
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
          Text(
            'Sign in to continue',
              style: (textTheme.headlineSmall ?? AppTheme.displayLarge).copyWith(
                fontSize: 20,
                color: colors.onBackground,
                fontWeight: FontWeight.w700,
              ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppTheme.spacing4),
          Text(
            'Use email or biometric login',
            style: AppTheme.bodySmall.copyWith(
              color: colors.onBackground.withOpacity(0.7),
              fontSize: 13,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppTheme.spacing16),

          // Email Field
          GlassCard(
            child: TextField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.username, AutofillHints.email],
              style: TextStyle(
                color: colors.onSurface,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
              decoration: InputDecoration(
                labelText: 'Email',
                labelStyle: TextStyle(color: colors.onSurface.withOpacity(0.7), fontSize: 14),
                hintStyle: TextStyle(color: colors.onSurface.withOpacity(0.5), fontSize: 14),
                prefixIcon: const Icon(Icons.email_outlined, color: AppTheme.primary),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
              ),
            ),
          ),
          const SizedBox(height: AppTheme.spacing12),

          // Password Field
          GlassCard(
            child: TextField(
              controller: _passwordController,
              obscureText: !_showPassword,
              autofillHints: const [AutofillHints.password],
              style: TextStyle(
                color: colors.onSurface,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
              decoration: InputDecoration(
                labelText: 'Password',
                labelStyle: TextStyle(color: colors.onSurface.withOpacity(0.7), fontSize: 14),
                hintStyle: TextStyle(color: colors.onSurface.withOpacity(0.5), fontSize: 14),
                prefixIcon: const Icon(Icons.lock_outline, color: AppTheme.primary),
                suffixIcon: IconButton(
                  onPressed: () => setState(() => _showPassword = !_showPassword),
                  icon: Icon(_showPassword ? Icons.visibility_off : Icons.visibility, color: colors.onSurface.withOpacity(0.7)),
                ),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
              ),
            ),
          ),
          const SizedBox(height: 4),

          // Sign In Button
          SizedBox(
            width: double.infinity,
            height: 44,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _signIn,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppTheme.radiusMD),
                ),
              ),
              child: _isLoading
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                    )
                  : const Text('Sign In', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            ),
          ),
          const SizedBox(height: 4),

          // Register Button
          SizedBox(
            width: double.infinity,
            height: 44,
            child: OutlinedButton(
              onPressed: _isLoading ? null : _register,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.primary,
                side: const BorderSide(color: AppTheme.primary, width: 2),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppTheme.radiusMD),
                ),
              ),
              child: const Text('Create Account', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            ),
          ),

          const SizedBox(height: 4),

          // Guest Mode
          TextButton(
            onPressed: _isLoading
                ? null
                : () async {
                    setState(() => _isLoading = true);
                    await context.read<AuthService>().signInAsGuest();
                    if (!mounted) return;
                    setState(() => _isLoading = false);
                    Navigator.of(context).pushReplacementNamed('/home');
                  },
            child: Text(
              'Continue as guest',
              style: AppTheme.labelLarge.copyWith(color: AppTheme.textSecondary),
            ),
          ),

          // Biometric Login (if available)
          if (_canUseBiometrics) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(child: Divider(color: AppTheme.glassBorder)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacing8),
                  child: Text('OR', style: AppTheme.bodySmall.copyWith(color: AppTheme.textTertiary, fontSize: 12)),
                ),
                Expanded(child: Divider(color: AppTheme.glassBorder)),
              ],
            ),
            const SizedBox(height: 4),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: OutlinedButton.icon(
                onPressed: _isLoading ? null : _signInWithBiometrics,
                icon: Icon(
                  _availableBiometrics.contains(BiometricType.face)
                      ? Icons.face
                      : Icons.fingerprint,
                ),
                label: Text('Quick login with $_biometricLabel'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.secondary,
                  side: const BorderSide(color: AppTheme.secondary, width: 2),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppTheme.radiusMD),
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 100), // Space for bottom navigation bar
        ],
      ),
    ),
    );
  }
}

// Bottom Page Indicator
class _BottomIndicator extends StatelessWidget {
  final int currentPage;
  final PageController pageController;
  final int totalPages;

  const _BottomIndicator({
    required this.currentPage,
    required this.pageController,
    this.totalPages = 2,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppTheme.spacing24),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        border: Border(
          top: BorderSide(color: AppTheme.glassBorder),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Back Button
            TextButton(
              onPressed: currentPage > 0
                  ? () => pageController.previousPage(
                        duration: AppTheme.animationNormal,
                        curve: Curves.easeInOut,
                      )
                  : null,
              child: Text(
                'Back',
                style: AppTheme.labelLarge.copyWith(
                  color: currentPage > 0 ? AppTheme.primary : AppTheme.textTertiary,
                ),
              ),
            ),

            // Page Indicators
            Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(totalPages, (index) {
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: AppTheme.spacing4),
                  width: index == currentPage ? 24 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    gradient: index == currentPage ? AppTheme.primaryGradient : null,
                    color: index == currentPage ? null : AppTheme.glassBorder,
                    borderRadius: BorderRadius.circular(AppTheme.radiusSM),
                  ),
                );
              }),
            ),

            // Next/Skip Button (hidden on page 0 - use Get Started instead)
            TextButton(
              onPressed: (currentPage > 0 && currentPage < (totalPages - 1))
                  ? () => pageController.nextPage(
                        duration: AppTheme.animationNormal,
                        curve: Curves.easeInOut,
                      )
                  : null,
              child: Text(
                (currentPage > 0 && currentPage < (totalPages - 1)) ? 'Next' : '',
                style: AppTheme.labelLarge.copyWith(
                  color: (currentPage > 0 && currentPage < (totalPages - 1)) ? AppTheme.primary : Colors.transparent,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

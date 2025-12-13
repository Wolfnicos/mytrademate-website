import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/subscription_provider.dart';
import '../theme/app_theme.dart';

/// Premium Paywall Screen 2025 - Ultra Modern Design
/// Shows pricing, features, and purchase buttons with glassmorphism
class PaywallScreen extends StatelessWidget {
  const PaywallScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Stack(
          children: [
            // Background Gradient Orbs (Premium effect)
            Positioned(
              top: -100,
              right: -100,
              child: Container(
                width: 300,
                height: 300,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      AppTheme.primary.withOpacity(0.15),
                      AppTheme.primary.withOpacity(0.0),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: -150,
              left: -100,
              child: Container(
                width: 350,
                height: 350,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      AppTheme.secondary.withOpacity(0.1),
                      AppTheme.secondary.withOpacity(0.0),
                    ],
                  ),
                ),
              ),
            ),

            // Main Content
            SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                horizontal: AppTheme.spacing24,
                vertical: AppTheme.spacing16,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Close Button
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const SizedBox(width: 40),
                      IconButton(
                        icon: Icon(
                          Icons.close_rounded,
                          color: AppTheme.textSecondary,
                          size: 28,
                        ),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppTheme.spacing16),

                  // Logo Header (Premium)
                  Center(
                    child: Container(
                      width: 120,
                      height: 120,
                      padding: const EdgeInsets.all(AppTheme.spacing16),
                      decoration: BoxDecoration(
                        gradient: AppTheme.glassGradient,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AppTheme.primary.withOpacity(0.3),
                          width: 2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.primary.withOpacity(0.2),
                            blurRadius: 30,
                            spreadRadius: 5,
                          ),
                        ],
                      ),
                      child: Image.asset(
                        'assets/logo/mytrademate-logo.png',
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppTheme.spacing32),

                  // Title (Bold & Modern)
                  Text(
                    'Unlock Premium',
                    style: AppTheme.headingLarge.copyWith(
                      fontSize: 40,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -1,
                      height: 1.1,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppTheme.spacing8),

                  // Subtitle (Clean)
                  Text(
                    'Advanced market insights & strategies',
                    style: AppTheme.bodyLarge.copyWith(
                      color: AppTheme.textSecondary,
                      fontSize: 17,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppTheme.spacing40),

                  // Feature Cards (Ultra Premium)
                  _buildPremiumFeature(
                    icon: Icons.auto_graph_rounded,
                    title: 'Multi-timeframe AI',
                    subtitle: '5m, 15m, 1h, 4h, 1D predictions',
                    gradient: AppTheme.primaryGradient,
                  ),
                  const SizedBox(height: AppTheme.spacing16),

                  _buildPremiumFeature(
                    icon: Icons.psychology_rounded,
                    title: 'Advanced Strategies',
                    subtitle: 'RSI/ML • Momentum • Breakout • Mean Reversion',
                    gradient: LinearGradient(
                      colors: [
                        AppTheme.secondary,
                        AppTheme.secondary.withOpacity(0.7),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppTheme.spacing16),

                  _buildPremiumFeature(
                    icon: Icons.account_balance_wallet_rounded,
                    title: 'Portfolio Tracking',
                    subtitle: 'Real-time insights & performance metrics',
                    gradient: LinearGradient(
                      colors: [
                        AppTheme.success,
                        AppTheme.success.withOpacity(0.7),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppTheme.spacing40),

                  // Pricing Section (Premium Glass Card)
                  Container(
                    padding: const EdgeInsets.all(AppTheme.spacing24),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          AppTheme.surface.withOpacity(0.4),
                          AppTheme.surface.withOpacity(0.2),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(AppTheme.radiusXL),
                      border: Border.all(
                        color: AppTheme.primary.withOpacity(0.3),
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.primary.withOpacity(0.1),
                          blurRadius: 20,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        // Monthly Price
                        Text(
                          '€6.99',
                          style: AppTheme.headingLarge.copyWith(
                            fontSize: 48,
                            fontWeight: FontWeight.w900,
                            height: 1,
                            letterSpacing: -2,
                          ),
                        ),
                        Text(
                          'per month',
                          style: AppTheme.bodyMedium.copyWith(
                            color: AppTheme.textTertiary,
                            fontSize: 15,
                          ),
                        ),

                        const SizedBox(height: AppTheme.spacing16),

                        // Divider
                        Container(
                          height: 1,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Colors.transparent,
                                AppTheme.glassBorder,
                                Colors.transparent,
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(height: AppTheme.spacing16),

                        // Annual Price (Highlighted)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              '€67.99',
                              style: AppTheme.headingLarge.copyWith(
                                fontSize: 36,
                                fontWeight: FontWeight.w900,
                                color: AppTheme.primary,
                                height: 1,
                                letterSpacing: -1.5,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Text(
                                'per year',
                                style: AppTheme.bodyMedium.copyWith(
                                  color: AppTheme.textSecondary,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppTheme.spacing8),

                        // Save Badge
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                AppTheme.success,
                                AppTheme.success.withOpacity(0.8),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(100),
                            boxShadow: [
                              BoxShadow(
                                color: AppTheme.success.withOpacity(0.3),
                                blurRadius: 12,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                          child: Text(
                            'SAVE 19%',
                            style: AppTheme.labelMedium.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1,
                            ),
                          ),
                        ),
                        const SizedBox(height: AppTheme.spacing16),

                        // 7-day free trial badge
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.primary.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(100),
                            border: Border.all(
                              color: AppTheme.primary.withOpacity(0.3),
                              width: 1,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.access_time_rounded,
                                color: AppTheme.primary,
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '7-Day Free Trial',
                                style: AppTheme.bodyMedium.copyWith(
                                  color: AppTheme.primary,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppTheme.spacing32),

                  // Subscribe Buttons (Modern)
                  Consumer<SubscriptionProvider>(
                    builder: (context, subscription, _) {
                      if (subscription.isLoading) {
                        return const Center(
                          child: CircularProgressIndicator(),
                        );
                      }

                      return Column(
                        children: [
                          // Annual Button (Primary - Gradient)
                          _buildModernButton(
                            context: context,
                            label: 'Start Free Trial - Annual',
                            onPressed: () async {
                              final success = await subscription.purchaseAnnual(context);
                              if (success && context.mounted) {
                                Navigator.pop(context);
                              }
                            },
                            isPrimary: true,
                          ),
                          const SizedBox(height: AppTheme.spacing12),

                          // Monthly Button (Secondary)
                          _buildModernButton(
                            context: context,
                            label: 'Start Free Trial - Monthly',
                            onPressed: () async {
                              final success = await subscription.purchaseMonthly(context);
                              if (success && context.mounted) {
                                Navigator.pop(context);
                              }
                            },
                            isPrimary: false,
                          ),
                          const SizedBox(height: AppTheme.spacing20),

                          // Restore Purchases
                          TextButton(
                            onPressed: () => subscription.restorePurchases(context),
                            child: Text(
                              'Restore Purchases',
                              style: AppTheme.bodyMedium.copyWith(
                                color: AppTheme.textTertiary,
                                decoration: TextDecoration.underline,
                                decorationColor: AppTheme.textTertiary,
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: AppTheme.spacing24),

                  // Footer Disclaimer (Subtle)
                  Text(
                    'View-only app • No trading execution • Not financial advice',
                    style: AppTheme.labelSmall.copyWith(
                      color: AppTheme.textTertiary.withOpacity(0.6),
                      fontSize: 12,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppTheme.spacing12),

                  // Auto-renewal disclosure (Required by Apple Guidelines 3.1.2)
                  Container(
                    padding: const EdgeInsets.all(AppTheme.spacing12),
                    decoration: BoxDecoration(
                      color: AppTheme.surface.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(AppTheme.radiusMD),
                      border: Border.all(
                        color: AppTheme.glassBorder,
                        width: 1,
                      ),
                    ),
                    child: Text(
                      'Start with a 7-day free trial. Payment will be charged to your Apple ID account after the trial ends. '
                      'Subscription automatically renews unless canceled at least 24 hours before the end of the current period. '
                      'You can manage and cancel your subscriptions in your App Store account settings.',
                      style: AppTheme.bodySmall.copyWith(
                        color: AppTheme.textTertiary.withOpacity(0.7),
                        fontSize: 10,
                        height: 1.4,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: AppTheme.spacing16),

                  // Privacy Policy & Terms (Required by Apple/Google)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      TextButton(
                        onPressed: () async {
                          final uri = Uri.parse('https://mytrademate.app/privacy-policy.html');
                          if (await canLaunchUrl(uri)) {
                            await launchUrl(uri, mode: LaunchMode.externalApplication);
                          }
                        },
                        child: Text(
                          'Privacy Policy',
                          style: AppTheme.labelSmall.copyWith(
                            color: AppTheme.textTertiary,
                            fontSize: 11,
                            decoration: TextDecoration.underline,
                            decorationColor: AppTheme.textTertiary,
                          ),
                        ),
                      ),
                      Text(
                        ' • ',
                        style: AppTheme.labelSmall.copyWith(
                          color: AppTheme.textTertiary.withOpacity(0.6),
                          fontSize: 11,
                        ),
                      ),
                      TextButton(
                        onPressed: () async {
                          final uri = Uri.parse('https://mytrademate.app/terms-of-service.html');
                          if (await canLaunchUrl(uri)) {
                            await launchUrl(uri, mode: LaunchMode.externalApplication);
                          }
                        },
                        child: Text(
                          'Terms of Service',
                          style: AppTheme.labelSmall.copyWith(
                            color: AppTheme.textTertiary,
                            fontSize: 11,
                            decoration: TextDecoration.underline,
                            decorationColor: AppTheme.textTertiary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppTheme.spacing24),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Premium Feature Card (2025 Design)
  Widget _buildPremiumFeature({
    required IconData icon,
    required String title,
    required String subtitle,
    required Gradient gradient,
  }) {
    return Container(
      padding: const EdgeInsets.all(AppTheme.spacing20),
      decoration: BoxDecoration(
        gradient: AppTheme.glassGradient,
        borderRadius: BorderRadius.circular(AppTheme.radiusLG),
        border: Border.all(
          color: AppTheme.glassBorder,
          width: 1,
        ),
      ),
      child: Row(
        children: [
          // Icon with Gradient Background
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              gradient: gradient,
              borderRadius: BorderRadius.circular(AppTheme.radiusMD),
              boxShadow: [
                BoxShadow(
                  color: gradient.colors.first.withOpacity(0.3),
                  blurRadius: 12,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Icon(
              icon,
              color: Colors.white,
              size: 28,
            ),
          ),
          const SizedBox(width: AppTheme.spacing16),

          // Text Content
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTheme.bodyLarge.copyWith(
                    fontWeight: FontWeight.w700,
                    fontSize: 17,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: AppTheme.bodySmall.copyWith(
                    color: AppTheme.textSecondary,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Modern Button (Premium 2025)
  Widget _buildModernButton({
    required BuildContext context,
    required String label,
    required VoidCallback onPressed,
    required bool isPrimary,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 60,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.radiusLG),
          ),
        ),
        child: Ink(
          decoration: BoxDecoration(
            gradient: isPrimary
                ? AppTheme.primaryGradient
                : LinearGradient(
                    colors: [
                      AppTheme.surface.withOpacity(0.5),
                      AppTheme.surface.withOpacity(0.3),
                    ],
                  ),
            borderRadius: BorderRadius.circular(AppTheme.radiusLG),
            border: Border.all(
              color: isPrimary
                  ? AppTheme.primary.withOpacity(0.3)
                  : AppTheme.glassBorder,
              width: isPrimary ? 0 : 1,
            ),
            boxShadow: isPrimary
                ? [
                    BoxShadow(
                      color: AppTheme.primary.withOpacity(0.4),
                      blurRadius: 20,
                      spreadRadius: 2,
                    ),
                  ]
                : null,
          ),
          child: Center(
            child: Text(
              label,
              style: AppTheme.bodyLarge.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 17,
                letterSpacing: 0.3,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

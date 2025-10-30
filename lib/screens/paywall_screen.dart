import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/subscription_provider.dart';
import '../theme/app_theme.dart';

/// Paywall screen for upgrading to Pro subscription
/// Shows pricing, features, and purchase buttons
class PaywallScreen extends StatelessWidget {
  const PaywallScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: AppTheme.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppTheme.spacing24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header Icon
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  gradient: AppTheme.primaryGradient,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.rocket_launch,
                  size: 40,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: AppTheme.spacing24),

              // Title
              Text(
                'Unlock Faster AI Signals',
                style: AppTheme.headingLarge.copyWith(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppTheme.spacing12),

              // Subtitle
              Text(
                'Get short-term predictions and price alerts',
                style: AppTheme.bodyLarge.copyWith(
                  color: AppTheme.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppTheme.spacing32),

              // Feature List
              _buildFeatureCard(
                icon: Icons.speed,
                title: 'Short-term predictions (5m–4h)',
                description: 'AI signals on 5m, 15m, 1h, and 4h timeframes',
              ),
              const SizedBox(height: AppTheme.spacing12),
              _buildFeatureCard(
                icon: Icons.notifications_active,
                title: 'Price alerts & faster refresh',
                description: 'Get notified of market moves instantly',
              ),
              const SizedBox(height: AppTheme.spacing12),
              _buildFeatureCard(
                icon: Icons.check_circle,
                title: 'Portfolio tracking',
                description: 'Read-only access to your holdings',
                isHighlighted: false,
              ),
              const SizedBox(height: AppTheme.spacing32),

              // Pricing Card
              Container(
                padding: const EdgeInsets.all(AppTheme.spacing20),
                decoration: BoxDecoration(
                  gradient: AppTheme.glassGradient,
                  borderRadius: BorderRadius.circular(AppTheme.radiusLG),
                  border: Border.all(
                    color: AppTheme.primary.withOpacity(0.3),
                    width: 1,
                  ),
                ),
                child: Column(
                  children: [
                    Text(
                      '€5.99/month',
                      style: AppTheme.headingLarge.copyWith(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: AppTheme.spacing4),
                    Text(
                      'or',
                      style: AppTheme.bodySmall.copyWith(
                        color: AppTheme.textTertiary,
                      ),
                    ),
                    const SizedBox(height: AppTheme.spacing4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '€57.50/year',
                          style: AppTheme.headingLarge.copyWith(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.primary,
                          ),
                        ),
                        const SizedBox(width: AppTheme.spacing8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppTheme.spacing8,
                            vertical: AppTheme.spacing4,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.success.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(AppTheme.radiusSM),
                          ),
                          child: Text(
                            'Save 20%',
                            style: AppTheme.labelSmall.copyWith(
                              color: AppTheme.success,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppTheme.spacing32),

              // Subscribe Buttons
              Consumer<SubscriptionProvider>(
                builder: (context, subscription, _) {
                  if (subscription.isLoading) {
                    return const Center(
                      child: CircularProgressIndicator(),
                    );
                  }

                  return Column(
                    children: [
                      // Annual Button (Highlighted)
                      _buildSubscribeButton(
                        context: context,
                        label: 'Subscribe Annual (Save 30%)',
                        icon: Icons.workspace_premium,
                        onPressed: () async {
                          final success = await subscription.purchaseAnnual(context);
                          if (success && context.mounted) {
                            Navigator.pop(context);
                          }
                        },
                        isPrimary: true,
                      ),
                      const SizedBox(height: AppTheme.spacing12),

                      // Monthly Button
                      _buildSubscribeButton(
                        context: context,
                        label: 'Subscribe Monthly',
                        icon: Icons.calendar_month,
                        onPressed: () async {
                          final success = await subscription.purchaseMonthly(context);
                          if (success && context.mounted) {
                            Navigator.pop(context);
                          }
                        },
                        isPrimary: false,
                      ),
                      const SizedBox(height: AppTheme.spacing16),

                      // Restore Purchases
                      TextButton(
                        onPressed: () => subscription.restorePurchases(context),
                        child: Text(
                          'Restore Purchases',
                          style: AppTheme.bodyMedium.copyWith(
                            color: AppTheme.textSecondary,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: AppTheme.spacing24),

              // Footer Disclaimer
              Container(
                padding: const EdgeInsets.all(AppTheme.spacing12),
                decoration: BoxDecoration(
                  color: AppTheme.surface.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(AppTheme.radiusMD),
                ),
                child: Text(
                  'View-only app. No trading execution. Not financial advice.',
                  style: AppTheme.labelSmall.copyWith(
                    color: AppTheme.textTertiary,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFeatureCard({
    required IconData icon,
    required String title,
    required String description,
    bool isHighlighted = true,
  }) {
    return Container(
      padding: const EdgeInsets.all(AppTheme.spacing16),
      decoration: BoxDecoration(
        gradient: isHighlighted ? AppTheme.glassGradient : null,
        color: isHighlighted ? null : AppTheme.surface.withOpacity(0.3),
        borderRadius: BorderRadius.circular(AppTheme.radiusMD),
        border: Border.all(
          color: isHighlighted
              ? AppTheme.primary.withOpacity(0.2)
              : AppTheme.glassBorder,
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              gradient: isHighlighted
                  ? AppTheme.primaryGradient
                  : LinearGradient(
                      colors: [
                        AppTheme.textSecondary.withOpacity(0.3),
                        AppTheme.textSecondary.withOpacity(0.2),
                      ],
                    ),
              borderRadius: BorderRadius.circular(AppTheme.radiusSM),
            ),
            child: Icon(
              icon,
              color: Colors.white,
              size: 20,
            ),
          ),
          const SizedBox(width: AppTheme.spacing12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTheme.bodyLarge.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
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

  Widget _buildSubscribeButton({
    required BuildContext context,
    required String label,
    required IconData icon,
    required VoidCallback onPressed,
    required bool isPrimary,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, color: Colors.white),
        label: Text(
          label,
          style: AppTheme.bodyLarge.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: isPrimary ? null : AppTheme.surface,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.radiusMD),
          ),
          elevation: isPrimary ? 4 : 0,
          shadowColor: isPrimary ? AppTheme.primary.withOpacity(0.5) : null,
        ).copyWith(
          backgroundColor: isPrimary
              ? WidgetStateProperty.all(AppTheme.primary)
              : WidgetStateProperty.all(AppTheme.surface),
        ),
      ),
    );
  }
}

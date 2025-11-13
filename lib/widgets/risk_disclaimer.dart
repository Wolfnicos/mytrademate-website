import 'package:flutter/material.dart';
// import '../design_system/app_colors.dart'; // Unused - commented out

/// A simple, reusable widget for risk disclaimers.
class RiskDisclaimer extends StatelessWidget {
  const RiskDisclaimer({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final Color bg = colors.surfaceVariant.withOpacity(0.7);
    final Color fg = colors.onSurface.withOpacity(0.78);
    final Color apiBg = colors.primary.withOpacity(0.12);
    final Color apiFg = colors.onSurface.withOpacity(0.82);

    return Column(
      children: [
        // API Integration Disclaimer (NEW - for Google Play compliance)
        Container(
          padding: const EdgeInsets.all(14.0),
          decoration: BoxDecoration(
            color: apiBg,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: colors.primary.withOpacity(0.3),
              width: 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.info_outline,
                color: colors.primary,
                size: 18,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Binance API Integration - Educational AI Insights Only\n'
                  'MyTradeMate connects to your Binance account via API. All orders are executed on Binance.com. We do not hold funds or provide financial advice.',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: apiFg,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Risk Disclaimer (original)
        Container(
          padding: const EdgeInsets.all(12.0),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            'Past performance is not indicative of future results. All trading involves risk.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: fg),
          ),
        ),
      ],
    );
  }
}


import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../ml/ensemble_predictor.dart';

/// Premium Neural Engine Card - 2025 Design
///
/// Features:
/// - Animated neural network visualization
/// - Data flow particles
/// - Real-time confidence gauges (dynamic)
/// - Holographic glow effects
/// - Model accuracy showcase
class NeuralEngineCard extends StatefulWidget {
  const NeuralEngineCard({super.key});

  @override
  State<NeuralEngineCard> createState() => _NeuralEngineCardState();
}

class _NeuralEngineCardState extends State<NeuralEngineCard>
    with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late AnimationController _flowController;
  late AnimationController _glowController;
  late Animation<double> _pulseAnimation;
  late Animation<double> _flowAnimation;
  late Animation<double> _glowAnimation;

  bool _isLoaded = false;
  int _modelCount = 51; // Total models available in assets/ml/

  @override
  void initState() {
    super.initState();

    // Pulse animation for the brain icon
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Flow animation for data particles
    _flowController = AnimationController(
      duration: const Duration(milliseconds: 3000),
      vsync: this,
    )..repeat();

    _flowAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(_flowController);

    // Glow animation for holographic effect
    _glowController = AnimationController(
      duration: const Duration(milliseconds: 4000),
      vsync: this,
    )..repeat(reverse: true);

    _glowAnimation = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(parent: _glowController, curve: Curves.easeInOut),
    );

    _checkModelsLoaded();
  }

  void _checkModelsLoaded() {
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) {
        final isLoaded = globalEnsemblePredictor.isLoaded;
        if (isLoaded != _isLoaded) {
          setState(() {
            _isLoaded = isLoaded;
            // _modelCount stays at 51 (total available models)
          });
        }
        if (!isLoaded) {
          _checkModelsLoaded();
        }
      }
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _flowController.dispose();
    _glowController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isActive = _isLoaded;

    return AnimatedBuilder(
      animation: Listenable.merge([_pulseAnimation, _flowAnimation, _glowAnimation]),
      builder: (context, child) {
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTheme.radiusXL),
            gradient: LinearGradient(
              colors: isActive
                  ? [
                      const Color(0xFF0F172A),
                      const Color(0xFF1E293B),
                    ]
                  : [
                      AppTheme.surface,
                      AppTheme.surfaceVariant,
                    ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            border: Border.all(
              color: isActive
                  ? Color.lerp(
                      AppTheme.primary,
                      AppTheme.secondary,
                      _glowAnimation.value,
                    )!.withOpacity(0.5)
                  : AppTheme.glassBorder,
              width: isActive ? 2 : 1,
            ),
            boxShadow: isActive
                ? [
                    BoxShadow(
                      color: AppTheme.primary.withOpacity(0.2 * _glowAnimation.value),
                      blurRadius: 30,
                      spreadRadius: 5,
                    ),
                    BoxShadow(
                      color: AppTheme.secondary.withOpacity(0.15 * _glowAnimation.value),
                      blurRadius: 40,
                      spreadRadius: 10,
                    ),
                  ]
                : AppTheme.glassShadow,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppTheme.radiusXL),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Stack(
                children: [
                  // Neural network background pattern
                  if (isActive)
                    Positioned.fill(
                      child: CustomPaint(
                        painter: NeuralNetworkPainter(
                          animation: _flowAnimation.value,
                          glowIntensity: _glowAnimation.value,
                        ),
                      ),
                    ),

                  // Main content
                  Padding(
                    padding: const EdgeInsets.all(AppTheme.spacing20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildHeader(isActive),
                        const SizedBox(height: AppTheme.spacing20),
                        if (isActive) ...[
                          _buildStatsRow(),
                          const SizedBox(height: AppTheme.spacing16),
                          _buildProcessingIndicator(),
                        ] else ...[
                          _buildLoadingState(),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeader(bool isActive) {
    return Row(
      children: [
        // Animated brain icon with holographic glow
        Transform.scale(
          scale: isActive ? _pulseAnimation.value : 1.0,
          child: Container(
            padding: const EdgeInsets.all(AppTheme.spacing16),
            decoration: BoxDecoration(
              gradient: isActive
                  ? LinearGradient(
                      colors: [
                        Color.lerp(AppTheme.primary, AppTheme.secondary, _glowAnimation.value)!,
                        Color.lerp(AppTheme.secondary, AppTheme.primary, _glowAnimation.value)!,
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    )
                  : LinearGradient(
                      colors: [
                        AppTheme.textTertiary.withOpacity(0.5),
                        AppTheme.textTertiary.withOpacity(0.3),
                      ],
                    ),
              borderRadius: BorderRadius.circular(AppTheme.radiusLG),
              boxShadow: isActive
                  ? [
                      BoxShadow(
                        color: AppTheme.primary.withOpacity(0.5 * _glowAnimation.value),
                        blurRadius: 20,
                        spreadRadius: 2,
                      ),
                    ]
                  : null,
            ),
            child: const Icon(
              Icons.psychology_alt,
              color: Colors.white,
              size: 28,
            ),
          ),
        ),
        const SizedBox(width: AppTheme.spacing16),

        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  ShaderMask(
                    shaderCallback: (bounds) => LinearGradient(
                      colors: isActive
                          ? [Colors.white, const Color(0xFFE0E7FF)]
                          : [AppTheme.textSecondary, AppTheme.textTertiary],
                    ).createShader(bounds),
                    child: Text(
                      'Neural Engine',
                      style: AppTheme.headingMedium.copyWith(
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppTheme.spacing12),
                  _buildStatusBadge(isActive),
                ],
              ),
              const SizedBox(height: AppTheme.spacing4),
              Text(
                isActive
                    ? 'Deep Learning • $_modelCount Models • 76 Indicators'
                    : 'Initializing neural pathways...',
                style: AppTheme.bodySmall.copyWith(
                  color: AppTheme.textTertiary,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStatusBadge(bool isActive) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.symmetric(
        horizontal: _spacing10,
        vertical: AppTheme.spacing4,
      ),
      decoration: BoxDecoration(
        gradient: isActive
            ? LinearGradient(
                colors: [
                  AppTheme.success.withOpacity(0.3),
                  AppTheme.success.withOpacity(0.1),
                ],
              )
            : null,
        color: isActive ? null : AppTheme.textTertiary.withOpacity(0.2),
        borderRadius: BorderRadius.circular(AppTheme.radiusFull),
        border: Border.all(
          color: isActive
              ? AppTheme.success.withOpacity(0.5)
              : AppTheme.textTertiary.withOpacity(0.3),
          width: 1,
        ),
        boxShadow: isActive
            ? [
                BoxShadow(
                  color: AppTheme.success.withOpacity(0.3),
                  blurRadius: 8,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: isActive ? AppTheme.success : AppTheme.textTertiary,
              shape: BoxShape.circle,
              boxShadow: isActive
                  ? [
                      BoxShadow(
                        color: AppTheme.success,
                        blurRadius: 6,
                        spreadRadius: 2,
                      ),
                    ]
                  : null,
            ),
          ),
          const SizedBox(width: _spacing6),
          Text(
            isActive ? 'ONLINE' : 'LOADING',
            style: AppTheme.labelSmall.copyWith(
              color: isActive ? AppTheme.success : AppTheme.textTertiary,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsRow() {
    return Row(
      children: [
        Expanded(child: _buildStatCard(
          icon: Icons.memory,
          value: '$_modelCount',
          label: 'AI Models',
          color: AppTheme.primary,
        )),
        const SizedBox(width: AppTheme.spacing12),
        Expanded(child: _buildStatCard(
          icon: Icons.insights,
          value: '76',
          label: 'Indicators',
          color: AppTheme.secondary,
        )),
        const SizedBox(width: AppTheme.spacing12),
        Expanded(child: _buildStatCard(
          icon: Icons.schedule,
          value: '5',
          label: 'Timeframes',
          color: AppTheme.success,
        )),
      ],
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required String value,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(AppTheme.spacing12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            color.withOpacity(0.15),
            color.withOpacity(0.05),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(AppTheme.radiusMD),
        border: Border.all(
          color: color.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: AppTheme.spacing8),
          Text(
            value,
            style: AppTheme.headingLarge.copyWith(
              color: color,
              fontWeight: FontWeight.w800,
              fontSize: 22,
            ),
          ),
          const SizedBox(height: _spacing2),
          Text(
            label,
            style: AppTheme.bodySmall.copyWith(
              color: AppTheme.textTertiary,
              fontSize: 10,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildProcessingIndicator() {
    return AnimatedBuilder(
      animation: _flowAnimation,
      builder: (context, child) {
        return Row(
          children: [
            // Animated dots
            SizedBox(
              width: 40,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: List.generate(3, (index) {
                  final delay = index * 0.3;
                  final animValue = ((_flowAnimation.value + delay) % 1.0);
                  final scale = 0.5 + 0.5 * math.sin(animValue * math.pi);
                  return Transform.scale(
                    scale: scale,
                    child: Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withOpacity(0.5 + 0.5 * scale),
                        shape: BoxShape.circle,
                      ),
                    ),
                  );
                }),
              ),
            ),
            const SizedBox(width: AppTheme.spacing12),
            Expanded(
              child: Text(
                'Analyzing market patterns in real-time',
                style: AppTheme.bodySmall.copyWith(
                  color: AppTheme.textTertiary,
                  fontSize: 11,
                ),
              ),
            ),
            // Processing speed indicator
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppTheme.spacing8,
                vertical: AppTheme.spacing4,
              ),
              decoration: BoxDecoration(
                color: AppTheme.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(AppTheme.radiusSM),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.speed,
                    color: AppTheme.primary,
                    size: 12,
                  ),
                  const SizedBox(width: AppTheme.spacing4),
                  Text(
                    '< 50ms',
                    style: AppTheme.monoMedium.copyWith(
                      color: AppTheme.primary,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildLoadingState() {
    return Column(
      children: [
        const SizedBox(height: AppTheme.spacing20),
        // Loading ring
        SizedBox(
          width: 80,
          height: 80,
          child: Stack(
            children: [
              // Outer ring
              Positioned.fill(
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    AppTheme.primary.withOpacity(0.3),
                  ),
                ),
              ),
              // Inner ring
              Center(
                child: SizedBox(
                  width: 60,
                  height: 60,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      AppTheme.secondary.withOpacity(0.5),
                    ),
                  ),
                ),
              ),
              // Center icon
              Center(
                child: Icon(
                  Icons.psychology,
                  color: AppTheme.primary.withOpacity(0.7),
                  size: 28,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppTheme.spacing20),
        Text(
          'Loading AI Models...',
          style: AppTheme.bodyMedium.copyWith(
            color: AppTheme.textSecondary,
          ),
        ),
        const SizedBox(height: AppTheme.spacing8),
        Text(
          'Initializing neural pathways',
          style: AppTheme.bodySmall.copyWith(
            color: AppTheme.textTertiary,
          ),
        ),
        const SizedBox(height: AppTheme.spacing20),
      ],
    );
  }
}

/// Custom painter for neural network background
class NeuralNetworkPainter extends CustomPainter {
  final double animation;
  final double glowIntensity;

  NeuralNetworkPainter({
    required this.animation,
    required this.glowIntensity,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    // Generate node positions (cached pattern)
    final nodes = <Offset>[];
    final random = math.Random(42); // Fixed seed for consistent pattern
    for (int i = 0; i < 12; i++) {
      nodes.add(Offset(
        random.nextDouble() * size.width,
        random.nextDouble() * size.height,
      ));
    }

    // Draw connections
    for (int i = 0; i < nodes.length; i++) {
      for (int j = i + 1; j < nodes.length; j++) {
        final distance = (nodes[i] - nodes[j]).distance;
        if (distance < size.width * 0.4) {
          final opacity = (1 - distance / (size.width * 0.4)) * 0.15 * glowIntensity;
          paint.color = AppTheme.primary.withOpacity(opacity);
          canvas.drawLine(nodes[i], nodes[j], paint);
        }
      }
    }

    // Draw animated data particles along connections
    final particlePaint = Paint()
      ..style = PaintingStyle.fill;

    for (int i = 0; i < nodes.length - 1; i++) {
      final start = nodes[i];
      final end = nodes[i + 1];
      final t = ((animation + i * 0.1) % 1.0);
      final particlePos = Offset.lerp(start, end, t)!;

      particlePaint.color = Color.lerp(
        AppTheme.primary,
        AppTheme.secondary,
        t,
      )!.withOpacity(0.6 * glowIntensity);

      canvas.drawCircle(particlePos, 2, particlePaint);
    }

    // Draw nodes
    final nodePaint = Paint()
      ..style = PaintingStyle.fill;

    for (int i = 0; i < nodes.length; i++) {
      final pulseScale = 1 + 0.3 * math.sin((animation * 2 * math.pi) + i);
      nodePaint.color = AppTheme.primary.withOpacity(0.3 * glowIntensity);
      canvas.drawCircle(nodes[i], 3 * pulseScale, nodePaint);
    }
  }

  @override
  bool shouldRepaint(covariant NeuralNetworkPainter oldDelegate) {
    return oldDelegate.animation != animation ||
           oldDelegate.glowIntensity != glowIntensity;
  }
}

// Additional spacing constants (not in AppTheme)
const double _spacing2 = 2.0;
const double _spacing6 = 6.0;
const double _spacing10 = 10.0;

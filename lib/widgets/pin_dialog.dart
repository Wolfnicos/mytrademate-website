import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';

/// Dialog for entering PIN code (4-6 digits)
/// Returns the entered PIN as String if confirmed, null if cancelled
class PINDialog extends StatefulWidget {
  final String title;
  final String description;
  final bool isSetup; // true for setup (requires confirmation), false for verification

  const PINDialog({
    super.key,
    required this.title,
    required this.description,
    this.isSetup = false,
  });

  @override
  State<PINDialog> createState() => _PINDialogState();

  /// Show PIN setup dialog (requires confirmation)
  static Future<String?> showSetup(BuildContext context) {
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const PINDialog(
        title: 'Set PIN Code',
        description: 'Enter a 4-6 digit PIN code',
        isSetup: true,
      ),
    );
  }

  /// Show PIN verification dialog
  static Future<String?> showVerify(BuildContext context) {
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const PINDialog(
        title: 'Enter PIN',
        description: 'Enter your PIN to continue',
        isSetup: false,
      ),
    );
  }
}

class _PINDialogState extends State<PINDialog> {
  final TextEditingController _pinController = TextEditingController();
  final TextEditingController _confirmController = TextEditingController();
  final FocusNode _pinFocus = FocusNode();
  final FocusNode _confirmFocus = FocusNode();

  bool _showConfirmField = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    // Auto-focus on PIN field when dialog opens
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pinFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _pinController.dispose();
    _confirmController.dispose();
    _pinFocus.dispose();
    _confirmFocus.dispose();
    super.dispose();
  }

  void _onPinEntered() {
    final pin = _pinController.text;

    // Validate PIN length
    if (pin.length < 4 || pin.length > 6) {
      setState(() => _errorMessage = 'PIN must be 4-6 digits');
      return;
    }

    // Validate PIN contains only digits
    if (!RegExp(r'^\d+$').hasMatch(pin)) {
      setState(() => _errorMessage = 'PIN must contain only numbers');
      return;
    }

    if (widget.isSetup && !_showConfirmField) {
      // Show confirmation field
      setState(() {
        _showConfirmField = true;
        _errorMessage = null;
      });
      _confirmFocus.requestFocus();
    } else if (widget.isSetup && _showConfirmField) {
      // Verify confirmation matches
      if (pin != _confirmController.text) {
        setState(() => _errorMessage = 'PINs do not match');
        return;
      }
      Navigator.of(context).pop(pin);
    } else {
      // Verification mode - just return the PIN
      Navigator.of(context).pop(pin);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AlertDialog(
      backgroundColor: isDark ? AppTheme.surface : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusLG),
      ),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(AppTheme.spacing8),
            decoration: BoxDecoration(
              gradient: AppTheme.primaryGradient,
              borderRadius: BorderRadius.circular(AppTheme.radiusSM),
            ),
            child: const Icon(Icons.lock, color: Colors.white, size: 20),
          ),
          const SizedBox(width: AppTheme.spacing12),
          Expanded(
            child: Text(
              widget.title,
              style: AppTheme.headingLarge.copyWith(
                color: AppTheme.getTextPrimary(context),
              ),
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.description,
            style: AppTheme.bodyMedium.copyWith(
              color: AppTheme.getTextSecondary(context),
            ),
          ),
          const SizedBox(height: AppTheme.spacing20),

          // PIN input field
          TextField(
            controller: _pinController,
            focusNode: _pinFocus,
            obscureText: true,
            keyboardType: TextInputType.number,
            maxLength: 6,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: AppTheme.headingLarge.copyWith(
              letterSpacing: 8,
              color: AppTheme.getTextPrimary(context),
            ),
            textAlign: TextAlign.center,
            decoration: InputDecoration(
              hintText: '••••',
              counterText: '',
              filled: true,
              fillColor: isDark ? AppTheme.glassWhite : Colors.grey[100],
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppTheme.radiusMD),
                borderSide: BorderSide(color: AppTheme.glassBorder),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppTheme.radiusMD),
                borderSide: BorderSide(
                  color: isDark ? AppTheme.glassBorder : Colors.grey[300]!,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppTheme.radiusMD),
                borderSide: const BorderSide(color: AppTheme.primary, width: 2),
              ),
              errorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppTheme.radiusMD),
                borderSide: const BorderSide(color: AppTheme.error, width: 2),
              ),
            ),
            onSubmitted: (_) => _onPinEntered(),
          ),

          // Confirmation field (only shown in setup mode)
          if (_showConfirmField) ...[
            const SizedBox(height: AppTheme.spacing16),
            Text(
              'Confirm PIN',
              style: AppTheme.bodyMedium.copyWith(
                color: AppTheme.getTextSecondary(context),
              ),
            ),
            const SizedBox(height: AppTheme.spacing8),
            TextField(
              controller: _confirmController,
              focusNode: _confirmFocus,
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: 6,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: AppTheme.headingLarge.copyWith(
                letterSpacing: 8,
                color: AppTheme.getTextPrimary(context),
              ),
              textAlign: TextAlign.center,
              decoration: InputDecoration(
                hintText: '••••',
                counterText: '',
                filled: true,
                fillColor: isDark ? AppTheme.glassWhite : Colors.grey[100],
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppTheme.radiusMD),
                  borderSide: BorderSide(color: AppTheme.glassBorder),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppTheme.radiusMD),
                  borderSide: BorderSide(
                    color: isDark ? AppTheme.glassBorder : Colors.grey[300]!,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppTheme.radiusMD),
                  borderSide: const BorderSide(color: AppTheme.primary, width: 2),
                ),
              ),
              onSubmitted: (_) => _onPinEntered(),
            ),
          ],

          // Error message
          if (_errorMessage != null) ...[
            const SizedBox(height: AppTheme.spacing12),
            Container(
              padding: const EdgeInsets.all(AppTheme.spacing12),
              decoration: BoxDecoration(
                color: AppTheme.error.withOpacity(0.1),
                borderRadius: BorderRadius.circular(AppTheme.radiusSM),
                border: Border.all(color: AppTheme.error.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, color: AppTheme.error, size: 20),
                  const SizedBox(width: AppTheme.spacing8),
                  Expanded(
                    child: Text(
                      _errorMessage!,
                      style: AppTheme.bodySmall.copyWith(color: AppTheme.error),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(
            'Cancel',
            style: TextStyle(color: AppTheme.getTextSecondary(context)),
          ),
        ),
        ElevatedButton(
          onPressed: _onPinEntered,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.primary,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppTheme.radiusMD),
            ),
          ),
          child: Text(_showConfirmField ? 'Confirm' : 'Continue'),
        ),
      ],
    );
  }
}

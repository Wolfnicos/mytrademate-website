import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import '../services/app_settings_service.dart';

/// Manages subscription state via RevenueCat
/// Entitlement: "MyTradeMate Pro"
/// Offering: "default"
/// Products: monthly, yearly
///
/// FREE TRIAL: First 48 hours after app install grants full Pro access
class SubscriptionProvider extends ChangeNotifier {
  bool _isProUser = false;
  bool _isLoading = false;
  String? _errorMessage;

  /// Returns true if user has Pro subscription OR is in 48h free trial
  bool get isProUser {
    // Check if in trial period (48h from first launch)
    final isInTrial = AppSettingsService().isInTrial;
    if (isInTrial) {
      // Log only once per minute to avoid spam
      return true;
    }

    // Otherwise check RevenueCat subscription
    return _isProUser;
  }

  /// Returns true only if user has paid Pro subscription (excludes trial)
  bool get hasProSubscription => _isProUser;

  /// Returns true if user is in trial period
  bool get isInTrial => AppSettingsService().isInTrial;

  /// Get remaining trial hours (null if not in trial)
  int? get trialHoursRemaining => AppSettingsService().trialHoursRemaining;

  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  /// Initialize RevenueCat SDK
  /// Call this once in main.dart
  static Future<void> initializeRevenueCat() async {
    try {
      // ✅ PRODUCTION API key configured
      const appleApiKey = 'appl_vVgBtEaVpppbqhilxwiMvBrJZEX'; // Production Apple key from RevenueCat
      const googleApiKey = 'goog_YOUR_GOOGLE_KEY'; // Android - add when launching on Google Play

      PurchasesConfiguration configuration;
      if (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS) {
        configuration = PurchasesConfiguration(appleApiKey);
      } else if (defaultTargetPlatform == TargetPlatform.android) {
        configuration = PurchasesConfiguration(googleApiKey);
      } else {
        debugPrint('⚠️ RevenueCat: Unsupported platform');
        return;
      }

      await Purchases.configure(configuration);
      debugPrint('✅ RevenueCat SDK initialized');
    } catch (e) {
      debugPrint('❌ RevenueCat initialization failed: $e');
    }
  }

  /// Check current subscription status
  /// Call this on app launch and after purchase
  Future<void> checkSubscriptionStatus() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final customerInfo = await Purchases.getCustomerInfo();

      // Check if user has "MyTradeMate Pro" entitlement
      final hasProEntitlement = customerInfo.entitlements.all['MyTradeMate Pro']?.isActive ?? false;

      _isProUser = hasProEntitlement;
      debugPrint('🔐 Subscription status: ${_isProUser ? "PRO" : "FREE"}');
    } catch (e) {
      debugPrint('❌ Error checking subscription: $e');
      _errorMessage = e.toString();
      _isProUser = false; // Default to free on error
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Purchase monthly subscription (€6.99/month)
  Future<bool> purchaseMonthly(BuildContext context) async {
    return await _purchasePackage(context, 'monthly');
  }

  /// Purchase annual subscription (€67.99/year, save 19%)
  Future<bool> purchaseAnnual(BuildContext context) async {
    return await _purchasePackage(context, 'annual');
  }

  /// Internal: Purchase a specific package
  Future<bool> _purchasePackage(BuildContext context, String packageType) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      // Fetch current offering
      final offerings = await Purchases.getOfferings();
      final offering = offerings.current;

      if (offering == null) {
        throw Exception('No offering found. Check RevenueCat dashboard.');
      }

      // Select package
      Package? package;
      if (packageType == 'monthly') {
        package = offering.monthly;
      } else if (packageType == 'annual') {
        package = offering.annual;
      }

      if (package == null) {
        throw Exception('Package "$packageType" not found in offering.');
      }

      // Make purchase
      final purchaseResult = await Purchases.purchasePackage(package);

      // Check if purchase was successful (SDK 9.x returns PurchaseResult)
      final hasProEntitlement = purchaseResult.customerInfo.entitlements.all['MyTradeMate Pro']?.isActive ?? false;
      _isProUser = hasProEntitlement;

      if (_isProUser) {
        debugPrint('✅ Purchase successful! User is now PRO');
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('🎉 Welcome to Pro! Enjoy faster AI predictions.'),
              backgroundColor: Colors.green,
            ),
          );
        }
        return true;
      } else {
        throw Exception('Purchase completed but Pro entitlement not active.');
      }
    } on PurchasesErrorCode catch (error) {
      debugPrint('❌ Purchase error: ${error.name}');

      // Handle user cancellation gracefully
      if (error == PurchasesErrorCode.purchaseCancelledError) {
        debugPrint('ℹ️ User cancelled purchase');
        _errorMessage = null; // Don't show error for cancellation
      } else {
        _errorMessage = _getUserFriendlyError(error);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(_errorMessage ?? 'Purchase failed'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
      return false;
    } catch (e) {
      debugPrint('❌ Unexpected purchase error: $e');
      _errorMessage = e.toString();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Restore previous purchases
  Future<bool> restorePurchases(BuildContext context) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final customerInfo = await Purchases.restorePurchases();

      final hasProEntitlement = customerInfo.entitlements.all['MyTradeMate Pro']?.isActive ?? false;
      _isProUser = hasProEntitlement;

      if (_isProUser) {
        debugPrint('✅ Purchases restored! User is PRO');
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Purchases restored successfully!'),
              backgroundColor: Colors.green,
            ),
          );
        }
        return true;
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('ℹ️ No active subscriptions found'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return false;
      }
    } catch (e) {
      debugPrint('❌ Restore error: $e');
      _errorMessage = e.toString();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Restore failed: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Convert technical error codes to user-friendly messages
  String _getUserFriendlyError(PurchasesErrorCode error) {
    switch (error) {
      case PurchasesErrorCode.purchaseNotAllowedError:
        return 'Purchases are not allowed on this device';
      case PurchasesErrorCode.purchaseInvalidError:
        return 'Purchase is invalid';
      case PurchasesErrorCode.networkError:
        return 'Network error. Please check your connection.';
      case PurchasesErrorCode.storeProblemError:
        return 'Problem with the app store. Try again later.';
      default:
        return 'Purchase failed. Please try again.';
    }
  }
}

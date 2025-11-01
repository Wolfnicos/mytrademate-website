import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';

/// Authentication service supporting Email/Password and Biometric (Face ID/Touch ID).
/// This is a simplified implementation - in production, you'd integrate with a real backend.
class AuthService extends ChangeNotifier {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  static const String _kIsAuthenticatedKey = 'is_authenticated';
  static const String _kEmailKey = 'user_email';
  static const String _kPasswordHashKey = 'user_password_hash';
  static const String _kBiometricsEnabledKey = 'biometrics_enabled';
  static const String _kPinHashKey = 'pin_hash';

  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  final LocalAuthentication _localAuth = LocalAuthentication();

  bool _isAuthenticated = false;
  String? _userEmail;
  bool _biometricsEnabled = false;
  bool _loaded = false;

  bool get isAuthenticated => _isAuthenticated;
  String? get userEmail => _userEmail;
  bool get biometricsEnabled => _biometricsEnabled;

  /// Load authentication state from secure storage
  Future<void> load() async {
    if (_loaded) return;
    try {
      final isAuthStr = await _secureStorage.read(key: _kIsAuthenticatedKey);
      _isAuthenticated = isAuthStr == 'true';
      _userEmail = await _secureStorage.read(key: _kEmailKey);
      final bioStr = await _secureStorage.read(key: _kBiometricsEnabledKey);
      _biometricsEnabled = bioStr == 'true';
      _loaded = true;
      notifyListeners();
    } catch (e) {
      debugPrint('AuthService: Error loading auth state: $e');
      _loaded = true;
    }
  }

  /// Check if device supports biometric authentication AND has biometrics enrolled
  Future<bool> canUseBiometrics() async {
    try {
      final canCheck = await _localAuth.canCheckBiometrics;
      final isDeviceSupported = await _localAuth.isDeviceSupported();

      if (!canCheck || !isDeviceSupported) {
        return false;
      }

      // IMPORTANT: Also check if any biometrics are actually enrolled
      final availableBiometrics = await _localAuth.getAvailableBiometrics();
      final hasEnrolledBiometrics = availableBiometrics.isNotEmpty;

      debugPrint('AuthService: canCheck=$canCheck, isDeviceSupported=$isDeviceSupported, '
          'availableBiometrics=$availableBiometrics, hasEnrolled=$hasEnrolledBiometrics');

      return hasEnrolledBiometrics;
    } catch (e) {
      debugPrint('AuthService: Error checking biometrics: $e');
      return false;
    }
  }

  /// Get list of available biometric types (face, fingerprint, etc.)
  Future<List<BiometricType>> getAvailableBiometrics() async {
    try {
      return await _localAuth.getAvailableBiometrics();
    } catch (e) {
      debugPrint('AuthService: Error getting available biometrics: $e');
      return [];
    }
  }

  /// Register new user with email and password
  Future<bool> register(String email, String password) async {
    try {
      // Hash password before storing (in production, send to backend)
      final passwordHash = _hashPassword(password);

      await _secureStorage.write(key: _kEmailKey, value: email);
      await _secureStorage.write(key: _kPasswordHashKey, value: passwordHash);
      await _secureStorage.write(key: _kIsAuthenticatedKey, value: 'true');

      _userEmail = email;
      _isAuthenticated = true;
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('AuthService: Error registering user: $e');
      return false;
    }
  }

  /// Sign in with email and password
  Future<bool> signInWithEmailPassword(String email, String password) async {
    try {
      final storedEmail = await _secureStorage.read(key: _kEmailKey);
      final storedPasswordHash = await _secureStorage.read(key: _kPasswordHashKey);

      // If no account exists yet, automatically register this email/password
      if (storedEmail == null || storedPasswordHash == null) {
        debugPrint('AuthService: No account found, auto-registering');
        return await register(email, password);
      }

      if (storedEmail != email) {
        debugPrint('AuthService: Email mismatch');
        return false;
      }

      final passwordHash = _hashPassword(password);
      if (passwordHash != storedPasswordHash) {
        debugPrint('AuthService: Invalid password');
        return false;
      }

      await _secureStorage.write(key: _kIsAuthenticatedKey, value: 'true');
      _userEmail = email;
      _isAuthenticated = true;
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('AuthService: Error signing in: $e');
      return false;
    }
  }

  /// Quick access without account (guest mode)
  Future<void> signInAsGuest() async {
    try {
      await _secureStorage.write(key: _kIsAuthenticatedKey, value: 'true');
      _userEmail = 'guest';
      _isAuthenticated = true;
      notifyListeners();
    } catch (e) {
      debugPrint('AuthService: Error signing in as guest: $e');
    }
  }

  /// Authenticate with biometrics (Face ID / Touch ID)
  Future<bool> authenticateWithBiometrics() async {
    try {
      final canUseBio = await canUseBiometrics();
      if (!canUseBio) {
        debugPrint('AuthService: Biometrics not available');
        return false;
      }

      // Check if user has an account registered
      final storedEmail = await _secureStorage.read(key: _kEmailKey);
      if (storedEmail == null) {
        debugPrint('AuthService: No account registered');
        return false;
      }

      final didAuthenticate = await _localAuth.authenticate(
        localizedReason: 'Authenticate to access your crypto portfolio',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: true,
        ),
      );

      if (didAuthenticate) {
        await _secureStorage.write(key: _kIsAuthenticatedKey, value: 'true');
        _userEmail = storedEmail;
        _isAuthenticated = true;
        notifyListeners();
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('AuthService: Error authenticating with biometrics: $e');
      return false;
    }
  }

  /// Enable biometric authentication
  Future<bool> enableBiometrics() async {
    try {
      final canUseBio = await canUseBiometrics();
      if (!canUseBio) return false;

      final didAuthenticate = await _localAuth.authenticate(
        localizedReason: 'Enable Face ID / Touch ID for quick access',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: true,
        ),
      );

      if (didAuthenticate) {
        await _secureStorage.write(key: _kBiometricsEnabledKey, value: 'true');
        _biometricsEnabled = true;
        notifyListeners();
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('AuthService: Error enabling biometrics: $e');
      return false;
    }
  }

  /// Disable biometric authentication
  Future<void> disableBiometrics() async {
    try {
      await _secureStorage.write(key: _kBiometricsEnabledKey, value: 'false');
      _biometricsEnabled = false;
      notifyListeners();
    } catch (e) {
      debugPrint('AuthService: Error disabling biometrics: $e');
    }
  }

  /// Check if a PIN is set
  Future<bool> hasPIN() async {
    try {
      final pinHash = await _secureStorage.read(key: _kPinHashKey);
      return pinHash != null && pinHash.isNotEmpty;
    } catch (e) {
      debugPrint('AuthService: Error checking PIN: $e');
      return false;
    }
  }

  /// Set a new PIN
  Future<bool> setPIN(String pin) async {
    try {
      if (pin.length < 4 || pin.length > 6) {
        debugPrint('AuthService: PIN must be 4-6 digits');
        return false;
      }

      // Verify PIN contains only digits
      if (!RegExp(r'^\d+$').hasMatch(pin)) {
        debugPrint('AuthService: PIN must contain only digits');
        return false;
      }

      final pinHash = _hashPassword(pin);
      await _secureStorage.write(key: _kPinHashKey, value: pinHash);
      debugPrint('AuthService: PIN set successfully');
      return true;
    } catch (e) {
      debugPrint('AuthService: Error setting PIN: $e');
      return false;
    }
  }

  /// Verify a PIN
  Future<bool> verifyPIN(String pin) async {
    try {
      final storedPinHash = await _secureStorage.read(key: _kPinHashKey);
      if (storedPinHash == null) {
        debugPrint('AuthService: No PIN set');
        return false;
      }

      final pinHash = _hashPassword(pin);
      final isValid = pinHash == storedPinHash;

      if (isValid) {
        // Mark user as authenticated
        await _secureStorage.write(key: _kIsAuthenticatedKey, value: 'true');
        _isAuthenticated = true;

        // Set user email to 'guest' or retrieve stored email
        final storedEmail = await _secureStorage.read(key: _kEmailKey);
        _userEmail = storedEmail ?? 'guest';

        notifyListeners();
      }

      return isValid;
    } catch (e) {
      debugPrint('AuthService: Error verifying PIN: $e');
      return false;
    }
  }

  /// Clear/delete PIN
  Future<void> clearPIN() async {
    try {
      await _secureStorage.delete(key: _kPinHashKey);
      debugPrint('AuthService: PIN cleared');
    } catch (e) {
      debugPrint('AuthService: Error clearing PIN: $e');
    }
  }

  /// Change PIN (requires old PIN verification)
  Future<bool> changePIN(String oldPin, String newPin) async {
    try {
      // First verify the old PIN
      final isOldPinValid = await verifyPIN(oldPin);
      if (!isOldPinValid) {
        debugPrint('AuthService: Old PIN is incorrect');
        return false;
      }

      // Validate new PIN
      if (newPin.length < 4 || newPin.length > 6) {
        debugPrint('AuthService: New PIN must be 4-6 digits');
        return false;
      }

      if (!RegExp(r'^\d+$').hasMatch(newPin)) {
        debugPrint('AuthService: New PIN must contain only digits');
        return false;
      }

      // Set the new PIN
      final newPinHash = _hashPassword(newPin);
      await _secureStorage.write(key: _kPinHashKey, value: newPinHash);
      debugPrint('AuthService: PIN changed successfully');
      return true;
    } catch (e) {
      debugPrint('AuthService: Error changing PIN: $e');
      return false;
    }
  }

  /// Sign out
  Future<void> signOut() async {
    try {
      await _secureStorage.write(key: _kIsAuthenticatedKey, value: 'false');
      _isAuthenticated = false;
      notifyListeners();
    } catch (e) {
      debugPrint('AuthService: Error signing out: $e');
    }
  }

  /// Delete account (for testing purposes)
  Future<void> deleteAccount() async {
    try {
      await _secureStorage.deleteAll();
      _isAuthenticated = false;
      _userEmail = null;
      _biometricsEnabled = false;
      notifyListeners();
    } catch (e) {
      debugPrint('AuthService: Error deleting account: $e');
    }
  }

  /// Hash password using SHA-256 (in production, use proper password hashing like bcrypt)
  String _hashPassword(String password) {
    final bytes = utf8.encode(password);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }
}

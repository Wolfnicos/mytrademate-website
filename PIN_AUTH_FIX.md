# PIN Authentication Fix - Branch `plan-b-portfolio` (LITE)

**Date:** 2025-11-01
**Branch:** plan-b-portfolio
**Commit:** 2a2556e

## Problem

After setting a PIN code during onboarding and signing out, when the user returned to the onboarding screen and tapped "Use PIN Code", the app was asking them to **SET PIN** again (requiring double entry for confirmation) instead of **VERIFYING** their existing PIN (single entry).

Additionally, on Android emulator (without enrolled biometrics), Face ID/Touch ID options were still showing and failing when tapped.

## Root Causes

1. **PIN Setup Logic Bug** in `lib/screens/onboarding_screen.dart`:
   - The `_setupPIN()` function always called `PINDialog.showSetup()` without checking if a PIN already existed
   - No distinction between first-time setup vs returning user verification

2. **Biometric Detection Issue** in multiple files:
   - Code only checked if device **supports** biometric API (`canCheckBiometrics` + `isDeviceSupported`)
   - Did NOT check if biometrics were actually **enrolled** on the device
   - Android emulator has biometric API support but no enrolled fingerprints/face

## Solution

### 1. Created Reusable PIN Dialog Component
**New File:** `lib/widgets/pin_dialog.dart`

- Two dialog modes:
  - **Setup Mode:** Requires entering PIN twice for confirmation
  - **Verify Mode:** Single PIN entry to verify existing PIN
- Static helper methods:
  - `PINDialog.showSetup(context)` - for first-time setup
  - `PINDialog.showVerify(context)` - for verification
- Validates 4-6 digit PINs
- Shows clear error messages

### 2. Added PIN Management to AuthService
**Modified:** `lib/services/auth_service.dart`

Added four new methods:

```dart
// Check if PIN is stored
Future<bool> hasPIN() async

// Set new PIN (validates 4-6 digits, stores SHA-256 hash)
Future<bool> setPIN(String pin) async

// Verify PIN and authenticate user
Future<bool> verifyPIN(String pin) async

// Delete stored PIN
Future<void> clearPIN() async
```

**Fixed Biometric Detection:**
```dart
Future<bool> canUseBiometrics() async {
  final canCheck = await _localAuth.canCheckBiometrics;
  final isDeviceSupported = await _localAuth.isDeviceSupported();

  // NEW: Check if biometrics are actually enrolled
  final availableBiometrics = await _localAuth.getAvailableBiometrics();
  final hasEnrolledBiometrics = availableBiometrics.isNotEmpty;

  return canCheck && isDeviceSupported && hasEnrolledBiometrics;
}
```

### 3. Fixed PIN Setup Flow in Onboarding
**Modified:** `lib/screens/onboarding_screen.dart`

**BEFORE (BROKEN):**
```dart
Future<void> _setupPIN() async {
  // Always showed setup dialog
  final pin = await PINDialog.showSetup(context);
  // ...
}
```

**AFTER (FIXED):**
```dart
Future<void> _setupPIN() async {
  final authService = context.read<AuthService>();
  final hasPIN = await authService.hasPIN();

  if (hasPIN) {
    // User has PIN - VERIFY it
    final pin = await PINDialog.showVerify(context);
    final isValid = await authService.verifyPIN(pin);

    if (isValid) {
      Navigator.of(context).pushReplacementNamed('/home');
    } else {
      _showError('Invalid PIN code');
    }
  } else {
    // User doesn't have PIN - SET it
    final pin = await PINDialog.showSetup(context);
    if (pin != null) {
      await authService.setPIN(pin);
      await authService.signInAsGuest();
      Navigator.of(context).pushReplacementNamed('/home');
    }
  }
}
```

Also updated biometric detection:
```dart
Future<void> _checkBiometricSupport() async {
  final canCheck = await _localAuth.canCheckBiometrics;
  final isDeviceSupported = await _localAuth.isDeviceSupported();

  // Check if biometrics are actually enrolled
  final availableBiometrics = await _localAuth.getAvailableBiometrics();
  final hasEnrolledBiometrics = availableBiometrics.isNotEmpty;

  setState(() {
    _canCheckBiometrics = canCheck && isDeviceSupported && hasEnrolledBiometrics;
  });
}
```

### 4. Fixed Biometric Detection in Settings
**Modified:** `lib/screens/settings_screen.dart`

Applied same biometric enrollment check as onboarding screen.

### 5. Added PIN Support to Welcome Screen (Optional)
**Modified:** `lib/screens/welcome_screen.dart`

Added PIN authentication option to welcome screen. **Note:** This may not be used on the LITE branch since email/password login is not visible on this branch.

### 6. Updated iOS Deployment Target
**Modified:**
- `ios/Podfile`
- `ios/Runner.xcodeproj/project.pbxproj`

Changed iOS deployment target from 13.0 to 14.0 (required by `workmanager_apple` plugin).

## Expected Behavior After Fix

### First-Time User Flow:
1. User opens app → Onboarding Screen 1 (Welcome)
2. Next → Onboarding Screen 2 (Premium Pricing - 2 days free trial)
3. Next → Onboarding Screen 3 (Authentication)
   - Shows "Use PIN Code" button (Face ID/Touch ID hidden if no biometrics enrolled)
4. User taps "Use PIN Code" → **SET PIN** dialog (enter PIN twice)
5. User enters PIN (123456) twice → Dashboard

### Returning User Flow (After Sign Out):
1. User taps "Sign Out" in Settings → Returns to Onboarding Screen 1
2. Next → Onboarding Screen 2 (Premium Pricing)
3. Next → Onboarding Screen 3 (Authentication)
   - Shows "Use PIN Code" button
4. User taps "Use PIN Code" → **ENTER PIN** dialog (single entry) ✅
5. User enters PIN (123456) once → Dashboard ✅

### Android Emulator (No Biometrics):
- Face ID/Touch ID options are **hidden** ✅
- Only "Use PIN Code" button is visible ✅

## Files Changed

- ✅ `lib/widgets/pin_dialog.dart` (NEW - 288 lines)
- ✅ `lib/services/auth_service.dart` (+76 lines)
- ✅ `lib/screens/onboarding_screen.dart` (+63 lines)
- ✅ `lib/screens/settings_screen.dart` (biometric fix)
- ✅ `lib/screens/welcome_screen.dart` (PIN support - optional)
- ✅ `ios/Podfile` (iOS 14.0)
- ✅ `ios/Runner.xcodeproj/project.pbxproj` (iOS 14.0)

**Total:** 7 files changed, 539 insertions(+), 16 deletions(-)

## Testing Results

✅ **Tested on Android Emulator (Pixel 7)**
- PIN setup works (enter twice)
- Sign out → PIN verification works (enter once)
- Face ID/Touch ID hidden (no enrolled biometrics)
- Invalid PIN shows error message
- App installs and runs successfully after storage cleanup

## Security Notes

- PINs are hashed with SHA-256 before storing in FlutterSecureStorage
- PINs must be 4-6 digits only
- Invalid PIN attempts show clear error messages
- No production backend - local authentication only (LITE branch)

## Next Steps

User will specify additional requirements after reviewing this fix.

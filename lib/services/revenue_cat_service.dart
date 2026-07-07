import 'dart:io';
import 'package:flutter/material.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

class RevenueCatService {
  // RevenueCat SDK keys are public client keys (safe to ship), but they MUST
  // match the platform: Android keys start with `goog_`, iOS keys with `appl_`.
  static const String _androidApiKey = 'goog_BqRTFllhpfXBoaAyotoFdUTvHOH';

  static const String _iosApiKey = 'appl_JPxnVYmbRgQQYClrKXwljwJzxcJ';

  static const String entitlementId = 'waypoint Pro';
  static const String _lifetimeProductId = 'waypoint_lifetime_7999';

  // Last entitlement result we were confident about. Persisted so a paying user
  // keeps access across launches and through transient network failures, and
  // seeded from disk on init. Only ever written from a *successful* check, so an
  // unconfirmed (free) user can never fake Pro by going offline.
  static const String _cacheKey = 'rc_last_known_pro';

  static bool _initialized = false;
  static SharedPreferences? _prefs;
  static bool? _cachedIsPro;

  static Future<void> initialize([SharedPreferences? prefs]) async {
    _prefs ??= prefs;
    _cachedIsPro ??= _prefs?.getBool(_cacheKey);
    if (_initialized) return;
    try {
      final apiKey = Platform.isIOS ? _iosApiKey : _androidApiKey;
      await Purchases.configure(PurchasesConfiguration(apiKey))
          .timeout(const Duration(seconds: 8));
      _initialized = true;
    } catch (e) {
      debugPrint('RevenueCat init error: $e');
    }
  }

  static void _rememberPro(bool isPro) {
    _cachedIsPro = isPro;
    _prefs?.setBool(_cacheKey, isPro);
  }

  static Future<bool> isProUser() async {
    try {
      final info = await Purchases.getCustomerInfo()
          .timeout(const Duration(seconds: 8));
      final active = info.entitlements.active.containsKey(entitlementId) ||
          // Fallback: lifetime entitlement not yet linked in the RC dashboard.
          info.nonSubscriptionTransactions
              .any((t) => t.productIdentifier == _lifetimeProductId);
      _rememberPro(active);
      return active;
    } catch (e) {
      // Network/timeout failure: fall back to the last entitlement we were sure
      // about so a paying user isn't locked out offline. Defaults to false for
      // anyone never confirmed Pro, so this can't be exploited for free access.
      return _cachedIsPro ?? false;
    }
  }

  static Future<Offerings?> getOfferings() async {
    try {
      return await Purchases.getOfferings()
          .timeout(const Duration(seconds: 5));
    } catch (e) {
      debugPrint('Error fetching offerings: $e');
      return null;
    }
  }

  static Future<bool> purchasePackage(Package package) async {
    try {
      // ignore: deprecated_member_use
      await Purchases.purchasePackage(package);
      final info = await Purchases.getCustomerInfo()
          .timeout(const Duration(seconds: 5));
      final active = info.entitlements.active.containsKey(entitlementId);
      if (active) _rememberPro(true);
      return active;
    } catch (e) {
      debugPrint('Purchase error: $e');
      return false;
    }
  }

  /// The RevenueCat app user ID for the current install (an anonymous
  /// `$RCAnonymousID:...` unless a user was ever logged in). Used to stitch the
  /// anonymous PostHog journey to the paying identity — it's the same ID
  /// RevenueCat's own PostHog connector keys events on. Never throws.
  static Future<String?> appUserId() async {
    try {
      return await Purchases.appUserID.timeout(const Duration(seconds: 5));
    } catch (e) {
      debugPrint('appUserId error: $e');
      return null;
    }
  }

  static Future<bool> restorePurchases() async {
    try {
      final info = await Purchases.restorePurchases()
          .timeout(const Duration(seconds: 10));
      final active = info.entitlements.active.containsKey(entitlementId);
      if (active) _rememberPro(true);
      return active;
    } catch (e) {
      debugPrint('Restore error: $e');
      return false;
    }
  }
}

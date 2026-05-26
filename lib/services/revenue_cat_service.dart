import 'dart:io';
import 'package:flutter/material.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

class RevenueCatService {
  static const String _iosApiKey = 'goog_BqRTFllhpfXBoaAyotoFdUTvHOH';
  static const String _androidApiKey = 'goog_BqRTFllhpfXBoaAyotoFdUTvHOH';

  static const String entitlementId = 'waypoint Pro';

  static bool _initialized = false;

  static Future<void> initialize() async {
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

  static const String _lifetimeProductId = 'waypoint_lifetime_7999';

  static Future<bool> isProUser() async {
    try {
      final info = await Purchases.getCustomerInfo()
          .timeout(const Duration(seconds: 5));
      if (info.entitlements.active.containsKey(entitlementId)) return true;
      // Fallback: entitlement not linked in RC dashboard yet
      return info.nonSubscriptionTransactions
          .any((t) => t.productIdentifier == _lifetimeProductId);
    } catch (e) {
      return false;
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
      return info.entitlements.active.containsKey(entitlementId);
    } catch (e) {
      debugPrint('Purchase error: $e');
      return false;
    }
  }

  static Future<bool> restorePurchases() async {
    try {
      final info = await Purchases.restorePurchases()
          .timeout(const Duration(seconds: 10));
      return info.entitlements.active.containsKey(entitlementId);
    } catch (e) {
      debugPrint('Restore error: $e');
      return false;
    }
  }
}
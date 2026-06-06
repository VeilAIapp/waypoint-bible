import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class HapticService {
  static SharedPreferences? _prefs;
  static const _kKey = 'haptic_enabled';

  static void init(SharedPreferences prefs) => _prefs = prefs;

  static bool get _enabled => _prefs?.getBool(_kKey) ?? true;

  static void light() {
    if (_enabled) HapticFeedback.lightImpact();
  }

  static void medium() {
    if (_enabled) HapticFeedback.mediumImpact();
  }

  static void selection() {
    if (_enabled) HapticFeedback.selectionClick();
  }
}

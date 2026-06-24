import 'package:home_widget/home_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/daily_verses.dart';
import 'revenue_cat_service.dart';

class WidgetUpdateService {
  static const _medium = 'WaypointWidgetMediumProvider';

  /// Full update: refreshes verse, streak, and Pro entitlement.
  /// Call on cold start (after RevenueCat is initialized) and on date change.
  static Future<void> updateAll(SharedPreferences prefs) async {
    final verse = getDailyVerse();
    final streak = prefs.getInt('streak') ?? 0;

    bool isPro = false;
    try {
      isPro = await RevenueCatService.isProUser();
    } catch (_) {}

    await Future.wait([
      HomeWidget.saveWidgetData<String>('verse_text', verse['text'] ?? ''),
      HomeWidget.saveWidgetData<String>('verse_ref', verse['ref'] ?? ''),
      HomeWidget.saveWidgetData<int>('streak', streak),
      HomeWidget.saveWidgetData<bool>('is_pro', isPro),
    ]);

    await _broadcastUpdate();
  }

  /// Fast update: pushes verse + streak without waiting for RevenueCat.
  /// Call immediately on app open so the widget shows today's verse right away.
  static Future<void> pushVerseAndStreak(SharedPreferences prefs) async {
    final verse = getDailyVerse();
    final streak = prefs.getInt('streak') ?? 0;
    try {
      await Future.wait([
        HomeWidget.saveWidgetData<String>('verse_text', verse['text'] ?? ''),
        HomeWidget.saveWidgetData<String>('verse_ref', verse['ref'] ?? ''),
        HomeWidget.saveWidgetData<int>('streak', streak),
      ]);
      await _broadcastUpdate();
    } catch (_) {}
  }

  /// Lightweight update: pushes just the streak to the widget without hitting
  /// RevenueCat. Call immediately after HomeScreen writes the new streak value
  /// to SharedPreferences so the widget shows the correct count on every open.
  static Future<void> pushStreakOnly(SharedPreferences prefs) async {
    final streak = prefs.getInt('streak') ?? 0;
    try {
      await HomeWidget.saveWidgetData<int>('streak', streak);
      await _broadcastUpdate();
    } catch (_) {}
  }

  static Future<void> _broadcastUpdate() async {
    await HomeWidget.updateWidget(androidName: _medium);
  }
}

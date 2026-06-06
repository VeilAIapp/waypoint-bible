import 'package:in_app_review/in_app_review.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ReviewService {
  static const _kCountKey = 'review_prompt_count';
  static const _kMaxPrompts = 2;
  static const _kChatTrigger = 5;

  static Future<void> maybeRequestAfterChat(SharedPreferences prefs) async {
    final chatCount = prefs.getInt('chat_count') ?? 0;
    if (chatCount != _kChatTrigger) return;
    await _request(prefs);
  }

  static Future<void> maybeRequestAfterPlanCompletion(SharedPreferences prefs) async {
    await _request(prefs);
  }

  static Future<void> _request(SharedPreferences prefs) async {
    final prompted = prefs.getInt(_kCountKey) ?? 0;
    if (prompted >= _kMaxPrompts) return;
    final review = InAppReview.instance;
    if (!await review.isAvailable()) return;
    await review.requestReview();
    await prefs.setInt(_kCountKey, prompted + 1);
  }
}

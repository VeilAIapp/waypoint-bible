import 'package:flutter/foundation.dart';
import 'package:posthog_flutter/posthog_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants.dart';
import 'revenue_cat_service.dart';

/// Single wrapper around PostHog for the pre-paywall product funnel.
///
/// CONTRACT — this must NEVER crash the app. Every public method is wrapped in
/// a try/catch that swallows and logs, and never rethrows. This is deliberate:
/// the AI response stream has crashed before, and any analytics call added near
/// it must be structurally incapable of throwing into that path. If PostHog
/// fails to init (or no key is provided), [_enabled] stays false and every
/// event call becomes a silent no-op — the app runs normally with analytics off.
///
/// Identity: PostHog generates and persists its own anonymous distinct_id, which
/// carries the whole anonymous pre-paywall journey. We NEVER reset it. On a
/// purchase/restore we call [Posthog.identify] with the RevenueCat app user ID —
/// the same ID RevenueCat's own PostHog connector uses — so the anonymous
/// journey stitches to the paying identity in one funnel.
class AnalyticsService {
  AnalyticsService._();
  static final AnalyticsService instance = AnalyticsService._();

  /// True only after a successful setup with a non-empty key. While false,
  /// every event call is a no-op.
  bool _enabled = false;

  SharedPreferences? _prefs;

  // Persisted once-ever flag so `first_question_asked` fires a single time per
  // user, and a persisted internal-device flag for funnel filtering.
  static const String _kFirstQuestionSentKey = 'analytics_first_question_sent';
  static const String _kInternalKey = 'analytics_is_internal';

  // ── Lifecycle ───────────────────────────────────────────────────────────────

  /// Initialise PostHog once, at app startup, before any event can fire.
  /// Safe to call even without a key — it just leaves analytics disabled.
  Future<void> init(SharedPreferences prefs) async {
    _prefs = prefs;
    try {
      if (kPostHogApiKey.isEmpty) {
        debugPrint('[analytics] no POSTHOG_API_KEY — analytics disabled');
        return;
      }
      final config = PostHogConfig(kPostHogApiKey)
        ..host = kPostHogHost
        // Lifecycle autocapture → app opened / backgrounded → D1/D7 retention
        // for free, no manual events needed.
        ..captureApplicationLifecycleEvents = true
        // Session replay records the screen; keep it OFF for privacy.
        ..sessionReplay = false
        ..debug = kDebugMode;
      await Posthog().setup(config);
      _enabled = true;

      // If this build/device is internal, tag every event so it can be filtered
      // out of the funnel. Reads both the compile-time flag and the runtime
      // toggle (which reaches prod builds on any device, e.g. a tester's phone).
      final internal =
          kInternalBuild || (_prefs?.getBool(_kInternalKey) ?? false);
      if (internal) {
        await Posthog().register('is_internal', true);
      }
    } catch (e) {
      _enabled = false;
      debugPrint('[analytics] init failed, analytics disabled: $e');
    }
  }

  // ── Six funnel events ─────────────────────────────────────────────────────────

  /// Each onboarding screen appears. [step] is e.g. "welcome", "first_question",
  /// "denomination", "trial". Never sends the chosen denomination value.
  void onboardingStepViewed(String step) =>
      _capture('onboarding_step_viewed', {'step': step});

  /// User finishes onboarding and enters the main app.
  void onboardingCompleted() => _capture('onboarding_completed');

  /// User sends their first-ever message to the AI companion. Guarded by a
  /// persistent flag so it fires exactly once per user, ever.
  void firstQuestionAsked() {
    try {
      if (!_enabled) return;
      if (_prefs?.getBool(_kFirstQuestionSentKey) == true) return;
      _prefs?.setBool(_kFirstQuestionSentKey, true);
      _capture('first_question_asked');
    } catch (e) {
      debugPrint('[analytics] firstQuestionAsked failed: $e');
    }
  }

  /// The AI response stream completed. [success] false means the stream errored.
  void answerReceived({required bool success}) =>
      _capture('answer_received', {'success': success});

  /// The RevenueCat paywall is presented.
  void paywallViewed() => _capture('paywall_viewed');

  /// Called on a successful purchase/restore. Always identifies PostHog with the
  /// RevenueCat app user ID (stitching the anonymous journey to the paying
  /// identity — critically, this runs for brand-new payers, not just restores).
  /// Fires `trial_started` only when [startedTrial] is true; a restore is an
  /// existing subscriber reinstalling, not a new trial, so it identifies but
  /// does not fire the funnel event.
  Future<void> onProUnlocked({required bool startedTrial}) async {
    try {
      if (!_enabled) return;
      final rcId = await RevenueCatService.appUserId();
      if (rcId != null && rcId.isNotEmpty) {
        await Posthog().identify(userId: rcId);
      }
      if (startedTrial) {
        await Posthog().capture(eventName: 'trial_started');
      }
    } catch (e) {
      debugPrint('[analytics] onProUnlocked failed: $e');
    }
  }

  // ── Internal-device toggle ────────────────────────────────────────────────────

  /// Marks (or unmarks) this device as internal at runtime and persists it, so
  /// you and family testers can be filtered out of the funnel on any build.
  Future<void> setInternal(bool value) async {
    try {
      await _prefs?.setBool(_kInternalKey, value);
      if (!_enabled) return;
      if (value) {
        await Posthog().register('is_internal', true);
      } else {
        await Posthog().unregister('is_internal');
      }
    } catch (e) {
      debugPrint('[analytics] setInternal failed: $e');
    }
  }

  bool get isInternal =>
      kInternalBuild || (_prefs?.getBool(_kInternalKey) ?? false);

  // ── Guarded primitive ─────────────────────────────────────────────────────────

  void _capture(String event, [Map<String, Object>? properties]) {
    try {
      if (!_enabled) return;
      // Fire-and-forget: we intentionally do not await so a slow/failing
      // network call can never block or throw into the caller (e.g. the stream
      // completion handler). PostHog queues and flushes internally.
      Posthog()
          .capture(eventName: event, properties: properties)
          .catchError((Object e) => debugPrint('[analytics] $event failed: $e'));
    } catch (e) {
      debugPrint('[analytics] $event threw: $e');
    }
  }
}

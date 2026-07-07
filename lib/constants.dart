// Injected at build time via --dart-define=ANTHROPIC_API_KEY=sk-ant-...
// Never hardcode this value here.
const String kAnthropicApiKey =
    String.fromEnvironment('ANTHROPIC_API_KEY');
const String kAnthropicModel = 'claude-sonnet-4-6';
// Used for structured/mechanical tasks (e.g. verse search) that don't need
// Sonnet's conversational depth — meaningfully cheaper per token.
const String kAnthropicHaikuModel = 'claude-haiku-4-5';
const String kAnthropicApiUrl = 'https://api.anthropic.com/v1/messages';

// ── PostHog analytics ─────────────────────────────────────────────────────────
// The PostHog *project* key (phc_...) is a publishable client key, but it is
// still injected via --dart-define so no key lives in committed source. If the
// key is empty (no dart-define), AnalyticsService silently disables itself and
// the app runs normally. Never hardcode a value here.
const String kPostHogApiKey = String.fromEnvironment('POSTHOG_API_KEY');
const String kPostHogHost = String.fromEnvironment(
  'POSTHOG_HOST',
  defaultValue: 'https://us.i.posthog.com',
);

// Marks this build/device as internal (you + family testers) so its events can
// be filtered out of the funnel. Set via --dart-define=WAYPOINT_INTERNAL=true
// for dev builds; can also be toggled at runtime on any device from Settings
// (see AnalyticsService.setInternal / the version-label toggle).
const bool kInternalBuild = bool.fromEnvironment('WAYPOINT_INTERNAL');

// Shared SharedPreferences key for the persisted Companion conversation.
// Written by onboarding (the user's first real question) and by ChatScreen
// (every subsequent message) so the two never drift out of sync.
const String kChatSessionKey = 'chat_session_history';

const List<String> kDenominations = [
  'Non-denominational',
  'Baptist',
  'Catholic',
  'Methodist',
  'Pentecostal / Charismatic',
  'Presbyterian / Reformed',
  'Lutheran',
  'Anglican / Episcopal',
  'Seventh-day Adventist',
  'Church of Christ',
];

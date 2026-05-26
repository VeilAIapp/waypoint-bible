// Injected at build time via --dart-define=ANTHROPIC_API_KEY=sk-ant-...
// Never hardcode this value here.
const String kAnthropicApiKey =
    String.fromEnvironment('ANTHROPIC_API_KEY');
const String kAnthropicModel = 'claude-opus-4-7';
const String kAnthropicApiUrl = 'https://api.anthropic.com/v1/messages';

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

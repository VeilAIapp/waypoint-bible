import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:purchases_ui_flutter/purchases_ui_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../constants.dart';
import '../services/analytics_service.dart';
import '../services/companion_prompt.dart';
import '../theme/app_theme.dart';

// Felt-need prompts — tapping one submits it immediately as the user's first
// real question. Chosen to surface a genuine reason to keep talking, not a
// scripted demo, so the "aha moment" is personal rather than canned.
const List<String> _kFeltNeedPrompts = [
  "I'm anxious about something",
  'I feel distant from God',
  'Explain a verse that confuses me',
  "I haven't opened my Bible in years",
];

/// One question/answer pair in the onboarding conversation. Onboarding allows
/// real follow-ups (not just a single scripted exchange), so this is a small
/// list rather than one flat set of fields.
class _QAExchange {
  final String question;
  String answer = '';
  bool loading = true;
  bool done = false;
  bool failed = false;
  _QAExchange(this.question);
}

class OnboardingScreen extends StatefulWidget {
  final SharedPreferences prefs;
  final VoidCallback onComplete;

  const OnboardingScreen({
    super.key,
    required this.prefs,
    required this.onComplete,
  });

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  // Page 2 — the user's first real question, and any follow-ups. A real
  // conversation, not a single scripted exchange — so it's a list.
  final TextEditingController _questionController = TextEditingController();
  final List<_QAExchange> _exchanges = [];
  final List<String> _charQueue = [];
  Timer? _charTimer;
  bool _apiStreamComplete = false;

  /// True while an answer is currently streaming — blocks a second submit
  /// and hides the input so it can't race with the in-flight request.
  bool get _busy => _exchanges.isNotEmpty && !_exchanges.last.done;

  // Page 3 — Setup
  String? _selectedDenomination;

  // Maps each PageView index to its funnel step name. Index 1 is now the
  // user's first real question (the "aha moment" moved here so it happens
  // fast, on their own felt need); index 2 is the denomination step (we track
  // that the step was viewed, never the chosen denomination value).
  static const List<String> _stepNames = [
    'welcome',
    'first_question',
    'denomination',
    'trial',
  ];

  void _trackStep(int page) {
    if (page >= 0 && page < _stepNames.length) {
      AnalyticsService.instance.onboardingStepViewed(_stepNames[page]);
    }
  }

  @override
  void initState() {
    super.initState();
    _trackStep(0);
  }

  @override
  void dispose() {
    _charTimer?.cancel();
    _pageController.dispose();
    _questionController.dispose();
    super.dispose();
  }

  // ── First-question AI streaming ──────────────────────────────────────────────

  /// Submits [question] — the user's first real Companion question, or a
  /// follow-up. No denomination has been chosen yet at this point, so the
  /// base system prompt is used — matching how a brand-new free user's first
  /// chat messages behave before ever visiting Settings. Prior exchanges on
  /// this page are sent as history so a follow-up has real context.
  Future<void> _askQuestion(String question) async {
    if (_busy) return;
    final trimmed = question.trim();
    if (trimmed.isEmpty) return;

    final isFirst = _exchanges.isEmpty;
    // Build history from exchanges so far, before adding the new one.
    final priorMessages = <Map<String, String>>[
      for (final e in _exchanges)
        if (e.done && !e.failed) ...[
          {'role': 'user', 'content': e.question},
          {'role': 'assistant', 'content': e.answer},
        ],
    ];

    final exchange = _QAExchange(trimmed);
    setState(() {
      _exchanges.add(exchange);
      _questionController.clear();
    });

    if (isFirst) {
      // This is a real, user-initiated question — it's the same funnel moment
      // chat_screen fires later for a returning user, guarded to fire once ever.
      AnalyticsService.instance.firstQuestionAsked();
    }

    final client = http.Client();
    try {
      final request = http.Request('POST', Uri.parse(kAnthropicApiUrl));
      request.headers.addAll({
        'Content-Type': 'application/json',
        'x-api-key': kAnthropicApiKey,
        'anthropic-version': '2023-06-01',
      });
      request.body = jsonEncode({
        'model': kAnthropicModel,
        'max_tokens': 800,
        'stream': true,
        'system': buildCompanionSystemPrompt(null),
        'messages': [...priorMessages, {'role': 'user', 'content': trimmed}],
      });

      final streamedResponse =
          await client.send(request).timeout(const Duration(seconds: 30));

      if (streamedResponse.statusCode != 200) {
        throw Exception('API error ${streamedResponse.statusCode}');
      }

      if (mounted) setState(() => exchange.loading = false);
      _startCharTimer(exchange);

      // Stateful UTF-8 decode + line splitting so multi-byte characters split
      // across a network chunk don't throw mid-stream (see chat_screen).
      await for (final line in streamedResponse.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())) {
        final trimmedLine = line.trim();
        if (!trimmedLine.startsWith('data: ')) continue;
        final data = trimmedLine.substring(6);
        if (data == '[DONE]') break;
        try {
          final json = jsonDecode(data);
          if (json['type'] == 'message_stop') break;
          if (json['type'] == 'content_block_delta') {
            final delta = json['delta'];
            if (delta != null && delta['type'] == 'text_delta') {
              final text = delta['text'] as String? ?? '';
              if (text.isNotEmpty) {
                _charQueue.addAll(text.characters);
              }
            }
          }
        } catch (_) {}
      }

      _apiStreamComplete = true;
      AnalyticsService.instance.answerReceived(success: true);
    } catch (e) {
      _charTimer?.cancel();
      _charTimer = null;
      _charQueue.clear();
      AnalyticsService.instance.answerReceived(success: false);
      if (mounted) {
        setState(() {
          exchange.loading = false;
          exchange.failed = true;
          exchange.answer =
              "Couldn't reach your Companion just now — but that's alright. "
              "You can pick up right where you left off once you're in the app.";
          exchange.done = true;
        });
      }
    } finally {
      client.close();
    }
  }

  void _startCharTimer(_QAExchange exchange) {
    _charTimer = Timer.periodic(const Duration(milliseconds: 16), (_) {
      if (_charQueue.isEmpty) {
        if (_apiStreamComplete && mounted) {
          _apiStreamComplete = false;
          _charTimer?.cancel();
          _charTimer = null;
          setState(() => exchange.done = true);
          _persistExchangesToChatSession();
        }
        return;
      }
      final buf = StringBuffer();
      for (int i = 0; i < 3 && _charQueue.isNotEmpty; i++) {
        buf.write(_charQueue.removeAt(0));
      }
      if (mounted) setState(() => exchange.answer += buf.toString());
    });
  }

  /// Saves every successful exchange so far as the start of the Companion
  /// conversation, so it's still there the first time the user opens the
  /// Companion tab — including any follow-ups asked here, not just the first.
  void _persistExchangesToChatSession() {
    final history = <Map<String, String>>[
      for (final e in _exchanges)
        if (e.done && !e.failed) ...[
          {'role': 'user', 'content': e.question},
          {'role': 'assistant', 'content': e.answer},
        ],
    ];
    if (history.isNotEmpty) {
      widget.prefs.setString(kChatSessionKey, jsonEncode(history));
    }
  }

  // ── Navigation ──────────────────────────────────────────────────────────────

  void _nextPage() {
    if (_currentPage < 3) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
      setState(() => _currentPage++);
      _trackStep(_currentPage);
    }
  }

  bool _trialLoading = false;

  Future<void> _startTrial() async {
    if (_trialLoading) return;
    setState(() => _trialLoading = true);
    try {
      AnalyticsService.instance.paywallViewed();
      final result =
          await RevenueCatUI.presentPaywall(displayCloseButton: true);
      if (!mounted) return;
      if (result == PaywallResult.purchased ||
          result == PaywallResult.restored) {
        // Identify PostHog with the RevenueCat ID on BOTH purchase and restore
        // (fire-and-forget so it never delays entering the app); only a purchase
        // fires the trial_started funnel event.
        unawaited(AnalyticsService.instance.onProUnlocked(
          startedTrial: result == PaywallResult.purchased,
        ));
        _complete();
      } else {
        // Dismissed without purchasing — stay on the page so they can
        // tap "Maybe later" to continue free.
        setState(() => _trialLoading = false);
      }
    } catch (_) {
      // RevenueCat error — don't block onboarding, just continue free.
      if (mounted) _complete();
    }
  }

  void _complete() {
    if (_selectedDenomination != null) {
      widget.prefs.setString('user_denomination', _selectedDenomination!);
    }
    widget.prefs.setBool('onboarding_complete', true);
    AnalyticsService.instance.onboardingCompleted();
    widget.onComplete();
  }

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final t = WaypointTheme.of(context);
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          Positioned.fill(child: CustomPaint(painter: _OnboardingBgPainter(t))),
          SafeArea(
            child: Column(
              children: [
                // Progress dots
                if (_currentPage > 0) ...[
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(
                      4,
                      (i) => Container(
                        width: i == _currentPage ? 20 : 7,
                        height: 7,
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        decoration: BoxDecoration(
                          color: i == _currentPage ? t.primary : t.cardBorder,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ),
                ],
                Expanded(
                  child: PageView(
                    controller: _pageController,
                    physics: const NeverScrollableScrollPhysics(),
                    children: [
                      _buildWelcomePage(t),
                      _buildFirstQuestionPage(t),
                      _buildSetupPage(t),
                      _buildTrialPage(t),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Page 1: Welcome ─────────────────────────────────────────────────────────

  Widget _buildWelcomePage(WaypointThemeData t) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Spacer(),
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [t.primary, t.secondary],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: t.primary.withValues(alpha: 0.3),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Icon(Icons.explore, color: t.onPrimary, size: 40),
          ),
          const SizedBox(height: 28),
          Text(
            'Waypoint',
            style: TextStyle(
              fontFamily: 'Georgia',
              fontSize: 36,
              fontWeight: FontWeight.bold,
              color: t.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Every question.\nEvery feeling.\nEvery verse.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Georgia',
              fontSize: 20,
              color: t.textSecondary,
              height: 1.6,
              fontStyle: FontStyle.italic,
            ),
          ),
          const Spacer(),
          _PrimaryButton(
            label: 'Get Started',
            onTap: _nextPage,
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  // ── Page 2: First real question ──────────────────────────────────────────────

  Widget _buildFirstQuestionPage(WaypointThemeData t) {
    final hasExchanges = _exchanges.isNotEmpty;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          Text(
            hasExchanges ? 'Your Companion' : "What's on your mind?",
            style: TextStyle(
              fontFamily: 'Georgia',
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: t.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            hasExchanges
                ? 'Ask a follow-up, or continue whenever you\'re ready.'
                : 'Ask anything — a question, a struggle, a verse you don\'t understand.',
            style: TextStyle(
              fontFamily: 'Georgia',
              fontSize: 14,
              color: t.textSecondary,
            ),
          ),
          const SizedBox(height: 20),

          if (!hasExchanges)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _kFeltNeedPrompts
                    .map((p) => GestureDetector(
                          onTap: () => _askQuestion(p),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: t.cardBg,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: t.cardBorder),
                            ),
                            child: Text(
                              p,
                              style: TextStyle(
                                fontFamily: 'Georgia',
                                fontSize: 13,
                                color: t.textPrimary,
                              ),
                            ),
                          ),
                        ))
                    .toList(),
              ),
            ),

          // Every exchange so far, in order — a real (if short) conversation,
          // not a single scripted Q&A.
          for (final e in _exchanges) ...[
            Align(
              alignment: Alignment.centerRight,
              child: Container(
                constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width * 0.8),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [t.primary, t.secondary],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(18),
                    topRight: Radius.circular(18),
                    bottomLeft: Radius.circular(18),
                    bottomRight: Radius.circular(4),
                  ),
                ),
                child: Text(
                  e.question,
                  style: TextStyle(
                    fontFamily: 'Georgia',
                    fontSize: 15,
                    height: 1.5,
                    color: t.onPrimary,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(minHeight: 80),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: t.cardBg.withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: t.cardBorder),
              ),
              child: e.loading || e.answer.isEmpty
                  ? _OnboardingDots()
                  : Text(
                      e.answer,
                      style: TextStyle(
                        fontFamily: 'Georgia',
                        fontSize: 15,
                        color: e.failed ? t.textSecondary : t.textPrimary,
                        height: 1.7,
                        fontStyle:
                            e.failed ? FontStyle.italic : FontStyle.normal,
                      ),
                    ),
            ),
            const SizedBox(height: 20),
          ],

          if (hasExchanges && !_busy) ...[
            _PrimaryButton(
              label: 'Continue →',
              onTap: _nextPage,
            ),
            const SizedBox(height: 16),
          ],

          if (!_busy)
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _questionController,
                    maxLines: null,
                    textCapitalization: TextCapitalization.sentences,
                    style: TextStyle(
                        fontFamily: 'Georgia',
                        fontSize: 15,
                        color: t.textPrimary),
                    decoration: InputDecoration(
                      hintText: hasExchanges
                          ? 'Ask a follow-up...'
                          : 'Or type your own question...',
                      hintStyle: TextStyle(
                          fontFamily: 'Georgia',
                          color: t.textHint,
                          fontSize: 14),
                      filled: true,
                      fillColor: t.inputFill,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 14),
                    ),
                    onSubmitted: _askQuestion,
                  ),
                ),
                const SizedBox(width: 10),
                GestureDetector(
                  onTap: () => _askQuestion(_questionController.text),
                  child: Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [t.primary, t.secondary],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.send_rounded,
                        color: t.onPrimary, size: 20),
                  ),
                ),
              ],
            ),

          const SizedBox(height: 16),
        ],
      ),
    );
  }

  // ── Page 3: Setup ───────────────────────────────────────────────────────────

  Widget _buildSetupPage(WaypointThemeData t) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          Text(
            'Want this tuned to your tradition?',
            style: TextStyle(
              fontFamily: 'Georgia',
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: t.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Totally optional — helps your Companion speak your language. Skip if you\'d rather not say.',
            style: TextStyle(
              fontFamily: 'Georgia',
              fontSize: 14,
              color: t.textSecondary,
              height: 1.4,
            ),
          ),

          const SizedBox(height: 24),

          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: kDenominations.map((d) {
              final selected = _selectedDenomination == d;
              return GestureDetector(
                onTap: () => setState(
                  () => _selectedDenomination = selected ? null : d,
                ),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: selected ? t.primary : t.cardBg,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: selected ? t.primary : t.cardBorder,
                    ),
                  ),
                  child: Text(
                    d,
                    style: TextStyle(
                      fontFamily: 'Georgia',
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: selected ? t.onPrimary : t.textPrimary,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),

          const SizedBox(height: 32),

          // Always enabled — this step never blocks progress. Tapping a
          // denomination chip a second time deselects it, so "Continue"
          // with nothing selected is a legitimate, easy skip.
          _PrimaryButton(
            label: 'Continue →',
            onTap: _nextPage,
          ),

          const SizedBox(height: 16),
        ],
      ),
    );
  }

  // ── Page 4: Trial ───────────────────────────────────────────────────────────

  Widget _buildTrialPage(WaypointThemeData t) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Spacer(),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [t.primary, t.secondary],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: t.primary.withValues(alpha: 0.3),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Icon(Icons.star, color: t.onPrimary, size: 40),
          ),
          const SizedBox(height: 28),
          Text(
            'Try Waypoint Pro',
            style: TextStyle(
              fontFamily: 'Georgia',
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: t.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Unlimited conversations, multiple Bible translations, reading plans and more.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Georgia',
              fontSize: 15,
              color: t.textSecondary,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Free for 7 days, then \$69.99/year — our best value.\nMonthly also available at \$19.99/mo.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Georgia',
              fontSize: 13,
              color: t.textHint,
              height: 1.5,
            ),
          ),
          const Spacer(),
          _PrimaryButton(
            label: 'Start 7 Days Free',
            onTap: _trialLoading ? null : _startTrial,
          ),
          const SizedBox(height: 14),
          GestureDetector(
            onTap: _complete,
            child: Text(
              'Maybe later',
              style: TextStyle(
                fontFamily: 'Georgia',
                fontSize: 14,
                color: t.textHint,
                decoration: TextDecoration.underline,
                decorationColor: t.textHint,
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

// ── Background painter ────────────────────────────────────────────────────────

class _OnboardingBgPainter extends CustomPainter {
  final WaypointThemeData t;
  const _OnboardingBgPainter(this.t);

  @override
  void paint(Canvas canvas, Size size) {
    final gradientPaint = Paint()
      ..shader = LinearGradient(
        colors: [t.gradTop, t.gradMid, t.gradBot],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        stops: const [0.0, 0.5, 1.0],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawRect(
        Rect.fromLTWH(0, 0, size.width, size.height), gradientPaint);

    final dotPaint = Paint()
      ..color = t.primary.withValues(alpha: 0.04)
      ..style = PaintingStyle.fill;
    const spacing = 22.0;
    for (double x = 0; x < size.width + spacing; x += spacing) {
      for (double y = 0; y < size.height + spacing; y += spacing) {
        canvas.drawCircle(Offset(x, y), 1.5, dotPaint);
      }
    }

    final arcPaint = Paint()
      ..color = t.primary.withValues(alpha: 0.05)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 50;
    canvas.drawArc(
      Rect.fromCenter(
        center: Offset(size.width + 40, -40),
        width: size.width * 1.1,
        height: size.width * 1.1,
      ),
      math.pi * 0.6,
      math.pi * 0.5,
      false,
      arcPaint,
    );
  }

  @override
  bool shouldRepaint(_OnboardingBgPainter old) => old.t != t;
}

// ── Shared widgets ────────────────────────────────────────────────────────────

class _PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;

  const _PrimaryButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = WaypointTheme.of(context);
    final enabled = onTap != null;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          gradient: enabled
              ? LinearGradient(
                  colors: [t.primary, t.secondary],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          color: enabled ? null : t.unearnedBg,
          borderRadius: BorderRadius.circular(24),
          boxShadow: enabled
              ? [
                  BoxShadow(
                    color: t.primary.withValues(alpha: 0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  )
                ]
              : [],
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontFamily: 'Georgia',
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: enabled ? t.onPrimary : t.textHint,
            ),
          ),
        ),
      ),
    );
  }
}

class _OnboardingDots extends StatefulWidget {
  const _OnboardingDots();

  @override
  State<_OnboardingDots> createState() => _OnboardingDotsState();
}

class _OnboardingDotsState extends State<_OnboardingDots>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _animation = Tween<double>(begin: 0.4, end: 1.0).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = WaypointTheme.of(context);
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: Opacity(
                opacity: i == 0
                    ? _animation.value
                    : i == 1
                        ? (_animation.value * 0.8 + 0.2)
                        : (1 - _animation.value * 0.6),
                child: Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: t.primary,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}

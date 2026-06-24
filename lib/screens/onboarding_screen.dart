import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:purchases_ui_flutter/purchases_ui_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../constants.dart';
import '../theme/app_theme.dart';

const String _onboardingVerse = 'John 1:1';
const String _onboardingVerseText =
    '"In the beginning was the Word, and the Word was with God, and the Word was God."';

const String _onboardingPrompt =
    'Explain John 1:1 in a warm, accessible way. Cover what "the Word" (Logos) means in Greek '
    'and what it means personally for someone reading it today. '
    'Keep it to 2 short paragraphs maximum. Be warm — like a wise friend. No headers or bullet points.';

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

  // Page 2 — AI explanation
  String _aiExplanation = '';
  bool _aiLoading = true;
  bool _aiDone = false;
  final List<String> _charQueue = [];
  Timer? _charTimer;
  bool _apiStreamComplete = false;

  // Page 3 — Setup
  String? _selectedDenomination;

  @override
  void initState() {
    super.initState();
    _fetchAiExplanation();
  }

  @override
  void dispose() {
    _charTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  // ── AI streaming ────────────────────────────────────────────────────────────

  Future<void> _fetchAiExplanation() async {
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
        'max_tokens': 350,
        'stream': true,
        'messages': [
          {'role': 'user', 'content': _onboardingPrompt}
        ],
      });

      final streamedResponse =
          await client.send(request).timeout(const Duration(seconds: 30));

      if (streamedResponse.statusCode != 200) {
        throw Exception('API error ${streamedResponse.statusCode}');
      }

      if (mounted) setState(() => _aiLoading = false);
      _startCharTimer();

      // Stateful UTF-8 decode + line splitting so multi-byte characters split
      // across a network chunk don't throw mid-stream (see chat_screen).
      await for (final line in streamedResponse.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())) {
        final trimmed = line.trim();
        if (!trimmed.startsWith('data: ')) continue;
        final data = trimmed.substring(6);
        if (data == '[DONE]') break;
        try {
          final json = jsonDecode(data);
          if (json['type'] == 'message_stop') break;
          if (json['type'] == 'content_block_delta') {
            final delta = json['delta'];
            if (delta != null && delta['type'] == 'text_delta') {
              final text = delta['text'] as String? ?? '';
              if (text.isNotEmpty) _charQueue.addAll(text.characters);
            }
          }
        } catch (_) {}
      }

      _apiStreamComplete = true;
    } catch (e) {
      // Stop the typewriter and drop any half-queued text before showing the
      // fallback, so leftover queued characters don't append onto it and the
      // periodic timer doesn't leak (it only self-cancels on a clean finish).
      _charTimer?.cancel();
      _charTimer = null;
      _charQueue.clear();
      if (mounted) {
        setState(() {
          _aiLoading = false;
          _aiExplanation =
              'John opens his gospel not with a birth story, but with eternity itself. '
              '"The Word" — in Greek, Logos — was a concept his readers already knew: '
              'the divine reason that holds all things together. John is saying that this Logos, '
              'this eternal creative force, became a person. Became Jesus. '
              'This is the most audacious claim in all of Scripture — and it changes everything.';
          _aiDone = true;
        });
      }
    } finally {
      client.close();
    }
  }

  void _startCharTimer() {
    _charTimer = Timer.periodic(const Duration(milliseconds: 16), (_) {
      if (_charQueue.isEmpty) {
        if (_apiStreamComplete && mounted) {
          _apiStreamComplete = false;
          _charTimer?.cancel();
          _charTimer = null;
          setState(() => _aiDone = true);
        }
        return;
      }
      final buf = StringBuffer();
      for (int i = 0; i < 3 && _charQueue.isNotEmpty; i++) {
        buf.write(_charQueue.removeAt(0));
      }
      if (mounted) setState(() => _aiExplanation += buf.toString());
    });
  }

  // ── Navigation ──────────────────────────────────────────────────────────────

  void _nextPage() {
    if (_currentPage < 3) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
      setState(() => _currentPage++);
    }
  }

  bool _trialLoading = false;

  Future<void> _startTrial() async {
    if (_trialLoading) return;
    setState(() => _trialLoading = true);
    try {
      final result =
          await RevenueCatUI.presentPaywall(displayCloseButton: true);
      if (!mounted) return;
      if (result == PaywallResult.purchased ||
          result == PaywallResult.restored) {
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
                      _buildAhaPage(t),
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

  // ── Page 2: Aha Moment ──────────────────────────────────────────────────────

  Widget _buildAhaPage(WaypointThemeData t) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          Text(
            'See what Waypoint can do',
            style: TextStyle(
              fontFamily: 'Georgia',
              fontSize: 13,
              color: t.textSecondary,
              letterSpacing: 0.5,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),

          // Verse card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [t.primary, t.secondary],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: t.primary.withValues(alpha: 0.25),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _onboardingVerseText,
                  style: TextStyle(
                    fontFamily: 'Georgia',
                    color: t.onPrimary,
                    fontSize: 17,
                    height: 1.6,
                    fontStyle: FontStyle.italic,
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: t.onPrimary.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _onboardingVerse,
                    style: TextStyle(
                      fontFamily: 'Georgia',
                      color: t.onPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // AI response area
          Container(
            width: double.infinity,
            constraints: const BoxConstraints(minHeight: 120),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: t.cardBg.withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: t.cardBorder),
            ),
            child: _aiLoading
                ? _OnboardingDots()
                : _aiExplanation.isEmpty
                    ? _OnboardingDots()
                    : Text(
                        _aiExplanation,
                        style: TextStyle(
                          fontFamily: 'Georgia',
                          fontSize: 15,
                          color: t.textPrimary,
                          height: 1.7,
                        ),
                      ),
          ),

          const SizedBox(height: 28),

          if (_aiDone)
            _PrimaryButton(
              label: 'This is incredible →',
              onTap: _nextPage,
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
            'Make it yours',
            style: TextStyle(
              fontFamily: 'Georgia',
              fontSize: 26,
              fontWeight: FontWeight.bold,
              color: t.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'One quick question and you\'re in.',
            style: TextStyle(
              fontFamily: 'Georgia',
              fontSize: 15,
              color: t.textSecondary,
            ),
          ),

          const SizedBox(height: 28),

          Text(
            'Your faith background',
            style: TextStyle(
              fontFamily: 'Georgia',
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: t.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'If you\'re unsure, select Non-denominational to start.',
            style: TextStyle(
              fontFamily: 'Georgia',
              fontSize: 13,
              color: t.textSecondary,
            ),
          ),
          const SizedBox(height: 12),

          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: kDenominations.map((d) {
              final selected = _selectedDenomination == d;
              return GestureDetector(
                onTap: () => setState(() => _selectedDenomination = d),
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

          _PrimaryButton(
            label: 'Almost there →',
            onTap: _selectedDenomination != null ? _nextPage : null,
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
            'Free for 7 days, then \$6.99/month.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Georgia',
              fontSize: 13,
              color: t.textHint,
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

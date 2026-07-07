import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:purchases_ui_flutter/purchases_ui_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../constants.dart';
import '../data/daily_verses.dart';
import '../services/analytics_service.dart';
import '../services/companion_prompt.dart';
import '../services/message_limit_service.dart';
import '../services/revenue_cat_service.dart';
import '../services/haptic_service.dart';
import '../services/review_service.dart';
import '../theme/app_theme.dart';
import '../widgets/waypoint_tooltip.dart';

// ── Data model ────────────────────────────────────────────────────────────────

class ChatMessage {
  String text;
  final bool isUser;
  final DateTime timestamp;

  ChatMessage({
    required this.text,
    required this.isUser,
    required this.timestamp,
  });
}

// ── Screen ────────────────────────────────────────────────────────────────────

class ChatScreen extends StatefulWidget {
  final SharedPreferences prefs;
  const ChatScreen({super.key, required this.prefs});

  @override
  State<ChatScreen> createState() => ChatScreenState();
}

class ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  final List<ChatMessage> _messages = [];
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<Map<String, String>> _conversationHistory = [];
  bool _isLoading = false;

  // ── Daily limit state ───────────────────────────────────────────────────────
  bool _isLimited = false;
  bool _paywallShownThisSession = false;

  // ── Follow-up chips ─────────────────────────────────────────────────────────
  List<String> _followUpChips = [];

  static const _kVerseChips = [
    'What\'s the historical context?',
    'How do I apply this today?',
    'Any related verses on this?',
  ];
  static const _kGeneralChips = [
    'Tell me more',
    'How does this apply to my life?',
    'What does Scripture say about this?',
  ];
  static final _kVersePattern = RegExp(r'\b\d?\s*[A-Z][a-z]+\s+\d+:\d+\b');

  void _generateFollowUpChips(String response) {
    final chips = _kVersePattern.hasMatch(response) ? _kVerseChips : _kGeneralChips;
    if (mounted) setState(() => _followUpChips = List.from(chips));
  }

  void _clearChips() {
    if (_followUpChips.isNotEmpty) setState(() => _followUpChips = []);
  }

  final List<String> _charQueue = [];
  Timer? _charTimer;
  ChatMessage? _streamingMessage;
  bool _apiStreamComplete = false;
  static const _charDelay = Duration(milliseconds: 18);

  void _startCharTimer() {
    _charTimer?.cancel();
    _charTimer = Timer.periodic(_charDelay, (_) {
      if (_charQueue.isEmpty) {
        if (_apiStreamComplete) {
          _apiStreamComplete = false;
          _stopCharTimer();
          setState(() => _streamingMessage = null);
          _scrollToBottom();
        }
        return;
      }
      final buf = StringBuffer();
      for (int i = 0; i < 3 && _charQueue.isNotEmpty; i++) {
        buf.write(_charQueue.removeAt(0));
      }
      setState(() {
        _streamingMessage?.text += buf.toString();
      });
      if (_streamingMessage != null &&
          _streamingMessage!.text.length % 10 == 0) {
        _scrollToBottom();
      }
    });
  }

  void _stopCharTimer() {
    _charTimer?.cancel();
    _charTimer = null;
  }

  void _enqueueText(String text) {
    _charQueue.addAll(text.characters);
    if (_charTimer == null || !_charTimer!.isActive) {
      _startCharTimer();
    }
  }

  static const _kSessionKey = kChatSessionKey;
  static const _kSessionMaxPairs = 10;

  void _saveChatSession() {
    final history = _conversationHistory;
    final toSave = history.length > _kSessionMaxPairs * 2
        ? history.sublist(history.length - _kSessionMaxPairs * 2)
        : history;
    widget.prefs.setString(_kSessionKey, jsonEncode(toSave));
  }

  void _loadChatSession() {
    final raw = widget.prefs.getString(_kSessionKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      for (final e in list) {
        final entry = Map<String, String>.from(e as Map);
        _conversationHistory.add(entry);
        _messages.add(ChatMessage(
          text: entry['content'] ?? '',
          isUser: entry['role'] == 'user',
          timestamp: DateTime.now(),
        ));
      }
    } catch (_) {}
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadChatSession();
    _inputController.addListener(() {
      if (_inputController.text.isNotEmpty) _clearChips();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkPendingPrompt());
    _refreshProAndLimits();
  }

  void sendPrompt(String prompt) {
    if (_isLoading) return;
    _sendMessageWithText(prompt);
  }

  void _checkPendingPrompt() {
    final pending = widget.prefs.getString('pending_prompt');
    if (pending != null && pending.isNotEmpty) {
      widget.prefs.remove('pending_prompt');
      _inputController.text = pending;
      _sendMessage();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkPendingPrompt();
      // Spec: check entitlement on every session resume — subscriptions can
      // lapse mid-day and purchases can be made outside the app.
      _refreshProAndLimits();
    }
  }

  /// Fetches a fresh RevenueCat entitlement and recalculates the daily limit
  /// state. Defaults to restricted if the network call fails (spec requirement).
  Future<void> _refreshProAndLimits() async {
    bool isPro = false;
    try {
      isPro = await RevenueCatService.isProUser();
    } catch (_) {
      // Network failure → default to restricted, never grant free access.
      isPro = false;
    }
    if (!mounted) return;
    if (isPro) setState(() => _isLimited = false);
    if (isPro) return;

    final day1 = await MessageLimitService.isDay1();
    if (!mounted) return;
    if (day1) {
      setState(() => _isLimited = false);
      return;
    }
    final count = await MessageLimitService.refreshAndGetCount();
    if (!mounted) return;
    setState(() => _isLimited = count >= MessageLimitService.dailyFreeLimit);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _charTimer?.cancel();
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _sendMessage() async {
    final text = _inputController.text.trim();
    if (text.isEmpty || _isLoading) return;
    await _sendMessageWithText(text);
    _inputController.clear();
  }

  Future<void> _sendMessageWithText(String text) async {
    if (text.isEmpty || _isLoading) return;
    HapticService.light();
    _clearChips();

    // Lock the UI immediately to prevent double-sends during async checks.
    setState(() => _isLoading = true);

    // Fresh entitlement check on every send. Defaults to restricted on error.
    bool isPro = false;
    try {
      isPro = await RevenueCatService.isProUser();
    } catch (_) {
      isPro = false;
    }
    if (!mounted) return;

    // Gate check for free users.
    if (!isPro) {
      final allowed = await MessageLimitService.canSendMessage();
      if (!mounted) return;
      if (!allowed) {
        setState(() {
          _isLoading = false;
          _isLimited = true;
        });
        return;
      }
    }

    // Capture day-1 status once so it stays consistent for this send cycle.
    final isDay1 = isPro ? false : await MessageLimitService.isDay1();
    if (!mounted) return;

    setState(() {
      _messages.add(ChatMessage(
        text: text,
        isUser: true,
        timestamp: DateTime.now(),
      ));
      // _isLoading already true
    });

    _scrollToBottom();
    _conversationHistory.add({'role': 'user', 'content': text});
    // Fires once per user, ever (guarded inside AnalyticsService). Reached only
    // after the daily-limit gate passed, so a blocked send never counts.
    AnalyticsService.instance.firstQuestionAsked();

    final aiMessage = ChatMessage(
      text: '',
      isUser: false,
      timestamp: DateTime.now(),
    );
    setState(() => _messages.add(aiMessage));
    _streamingMessage = aiMessage;

    // Record the message NOW — before awaiting the response — so an app-kill
    // between send and response still consumes the daily quota (spec requirement).
    if (!isPro && !isDay1) {
      await MessageLimitService.recordMessageSent();
    }

    try {
      final fullResponse = await _streamAnthropicApi(
        onChunk: (chunk) => _enqueueText(chunk),
      );

      _apiStreamComplete = true;
      // Aha-moment signal: the response stream completed successfully. This call
      // is fully guarded and cannot throw back into the stream path.
      AnalyticsService.instance.answerReceived(success: true);
      _conversationHistory.add({'role': 'assistant', 'content': fullResponse});
      _saveChatSession();
      _generateFollowUpChips(fullResponse);

      // After the full response is displayed, check whether the limit is now
      // reached and show the paywall sheet once per session.
      if (!isPro && !isDay1 && mounted) {
        final count = await MessageLimitService.refreshAndGetCount();
        if (mounted) {
          final nowLimited = count >= MessageLimitService.dailyFreeLimit;
          setState(() => _isLimited = nowLimited);
          if (nowLimited && !_paywallShownThisSession) {
            _paywallShownThisSession = true;
            WidgetsBinding.instance
                .addPostFrameCallback((_) => _showPaywallSheet());
          }
        }
      }

      final chatCount = (widget.prefs.getInt('chat_count') ?? 0) + 1;
      widget.prefs.setInt('chat_count', chatCount);
      ReviewService.maybeRequestAfterChat(widget.prefs);
      if (mounted) setState(() => _isLoading = false);
      _scrollToBottom();
    } catch (e) {
      _stopCharTimer();
      _charQueue.clear();
      _apiStreamComplete = false;
      _streamingMessage = null;
      AnalyticsService.instance.answerReceived(success: false);
      final receivedContent = aiMessage.text.isNotEmpty;
      if (mounted) {
        setState(() {
          if (aiMessage.text.isEmpty) aiMessage.text = _friendlyErrorMessage(e);
          _isLoading = false;
        });
      }
      if (_conversationHistory.isNotEmpty) _conversationHistory.removeLast();
      // The message was charged against the daily quota before sending (to
      // survive app-kill). If the request failed before any answer streamed,
      // hand that message back so a network blip doesn't cost a free user one
      // of their two daily conversations for nothing.
      if (!isPro && !isDay1 && !receivedContent) {
        await MessageLimitService.recordMessageRefund();
        final count = await MessageLimitService.refreshAndGetCount();
        if (mounted) {
          setState(() =>
              _isLimited = count >= MessageLimitService.dailyFreeLimit);
        }
      }
      _scrollToBottom();
    }
  }

  /// Shows the Pro paywall as a bottom sheet — natural continuation, not a
  /// hard navigation push. Only shown once per session after dismissal.
  void _showPaywallSheet() {
    if (!mounted) return;
    final t = WaypointTheme.of(context);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => _CompanionPaywallSheet(
        t: t,
        onProUnlocked: () {
          Navigator.of(sheetCtx).pop();
          if (mounted) setState(() => _isLimited = false);
        },
        onDismiss: () => Navigator.of(sheetCtx).pop(),
      ),
    );
  }

  Future<String> _streamAnthropicApi({
    required void Function(String chunk) onChunk,
  }) async {
    final denomination = widget.prefs.getString('user_denomination');
    final client = http.Client();
    final fullBuffer = StringBuffer();

    try {
      final request = http.Request('POST', Uri.parse(kAnthropicApiUrl));

      request.headers.addAll({
        'Content-Type': 'application/json',
        'x-api-key': kAnthropicApiKey,
        'anthropic-version': '2023-06-01',
      });

      final rawHistory = _conversationHistory.length > 20
          ? _conversationHistory.sublist(_conversationHistory.length - 20)
          : _conversationHistory;

      // Prompt caching: the system prompt alone is well under Sonnet's 2048-
      // token cache-write minimum, so a marker there alone would silently do
      // nothing. Instead, mark the last message in the (stateless, fully
      // resent) history — that caches the whole rendered prefix (system + all
      // prior turns) as one unit. The prefix grows every turn, so within a
      // conversation it clears the threshold and gets cheaper as it goes.
      final historyToSend = <Map<String, dynamic>>[
        for (var i = 0; i < rawHistory.length; i++)
          if (i == rawHistory.length - 1)
            {
              'role': rawHistory[i]['role'],
              'content': [
                {
                  'type': 'text',
                  'text': rawHistory[i]['content'],
                  'cache_control': {'type': 'ephemeral'},
                }
              ],
            }
          else
            rawHistory[i],
      ];

      request.body = jsonEncode({
        'model': kAnthropicModel,
        // The system prompt targets ~350-400 words (~550-600 tokens) per
        // reply; 1024 gives headroom for a well-developed answer without
        // leaving the door open to an 8000+ token runaway that used to take
        // four "continue"s to even fully render.
        'max_tokens': 1024,
        'stream': true,
        'system': buildCompanionSystemPrompt(denomination),
        'messages': historyToSend,
      });

      final streamedResponse = await client.send(request)
          .timeout(const Duration(seconds: 30));

      if (streamedResponse.statusCode == 401) {
        throw Exception('invalid_api_key');
      } else if (streamedResponse.statusCode == 429) {
        throw Exception('rate_limited');
      } else if (streamedResponse.statusCode != 200) {
        throw Exception('api_error_${streamedResponse.statusCode}');
      }

      // Decode the byte stream with the stateful UTF-8 decoder + LineSplitter so
      // multi-byte characters (smart quotes, em-dashes, emoji) that straddle a
      // network chunk boundary are reassembled correctly. Calling utf8.decode()
      // on each raw chunk throws on a split sequence and aborts the response.
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
              if (text.isNotEmpty) {
                onChunk(text);
                fullBuffer.write(text);
              }
            }
          }
        } catch (_) {
          // skip malformed lines
        }
      }
    } finally {
      client.close();
    }

    return fullBuffer.toString();
  }

  String _friendlyErrorMessage(Object e) {
    final msg = e.toString();
    if (msg.contains('invalid_api_key')) {
      return "There's an issue with the API key. Please check your settings.";
    } else if (msg.contains('rate_limited')) {
      return "Getting a lot of requests right now. Please wait a moment and try again.";
    } else if (msg.contains('TimeoutException') ||
        msg.contains('SocketException') ||
        msg.contains('Failed host lookup') ||
        msg.contains('Network is unreachable')) {
      return "You appear to be offline. Please check your connection and try again.";
    }
    return "Something went wrong. Please try again in a moment.";
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _clearConversation() {
    final t = WaypointTheme.of(context);
    showDialog(
      context: context,
      builder: (dialogCtx) {
        return AlertDialog(
          backgroundColor: t.cardBg,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(
            'Start a new conversation?',
            style: TextStyle(
              fontFamily: 'Georgia',
              fontSize: 18,
              color: t.textPrimary,
            ),
          ),
          content: Text(
            'This will clear your current conversation.',
            style: TextStyle(
              fontFamily: 'Georgia',
              fontSize: 14,
              color: t.textSecondary,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: Text(
                'Cancel',
                style: TextStyle(
                  fontFamily: 'Georgia',
                  color: t.textSecondary,
                ),
              ),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(dialogCtx);
                _stopCharTimer();
                _charQueue.clear();
                _apiStreamComplete = false;
                _streamingMessage = null;
                widget.prefs.remove(_kSessionKey);
                setState(() {
                  _messages.clear();
                  _conversationHistory.clear();
                  _isLoading = false;
                  _followUpChips = [];
                });
              },
              child: Text(
                'Start fresh',
                style: TextStyle(
                  fontFamily: 'Georgia',
                  color: t.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = WaypointTheme.of(context);
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        title: Text(
          'Companion',
          style: TextStyle(
            fontFamily: 'Georgia',
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: t.textPrimary,
          ),
        ),
        actions: [
          GestureDetector(
            onTap: _isLoading ? null : _clearConversation,
            child: Container(
              margin: const EdgeInsets.only(right: 16),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: t.cardBg.withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: t.cardBorder),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.add, size: 14, color: t.primary),
                  const SizedBox(width: 4),
                  Text(
                    'New',
                    style: TextStyle(
                      fontFamily: 'Georgia',
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: t.primary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(painter: _ChatBackgroundPainter(t)),
          ),
          SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: Stack(
                    children: [
                      ListView.builder(
                        controller: _scrollController,
                        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                        itemCount: _messages.length,
                        itemBuilder: (context, index) {
                          final message = _messages[index];
                          final isStreaming = _isLoading && message == _streamingMessage;
                          return _MessageBubble(message: message, isStreaming: isStreaming, t: t);
                        },
                      ),
                      if (_messages.isEmpty)
                        _VerseOfDayEmpty(
                          t: t,
                          onTap: (ref) {
                            _inputController.text = 'Tell me about $ref';
                          },
                        ),
                      WaypointTooltipBubble(
                        prefKey: 'tooltip_seen_chat',
                        message: 'Ask me anything — a verse, a feeling, or a question about faith',
                        prefs: widget.prefs,
                        alignment: Alignment.bottomCenter,
                      ),
                    ],
                  ),
                ),
                if (_followUpChips.isNotEmpty && !_isLoading)
                  _FollowUpChipsRow(
                    chips: _followUpChips,
                    t: t,
                    onTap: (chip) {
                      HapticService.selection();
                      _clearChips();
                      _sendMessageWithText(chip);
                    },
                  ),
                _InputBar(
                  controller: _inputController,
                  isLoading: _isLoading,
                  isLimited: _isLimited,
                  onSend: _sendMessage,
                  t: t,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Background painter ────────────────────────────────────────────────────────

class _ChatBackgroundPainter extends CustomPainter {
  final WaypointThemeData t;
  _ChatBackgroundPainter(this.t);

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
    const radius = 1.5;
    for (double x = 0; x < size.width + spacing; x += spacing) {
      for (double y = 0; y < size.height + spacing; y += spacing) {
        canvas.drawCircle(Offset(x, y), radius, dotPaint);
      }
    }

    final arcPaint = Paint()
      ..color = t.primary.withValues(alpha: 0.04)
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
  bool shouldRepaint(_ChatBackgroundPainter old) => old.t != t;
}

// ── Message bubble ────────────────────────────────────────────────────────────

class _MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final bool isStreaming;
  final WaypointThemeData t;
  const _MessageBubble({required this.message, this.isStreaming = false, required this.t});

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
              decoration: BoxDecoration(
                gradient: isUser
                    ? LinearGradient(
                        colors: [t.primary, t.secondary],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      )
                    : null,
                color: isUser ? null : t.cardBg.withValues(alpha: 0.9),
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(18),
                  topRight: const Radius.circular(18),
                  bottomLeft: Radius.circular(isUser ? 18 : 4),
                  bottomRight: Radius.circular(isUser ? 4 : 18),
                ),
                border: isUser
                    ? null
                    : Border.all(color: t.cardBorder),
                boxShadow: [
                  BoxShadow(
                    color: isUser
                        ? t.primary.withValues(alpha: 0.2)
                        : Colors.black.withValues(alpha: 0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: isStreaming && message.text.isEmpty
                  ? _DotsInBubble(t: t)
                  : isStreaming
                      ? _StreamingText(text: message.text, t: t)
                      : Text(
                          message.text,
                          style: TextStyle(
                            fontFamily: 'Georgia',
                            fontSize: 15,
                            height: 1.6,
                            color: isUser ? t.onPrimary : t.textPrimary,
                          ),
                        ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DotsInBubble extends StatefulWidget {
  final WaypointThemeData t;
  const _DotsInBubble({required this.t});

  @override
  State<_DotsInBubble> createState() => _DotsInBubbleState();
}

class _DotsInBubbleState extends State<_DotsInBubble>
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
                    color: widget.t.primary,
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

class _StreamingText extends StatefulWidget {
  final String text;
  final WaypointThemeData t;
  const _StreamingText({required this.text, required this.t});

  @override
  State<_StreamingText> createState() => _StreamingTextState();
}

class _StreamingTextState extends State<_StreamingText>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        children: [
          TextSpan(
            text: widget.text,
            style: TextStyle(
              fontFamily: 'Georgia',
              fontSize: 15,
              height: 1.6,
              color: widget.t.textPrimary,
            ),
          ),
          WidgetSpan(
            child: FadeTransition(
              opacity: _controller,
              child: Container(
                width: 2,
                height: 16,
                margin: const EdgeInsets.only(left: 1, bottom: 1),
                decoration: BoxDecoration(
                  color: widget.t.primary,
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Verse of the day empty state ──────────────────────────────────────────────

class _VerseOfDayEmpty extends StatelessWidget {
  final WaypointThemeData t;
  final void Function(String ref) onTap;
  const _VerseOfDayEmpty({required this.t, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final dayOfYear = now.difference(DateTime(now.year, 1, 1)).inDays;
    final verse = kDailyVerses[dayOfYear % kDailyVerses.length];
    final ref = verse['ref']!;
    final text = verse['text']!;

    return Center(
      child: GestureDetector(
        onTap: () => onTap(ref),
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Today',
                style: TextStyle(
                  fontFamily: 'Georgia',
                  fontSize: 11,
                  letterSpacing: 2.0,
                  color: t.textHint,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                '“$text”',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Georgia',
                  fontSize: 16,
                  height: 1.7,
                  fontStyle: FontStyle.italic,
                  color: t.textPrimary.withValues(alpha: 0.75),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                ref,
                style: TextStyle(
                  fontFamily: 'Georgia',
                  fontSize: 13,
                  color: t.primary.withValues(alpha: 0.7),
                  letterSpacing: 0.3,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'tap to explore',
                style: TextStyle(
                  fontFamily: 'Georgia',
                  fontSize: 11,
                  letterSpacing: 1.2,
                  color: t.textHint.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Follow-up chips ───────────────────────────────────────────────────────────

class _FollowUpChipsRow extends StatelessWidget {
  final List<String> chips;
  final WaypointThemeData t;
  final void Function(String chip) onTap;

  const _FollowUpChipsRow({
    required this.chips,
    required this.t,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: chips.map((chip) => Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => onTap(chip),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: t.cardBg.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: t.primary.withValues(alpha: 0.35)),
                ),
                child: Text(
                  chip,
                  style: TextStyle(
                    fontFamily: 'Georgia',
                    fontSize: 13,
                    color: t.primary,
                  ),
                ),
              ),
            ),
          )).toList(),
        ),
      ),
    );
  }
}

// ── Input bar ─────────────────────────────────────────────────────────────────

class _InputBar extends StatelessWidget {
  final TextEditingController controller;
  final bool isLoading;
  final bool isLimited;
  final VoidCallback onSend;
  final WaypointThemeData t;

  const _InputBar({
    required this.controller,
    required this.isLoading,
    required this.isLimited,
    required this.onSend,
    required this.t,
  });

  @override
  Widget build(BuildContext context) {
    final isDisabled = isLoading || isLimited;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
      decoration: BoxDecoration(
        color: t.cardBg.withValues(alpha: 0.85),
        border: Border(top: BorderSide(color: t.cardBorder)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isLimited)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                '2 free conversations used today. Come back tomorrow or go Pro for unlimited.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Georgia',
                  fontSize: 12,
                  color: t.textHint,
                ),
              ),
            ),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  enabled: !isDisabled,
                  maxLines: null,
                  keyboardType: TextInputType.multiline,
                  textCapitalization: TextCapitalization.sentences,
                  autocorrect: false,
                  enableSuggestions: false,
                  style: TextStyle(
                    fontFamily: 'Georgia',
                    fontSize: 15,
                    color: isLimited ? t.textHint : t.textPrimary,
                  ),
                  decoration: InputDecoration(
                    hintText: isLimited
                        ? '2 free conversations used today'
                        : 'Ask anything about Scripture...',
                    hintStyle: TextStyle(
                      fontFamily: 'Georgia',
                      color: t.textHint,
                      fontSize: 14,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide.none,
                    ),
                    filled: true,
                    fillColor: isLimited ? t.unearnedBg : t.inputFill,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  ),
                  onSubmitted: isDisabled ? null : (_) => onSend(),
                ),
              ),
              const SizedBox(width: 10),
              GestureDetector(
                onTap: isDisabled ? null : onSend,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    gradient: isDisabled
                        ? null
                        : LinearGradient(
                            colors: [t.primary, t.secondary],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                    color: isDisabled ? t.textHint : null,
                    shape: BoxShape.circle,
                    boxShadow: isDisabled
                        ? []
                        : [
                            BoxShadow(
                              color: t.primary.withValues(alpha: 0.3),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ],
                  ),
                  child: Icon(
                    isLoading ? Icons.hourglass_empty : Icons.send_rounded,
                    color: isDisabled ? t.background : t.onPrimary,
                    size: 20,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Pro paywall bottom sheet ───────────────────────────────────────────────────

class _CompanionPaywallSheet extends StatefulWidget {
  final WaypointThemeData t;
  final VoidCallback onProUnlocked;
  final VoidCallback onDismiss;

  const _CompanionPaywallSheet({
    required this.t,
    required this.onProUnlocked,
    required this.onDismiss,
  });

  @override
  State<_CompanionPaywallSheet> createState() => _CompanionPaywallSheetState();
}

class _CompanionPaywallSheetState extends State<_CompanionPaywallSheet> {
  bool _busy = false;

  Future<void> _startTrial() async {
    setState(() => _busy = true);
    try {
      AnalyticsService.instance.paywallViewed();
      final result =
          await RevenueCatUI.presentPaywall(displayCloseButton: true);
      if (!mounted) return;
      if (result == PaywallResult.purchased ||
          result == PaywallResult.restored) {
        unawaited(AnalyticsService.instance.onProUnlocked(
          startedTrial: result == PaywallResult.purchased,
        ));
        widget.onProUnlocked();
      } else {
        setState(() => _busy = false);
      }
    } catch (_) {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restorePurchase() async {
    setState(() => _busy = true);
    try {
      final restored = await RevenueCatService.restorePurchases();
      if (!mounted) return;
      if (restored) {
        // Restore stitches identity but is not a new trial.
        unawaited(AnalyticsService.instance.onProUnlocked(startedTrial: false));
        widget.onProUnlocked();
      } else {
        setState(() => _busy = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'No active subscription found.',
                style: TextStyle(fontFamily: 'Georgia'),
              ),
            ),
          );
        }
      }
    } catch (_) {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    return Container(
      decoration: BoxDecoration(
        color: t.cardBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
        24,
        20,
        24,
        MediaQuery.of(context).viewInsets.bottom + 40,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: t.cardBorder,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 24),
          // Icon
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [t.primary, t.secondary],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.auto_awesome, color: t.onPrimary, size: 30),
          ),
          const SizedBox(height: 16),
          Text(
            'Go Pro for Unlimited Access',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Georgia',
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: t.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            "You've used your 2 free conversations today.\nUnlock unlimited Companion chats with Waypoint Pro.",
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Georgia',
              fontSize: 14,
              height: 1.6,
              color: t.textSecondary,
            ),
          ),
          const SizedBox(height: 28),
          // Primary CTA
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _busy ? null : _startTrial,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24)),
                backgroundColor: t.primary,
                foregroundColor: t.onPrimary,
                disabledBackgroundColor: t.textHint,
              ),
              child: _busy
                  ? SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                          color: t.onPrimary, strokeWidth: 2),
                    )
                  : const Text(
                      'Start 7 Days Free',
                      style: TextStyle(
                        fontFamily: 'Georgia',
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _busy ? null : _restorePurchase,
            child: Text(
              'Restore Purchase',
              style: TextStyle(
                fontFamily: 'Georgia',
                fontSize: 13,
                color: t.textSecondary,
              ),
            ),
          ),
          TextButton(
            onPressed: widget.onDismiss,
            child: Text(
              'Maybe later',
              style: TextStyle(
                fontFamily: 'Georgia',
                fontSize: 13,
                color: t.textHint,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/daily_verses.dart';
import '../data/reading_plans.dart';
import '../data/bible_studies.dart';
import '../services/widget_update_service.dart';
import '../theme/app_theme.dart';
import '../widgets/waypoint_tooltip.dart';
import 'reading_plans_screen.dart';
import 'bible_studies_screen.dart';

class HomeScreen extends StatefulWidget {
  final SharedPreferences prefs;
  final VoidCallback onNavigateToChat;
  final VoidCallback onNavigateToBible;
  final VoidCallback onNavigateToHub;
  final void Function(String prompt) onPromptSelected;
  final VoidCallback onNavigateToSearch;

  const HomeScreen({
    super.key,
    required this.prefs,
    required this.onNavigateToChat,
    required this.onNavigateToBible,
    required this.onNavigateToHub,
    required this.onPromptSelected,
    required this.onNavigateToSearch,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _streak = 0;
  bool _welcomeBack = false;
  late Map<String, String> _todayVerse;

  static const List<Map<String, String>> _promptPool = [
    {'label': 'Where should I start reading?', 'prompt': 'I\'m not sure where to start reading the Bible. Can you help me figure out where to begin?'},
    {'label': 'Help me understand a verse', 'prompt': 'I\'d like help understanding a Bible verse. Can you walk me through what it means?'},
    {'label': 'I have a question about faith', 'prompt': 'I have a question about faith that I\'ve been thinking about. Can you help me think through it?'},
    {'label': 'Does the Old Testament point to Jesus?', 'prompt': 'Does the Old Testament point to Jesus? I\'d love to understand how the Hebrew Scriptures anticipate Christ.'},
    {'label': 'What is the gospel in one sentence?', 'prompt': 'What is the gospel? Can you summarize it in one sentence?'},
    {'label': 'Who wrote the Bible?', 'prompt': 'Who wrote the Bible? I\'m curious about its human authors and how it came together.'},
    {'label': 'What did Jesus mean by Kingdom of God?', 'prompt': 'What did Jesus mean by the Kingdom of God? He talked about it constantly — what was he describing?'},
    {'label': 'Why are there four Gospels?', 'prompt': 'Why are there four Gospels? Why did the early church preserve four accounts instead of one?'},
    {'label': 'What is grace?', 'prompt': 'What is grace? I hear the word a lot in church but want to understand what it really means.'},
    {'label': 'Who was Paul before he met Jesus?', 'prompt': 'Who was Paul before he met Jesus? What was his background and why does it matter?'},
    {'label': 'What is the Holy Spirit?', 'prompt': 'What is the Holy Spirit? I want to understand who the Spirit is and what the Spirit does.'},
    {'label': 'Did the disciples doubt Jesus?', 'prompt': 'Did the disciples doubt Jesus? I\'m curious whether they really believed or struggled like I do.'},
    {'label': 'What does it mean to be saved?', 'prompt': 'What does it mean to be saved? I want to understand salvation beyond just a simple answer.'},
    {'label': 'Why did Jesus speak in parables?', 'prompt': 'Why did Jesus speak in parables? What was he trying to accomplish by teaching that way?'},
    {'label': 'What happened between the Testaments?', 'prompt': 'What happened between the Old and New Testaments? There\'s a 400-year gap — what went on?'},
    {'label': 'What happened to Lazarus after death?', 'prompt': 'What happened to Lazarus after Jesus raised him from the dead? Does the Bible tell us?'},
    {'label': 'What became of Jesus\' disciples?', 'prompt': 'What happened to the disciples after Jesus died and rose? Where did they go and what did they do?'},
    {'label': 'Why did God choose Abraham?', 'prompt': 'Why did God choose Abraham? What made him significant and why does his story matter so much?'},
    {'label': 'What is the armor of God?', 'prompt': 'What is the armor of God from Ephesians 6? What does each piece represent?'},
    {'label': 'Who was Melchizedek?', 'prompt': 'Who was Melchizedek? He appears briefly in Genesis and Hebrews keeps referring back to him.'},
  ];

  List<Map<String, String>> _selectedPrompts = [];

  @override
  void initState() {
    super.initState();
    _todayVerse = getDailyVerse();
    _selectPrompts();
    _updateStreak();
  }

  String _greeting() {
    if (_welcomeBack) return 'Good to see you again.';
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning.';
    if (hour < 17) return 'Good afternoon.';
    return 'Good evening.';
  }

  void _navigateToPlan(BuildContext context, ReadingPlan plan, int currentDay) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ReadingPlanDetailScreen(
          plan: plan,
          currentDay: currentDay,
          prefs: widget.prefs,
          onPromptSelected: widget.onPromptSelected,
          onProgressUpdate: (day) {
            try {
              final raw = widget.prefs.getString('reading_plan_progress') ?? '{}';
              final map = (jsonDecode(raw) as Map<String, dynamic>)
                  .map((k, v) => MapEntry(k, v as int));
              map[plan.id] = day;
              widget.prefs.setString('reading_plan_progress', jsonEncode(map));
            } catch (_) {}
            if (day >= plan.totalDays) {
              final badges = widget.prefs.getStringList('earned_badges') ?? [];
              if (!badges.contains('plan_${plan.id}')) {
                badges.add('plan_${plan.id}');
                widget.prefs.setStringList('earned_badges', badges);
              }
            }
          },
        ),
      ),
    ).then((_) {
      if (mounted) setState(() {});
    });
  }

  void _navigateToStudy(BuildContext context, BibleStudy study, int currentDay) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StudyDetailScreen(
          study: study,
          currentDay: currentDay,
          prefs: widget.prefs,
          onPromptSelected: widget.onPromptSelected,
          onProgressUpdate: (day) {
            try {
              final raw = widget.prefs.getString('study_progress') ?? '{}';
              final map = (jsonDecode(raw) as Map<String, dynamic>)
                  .map((k, v) => MapEntry(k, v as int));
              map[study.id] = day;
              widget.prefs.setString('study_progress', jsonEncode(map));
            } catch (_) {}
            if (day >= study.totalDays) {
              final badges = widget.prefs.getStringList('earned_badges') ?? [];
              if (!badges.contains('study_${study.id}')) {
                badges.add('study_${study.id}');
                widget.prefs.setStringList('earned_badges', badges);
              }
            }
          },
        ),
      ),
    ).then((_) {
      if (mounted) setState(() {});
    });
  }

  void _selectPrompts() {
    final lastShown = widget.prefs.getStringList('last_shown_prompts') ?? [];
    final lastShownSet = Set<String>.from(lastShown);

    final others = _promptPool.where((p) => !lastShownSet.contains(p['label'])).toList();
    final recent = _promptPool.where((p) => lastShownSet.contains(p['label'])).toList();

    final rng = math.Random();
    others.shuffle(rng);
    recent.shuffle(rng);

    final selected = [...others, ...recent].take(3).toList();

    widget.prefs.setStringList(
      'last_shown_prompts',
      selected.map((p) => p['label']!).toList(),
    );
    _selectedPrompts = selected;
  }

  void _updateStreak() {
    final prefs = widget.prefs;
    final today = DateTime.now();
    final todayKey =
        '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
    final lastOpenKey = prefs.getString('last_open_date');
    int streak = prefs.getInt('streak') ?? 0;

    if (lastOpenKey == null) {
      streak = 1;
    } else {
      try {
        final lastOpen = DateTime.parse(lastOpenKey);
        final difference = today.difference(lastOpen).inDays;
        if (difference == 0) {
          // same day
        } else if (difference == 1) {
          streak += 1;
        } else {
          if (difference >= 3) _welcomeBack = true;
          streak = 1;
        }
      } catch (_) {
        streak = 1;
      }
    }

    prefs.setString('last_open_date', todayKey);
    prefs.setInt('streak', streak);
    setState(() => _streak = streak);
    // Push the confirmed streak to home screen widgets immediately so the
    // widget never shows a stale value from the previous session.
    WidgetUpdateService.pushStreakOnly(prefs);
  }

  List<_DayCircleData> _buildWeekData() {
    final today = DateTime.now();
    final List<_DayCircleData> days = [];

    for (int i = -3; i <= 3; i++) {
      final day = today.add(Duration(days: i));
      final isToday = i == 0;
      final isFuture = i > 0;
      final isPast = i < 0;

      bool hit = false;
      if (isToday) {
        hit = true;
      } else if (isPast) {
        hit = (_streak - 1) >= (-i);
      }

      days.add(_DayCircleData(
        day: day.day,
        isToday: isToday,
        isFuture: isFuture,
        hit: hit,
      ));
    }

    return days;
  }

  void _openChatWithPrompt(BuildContext context, String prompt) {
    widget.onPromptSelected(prompt);
  }

  @override
  Widget build(BuildContext context) {
    final t = WaypointTheme.of(context);
    final weekData = _buildWeekData();

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        title: Text(
          _greeting(),
          style: TextStyle(
            fontFamily: 'Georgia',
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: t.textPrimary,
          ),
        ),
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(painter: _BackgroundPainter(t)),
          ),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [

                  // ── Verse of the Day ────────────────────────
                  GestureDetector(
                    onTap: () {
                      final ref = _todayVerse['ref']!;
                      final text = _todayVerse['text']!;
                      widget.onPromptSelected(
                        'Today\'s verse is $ref: "$text" — '
                        'Can you help me reflect on what this means and how I can carry it with me today?',
                      );
                    },
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(16, 18, 18, 14),
                      decoration: BoxDecoration(
                        color: t.cardBg.withValues(alpha: 0.92),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: t.cardBorder),
                        boxShadow: [
                          BoxShadow(
                            color: t.primary.withValues(alpha: 0.08),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Container(
                              width: 4,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [t.primary, t.secondary],
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                ),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(Icons.wb_sunny_outlined,
                                          color: t.primary, size: 13),
                                      const SizedBox(width: 5),
                                      Text(
                                        'VERSE OF THE DAY',
                                        style: TextStyle(
                                          fontFamily: 'Georgia',
                                          color: t.primary,
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          letterSpacing: 1.1,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    '"${_todayVerse['text']}"',
                                    style: TextStyle(
                                      fontFamily: 'Georgia',
                                      color: t.textPrimary,
                                      fontSize: 16,
                                      height: 1.65,
                                      fontStyle: FontStyle.italic,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        _todayVerse['ref']!,
                                        style: TextStyle(
                                          fontFamily: 'Georgia',
                                          color: t.primary,
                                          fontSize: 13,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      Text(
                                        'Discuss →',
                                        style: TextStyle(
                                          fontFamily: 'Georgia',
                                          color: t.primary,
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 14),

                  // ── Streak — seven day circles ───────────────
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 16),
                    decoration: BoxDecoration(
                      color: t.cardBg.withValues(alpha: 0.75),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                          color: t.cardBorder.withValues(alpha: 0.8)),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            RichText(
                              text: TextSpan(
                                children: [
                                  TextSpan(
                                    text: '$_streak',
                                    style: TextStyle(
                                      fontFamily: 'Georgia',
                                      fontSize: 28,
                                      fontWeight: FontWeight.bold,
                                      color: t.primary,
                                    ),
                                  ),
                                  TextSpan(
                                    text: ' day streak',
                                    style: TextStyle(
                                      fontFamily: 'Georgia',
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold,
                                      color: t.textPrimary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Icon(Icons.explore, color: t.primary, size: 20),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: weekData.map((d) => _DayCircle(data: d, t: t)).toList(),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 14),

                  // ── Prompt chips ─────────────────────────────
                  SizedBox(
                    height: 44,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _selectedPrompts.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 8),
                      itemBuilder: (context, index) {
                        final p = _selectedPrompts[index];
                        return GestureDetector(
                          onTap: () =>
                              _openChatWithPrompt(context, p['prompt']!),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 10),
                            decoration: BoxDecoration(
                              color: t.cardBg.withValues(alpha: 0.85),
                              borderRadius: BorderRadius.circular(22),
                              border: Border.all(color: t.cardBorder),
                              boxShadow: [
                                BoxShadow(
                                  color: t.primary.withValues(alpha: 0.06),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Text(
                              p['label']!,
                              style: TextStyle(
                                fontFamily: 'Georgia',
                                fontSize: 13,
                                color: t.textPrimary,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),

                  Builder(builder: (ctx) {
                    ReadingPlan? activePlan;
                    int activePlanDay = 0;
                    BibleStudy? activeStudy;
                    int activeStudyDay = 0;
                    try {
                      final raw = widget.prefs.getString('reading_plan_progress') ?? '{}';
                      final map = (jsonDecode(raw) as Map<String, dynamic>)
                          .map((k, v) => MapEntry(k, v as int));
                      for (final p in kReadingPlans) {
                        final d = map[p.id] ?? 0;
                        if (d > 0 && d < p.totalDays) {
                          activePlan = p;
                          activePlanDay = d;
                          break;
                        }
                      }
                    } catch (_) {}
                    try {
                      final raw = widget.prefs.getString('study_progress') ?? '{}';
                      final map = (jsonDecode(raw) as Map<String, dynamic>)
                          .map((k, v) => MapEntry(k, v as int));
                      for (final s in kBibleStudies) {
                        final d = map[s.id] ?? 0;
                        if (d > 0 && d < s.totalDays) {
                          activeStudy = s;
                          activeStudyDay = d;
                          break;
                        }
                      }
                    } catch (_) {}

                    if (activePlan == null && activeStudy == null) {
                      return const SizedBox(height: 24);
                    }
                    return Column(
                      children: [
                        const SizedBox(height: 14),
                        GestureDetector(
                          onTap: () => activePlan != null
                              ? _navigateToPlan(ctx, activePlan, activePlanDay)
                              : _navigateToStudy(ctx, activeStudy!, activeStudyDay),
                          child: _HomeProgressCard(
                            plan: activePlan,
                            study: activeStudy,
                            planDay: activePlanDay,
                            studyDay: activeStudyDay,
                            t: t,
                          ),
                        ),
                        const SizedBox(height: 14),
                      ],
                    );
                  }),

                  // ── Quick access grid ────────────────────────
                  Row(
                    children: [
                      Expanded(
                        child: _QuickTile(
                          icon: Icons.chat_bubble_outline,
                          title: 'Companion',
                          subtitle: 'Ask anything about faith or Scripture',
                          t: t,
                          onTap: widget.onNavigateToChat,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _QuickTile(
                          icon: Icons.menu_book_outlined,
                          title: () {
                            final book = widget.prefs.getString('bible_scroll_book');
                            return book != null ? 'Keep Reading' : 'Bible';
                          }(),
                          subtitle: () {
                            final book = widget.prefs.getString('bible_scroll_book');
                            final ch = widget.prefs.getInt('bible_scroll_chapter');
                            if (book != null && ch != null) return '$book $ch';
                            return 'Read and explore Scripture';
                          }(),
                          t: t,
                          onTap: widget.onNavigateToBible,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _QuickTile(
                          icon: Icons.search,
                          title: 'Search',
                          subtitle: 'Find verses by topic, feeling, or keyword',
                          t: t,
                          onTap: widget.onNavigateToSearch,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _QuickTile(
                          icon: Icons.emoji_events_outlined,
                          title: 'My Journey',
                          subtitle: 'Badges, highlights and journal',
                          t: t,
                          onTap: widget.onNavigateToHub,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
          WaypointTooltipBubble(
            prefKey: 'tooltip_seen_home',
            message: 'Tap any of these to start a conversation',
            prefs: widget.prefs,
            alignment: const Alignment(0, -0.16),
          ),
        ],
      ),
    );
  }
}

// ── Active progress card ──────────────────────────────────────────────────────

class _HomeProgressCard extends StatelessWidget {
  final ReadingPlan? plan;
  final BibleStudy? study;
  final int planDay;
  final int studyDay;
  final WaypointThemeData t;

  const _HomeProgressCard({
    required this.plan,
    required this.study,
    required this.planDay,
    required this.studyDay,
    required this.t,
  });

  @override
  Widget build(BuildContext context) {
    final bool isPlan = plan != null;
    final String title = isPlan ? plan!.title : study!.title;
    final int currentDay = isPlan ? planDay : studyDay;
    final int totalDays = isPlan ? plan!.totalDays : study!.totalDays;
    final IconData icon = isPlan ? plan!.iconData : study!.iconData;
    final double percent = totalDays > 0 ? currentDay / totalDays : 0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: t.accentLight,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: t.primary.withValues(alpha: 0.5), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: t.primary.withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [t.primary, t.secondary],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(icon, color: t.onPrimary, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontFamily: 'Georgia',
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: t.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      'Day $currentDay of $totalDays',
                      style: TextStyle(
                        fontFamily: 'Georgia',
                        fontSize: 12,
                        color: t.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                'Continue →',
                style: TextStyle(
                  fontFamily: 'Georgia',
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: t.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: percent,
              backgroundColor: t.progressBg,
              valueColor: AlwaysStoppedAnimation<Color>(t.primary),
              minHeight: 5,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Day circle data ───────────────────────────────────────────────────────────

class _DayCircleData {
  final int day;
  final bool isToday;
  final bool isFuture;
  final bool hit;

  const _DayCircleData({
    required this.day,
    required this.isToday,
    required this.isFuture,
    required this.hit,
  });
}

class _DayCircle extends StatelessWidget {
  final _DayCircleData data;
  final WaypointThemeData t;

  const _DayCircle({required this.data, required this.t});

  @override
  Widget build(BuildContext context) {
    final Color circleColor;
    final Color textColor;
    final Border? border;
    final List<BoxShadow> shadows;

    if (data.isFuture) {
      circleColor = t.unearnedBg;
      textColor = t.textHint;
      border = Border.all(color: t.cardBorder, width: 1.5);
      shadows = [];
    } else if (data.hit) {
      circleColor = t.primary;
      textColor = t.onPrimary;
      border = null;
      shadows = [
        BoxShadow(
          color: t.primary.withValues(alpha: 0.3),
          blurRadius: 6,
          offset: const Offset(0, 2),
        ),
      ];
    } else {
      circleColor = t.unearnedBg;
      textColor = t.textHint;
      border = Border.all(color: t.cardBorder, width: 1.5);
      shadows = [];
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: data.isToday ? 38 : 34,
          height: data.isToday ? 38 : 34,
          decoration: BoxDecoration(
            color: circleColor,
            shape: BoxShape.circle,
            border: data.isToday && !data.hit
                ? Border.all(color: t.primary, width: 2)
                : border,
            boxShadow: shadows,
          ),
          child: Center(
            child: Text(
              '${data.day}',
              style: TextStyle(
                fontFamily: 'Georgia',
                fontSize: data.isToday ? 14 : 12,
                fontWeight: FontWeight.bold,
                color: (data.hit && !data.isFuture) ? t.onPrimary : textColor,
              ),
            ),
          ),
        ),
        if (data.isToday) ...[
          const SizedBox(height: 4),
          Container(
            width: 4,
            height: 4,
            decoration: BoxDecoration(
              color: t.primary,
              shape: BoxShape.circle,
            ),
          ),
        ],
      ],
    );
  }
}

// ── Background painter ────────────────────────────────────────────────────────

class _BackgroundPainter extends CustomPainter {
  final WaypointThemeData t;
  _BackgroundPainter(this.t);

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
      ..strokeWidth = 60;
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

    final arcPaint2 = Paint()
      ..color = t.secondary.withValues(alpha: 0.07)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 40;
    canvas.drawArc(
      Rect.fromCenter(
        center: Offset(-30, size.height + 30),
        width: size.width * 0.7,
        height: size.width * 0.7,
      ),
      math.pi * 1.5,
      math.pi * 0.4,
      false,
      arcPaint2,
    );
  }

  @override
  bool shouldRepaint(_BackgroundPainter old) => old.t != t;
}

// ── Quick tile ────────────────────────────────────────────────────────────────

class _QuickTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final WaypointThemeData t;
  final VoidCallback onTap;

  const _QuickTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.t,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: t.cardBg.withValues(alpha: 0.78),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: t.cardBorder.withValues(alpha: 0.8)),
          boxShadow: [
            BoxShadow(
              color: t.primary.withValues(alpha: 0.06),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [t.primary, t.secondary],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: t.onPrimary, size: 22),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: TextStyle(
                fontFamily: 'Georgia',
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: t.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(
                fontFamily: 'Georgia',
                fontSize: 12,
                color: t.textSecondary,
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

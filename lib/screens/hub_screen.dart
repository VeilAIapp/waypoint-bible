import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/reading_plans.dart';
import 'reading_plans_screen.dart';
import 'bible_studies_screen.dart';
import 'journey_screen.dart';
import 'highlights_screen.dart';
import 'journal_screen.dart';
import 'settings_screen.dart';
import '../services/notification_service.dart';
import '../theme/app_theme.dart';
import '../widgets/waypoint_tooltip.dart';

class HubScreen extends StatefulWidget {
  final SharedPreferences prefs;
  final void Function(String prompt) onPromptSelected;

  const HubScreen({
    super.key,
    required this.prefs,
    required this.onPromptSelected,
  });

  @override
  State<HubScreen> createState() => _HubScreenState();
}

class _HubScreenState extends State<HubScreen> {
  String _notificationSubtitle = 'Every morning at 8:00 AM';
  Map<String, int> _planProgress = {};

  @override
  void initState() {
    super.initState();
    final savedTime = widget.prefs.getString('notification_time');
    if (savedTime != null) {
      _notificationSubtitle = 'Every morning at $savedTime';
    }
    _loadPlanProgress();
  }

  void _loadPlanProgress() {
    final raw = widget.prefs.getString('reading_plan_progress') ?? '{}';
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      _planProgress = map.map((k, v) => MapEntry(k, v as int));
    } catch (_) {
      _planProgress = {};
    }
  }

  ReadingPlan? get _activePlan {
    for (final plan in kReadingPlans) {
      final progress = _planProgress[plan.id] ?? 0;
      if (progress > 0 && progress < plan.totalDays) return plan;
    }
    return null;
  }

  Future<void> _showNotificationTimePicker() async {
    TimeOfDay initial = const TimeOfDay(hour: 8, minute: 0);
    final savedTime = widget.prefs.getString('notification_time');
    if (savedTime != null) {
      final (h, m) = NotificationService.parseTimeString(savedTime);
      initial = TimeOfDay(hour: h, minute: m);
    }

    final picked = await showTimePicker(context: context, initialTime: initial);
    if (picked == null || !mounted) return;

    final period = picked.period == DayPeriod.am ? 'AM' : 'PM';
    final hour12 = picked.hourOfPeriod == 0 ? 12 : picked.hourOfPeriod;
    final minuteStr = picked.minute.toString().padLeft(2, '0');
    final timeStr = '$hour12:$minuteStr $period';

    await widget.prefs.setString('notification_time', timeStr);
    try {
      await NotificationService.scheduleDaily(picked.hour, picked.minute);
    } catch (_) {}

    setState(() => _notificationSubtitle = 'Every morning at $timeStr');
  }

  void _refreshNotificationSubtitle() {
    final savedTime = widget.prefs.getString('notification_time');
    setState(() {
      _notificationSubtitle = savedTime != null
          ? 'Every morning at $savedTime'
          : 'Every morning at 8:00 AM';
    });
  }

  void _push(BuildContext context, Widget screen, {bool refreshNotification = false}) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen)).then((_) {
      if (!mounted) return;
      setState(() => _loadPlanProgress());
      if (refreshNotification) _refreshNotificationSubtitle();
    });
  }

  void _navigateToActivePlan(BuildContext context, ReadingPlan plan) {
    final currentDay = _planProgress[plan.id]!;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ReadingPlanDetailScreen(
          plan: plan,
          currentDay: currentDay,
          prefs: widget.prefs,
          onPromptSelected: widget.onPromptSelected,
          onProgressUpdate: (day) {
            final updated = Map<String, int>.from(_planProgress)..[plan.id] = day;
            widget.prefs.setString('reading_plan_progress', jsonEncode(updated));
            if (mounted) setState(() => _planProgress = updated);
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
      if (mounted) setState(() => _loadPlanProgress());
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = WaypointTheme.of(context);
    final streak = widget.prefs.getInt('streak') ?? 0;
    final chatCount = widget.prefs.getInt('chat_count') ?? 0;
    // Count earned badges the same way Journey does — only ids defined in
    // kAllBadges, and including milestone badges auto-derived from streak/chat/
    // setup — so this stat matches the Journey screen even before it's opened.
    final earnedIds = earnedBadgeIds(widget.prefs);
    final badgeCount = kAllBadges.where((b) => earnedIds.contains(b.id)).length;
    final journalCount = (widget.prefs.getStringList('journal_entries') ?? []).length;

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        title: Text(
          'My Waypoint',
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
          Positioned.fill(child: CustomPaint(painter: _HubBackgroundPainter(t))),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Stats grid ───────────────────────────────
                  Column(
                    children: [
                      Row(
                        children: [
                          _StatCard(label: 'Day Streak', value: '$streak', icon: Icons.explore, t: t),
                          const SizedBox(width: 12),
                          _StatCard(label: 'Conversations', value: '$chatCount', icon: Icons.chat_bubble_outline, t: t),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          _StatCard(label: 'Badges', value: '$badgeCount', icon: Icons.star_outline, t: t),
                          const SizedBox(width: 12),
                          _StatCard(label: 'Journal', value: '$journalCount', icon: Icons.book_outlined, t: t, onTap: () => _push(context, JournalScreen(prefs: widget.prefs))),
                        ],
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // ── Your Journey ─────────────────────────────
                  Text(
                    'Your Journey',
                    style: TextStyle(
                      fontFamily: 'Georgia',
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: t.textPrimary,
                    ),
                  ),

                  const SizedBox(height: 14),

                  Builder(builder: (ctx) {
                    final active = _activePlan;
                    if (active != null) {
                      return _ActivePlanHubCard(
                        plan: active,
                        currentDay: _planProgress[active.id]!,
                        t: t,
                        onContinue: () => _navigateToActivePlan(ctx, active),
                        onBrowse: () => _push(ctx, ReadingPlansScreen(
                          prefs: widget.prefs,
                          onPromptSelected: widget.onPromptSelected,
                        )),
                      );
                    }
                    return _HubCard(
                      icon: Icons.route_outlined,
                      title: 'Reading Plans',
                      subtitle: 'Guided journeys through Scripture',
                      t: t,
                      onTap: () => _push(
                        ctx,
                        ReadingPlansScreen(
                          prefs: widget.prefs,
                          onPromptSelected: widget.onPromptSelected,
                        ),
                      ),
                    );
                  }),
                  const SizedBox(height: 10),
                  _HubCard(
                    icon: Icons.local_library_outlined,
                    title: 'Bible Studies',
                    subtitle: 'Deep dives into key topics and books',
                    t: t,
                    onTap: () => _push(
                      context,
                      BibleStudiesScreen(
                        prefs: widget.prefs,
                        onPromptSelected: widget.onPromptSelected,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  _HubCard(
                    icon: Icons.bookmark_outline,
                    title: 'Highlights',
                    subtitle: 'Verses that have spoken to you',
                    t: t,
                    onTap: () => _push(
                      context,
                      HighlightsScreen(prefs: widget.prefs),
                    ),
                  ),
                  const SizedBox(height: 10),
                  _HubCard(
                    icon: Icons.emoji_events_outlined,
                    title: 'My Journey',
                    subtitle: 'View your badges and progress',
                    t: t,
                    onTap: () => _push(
                      context,
                      JourneyScreen(prefs: widget.prefs),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // ── Account ──────────────────────────────────
                  Text(
                    'Account',
                    style: TextStyle(
                      fontFamily: 'Georgia',
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: t.textPrimary,
                    ),
                  ),

                  const SizedBox(height: 14),

                  _HubCard(
                    icon: Icons.notifications_outlined,
                    title: 'Daily Verse Notification',
                    subtitle: _notificationSubtitle,
                    t: t,
                    onTap: _showNotificationTimePicker,
                  ),
                  const SizedBox(height: 10),
                  _HubCard(
                    icon: Icons.settings_outlined,
                    title: 'Settings',
                    subtitle: 'Faith background and preferences',
                    t: t,
                    onTap: () => _push(
                      context,
                      SettingsScreen(prefs: widget.prefs),
                      refreshNotification: true,
                    ),
                  ),

                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
          WaypointTooltipBubble(
            prefKey: 'tooltip_seen_hub',
            message: 'Your highlighted verses live here',
            prefs: widget.prefs,
            alignment: const Alignment(0, 0.18),
          ),
        ],
      ),
    );
  }
}

// ── Stat card ─────────────────────────────────────────────────────────────────

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final WaypointThemeData t;
  final VoidCallback? onTap;

  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.t,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
        decoration: BoxDecoration(
          color: t.cardBg.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: t.cardBorder),
          boxShadow: [
            BoxShadow(
              color: t.primary.withValues(alpha: 0.07),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          children: [
            Icon(icon, color: t.primary, size: 18),
            const SizedBox(height: 6),
            Text(
              value,
              style: TextStyle(
                fontFamily: 'Georgia',
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: t.primary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Georgia',
                fontSize: 11,
                color: t.textSecondary,
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }
}

// ── Hub card ──────────────────────────────────────────────────────────────────

class _HubCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final WaypointThemeData t;
  final VoidCallback onTap;

  const _HubCard({
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
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: t.cardBg.withValues(alpha: 0.78),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: t.cardBorder.withValues(alpha: 0.8)),
          boxShadow: [
            BoxShadow(
              color: t.primary.withValues(alpha: 0.06),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [t.primary, t.secondary],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: t.onPrimary, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontFamily: 'Georgia',
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: t.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontFamily: 'Georgia',
                      fontSize: 12,
                      color: t.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: t.textHint, size: 20),
          ],
        ),
      ),
    );
  }
}

// ── Active plan hub card ──────────────────────────────────────────────────────

class _ActivePlanHubCard extends StatelessWidget {
  final ReadingPlan plan;
  final int currentDay;
  final WaypointThemeData t;
  final VoidCallback onContinue;
  final VoidCallback onBrowse;

  const _ActivePlanHubCard({
    required this.plan,
    required this.currentDay,
    required this.t,
    required this.onContinue,
    required this.onBrowse,
  });

  @override
  Widget build(BuildContext context) {
    final percent = currentDay / plan.totalDays;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: t.accentLight,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: t.primary, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: t.primary.withValues(alpha: 0.12),
            blurRadius: 14,
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
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [t.primary, t.secondary],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(plan.iconData, color: t.onPrimary, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      plan.title,
                      style: TextStyle(
                        fontFamily: 'Georgia',
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: t.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Day $currentDay of ${plan.totalDays}',
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
              GestureDetector(
                onTap: onBrowse,
                child: Text(
                  'All Plans',
                  style: TextStyle(
                    fontFamily: 'Georgia',
                    fontSize: 12,
                    color: t.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: percent,
              backgroundColor: t.progressBg,
              valueColor: AlwaysStoppedAnimation<Color>(t.primary),
              minHeight: 6,
            ),
          ),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: onContinue,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 11),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [t.primary, t.secondary],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: t.primary.withValues(alpha: 0.25),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Center(
                child: Text(
                  'Continue Day $currentDay →',
                  style: TextStyle(
                    fontFamily: 'Georgia',
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: t.onPrimary,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Background painter ────────────────────────────────────────────────────────

class _HubBackgroundPainter extends CustomPainter {
  final WaypointThemeData t;
  _HubBackgroundPainter(this.t);

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
      arcPaint,
    );
  }

  @override
  bool shouldRepaint(_HubBackgroundPainter old) => old.t != t;
}

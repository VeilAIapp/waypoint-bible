import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/reading_plans.dart';
import '../theme/app_theme.dart';

class ReadingPlansScreen extends StatefulWidget {
  final SharedPreferences prefs;
  final void Function(String prompt) onPromptSelected;

  const ReadingPlansScreen({
    super.key,
    required this.prefs,
    required this.onPromptSelected,
  });

  @override
  State<ReadingPlansScreen> createState() => _ReadingPlansScreenState();
}

class _ReadingPlansScreenState extends State<ReadingPlansScreen> {
  Map<String, int> _progress = {};

  @override
  void initState() {
    super.initState();
    _loadProgress();
  }

  void _loadProgress() {
    final raw = widget.prefs.getString('reading_plan_progress') ?? '{}';
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      _progress = map.map((k, v) => MapEntry(k, v as int));
    } catch (_) {
      _progress = {};
    }
  }

  void _saveProgress() {
    widget.prefs.setString('reading_plan_progress', jsonEncode(_progress));
  }

  Widget _buildPlanCard(ReadingPlan plan, WaypointThemeData t) {
    final progress = _progress[plan.id] ?? 0;
    return _PlanCard(
      plan: plan,
      currentDay: progress,
      t: t,
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ReadingPlanDetailScreen(
            plan: plan,
            currentDay: progress,
            prefs: widget.prefs,
            onPromptSelected: widget.onPromptSelected,
            onProgressUpdate: (day) {
              setState(() => _progress[plan.id] = day);
              _saveProgress();
              if (day >= plan.totalDays) {
                final badges = widget.prefs.getStringList('earned_badges') ?? [];
                badges.add('plan_${plan.id}');
                widget.prefs.setStringList('earned_badges', badges);
              }
            },
          ),
        ),
      ),
    );
  }

  List<Widget> _buildPlanList(WaypointThemeData t) {
    final active = kReadingPlans.where((p) {
      final prog = _progress[p.id] ?? 0;
      return prog > 0 && prog < p.totalDays;
    }).toList();
    final others = kReadingPlans.where((p) {
      final prog = _progress[p.id] ?? 0;
      return !(prog > 0 && prog < p.totalDays);
    }).toList();

    final widgets = <Widget>[];
    if (active.isNotEmpty) {
      widgets.add(_SectionLabel(text: 'In Progress', t: t));
      widgets.add(const SizedBox(height: 10));
      for (final plan in active) {
        widgets.add(_buildPlanCard(plan, t));
      }
      if (others.isNotEmpty) {
        widgets.add(const SizedBox(height: 8));
        widgets.add(_SectionLabel(text: 'Available Plans', t: t));
        widgets.add(const SizedBox(height: 10));
      }
    }
    for (final plan in others) {
      widgets.add(_buildPlanCard(plan, t));
    }
    return widgets;
  }

  @override
  Widget build(BuildContext context) {
    final t = WaypointTheme.of(context);
    final hasActive = kReadingPlans.any((p) {
      final prog = _progress[p.id] ?? 0;
      return prog > 0 && prog < p.totalDays;
    });
    return Scaffold(
      backgroundColor: t.background,
      appBar: AppBar(
        backgroundColor: t.background,
        centerTitle: true,
        title: Text(
          'Reading Plans',
          style: TextStyle(
            fontFamily: 'Georgia',
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: t.textPrimary,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              hasActive ? 'Your reading plans' : 'Choose a plan to begin',
              style: TextStyle(
                fontFamily: 'Georgia',
                fontSize: 15,
                color: t.textSecondary,
              ),
            ),
            const SizedBox(height: 20),
            ..._buildPlanList(t),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  final WaypointThemeData t;
  const _SectionLabel({required this.text, required this.t});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontFamily: 'Georgia',
        fontSize: 14,
        fontWeight: FontWeight.bold,
        color: t.textPrimary,
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  final ReadingPlan plan;
  final int currentDay;
  final WaypointThemeData t;
  final VoidCallback onTap;

  const _PlanCard({
    required this.plan,
    required this.currentDay,
    required this.t,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final percent = currentDay / plan.totalDays;
    final isActive = currentDay > 0 && currentDay < plan.totalDays;
    final isComplete = currentDay >= plan.totalDays;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isActive ? t.accentLight : t.cardBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isActive ? t.primary : t.cardBorder,
            width: isActive ? 1.5 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: t.primary.withValues(alpha: isActive ? 0.12 : 0.06),
              blurRadius: isActive ? 16 : 10,
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
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [t.primary, t.secondary],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Icon(plan.iconData, color: t.onPrimary, size: 26),
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
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: t.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        plan.subtitle,
                        style: TextStyle(
                          fontFamily: 'Georgia',
                          fontSize: 13,
                          color: t.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                if (isComplete)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: t.accentLight,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '✓ Done',
                      style: TextStyle(
                        fontFamily: 'Georgia',
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: t.primary,
                      ),
                    ),
                  )
                else if (isActive)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: t.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'IN PROGRESS',
                      style: TextStyle(
                        fontFamily: 'Georgia',
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: t.primary,
                        letterSpacing: 0.8,
                      ),
                    ),
                  )
                else
                  Icon(Icons.chevron_right, color: t.textHint),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              plan.description,
              style: TextStyle(
                fontFamily: 'Georgia',
                fontSize: 13,
                color: t.textSecondary,
                height: 1.5,
              ),
            ),
            if (isActive) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  Text(
                    'Day $currentDay of ${plan.totalDays}',
                    style: TextStyle(
                      fontFamily: 'Georgia',
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: t.primary,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${(percent * 100).round()}%',
                    style: TextStyle(
                      fontFamily: 'Georgia',
                      fontSize: 12,
                      color: t.textSecondary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: percent,
                  backgroundColor: t.progressBg,
                  valueColor: AlwaysStoppedAnimation<Color>(t.primary),
                  minHeight: 8,
                ),
              ),
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [t.primary, t.secondary],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: t.primary.withValues(alpha: 0.3),
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
            ] else if (currentDay == 0) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [t.primary, t.secondary],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'Begin Plan',
                  style: TextStyle(
                    fontFamily: 'Georgia',
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: t.onPrimary,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Reading Plan Detail Screen ────────────────────────────────────────────────

class ReadingPlanDetailScreen extends StatefulWidget {
  final ReadingPlan plan;
  final int currentDay;
  final SharedPreferences prefs;
  final void Function(String prompt) onPromptSelected;
  final void Function(int day) onProgressUpdate;

  const ReadingPlanDetailScreen({
    super.key,
    required this.plan,
    required this.currentDay,
    required this.prefs,
    required this.onPromptSelected,
    required this.onProgressUpdate,
  });

  @override
  State<ReadingPlanDetailScreen> createState() => _ReadingPlanDetailScreenState();
}

class _ReadingPlanDetailScreenState extends State<ReadingPlanDetailScreen> {
  late int _currentDay;

  @override
  void initState() {
    super.initState();
    _currentDay = widget.currentDay == 0 ? 1 : widget.currentDay;
  }

  ReadingDay get _today => widget.plan.days[_currentDay - 1];

  void _markComplete() {
    if (_currentDay < widget.plan.totalDays) {
      setState(() => _currentDay++);
    }
    widget.onProgressUpdate(_currentDay);
  }

  void _discuss() {
    widget.onPromptSelected(
      'I\'m reading ${_today.passage} today as part of my reading plan. '
      'Can you help me understand this passage — its context, key themes, and how to apply it to my life today?'
    );
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final t = WaypointTheme.of(context);
    return Scaffold(
      backgroundColor: t.background,
      appBar: AppBar(
        backgroundColor: t.background,
        centerTitle: true,
        title: Text(
          widget.plan.title,
          style: TextStyle(
            fontFamily: 'Georgia',
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: t.textPrimary,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Progress bar
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: _currentDay / widget.plan.totalDays,
                      backgroundColor: t.progressBg,
                      valueColor: AlwaysStoppedAnimation<Color>(t.primary),
                      minHeight: 6,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  'Day $_currentDay of ${widget.plan.totalDays}',
                  style: TextStyle(
                    fontFamily: 'Georgia',
                    fontSize: 12,
                    color: t.textSecondary,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),

            Text(
              'DAY $_currentDay',
              style: TextStyle(
                fontFamily: 'Georgia',
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: t.primary,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _today.passage,
              style: TextStyle(
                fontFamily: 'Georgia',
                fontSize: 26,
                fontWeight: FontWeight.bold,
                color: t.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _today.summary,
              style: TextStyle(
                fontFamily: 'Georgia',
                fontSize: 15,
                color: t.textSecondary,
                height: 1.5,
                fontStyle: FontStyle.italic,
              ),
            ),

            const SizedBox(height: 28),

            // Discuss button
            GestureDetector(
              onTap: _discuss,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 16),
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
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.chat_bubble_outline, color: t.onPrimary, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        'Discuss with Companion',
                        style: TextStyle(
                          fontFamily: 'Georgia',
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: t.onPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            const SizedBox(height: 12),

            // Mark complete
            GestureDetector(
              onTap: _markComplete,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: t.cardBg,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: t.cardBorder),
                ),
                child: Center(
                  child: Text(
                    _currentDay >= widget.plan.totalDays
                        ? 'Plan Complete!'
                        : 'Mark Complete & Next Day →',
                    style: TextStyle(
                      fontFamily: 'Georgia',
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: _currentDay >= widget.plan.totalDays
                          ? t.primary
                          : t.textPrimary,
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 32),

            Text(
              'Upcoming',
              style: TextStyle(
                fontFamily: 'Georgia',
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: t.textPrimary,
              ),
            ),
            const SizedBox(height: 12),

            ...widget.plan.days
                .where((d) => d.day >= _currentDay && d.day <= _currentDay + 6)
                .map((d) => GestureDetector(
                      onTap: () => setState(() => _currentDay = d.day),
                      child: Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: d.day == _currentDay
                              ? t.accentLight
                              : t.cardBg,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: d.day == _currentDay
                                ? t.primary
                                : t.cardBorder,
                            width: d.day == _currentDay ? 2 : 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: d.day < _currentDay
                                    ? t.primary
                                    : d.day == _currentDay
                                        ? t.accentLight
                                        : t.unearnedBg,
                                shape: BoxShape.circle,
                                border: d.day == _currentDay
                                    ? Border.all(color: t.primary, width: 2)
                                    : null,
                              ),
                              child: Center(
                                child: d.day < _currentDay
                                    ? Icon(Icons.check, color: t.onPrimary, size: 16)
                                    : Text(
                                        '${d.day}',
                                        style: TextStyle(
                                          fontFamily: 'Georgia',
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          color: d.day == _currentDay
                                              ? t.primary
                                              : t.textHint,
                                        ),
                                      ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    d.passage,
                                    style: TextStyle(
                                      fontFamily: 'Georgia',
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color: d.day == _currentDay
                                          ? t.primary
                                          : t.textPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    d.summary,
                                    style: TextStyle(
                                      fontFamily: 'Georgia',
                                      fontSize: 12,
                                      color: t.textSecondary,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    )),

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

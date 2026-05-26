import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/bible_studies.dart';
import '../theme/app_theme.dart';

class BibleStudiesScreen extends StatefulWidget {
  final SharedPreferences prefs;
  final void Function(String prompt) onPromptSelected;

  const BibleStudiesScreen({
    super.key,
    required this.prefs,
    required this.onPromptSelected,
  });

  @override
  State<BibleStudiesScreen> createState() => _BibleStudiesScreenState();
}

class _BibleStudiesScreenState extends State<BibleStudiesScreen> {
  Map<String, int> _progress = {};

  @override
  void initState() {
    super.initState();
    _loadProgress();
  }

  void _loadProgress() {
    final raw = widget.prefs.getString('study_progress') ?? '{}';
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      _progress = map.map((k, v) => MapEntry(k, v as int));
    } catch (_) {
      _progress = {};
    }
  }

  void _saveProgress() {
    widget.prefs.setString('study_progress', jsonEncode(_progress));
  }

  int _getProgress(String studyId) => _progress[studyId] ?? 0;

  @override
  Widget build(BuildContext context) {
    final t = WaypointTheme.of(context);
    return Scaffold(
      backgroundColor: t.background,
      appBar: AppBar(
        backgroundColor: t.background,
        centerTitle: true,
        title: Text(
          'Bible Studies',
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
              'Choose a study to begin',
              style: TextStyle(
                fontFamily: 'Georgia',
                fontSize: 15,
                color: t.textSecondary,
              ),
            ),
            const SizedBox(height: 20),
            ...kBibleStudies.map((study) {
              final progress = _getProgress(study.id);
              return _StudyCard(
                study: study,
                currentDay: progress,
                t: t,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => StudyDetailScreen(
                      study: study,
                      currentDay: progress,
                      prefs: widget.prefs,
                      onPromptSelected: widget.onPromptSelected,
                      onProgressUpdate: (day) {
                        setState(() => _progress[study.id] = day);
                        _saveProgress();
                        if (day >= study.totalDays) {
                          final badges = widget.prefs
                                  .getStringList('earned_badges') ??
                              [];
                          badges.add('study_${study.id}');
                          widget.prefs.setStringList('earned_badges', badges);
                        }
                      },
                    ),
                  ),
                ),
              );
            }),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _StudyCard extends StatelessWidget {
  final BibleStudy study;
  final int currentDay;
  final WaypointThemeData t;
  final VoidCallback onTap;

  const _StudyCard({
    required this.study,
    required this.currentDay,
    required this.t,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final percent = currentDay / study.totalDays;
    final isStarted = currentDay > 0;
    final isComplete = currentDay >= study.totalDays;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: t.cardBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: t.cardBorder),
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
                  child: Icon(study.iconData, color: t.onPrimary, size: 26),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        study.title,
                        style: TextStyle(
                          fontFamily: 'Georgia',
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: t.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        study.subtitle,
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
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
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
                else
                  Icon(Icons.chevron_right, color: t.textHint),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              study.description,
              style: TextStyle(
                fontFamily: 'Georgia',
                fontSize: 13,
                color: t.textSecondary,
                height: 1.5,
              ),
            ),
            if (isStarted) ...[
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: percent,
                        backgroundColor: t.progressBg,
                        valueColor: AlwaysStoppedAnimation<Color>(t.primary),
                        minHeight: 6,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Day $currentDay of ${study.totalDays}',
                    style: TextStyle(
                      fontFamily: 'Georgia',
                      fontSize: 12,
                      color: t.textSecondary,
                    ),
                  ),
                ],
              ),
            ] else ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [t.primary, t.secondary],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'Begin Study',
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

// ── Study Detail Screen ───────────────────────────────────────────────────────

class StudyDetailScreen extends StatefulWidget {
  final BibleStudy study;
  final int currentDay;
  final SharedPreferences prefs;
  final void Function(String prompt) onPromptSelected;
  final void Function(int day) onProgressUpdate;

  const StudyDetailScreen({
    super.key,
    required this.study,
    required this.currentDay,
    required this.prefs,
    required this.onPromptSelected,
    required this.onProgressUpdate,
  });

  @override
  State<StudyDetailScreen> createState() => _StudyDetailScreenState();
}

class _StudyDetailScreenState extends State<StudyDetailScreen> {
  late int _currentDay;

  @override
  void initState() {
    super.initState();
    _currentDay = widget.currentDay == 0 ? 1 : widget.currentDay;
  }

  StudyDay get _today => widget.study.days[_currentDay - 1];

  void _completeDay() {
    if (_currentDay < widget.study.totalDays) {
      setState(() => _currentDay++);
    }
    widget.onProgressUpdate(_currentDay);
  }

  void _reflect() {
    widget.onPromptSelected(_today.aiPrompt);
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
          widget.study.title,
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
                      value: _currentDay / widget.study.totalDays,
                      backgroundColor: t.progressBg,
                      valueColor: AlwaysStoppedAnimation<Color>(t.primary),
                      minHeight: 6,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  'Day $_currentDay of ${widget.study.totalDays}',
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
              _today.title,
              style: TextStyle(
                fontFamily: 'Georgia',
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: t.textPrimary,
              ),
            ),

            const SizedBox(height: 20),

            // Passage card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 18, 18, 18),
              decoration: BoxDecoration(
                color: t.cardBg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: t.cardBorder),
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
                          Text(
                            _today.passage,
                            style: TextStyle(
                              fontFamily: 'Georgia',
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: t.primary,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '"${_today.passageText}"',
                            style: TextStyle(
                              fontFamily: 'Georgia',
                              fontSize: 16,
                              color: t.textPrimary,
                              height: 1.65,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            // Reflection
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: t.accentLight,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                    color: t.cardBorder.withValues(alpha: 0.5)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.lightbulb_outline, color: t.primary, size: 16),
                      const SizedBox(width: 6),
                      Text(
                        'REFLECT',
                        style: TextStyle(
                          fontFamily: 'Georgia',
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: t.primary,
                          letterSpacing: 1.1,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _today.reflection,
                    style: TextStyle(
                      fontFamily: 'Georgia',
                      fontSize: 15,
                      color: t.textPrimary,
                      height: 1.6,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Reflect with AI button
            GestureDetector(
              onTap: _reflect,
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
                      Icon(Icons.chat_bubble_outline,
                          color: t.onPrimary, size: 18),
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

            if (_currentDay < widget.study.totalDays)
              GestureDetector(
                onTap: _completeDay,
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
                      'Mark Complete & Continue →',
                      style: TextStyle(
                        fontFamily: 'Georgia',
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: t.textPrimary,
                      ),
                    ),
                  ),
                ),
              )
            else
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: t.accentLight,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: t.cardBorder),
                ),
                child: Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle_outline, color: t.primary, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        'Study Complete!',
                        style: TextStyle(
                          fontFamily: 'Georgia',
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: t.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            const SizedBox(height: 32),

            Text(
              'All Days',
              style: TextStyle(
                fontFamily: 'Georgia',
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: t.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate:
                  const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                crossAxisSpacing: 6,
                mainAxisSpacing: 6,
                childAspectRatio: 1,
              ),
              itemCount: widget.study.totalDays,
              itemBuilder: (context, index) {
                final day = index + 1;
                final isCurrentDay = day == _currentDay;
                final isCompleted = day < _currentDay;
                return GestureDetector(
                  onTap: () => setState(() => _currentDay = day),
                  child: Container(
                    decoration: BoxDecoration(
                      color: isCompleted
                          ? t.primary
                          : isCurrentDay
                              ? t.accentLight
                              : t.cardBg,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isCurrentDay
                            ? t.primary
                            : t.cardBorder,
                        width: isCurrentDay ? 2 : 1,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        '$day',
                        style: TextStyle(
                          fontFamily: 'Georgia',
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: isCompleted
                              ? t.onPrimary
                              : isCurrentDay
                                  ? t.primary
                                  : t.textHint,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

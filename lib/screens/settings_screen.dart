import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/notification_service.dart';
import '../services/revenue_cat_service.dart';
import '../constants.dart';
import '../theme/app_theme.dart';
import 'paywall_screen.dart';

const String kDenominationKey = 'user_denomination';
const String kTranslationKey = 'bible_translation';

const _kTranslations = [
  {'code': 'BSB', 'name': 'Berean Standard Bible'},
  {'code': 'KJV', 'name': 'King James Version'},
  {'code': 'WEB', 'name': 'World English Bible'},
];

class SettingsScreen extends StatefulWidget {
  final SharedPreferences prefs;

  const SettingsScreen({super.key, required this.prefs});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String? _selectedDenomination;
  String _selectedTranslation = 'BSB';
  String _notificationSubtitle = 'Every morning at 8:00 AM';
  bool _isPro = false;

  @override
  void initState() {
    super.initState();
    _selectedDenomination = widget.prefs.getString(kDenominationKey);
    _selectedTranslation = widget.prefs.getString(kTranslationKey) ?? 'BSB';
    final savedTime = widget.prefs.getString('notification_time');
    if (savedTime != null) {
      _notificationSubtitle = 'Every morning at $savedTime';
    }
    _checkPro();
  }

  Future<void> _checkPro() async {
    try {
      final isPro = await RevenueCatService.isProUser();
      if (mounted) setState(() => _isPro = isPro);
    } catch (_) {}
  }

  Future<void> _openPaywall() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PaywallScreen(
          onContinueFree: () {},
          onProUnlocked: () => setState(() => _isPro = true),
        ),
      ),
    );
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

  void _selectTranslation(String code) {
    widget.prefs.setString(kTranslationKey, code);
    setState(() => _selectedTranslation = code);
    Navigator.of(context).pop();
  }

  void _showTranslationPicker() {
    final t = WaypointTheme.of(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: t.cardBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: t.cardBorder,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  'Bible Translation',
                  style: TextStyle(
                    fontFamily: 'Georgia',
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: t.textPrimary,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              ..._kTranslations.map((tr) => ListTile(
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 24, vertical: 2),
                    title: Text(
                      tr['code']!,
                      style: TextStyle(
                        fontFamily: 'Georgia',
                        fontSize: 16,
                        color: t.textPrimary,
                        fontWeight: _selectedTranslation == tr['code']
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                    subtitle: Text(
                      tr['name']!,
                      style: TextStyle(
                        fontFamily: 'Georgia',
                        fontSize: 13,
                        color: t.textSecondary,
                      ),
                    ),
                    trailing: _selectedTranslation == tr['code']
                        ? Icon(Icons.check_circle, color: t.primary)
                        : Icon(Icons.radio_button_unchecked,
                            color: t.cardBorder),
                    onTap: () => _selectTranslation(tr['code']!),
                  )),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open link')),
        );
      }
    }
  }

  void _showFeedbackSheet() async {
    final body = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: WaypointTheme.of(context).cardBg,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => const _FeedbackSheet(),
    );

    if (body == null || !mounted) return;

    final t = WaypointTheme.of(context);
    final uri = Uri.parse(
      'mailto:hello@waypointbible.app'
      '?subject=${Uri.encodeComponent('Waypoint Feedback')}'
      '&body=${Uri.encodeComponent(body)}',
    );
    await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Thank you! We appreciate your feedback.',
            style: TextStyle(fontFamily: 'Georgia'),
          ),
          backgroundColor: t.primary,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  void _selectDenomination(String denomination) {
    widget.prefs.setString(kDenominationKey, denomination);
    setState(() => _selectedDenomination = denomination);
    Navigator.of(context).pop();
  }

  void _showDenominationPicker() {
    final t = WaypointTheme.of(context);
    final sheetMaxHeight = MediaQuery.of(context).size.height * 0.75;
    showModalBottomSheet(
      context: context,
      backgroundColor: t.cardBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) {
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: sheetMaxHeight,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 12),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: t.cardBorder,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 20),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text(
                    'Your Faith Background',
                    style: TextStyle(
                      fontFamily: 'Georgia',
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: t.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text(
                    'If you\'re unsure, select Non-denominational to start — you can always change it later.',
                    style: TextStyle(
                      fontFamily: 'Georgia',
                      fontSize: 13,
                      color: t.textSecondary,
                      height: 1.5,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: kDenominations
                          .map((d) => ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 24, vertical: 2),
                                title: Text(
                                  d,
                                  style: TextStyle(
                                    fontFamily: 'Georgia',
                                    fontSize: 16,
                                    color: t.textPrimary,
                                    fontWeight: _selectedDenomination == d
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                  ),
                                ),
                                trailing: _selectedDenomination == d
                                    ? Icon(Icons.check_circle,
                                        color: t.primary)
                                    : Icon(Icons.radio_button_unchecked,
                                        color: t.cardBorder),
                                onTap: () => _selectDenomination(d),
                              ))
                          .toList(),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = WaypointTheme.of(context);
    final themeService = WaypointTheme.serviceOf(context);
    final currentThemeName = themeService.currentTheme;

    return Scaffold(
      backgroundColor: t.background,
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: t.background,
        foregroundColor: t.textPrimary,
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          // ── Theme Selector ────────────────────────────────────
          Text(
            'App Theme',
            style: TextStyle(
              fontFamily: 'Georgia',
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: t.textSecondary,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 12),

          // Row 1: Sunrise + Midnight
          Row(
            children: [
              Expanded(
                child: _ThemePreviewCard(
                  name: 'Sunrise',
                  themeData: WaypointThemeData.sunrise,
                  isSelected: currentThemeName == ThemeName.sunrise,
                  activeT: t,
                  onTap: () => themeService.setTheme(ThemeName.sunrise),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _ThemePreviewCard(
                  name: 'Midnight',
                  themeData: WaypointThemeData.midnight,
                  isSelected: currentThemeName == ThemeName.midnight,
                  activeT: t,
                  onTap: () => themeService.setTheme(ThemeName.midnight),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Row 2: Forest + Vespers
          Row(
            children: [
              Expanded(
                child: _ThemePreviewCard(
                  name: 'Forest',
                  themeData: WaypointThemeData.forest,
                  isSelected: currentThemeName == ThemeName.forest,
                  activeT: t,
                  onTap: () => themeService.setTheme(ThemeName.forest),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _ThemePreviewCard(
                  name: 'Vespers',
                  themeData: WaypointThemeData.vespers,
                  isSelected: currentThemeName == ThemeName.vespers,
                  activeT: t,
                  onTap: () => themeService.setTheme(ThemeName.vespers),
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),

          _SettingsTile(
            icon: Icons.menu_book_outlined,
            title: 'Bible Translation',
            subtitle: _selectedTranslation,
            t: t,
            onTap: _showTranslationPicker,
          ),
          const SizedBox(height: 12),
          _SettingsTile(
            icon: Icons.notifications_outlined,
            title: 'Daily Verse Notification',
            subtitle: _notificationSubtitle,
            t: t,
            onTap: _showNotificationTimePicker,
          ),
          const SizedBox(height: 12),
          _SettingsTile(
            icon: Icons.church_outlined,
            title: 'Faith Background',
            subtitle: _selectedDenomination ?? 'Not specified',
            t: t,
            onTap: _showDenominationPicker,
          ),
          const SizedBox(height: 12),
          _SettingsTile(
            icon: Icons.workspace_premium_outlined,
            title: _isPro ? 'Waypoint Pro' : 'Go Pro',
            subtitle: _isPro
                ? 'Active — enjoy full access'
                : 'Unlock Companion, Search & more',
            t: t,
            onTap: _isPro ? () {} : _openPaywall,
          ),
          const SizedBox(height: 12),
          _SettingsTile(
            icon: Icons.chat_outlined,
            title: 'Send Feedback',
            subtitle: 'Share a thought or report an issue',
            t: t,
            onTap: _showFeedbackSheet,
          ),
          const SizedBox(height: 32),
          Center(
            child: Text(
              'Waypoint • Version 1.1.0',
              style: TextStyle(
                fontFamily: 'Georgia',
                fontSize: 13,
                color: t.textHint,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              GestureDetector(
                onTap: () => _launchUrl(
                    'https://VeilAIapp.github.io/waypoint-legal/privacy_policy.html'),
                child: Text(
                  'Privacy Policy',
                  style: TextStyle(
                    fontFamily: 'Georgia',
                    fontSize: 12,
                    color: t.textSecondary,
                    decoration: TextDecoration.underline,
                    decorationColor: t.textSecondary,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Text(
                  '·',
                  style: TextStyle(
                    fontFamily: 'Georgia',
                    fontSize: 12,
                    color: t.textHint,
                  ),
                ),
              ),
              GestureDetector(
                onTap: () => _launchUrl(
                    'https://VeilAIapp.github.io/waypoint-legal/terms_of_service.html'),
                child: Text(
                  'Terms of Service',
                  style: TextStyle(
                    fontFamily: 'Georgia',
                    fontSize: 12,
                    color: t.textSecondary,
                    decoration: TextDecoration.underline,
                    decorationColor: t.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

// ── Live theme preview card ───────────────────────────────────────────────────

class _ThemePreviewCard extends StatelessWidget {
  final String name;
  final WaypointThemeData themeData;
  final WaypointThemeData activeT;
  final bool isSelected;
  final VoidCallback onTap;

  const _ThemePreviewCard({
    required this.name,
    required this.themeData,
    required this.activeT,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final td = themeData;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? activeT.primary : activeT.cardBorder,
            width: isSelected ? 2.5 : 1.5,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(13),
          child: Container(
            color: td.background,
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Mini app bar ──────────────────────────────
                Row(
                  children: [
                    Container(
                      width: 30,
                      height: 4,
                      decoration: BoxDecoration(
                        color: td.textPrimary.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const Spacer(),
                    Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: td.primary.withValues(alpha: 0.85),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 9),

                // ── Mini verse card ───────────────────────────
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  decoration: BoxDecoration(
                    color: td.cardBg,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: td.cardBorder),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 3,
                        height: 28,
                        decoration: BoxDecoration(
                          color: td.primary,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              height: 4,
                              decoration: BoxDecoration(
                                color: td.textPrimary.withValues(alpha: 0.6),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            const SizedBox(height: 5),
                            Container(
                              height: 4,
                              width: double.infinity,
                              decoration: BoxDecoration(
                                color: td.textPrimary.withValues(alpha: 0.35),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            const SizedBox(height: 5),
                            Container(
                              height: 4,
                              width: 28,
                              decoration: BoxDecoration(
                                color: td.primary.withValues(alpha: 0.7),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 9),

                // ── Mini streak dots ──────────────────────────
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: List.generate(7, (i) {
                    final filled = i < 4;
                    return Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: filled ? td.primary : td.unearnedBg,
                        border: filled
                            ? null
                            : Border.all(color: td.cardBorder, width: 0.8),
                      ),
                    );
                  }),
                ),

                const SizedBox(height: 10),

                // ── Mini nav bar ──────────────────────────────
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  decoration: BoxDecoration(
                    color: td.navBg,
                    borderRadius: BorderRadius.circular(6),
                    border: Border(
                      top: BorderSide(color: td.cardBorder, width: 0.5),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _MiniNavDot(color: td.primary, active: true),
                      _MiniNavDot(color: td.textHint, active: false),
                      _MiniNavDot(color: td.textHint, active: false),
                      _MiniNavDot(color: td.textHint, active: false),
                    ],
                  ),
                ),

                const SizedBox(height: 10),

                // ── Label + selection indicator ───────────────
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      name,
                      style: TextStyle(
                        fontFamily: 'Georgia',
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: td.textPrimary,
                      ),
                    ),
                    if (isSelected)
                      Container(
                        width: 16,
                        height: 16,
                        decoration: BoxDecoration(
                          color: td.primary,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.check,
                          color: td.onPrimary,
                          size: 10,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Feedback sheet ────────────────────────────────────────────────────────────

class _FeedbackSheet extends StatefulWidget {
  const _FeedbackSheet();

  @override
  State<_FeedbackSheet> createState() => _FeedbackSheetState();
}

class _FeedbackSheetState extends State<_FeedbackSheet> {
  final _controller = TextEditingController();
  String? _selectedMood;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = WaypointTheme.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 12),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: t.cardBorder,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(
                'Send Feedback',
                style: TextStyle(
                  fontFamily: 'Georgia',
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: t.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'We read every message.',
                style: TextStyle(
                  fontFamily: 'Georgia',
                  fontSize: 13,
                  color: t.textSecondary,
                ),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  for (final mood in ['😊', '😐', '😞'])
                    GestureDetector(
                      onTap: () => setState(() => _selectedMood = mood),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          color: _selectedMood == mood
                              ? t.primary.withValues(alpha: 0.12)
                              : t.background,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: _selectedMood == mood
                                ? t.primary
                                : t.cardBorder,
                            width: _selectedMood == mood ? 2 : 1,
                          ),
                        ),
                        child: Center(
                          child: Text(
                            mood,
                            style: const TextStyle(fontSize: 32),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              Container(
                decoration: BoxDecoration(
                  color: t.inputFill,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: t.cardBorder),
                ),
                child: TextField(
                  controller: _controller,
                  maxLines: 4,
                  style: TextStyle(
                    fontFamily: 'Georgia',
                    fontSize: 15,
                    color: t.textPrimary,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Tell us what\'s on your mind...',
                    hintStyle: TextStyle(
                      fontFamily: 'Georgia',
                      color: t.textHint,
                      fontSize: 15,
                    ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.all(16),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              GestureDetector(
                onTap: () {
                  final mood = _selectedMood ?? '';
                  final message = _controller.text.trim();
                  final moodLine = mood.isNotEmpty ? 'Mood: $mood\n\n' : '';
                  final body =
                      '$moodLine${message.isEmpty ? '(no message)' : message}';
                  Navigator.of(context).pop(body);
                },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 14),
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
                    child: Text(
                      'Submit Feedback',
                      style: TextStyle(
                        fontFamily: 'Georgia',
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: t.onPrimary,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniNavDot extends StatelessWidget {
  final Color color;
  final bool active;
  const _MiniNavDot({required this.color, required this.active});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: active ? 12 : 8,
      height: active ? 5 : 4,
      decoration: BoxDecoration(
        color: color.withValues(alpha: active ? 0.9 : 0.5),
        borderRadius: BorderRadius.circular(3),
      ),
    );
  }
}

// ── Settings tile ─────────────────────────────────────────────────────────────

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final WaypointThemeData t;
  final VoidCallback onTap;

  const _SettingsTile({
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
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: t.cardBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: t.cardBorder),
        ),
        child: Row(
          children: [
            Icon(icon, color: t.primary, size: 22),
            const SizedBox(width: 16),
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
                      fontSize: 13,
                      color: t.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: t.textHint),
          ],
        ),
      ),
    );
  }
}

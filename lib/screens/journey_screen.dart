import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_theme.dart';

// ── Badge definitions ─────────────────────────────────────────────────────────

class Badge {
  final String id;
  final IconData iconData;
  final String name;
  final String description;
  final String category;

  const Badge({
    required this.id,
    required this.iconData,
    required this.name,
    required this.description,
    required this.category,
  });
}

const List<Badge> kAllBadges = [
  Badge(id: 'streak_3',          iconData: Icons.eco,                   name: 'First Steps',         description: '3 day streak',               category: 'Streaks'),
  Badge(id: 'streak_7',          iconData: Icons.spa,                   name: 'Faithful Week',        description: '7 day streak',               category: 'Streaks'),
  Badge(id: 'streak_30',         iconData: Icons.park,                  name: 'Seeking Heart',        description: '30 day streak',              category: 'Streaks'),
  Badge(id: 'streak_100',        iconData: Icons.auto_awesome,          name: 'Abiding',              description: '100 day streak',             category: 'Streaks'),
  Badge(id: 'streak_365',        iconData: Icons.workspace_premium,     name: 'Year of Grace',        description: '365 day streak',             category: 'Streaks'),
  Badge(id: 'chat_1',            iconData: Icons.chat_bubble,           name: 'Ask and Receive',      description: 'First conversation',         category: 'Companion'),
  Badge(id: 'chat_10',           iconData: Icons.local_fire_department, name: 'Deeper Waters',        description: '10 conversations',           category: 'Companion'),
  Badge(id: 'chat_50',           iconData: Icons.menu_book,             name: 'Student of the Word',  description: '50 conversations',           category: 'Companion'),
  Badge(id: 'setup_denomination',iconData: Icons.church,                name: 'Rooted',               description: 'Set your faith background',  category: 'Journey'),
  Badge(id: 'journal_1',         iconData: Icons.edit_note,             name: 'Written on the Heart', description: 'First journal entry',        category: 'Journey'),
  Badge(id: 'highlight_1',       iconData: Icons.star,                  name: 'Marked',               description: 'First verse highlighted',    category: 'Journey'),
  Badge(id: 'book_john',         iconData: Icons.history_edu,           name: 'Word Made Flesh',      description: 'Read the book of John',      category: 'Books'),
  Badge(id: 'book_psalms',       iconData: Icons.music_note,            name: 'Songs of Ascent',      description: 'Read the Psalms',            category: 'Books'),
  Badge(id: 'book_proverbs',     iconData: Icons.psychology,            name: 'Wisdom Seeker',        description: 'Read Proverbs',              category: 'Books'),
  Badge(id: 'book_romans',       iconData: Icons.bolt,                  name: 'The Gospel Unpacked',  description: 'Read Romans',                category: 'Books'),
  Badge(id: 'book_genesis',      iconData: Icons.public,                name: 'From the Beginning',   description: 'Read Genesis',               category: 'Books'),
];

// ── Journal entry model ───────────────────────────────────────────────────────

class JournalEntry {
  final String id;
  final String text;
  final String? verseRef;
  final DateTime createdAt;

  JournalEntry({
    required this.id,
    required this.text,
    this.verseRef,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        'verseRef': verseRef,
        'createdAt': createdAt.toIso8601String(),
      };

  factory JournalEntry.fromJson(Map<String, dynamic> json) => JournalEntry(
        id: json['id'],
        text: json['text'],
        verseRef: json['verseRef'],
        createdAt: DateTime.parse(json['createdAt']),
      );
}

// ── Journey screen ────────────────────────────────────────────────────────────

class JourneyScreen extends StatefulWidget {
  final SharedPreferences prefs;
  const JourneyScreen({super.key, required this.prefs});

  @override
  State<JourneyScreen> createState() => _JourneyScreenState();
}

class _JourneyScreenState extends State<JourneyScreen> {
  late Set<String> _earnedBadgeIds;
  List<JournalEntry> _entries = [];

  @override
  void initState() {
    super.initState();
    _loadEarnedBadges();
    _checkAutoEarnBadges();
    _loadEntries();
  }

  void _loadEarnedBadges() {
    final earned = widget.prefs.getStringList('earned_badges') ?? [];
    _earnedBadgeIds = earned.toSet();
  }

  void _checkAutoEarnBadges() {
    final streak = widget.prefs.getInt('streak') ?? 0;
    final chatCount = widget.prefs.getInt('chat_count') ?? 0;
    final denomination = widget.prefs.getString('user_denomination');

    if (streak >= 3) _earnedBadgeIds.add('streak_3');
    if (streak >= 7) _earnedBadgeIds.add('streak_7');
    if (streak >= 30) _earnedBadgeIds.add('streak_30');
    if (streak >= 100) _earnedBadgeIds.add('streak_100');
    if (streak >= 365) _earnedBadgeIds.add('streak_365');
    if (chatCount >= 1) _earnedBadgeIds.add('chat_1');
    if (chatCount >= 10) _earnedBadgeIds.add('chat_10');
    if (chatCount >= 50) _earnedBadgeIds.add('chat_50');
    if (denomination != null) _earnedBadgeIds.add('setup_denomination');

    widget.prefs.setStringList('earned_badges', _earnedBadgeIds.toList());
  }

  void _loadEntries() {
    final raw = widget.prefs.getStringList('journal_entries') ?? [];
    _entries = raw
        .expand((e) {
          try {
            return [JournalEntry.fromJson(jsonDecode(e))];
          } catch (_) {
            return <JournalEntry>[];
          }
        })
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  void _saveEntries() {
    final raw = _entries.map((e) => jsonEncode(e.toJson())).toList();
    widget.prefs.setStringList('journal_entries', raw);
  }

  void _addEntry(String text, String? verseRef) {
    final entry = JournalEntry(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      text: text,
      verseRef: verseRef?.isNotEmpty == true ? verseRef : null,
      createdAt: DateTime.now(),
    );
    setState(() {
      _entries.insert(0, entry);
      _earnedBadgeIds.add('journal_1');
      widget.prefs.setStringList('earned_badges', _earnedBadgeIds.toList());
    });
    _saveEntries();
  }

  void _deleteEntry(String id) {
    setState(() {
      _entries.removeWhere((e) => e.id == id);
    });
    _saveEntries();
  }

  void _showNewEntrySheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: WaypointTheme.of(context).cardBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _NewEntrySheet(onSave: _addEntry),
    );
  }

  void _showBadgeDetail(Badge badge, bool earned) {
    final t = WaypointTheme.of(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: t.cardBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: t.cardBorder,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 24),
                Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: earned
                        ? LinearGradient(
                            colors: [t.primary, t.secondary],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          )
                        : null,
                    color: earned ? null : t.unearnedBg,
                    border: Border.all(color: t.cardBorder, width: 2),
                  ),
                  child: Icon(
                    badge.iconData,
                    size: 40,
                    color: earned ? t.onPrimary : t.textHint,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  badge.name,
                  style: TextStyle(
                    fontFamily: 'Georgia',
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: earned ? t.textPrimary : t.textHint,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  badge.description,
                  style: TextStyle(
                    fontFamily: 'Georgia',
                    fontSize: 15,
                    color: t.textSecondary,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: earned ? t.accentLight : t.unearnedBg,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    earned ? '✓ Earned' : 'Not yet earned',
                    style: TextStyle(
                      fontFamily: 'Georgia',
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: earned ? t.primary : t.textHint,
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
    final earnedBadges =
        kAllBadges.where((b) => _earnedBadgeIds.contains(b.id)).toList();
    final lockedBadges =
        kAllBadges.where((b) => !_earnedBadgeIds.contains(b.id)).toList();
    final allOrdered = [...earnedBadges, ...lockedBadges];

    return Scaffold(
      backgroundColor: t.background,
      appBar: AppBar(
        backgroundColor: t.background,
        centerTitle: true,
        title: Text(
          'My Journey',
          style: TextStyle(
            fontFamily: 'Georgia',
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: t.textPrimary,
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showNewEntrySheet,
        backgroundColor: t.primary,
        child: Icon(Icons.add, color: t.onPrimary),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            // ── Badge shelf ───────────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Badges',
                  style: TextStyle(
                    fontFamily: 'Georgia',
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: t.textPrimary,
                  ),
                ),
                Text(
                  '${earnedBadges.length} of ${kAllBadges.length} earned',
                  style: TextStyle(
                    fontFamily: 'Georgia',
                    fontSize: 13,
                    color: t.textSecondary,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 14),

            SizedBox(
              height: 110,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: allOrdered.length,
                separatorBuilder: (_, _) => const SizedBox(width: 12),
                itemBuilder: (context, index) {
                  final badge = allOrdered[index];
                  final earned = _earnedBadgeIds.contains(badge.id);
                  return GestureDetector(
                    onTap: () => _showBadgeDetail(badge, earned),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 70,
                          height: 70,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: earned
                                ? LinearGradient(
                                    colors: [t.primary, t.secondary],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  )
                                : null,
                            color: earned ? null : t.unearnedBg,
                            border: Border.all(
                              color: t.cardBorder,
                              width: 2,
                            ),
                            boxShadow: earned
                                ? [
                                    BoxShadow(
                                      color: t.primary.withValues(alpha: 0.15),
                                      blurRadius: 8,
                                      offset: const Offset(0, 3),
                                    )
                                  ]
                                : [],
                          ),
                          child: Center(
                            child: Icon(
                              badge.iconData,
                              size: 28,
                              color: earned ? t.onPrimary : t.textHint.withValues(alpha: 0.4),
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        SizedBox(
                          width: 70,
                          child: Text(
                            badge.name,
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: 'Georgia',
                              fontSize: 10,
                              color: earned ? t.textPrimary : t.textHint,
                              fontWeight: earned
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),

            const SizedBox(height: 32),

            // ── Journal & Highlights ──────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Journal & Highlights',
                  style: TextStyle(
                    fontFamily: 'Georgia',
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: t.textPrimary,
                  ),
                ),
                GestureDetector(
                  onTap: _showNewEntrySheet,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 7),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [t.primary, t.secondary],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.add, size: 14, color: t.onPrimary),
                        const SizedBox(width: 4),
                        Text(
                          'New Entry',
                          style: TextStyle(
                            fontFamily: 'Georgia',
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: t.onPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            if (_entries.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  color: t.cardBg,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: t.cardBorder),
                ),
                child: Column(
                  children: [
                    Icon(Icons.edit_note, size: 44, color: t.textHint),
                    const SizedBox(height: 12),
                    Text(
                      'Nothing saved yet',
                      style: TextStyle(
                        fontFamily: 'Georgia',
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: t.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Tap New Entry to write your first reflection',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'Georgia',
                        fontSize: 13,
                        color: t.textHint,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              )
            else
              ...(_entries.map((entry) => _JournalCard(
                    entry: entry,
                    t: t,
                    onDelete: () => _deleteEntry(entry.id),
                  ))),

            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }
}

// ── Journal card ──────────────────────────────────────────────────────────────

class _JournalCard extends StatelessWidget {
  final JournalEntry entry;
  final WaypointThemeData t;
  final VoidCallback onDelete;

  const _JournalCard({required this.entry, required this.t, required this.onDelete});

  String _formatDate(DateTime dt) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: t.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: t.cardBorder),
        boxShadow: [
          BoxShadow(
            color: t.primary.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              if (entry.verseRef != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: t.accentLight,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    entry.verseRef!,
                    style: TextStyle(
                      fontFamily: 'Georgia',
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: t.primary,
                    ),
                  ),
                )
              else
                const SizedBox(),
              Row(
                children: [
                  Text(
                    _formatDate(entry.createdAt),
                    style: TextStyle(
                      fontFamily: 'Georgia',
                      fontSize: 12,
                      color: t.textHint,
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () {
                      showDialog(
                        context: context,
                        builder: (_) {
                          return AlertDialog(
                            backgroundColor: t.cardBg,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16)),
                            title: Text(
                              'Delete entry?',
                              style: TextStyle(
                                  fontFamily: 'Georgia',
                                  color: t.textPrimary),
                            ),
                            content: Text(
                              'This cannot be undone.',
                              style: TextStyle(
                                  fontFamily: 'Georgia',
                                  color: t.textSecondary),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: Text('Cancel',
                                    style: TextStyle(
                                        fontFamily: 'Georgia',
                                        color: t.textSecondary)),
                              ),
                              TextButton(
                                onPressed: () {
                                  Navigator.pop(context);
                                  onDelete();
                                },
                                child: Text('Delete',
                                    style: TextStyle(
                                        fontFamily: 'Georgia',
                                        color: t.primary,
                                        fontWeight: FontWeight.bold)),
                              ),
                            ],
                          );
                        },
                      );
                    },
                    child: Icon(Icons.more_horiz, color: t.textHint, size: 18),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            entry.text,
            style: TextStyle(
              fontFamily: 'Georgia',
              fontSize: 15,
              color: t.textPrimary,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }
}

// ── New entry sheet ───────────────────────────────────────────────────────────

class _NewEntrySheet extends StatefulWidget {
  final void Function(String text, String verseRef) onSave;
  const _NewEntrySheet({required this.onSave});

  @override
  State<_NewEntrySheet> createState() => _NewEntrySheetState();
}

class _NewEntrySheetState extends State<_NewEntrySheet> {
  final _textController = TextEditingController();
  final _verseController = TextEditingController();

  @override
  void dispose() {
    _textController.dispose();
    _verseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = WaypointTheme.of(context);
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: t.cardBorder,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'New Journal Entry',
                style: TextStyle(
                  fontFamily: 'Georgia',
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: t.textPrimary,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _verseController,
                style: TextStyle(
                  fontFamily: 'Georgia',
                  fontSize: 14,
                  color: t.textPrimary,
                ),
                decoration: InputDecoration(
                  hintText: 'Verse reference (optional) — e.g. John 3:16',
                  hintStyle: TextStyle(
                    fontFamily: 'Georgia',
                    color: t.textHint,
                    fontSize: 14,
                  ),
                  filled: true,
                  fillColor: t.inputFill,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  prefixIcon: Icon(
                    Icons.menu_book_outlined,
                    color: t.primary,
                    size: 18,
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _textController,
                maxLines: 6,
                autofocus: true,
                style: TextStyle(
                  fontFamily: 'Georgia',
                  fontSize: 15,
                  color: t.textPrimary,
                  height: 1.6,
                ),
                decoration: InputDecoration(
                  hintText: 'What\'s on your heart today?',
                  hintStyle: TextStyle(
                    fontFamily: 'Georgia',
                    color: t.textHint,
                    fontSize: 15,
                  ),
                  filled: true,
                  fillColor: t.inputFill,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.all(16),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: GestureDetector(
                  onTap: () {
                    final text = _textController.text.trim();
                    if (text.isEmpty) return;
                    Navigator.pop(context);
                    widget.onSave(text, _verseController.text.trim());
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [t.primary, t.secondary],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Center(
                      child: Text(
                        'Save Entry',
                        style: TextStyle(
                          fontFamily: 'Georgia',
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: t.onPrimary,
                        ),
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

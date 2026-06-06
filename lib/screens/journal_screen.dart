import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_theme.dart';
import 'journey_screen.dart' show JournalEntry;

class JournalScreen extends StatefulWidget {
  final SharedPreferences prefs;
  const JournalScreen({super.key, required this.prefs});

  @override
  State<JournalScreen> createState() => _JournalScreenState();
}

class _JournalScreenState extends State<JournalScreen> {
  List<JournalEntry> _entries = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    final raw = widget.prefs.getStringList('journal_entries') ?? [];
    setState(() {
      _entries = raw.expand((e) {
        try {
          return [JournalEntry.fromJson(jsonDecode(e))];
        } catch (_) {
          return <JournalEntry>[];
        }
      }).toList();
    });
  }

  void _delete(String id) {
    setState(() => _entries.removeWhere((e) => e.id == id));
    final raw = _entries.map((e) => jsonEncode(e.toJson())).toList();
    widget.prefs.setStringList('journal_entries', raw);
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
          'Journal',
          style: TextStyle(
            fontFamily: 'Georgia',
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: t.textPrimary,
          ),
        ),
      ),
      body: _entries.isEmpty ? _buildEmpty(t) : _buildList(t),
    );
  }

  Widget _buildEmpty(WaypointThemeData t) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    t.primary.withValues(alpha: 0.12),
                    t.secondary.withValues(alpha: 0.08),
                  ],
                ),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.edit_note_rounded, size: 48, color: t.primary),
            ),
            const SizedBox(height: 24),
            Text(
              'Nothing written yet',
              style: TextStyle(
                fontFamily: 'Georgia',
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: t.textPrimary,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Long-press any verse in the Bible\nto save a reflection here.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Georgia',
                fontSize: 14,
                color: t.textHint,
                height: 1.6,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildList(WaypointThemeData t) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      itemCount: _entries.length,
      itemBuilder: (_, i) => _JournalCard(
        entry: _entries[i],
        t: t,
        onDelete: () => _confirmDelete(_entries[i].id, t),
      ),
    );
  }

  void _confirmDelete(String id, WaypointThemeData t) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: t.cardBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Delete entry?',
          style: TextStyle(fontFamily: 'Georgia', color: t.textPrimary),
        ),
        content: Text(
          'This cannot be undone.',
          style: TextStyle(fontFamily: 'Georgia', color: t.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel',
                style: TextStyle(fontFamily: 'Georgia', color: t.textSecondary)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _delete(id);
            },
            child: Text('Delete',
                style: TextStyle(fontFamily: 'Georgia', color: Colors.red)),
          ),
        ],
      ),
    );
  }
}

class _JournalCard extends StatelessWidget {
  final JournalEntry entry;
  final WaypointThemeData t;
  final VoidCallback onDelete;

  const _JournalCard({
    required this.entry,
    required this.t,
    required this.onDelete,
  });

  String _formatDate(DateTime dt) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
                    onTap: onDelete,
                    child: Icon(Icons.delete_outline,
                        size: 18, color: t.textHint),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
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

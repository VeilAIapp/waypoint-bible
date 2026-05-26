import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_theme.dart';
import '../services/bible_api_service.dart';
import '../models/verse_highlight.dart';

class BibleVerseScreen extends StatefulWidget {
  final String bookName;
  final int chapter;
  final SharedPreferences prefs;
  final void Function(String prompt)? onPromptSelected;

  const BibleVerseScreen({
    super.key,
    required this.bookName,
    required this.chapter,
    required this.prefs,
    this.onPromptSelected,
  });

  @override
  State<BibleVerseScreen> createState() => _BibleVerseScreenState();
}

class _BibleVerseScreenState extends State<BibleVerseScreen> {
  BibleChapterData? _data;
  String? _error;
  bool _loading = true;
  late int _currentChapter;
  late String _translation;
  Set<String> _highlightedRefs = {};

  @override
  void initState() {
    super.initState();
    _currentChapter = widget.chapter;
    _translation = widget.prefs.getString('bible_translation') ?? BibleApiService.defaultTranslation;
    _highlightedRefs = loadHighlights(widget.prefs).map((h) => h.verseRef).toSet();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await BibleApiService.fetchChapter(
        widget.bookName,
        _currentChapter,
        translation: _translation,
      );
      if (mounted) setState(() { _data = data; _loading = false; });
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Could not load chapter. Please check your connection and try again.';
          _loading = false;
        });
      }
    }
  }

  int get _totalChapters => BibleApiService.chapterCounts[widget.bookName] ?? 1;

  void _goToChapter(int chapter) {
    setState(() => _currentChapter = chapter);
    _load();
  }

  void _toggleHighlight(BuildContext screenCtx, BibleVerse verse, WaypointThemeData t) {
    final ref = '${widget.bookName} $_currentChapter:${verse.number}';
    final highlights = loadHighlights(widget.prefs);
    final idx = highlights.indexWhere((h) => h.verseRef == ref);

    if (idx != -1) {
      highlights.removeAt(idx);
      saveHighlights(widget.prefs, highlights);
      setState(() => _highlightedRefs.remove(ref));
      ScaffoldMessenger.of(screenCtx).showSnackBar(SnackBar(
        content: const Text('Highlight removed', style: TextStyle(fontFamily: 'Georgia')),
        backgroundColor: t.primary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
    } else {
      final highlight = VerseHighlight(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        verseRef: ref,
        verseText: verse.text,
        createdAt: DateTime.now(),
      );
      highlights.insert(0, highlight);
      saveHighlights(widget.prefs, highlights);
      setState(() => _highlightedRefs.add(ref));

      final badges = widget.prefs.getStringList('earned_badges') ?? [];
      if (!badges.contains('highlight_1')) {
        badges.add('highlight_1');
        widget.prefs.setStringList('earned_badges', badges);
      }

      ScaffoldMessenger.of(screenCtx).showSnackBar(SnackBar(
        content: const Text('Verse highlighted', style: TextStyle(fontFamily: 'Georgia')),
        backgroundColor: t.primary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
    }
  }

  void _showVerseActions(BuildContext screenCtx, BibleVerse verse, WaypointThemeData t) {
    final ref = '${widget.bookName} $_currentChapter:${verse.number}';
    final isHighlighted = _highlightedRefs.contains(ref);

    showModalBottomSheet(
      context: screenCtx,
      backgroundColor: t.cardBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 4),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: t.cardBorder,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: t.accentLight,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: t.cardBorder),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ref,
                      style: TextStyle(
                        fontFamily: 'Georgia',
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: t.primary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      verse.text,
                      style: TextStyle(
                        fontFamily: 'Georgia',
                        fontSize: 14,
                        color: t.textPrimary,
                        height: 1.5,
                      ),
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
            _ActionTile(
              icon: Icons.chat_bubble_outline,
              label: 'Discuss with AI Companion',
              color: t.primary,
              onTap: () {
                final prompt =
                    'I\'d like to discuss $ref ($_translation): "${verse.text}" — '
                    'Can you explain what this verse means, its historical context, '
                    'and how I can apply it to my life today?';
                Navigator.pop(sheetCtx);
                Navigator.of(screenCtx).popUntil((route) => route.isFirst);
                widget.onPromptSelected?.call(prompt);
              },
            ),
            _ActionTile(
              icon: Icons.book_outlined,
              label: 'Add to Journal',
              color: t.primary,
              onTap: () {
                Navigator.pop(sheetCtx);
                _showAddToJournalDialog(screenCtx, verse, ref, t);
              },
            ),
            _ActionTile(
              icon: isHighlighted ? Icons.bookmark : Icons.bookmark_outline,
              label: isHighlighted ? 'Remove Highlight' : 'Highlight Verse',
              color: t.primary,
              onTap: () {
                Navigator.pop(sheetCtx);
                _toggleHighlight(screenCtx, verse, t);
              },
            ),
            _ActionTile(
              icon: Icons.copy_outlined,
              label: 'Copy Verse',
              color: t.textSecondary,
              onTap: () {
                Navigator.pop(sheetCtx);
                Clipboard.setData(ClipboardData(text: '$ref ($_translation)\n${verse.text}'));
                ScaffoldMessenger.of(screenCtx).showSnackBar(
                  SnackBar(
                    content: const Text(
                      'Verse copied',
                      style: TextStyle(fontFamily: 'Georgia'),
                    ),
                    backgroundColor: t.primary,
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                );
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _showAddToJournalDialog(
    BuildContext context,
    BibleVerse verse,
    String ref,
    WaypointThemeData t,
  ) {
    final controller = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: t.cardBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Add to Journal',
          style: TextStyle(fontFamily: 'Georgia', color: t.textPrimary),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              ref,
              style: TextStyle(
                fontFamily: 'Georgia',
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: t.primary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              verse.text,
              style: TextStyle(
                fontFamily: 'Georgia',
                fontSize: 13,
                color: t.textSecondary,
                height: 1.4,
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              autofocus: true,
              maxLines: 4,
              style: TextStyle(fontFamily: 'Georgia', color: t.textPrimary),
              decoration: InputDecoration(
                hintText: 'What does this verse mean to you?',
                hintStyle: TextStyle(fontFamily: 'Georgia', color: t.textHint),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Cancel',
              style: TextStyle(fontFamily: 'Georgia', color: t.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () {
              final text = controller.text.trim();
              if (text.isNotEmpty) {
                _saveJournalEntry(text, ref);
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text(
                      'Added to journal',
                      style: TextStyle(fontFamily: 'Georgia'),
                    ),
                    backgroundColor: t.primary,
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                );
              }
            },
            child: Text(
              'Save',
              style: TextStyle(
                fontFamily: 'Georgia',
                color: t.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    ).whenComplete(() => controller.dispose());
  }

  void _saveJournalEntry(String text, String verseRef) {
    final entries = widget.prefs.getStringList('journal_entries') ?? [];
    entries.insert(
      0,
      jsonEncode({
        'id': DateTime.now().millisecondsSinceEpoch.toString(),
        'text': text,
        'verseRef': verseRef,
        'createdAt': DateTime.now().toIso8601String(),
      }),
    );
    widget.prefs.setStringList('journal_entries', entries);

    final badges = widget.prefs.getStringList('earned_badges') ?? [];
    if (!badges.contains('journal_1')) {
      badges.add('journal_1');
      widget.prefs.setStringList('earned_badges', badges);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = WaypointTheme.of(context);
    return Scaffold(
      backgroundColor: t.background,
      appBar: AppBar(
        backgroundColor: t.background,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios, color: t.textPrimary, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          '${widget.bookName} $_currentChapter',
          style: TextStyle(
            fontFamily: 'Georgia',
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: t.textPrimary,
          ),
        ),
        centerTitle: true,
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 16),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              color: t.cardBg,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: t.cardBorder),
            ),
            child: Text(
              _translation,
              style: TextStyle(
                fontFamily: 'Georgia',
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: t.primary,
              ),
            ),
          ),
        ],
      ),
      body: _buildBody(context, t),
      bottomNavigationBar: _buildChapterNav(context, t),
    );
  }

  Widget _buildBody(BuildContext context, WaypointThemeData t) {
    if (_loading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: t.primary, strokeWidth: 2),
            const SizedBox(height: 16),
            Text(
              'Loading chapter...',
              style: TextStyle(
                fontFamily: 'Georgia',
                color: t.textSecondary,
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.wifi_off_outlined, size: 48, color: t.textHint),
              const SizedBox(height: 16),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Georgia',
                  color: t.textSecondary,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _load,
                child: const Text('Try Again',
                    style: TextStyle(fontFamily: 'Georgia')),
              ),
            ],
          ),
        ),
      );
    }

    final verses = _data?.verses ?? [];
    if (verses.isEmpty) {
      return Center(
        child: Text(
          'No verses found for this chapter.',
          style: TextStyle(fontFamily: 'Georgia', color: t.textSecondary),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
      itemCount: verses.length,
      itemBuilder: (ctx, i) {
        final verse = verses[i];
        return _VerseItem(
          verse: verse,
          t: t,
          onAction: () => _showVerseActions(context, verse, t),
          isHighlighted: _highlightedRefs.contains(
              '${widget.bookName} $_currentChapter:${verse.number}'),
        );
      },
    );
  }

  Widget _buildChapterNav(BuildContext context, WaypointThemeData t) {
    final hasPrev = _currentChapter > 1;
    final hasNext = _currentChapter < _totalChapters;

    return SafeArea(
      top: false,
      child: Container(
        height: 52,
        decoration: BoxDecoration(
          color: t.navBg,
          border: Border(top: BorderSide(color: t.cardBorder)),
        ),
        child: Row(
          children: [
            Expanded(
              child: TextButton(
                onPressed: hasPrev ? () => _goToChapter(_currentChapter - 1) : null,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.arrow_back_ios,
                      size: 13,
                      color: hasPrev ? t.primary : t.textHint,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Previous',
                      style: TextStyle(
                        fontFamily: 'Georgia',
                        fontSize: 14,
                        color: hasPrev ? t.primary : t.textHint,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Container(width: 1, height: 28, color: t.cardBorder),
            Expanded(
              child: TextButton(
                onPressed: hasNext ? () => _goToChapter(_currentChapter + 1) : null,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Next',
                      style: TextStyle(
                        fontFamily: 'Georgia',
                        fontSize: 14,
                        color: hasNext ? t.primary : t.textHint,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.arrow_forward_ios,
                      size: 13,
                      color: hasNext ? t.primary : t.textHint,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VerseItem extends StatelessWidget {
  final BibleVerse verse;
  final WaypointThemeData t;
  final VoidCallback onAction;
  final bool isHighlighted;

  const _VerseItem({
    required this.verse,
    required this.t,
    required this.onAction,
    required this.isHighlighted,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onAction,
      onLongPress: onAction,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isHighlighted)
              Padding(
                padding: const EdgeInsets.only(top: 3, right: 4),
                child: Icon(Icons.bookmark, size: 12, color: t.primary),
              ),
            Expanded(
              child: RichText(
                text: TextSpan(
                  children: [
                    TextSpan(
                      text: '${verse.number} ',
                      style: TextStyle(
                        fontFamily: 'Georgia',
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: t.primary,
                        height: 1.8,
                      ),
                    ),
                    TextSpan(
                      text: verse.text,
                      style: TextStyle(
                        fontFamily: 'Georgia',
                        fontSize: 17,
                        color: t.textPrimary,
                        height: 1.75,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionTile({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: color, size: 22),
      title: Text(
        label,
        style: TextStyle(fontFamily: 'Georgia', color: color, fontSize: 15),
      ),
      onTap: onTap,
    );
  }
}

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

// Represents a single row in the infinite scroll list — either a chapter divider or a verse.
class _ListItem {
  final bool isHeader;
  final BibleChapterData chapter;
  final BibleVerse? verse;

  const _ListItem.header(this.chapter)
      : isHeader = true,
        verse = null;

  const _ListItem.verse(this.chapter, BibleVerse v)
      : isHeader = false,
        verse = v;
}

class _BibleVerseScreenState extends State<BibleVerseScreen> {
  final _scrollController = ScrollController();
  final List<BibleChapterData> _chapters = [];
  final List<_ListItem> _items = [];

  bool _initialLoading = true;
  String? _initialError;
  bool _loadingPrev = false;
  bool _loadingNext = false;
  bool _reachedStart = false;
  bool _reachedEnd = false;
  bool _hasScrolledPastTopThreshold = false;
  String _headerLabel = '';
  late String _translation;
  Set<String> _highlightedRefs = {};

  // SharedPreferences keys for scroll position memory
  static const _kScrollBook = 'bible_scroll_book';
  static const _kScrollChapter = 'bible_scroll_chapter';
  static const _kScrollOffset = 'bible_scroll_offset';

  // Approximate item heights used only for chapter-heading estimation while scrolling.
  // Exact pixel accuracy is not needed — just close enough to know which chapter is visible.
  static const double _kVerseEstHeight = 90.0;
  static const double _kDividerEstHeight = 68.0;

  @override
  void initState() {
    super.initState();
    _translation =
        widget.prefs.getString('bible_translation') ?? BibleApiService.defaultTranslation;
    _highlightedRefs =
        loadHighlights(widget.prefs).map((h) => h.verseRef).toSet();
    _headerLabel = '${widget.bookName} ${widget.chapter}';
    _scrollController.addListener(_onScroll);
    _loadInitialChapter();
  }

  @override
  void dispose() {
    _saveScrollPosition();
    _scrollController.dispose();
    super.dispose();
  }

  // ── Scroll position memory ──────────────────────────────────────────────────

  void _saveScrollPosition() {
    if (_chapters.isEmpty || !_scrollController.hasClients) return;
    widget.prefs.setString(_kScrollBook, widget.bookName);
    widget.prefs.setInt(_kScrollChapter, widget.chapter);
    widget.prefs.setDouble(_kScrollOffset, _scrollController.offset);
  }

  void _maybeRestoreScrollPosition() {
    final savedBook = widget.prefs.getString(_kScrollBook);
    final savedChapter = widget.prefs.getInt(_kScrollChapter);
    final savedOffset = widget.prefs.getDouble(_kScrollOffset);
    if (savedBook == widget.bookName &&
        savedChapter == widget.chapter &&
        savedOffset != null &&
        savedOffset > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          final max = _scrollController.position.maxScrollExtent;
          _scrollController.jumpTo(savedOffset.clamp(0.0, max));
        }
      });
    }
  }

  // ── Chapter loading ─────────────────────────────────────────────────────────

  Future<void> _loadInitialChapter() async {
    try {
      final data = await BibleApiService.fetchChapter(
        widget.bookName,
        widget.chapter,
        translation: _translation,
      );
      if (!mounted) return;
      setState(() {
        _chapters.add(data);
        _rebuildItems();
        _reachedStart = !data.hasPrev;
        _reachedEnd = !data.hasNext;
        _initialLoading = false;
        _headerLabel = '${data.bookName} ${data.chapterNumber}';
      });
      _maybeRestoreScrollPosition();
    } catch (_) {
      if (mounted) {
        setState(() {
          _initialError =
              'Could not load chapter. Please check your connection and try again.';
          _initialLoading = false;
        });
      }
    }
  }

  Future<void> _loadNext() async {
    if (_loadingNext || _reachedEnd || _chapters.isEmpty) return;
    setState(() => _loadingNext = true);
    final nextNum = _chapters.last.chapterNumber + 1;
    try {
      final data = await BibleApiService.fetchChapter(
        widget.bookName,
        nextNum,
        translation: _translation,
      );
      if (!mounted) return;
      setState(() {
        _chapters.add(data);
        _items.add(_ListItem.header(data));
        for (final v in data.verses) {
          _items.add(_ListItem.verse(data, v));
        }
        _reachedEnd = !data.hasNext;
        _loadingNext = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingNext = false);
    }
  }

  Future<void> _loadPrev() async {
    if (_loadingPrev || _reachedStart || _chapters.isEmpty) return;
    setState(() => _loadingPrev = true);
    final prevNum = _chapters.first.chapterNumber - 1;
    try {
      final data = await BibleApiService.fetchChapter(
        widget.bookName,
        prevNum,
        translation: _translation,
      );
      if (!mounted) return;

      // Capture old maxScrollExtent before inserting content above current view.
      final oldMax = _scrollController.hasClients
          ? _scrollController.position.maxScrollExtent
          : 0.0;

      final newItems = [
        _ListItem.header(data),
        ...data.verses.map((v) => _ListItem.verse(data, v)),
      ];

      setState(() {
        _chapters.insert(0, data);
        _items.insertAll(0, newItems);
        _reachedStart = !data.hasPrev;
        _loadingPrev = false;
      });

      // After the frame repaints, scroll down by the exact height gained above
      // the current position so the visible content stays locked in place.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scrollController.hasClients) return;
        final newMax = _scrollController.position.maxScrollExtent;
        final delta = newMax - oldMax;
        if (delta > 0) {
          _scrollController.jumpTo(
            (_scrollController.offset + delta).clamp(0.0, newMax),
          );
        }
      });
    } catch (_) {
      if (mounted) setState(() => _loadingPrev = false);
    }
  }

  void _rebuildItems() {
    _items.clear();
    for (final ch in _chapters) {
      _items.add(_ListItem.header(ch));
      for (final v in ch.verses) {
        _items.add(_ListItem.verse(ch, v));
      }
    }
  }

  // ── Scroll listener ─────────────────────────────────────────────────────────

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    final offset = pos.pixels;
    final max = pos.maxScrollExtent;
    if (max <= 0) return;

    _updateHeaderLabel(offset);

    if (offset > max * 0.30) {
      _hasScrolledPastTopThreshold = true;
    }

    if (offset > max * 0.70 && !_loadingNext && !_reachedEnd) {
      _loadNext();
    }
    if (_hasScrolledPastTopThreshold && offset < max * 0.30 && !_loadingPrev && !_reachedStart) {
      _loadPrev();
    }
  }

  // Estimates which chapter is at the top of the viewport using cumulative
  // approximate heights. Close enough for a heading label; no pixel-perfect math needed.
  void _updateHeaderLabel(double offset) {
    if (_chapters.isEmpty) return;
    double cumulative = 0;
    BibleChapterData? current;
    for (final ch in _chapters) {
      final height = _kDividerEstHeight + ch.verses.length * _kVerseEstHeight;
      if (offset < cumulative + height) {
        current = ch;
        break;
      }
      cumulative += height;
    }
    current ??= _chapters.last;
    final label = '${current.bookName} ${current.chapterNumber}';
    if (label != _headerLabel) {
      setState(() => _headerLabel = label);
    }
  }

  // ── Verse actions ───────────────────────────────────────────────────────────

  void _toggleHighlight(
      BuildContext screenCtx, BibleVerse verse, int chapterNum, WaypointThemeData t) {
    final ref = '${widget.bookName} $chapterNum:${verse.number}';
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

  void _showVerseActions(
      BuildContext screenCtx, BibleVerse verse, int chapterNum, WaypointThemeData t) {
    final ref = '${widget.bookName} $chapterNum:${verse.number}';
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
                _toggleHighlight(screenCtx, verse, chapterNum, t);
              },
            ),
            _ActionTile(
              icon: Icons.copy_outlined,
              label: 'Copy Verse',
              color: t.textSecondary,
              onTap: () {
                Navigator.pop(sheetCtx);
                Clipboard.setData(
                    ClipboardData(text: '$ref ($_translation)\n${verse.text}'));
                ScaffoldMessenger.of(screenCtx).showSnackBar(
                  SnackBar(
                    content: const Text('Verse copied',
                        style: TextStyle(fontFamily: 'Georgia')),
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
                    content: const Text('Added to journal',
                        style: TextStyle(fontFamily: 'Georgia')),
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

  // ── Build ───────────────────────────────────────────────────────────────────

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
        // Title tracks the chapter currently visible at the top of the scroll view.
        title: Text(
          _headerLabel,
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
    );
  }

  Widget _buildBody(BuildContext context, WaypointThemeData t) {
    if (_initialLoading) {
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

    if (_initialError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.wifi_off_outlined, size: 48, color: t.textHint),
              const SizedBox(height: 16),
              Text(
                _initialError!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Georgia',
                  color: t.textSecondary,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    _initialLoading = true;
                    _initialError = null;
                    _chapters.clear();
                    _items.clear();
                  });
                  _loadInitialChapter();
                },
                child: const Text('Try Again',
                    style: TextStyle(fontFamily: 'Georgia')),
              ),
            ],
          ),
        ),
      );
    }

    if (_items.isEmpty) {
      return Center(
        child: Text(
          'No verses found.',
          style: TextStyle(fontFamily: 'Georgia', color: t.textSecondary),
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 48),
      itemCount: _items.length,
      itemBuilder: (ctx, i) {
        final item = _items[i];
        if (item.isHeader) {
          return _ChapterDivider(
            bookName: item.chapter.bookName,
            chapterNumber: item.chapter.chapterNumber,
            t: t,
            isFirst: i == 0,
          );
        }
        final verse = item.verse!;
        final chNum = item.chapter.chapterNumber;
        final ref = '${widget.bookName} $chNum:${verse.number}';
        return _VerseItem(
          verse: verse,
          t: t,
          onAction: () => _showVerseActions(context, verse, chNum, t),
          isHighlighted: _highlightedRefs.contains(ref),
        );
      },
    );
  }
}

// ── Widgets ─────────────────────────────────────────────────────────────────

class _ChapterDivider extends StatelessWidget {
  final String bookName;
  final int chapterNumber;
  final WaypointThemeData t;
  final bool isFirst;

  const _ChapterDivider({
    required this.bookName,
    required this.chapterNumber,
    required this.t,
    required this.isFirst,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: isFirst ? 12 : 44, bottom: 20),
      child: Row(
        children: [
          Expanded(child: Divider(color: t.cardBorder, thickness: 1)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              '$bookName $chapterNumber',
              style: TextStyle(
                fontFamily: 'Georgia',
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: t.primary,
                letterSpacing: 0.5,
              ),
            ),
          ),
          Expanded(child: Divider(color: t.cardBorder, thickness: 1)),
        ],
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

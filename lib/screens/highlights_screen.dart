import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/verse_highlight.dart';
import '../services/bible_api_service.dart';
import '../theme/app_theme.dart';
import 'bible_verse_screen.dart';

// ── Sort mode ────────────────────────────────────────────────────────────────

enum _SortMode { recent, byBook }

// Parse "John 3:16" → (book: "John", chapter: 3)
(String, int)? _parseRef(String ref) {
  final colon = ref.lastIndexOf(':');
  if (colon == -1) return null;
  final beforeColon = ref.substring(0, colon);
  final lastSpace = beforeColon.lastIndexOf(' ');
  if (lastSpace == -1) return null;
  final book = beforeColon.substring(0, lastSpace);
  final chapter = int.tryParse(beforeColon.substring(lastSpace + 1));
  if (chapter == null) return null;
  return (book, chapter);
}

int _bookSortKey(String verseRef) {
  final parsed = _parseRef(verseRef);
  if (parsed == null) return 999;
  final (book, _) = parsed;
  return BibleApiService.bookNumbers[book] ?? 999;
}

// ── Screen ────────────────────────────────────────────────────────────────────

class HighlightsScreen extends StatefulWidget {
  final SharedPreferences prefs;
  const HighlightsScreen({super.key, required this.prefs});

  @override
  State<HighlightsScreen> createState() => _HighlightsScreenState();
}

class _HighlightsScreenState extends State<HighlightsScreen> {
  List<VerseHighlight> _highlights = [];
  _SortMode _sort = _SortMode.recent;

  @override
  void initState() {
    super.initState();
    _highlights = loadHighlights(widget.prefs);
  }

  List<VerseHighlight> get _sorted {
    final list = List<VerseHighlight>.from(_highlights);
    if (_sort == _SortMode.recent) {
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    } else {
      list.sort((a, b) {
        final cmp = _bookSortKey(a.verseRef).compareTo(_bookSortKey(b.verseRef));
        if (cmp != 0) return cmp;
        return a.verseRef.compareTo(b.verseRef);
      });
    }
    return list;
  }

  void _editNote(VerseHighlight h) {
    showDialog<void>(
      context: context,
      builder: (_) => _NoteEditDialog(
        highlight: h,
        onSave: (note) {
          setState(() => h.note = note);
          final idx = _highlights.indexWhere((x) => x.id == h.id);
          if (idx != -1) _highlights[idx].note = note;
          saveHighlights(widget.prefs, _highlights);
        },
      ),
    );
  }

  void _navigateToVerse(VerseHighlight h) {
    final parsed = _parseRef(h.verseRef);
    if (parsed == null) return;
    final (book, chapter) = parsed;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BibleVerseScreen(
          bookName: book,
          chapter: chapter,
          prefs: widget.prefs,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = WaypointTheme.of(context);
    final sorted = _sorted;

    return Scaffold(
      backgroundColor: t.background,
      appBar: AppBar(
        backgroundColor: t.background,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios, color: t.textPrimary, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        centerTitle: true,
        title: Text(
          'Highlights',
          style: TextStyle(
            fontFamily: 'Georgia',
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: t.textPrimary,
          ),
        ),
        actions: [
          if (sorted.isNotEmpty)
            PopupMenuButton<_SortMode>(
              icon: Icon(Icons.sort, color: t.textSecondary),
              color: t.cardBg,
              onSelected: (mode) => setState(() => _sort = mode),
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: _SortMode.recent,
                  child: Row(
                    children: [
                      Icon(
                        Icons.access_time,
                        size: 18,
                        color: _sort == _SortMode.recent
                            ? t.primary
                            : t.textSecondary,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Most Recent',
                        style: TextStyle(
                          fontFamily: 'Georgia',
                          color: t.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: _SortMode.byBook,
                  child: Row(
                    children: [
                      Icon(
                        Icons.menu_book_outlined,
                        size: 18,
                        color: _sort == _SortMode.byBook
                            ? t.primary
                            : t.textSecondary,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'By Book',
                        style: TextStyle(
                          fontFamily: 'Georgia',
                          color: t.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
      body: sorted.isEmpty ? _buildEmpty(t) : _buildList(sorted, t),
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
              child: Icon(Icons.bookmark_outline, size: 48, color: t.primary),
            ),
            const SizedBox(height: 24),
            Text(
              'No highlights yet',
              style: TextStyle(
                fontFamily: 'Georgia',
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: t.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Tap any verse while reading the Bible,\nthen choose "Highlight Verse" to save\nverses that speak to you.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Georgia',
                fontSize: 14,
                color: t.textSecondary,
                height: 1.65,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildList(List<VerseHighlight> highlights, WaypointThemeData t) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      itemCount: highlights.length,
      itemBuilder: (_, i) => _HighlightCard(
        highlight: highlights[i],
        t: t,
        onNoteEdit: () => _editNote(highlights[i]),
        onRefTap: () => _navigateToVerse(highlights[i]),
      ),
    );
  }
}

// ── Highlight card ────────────────────────────────────────────────────────────

class _HighlightCard extends StatelessWidget {
  final VerseHighlight highlight;
  final WaypointThemeData t;
  final VoidCallback onNoteEdit;
  final VoidCallback onRefTap;

  const _HighlightCard({
    required this.highlight,
    required this.t,
    required this.onNoteEdit,
    required this.onRefTap,
  });

  @override
  Widget build(BuildContext context) {
    final d = highlight.createdAt;
    const months = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final dateStr = '${months[d.month]} ${d.day}, ${d.year}';
    final hasNote = highlight.note != null && highlight.note!.isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
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
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Gradient left bar
                Container(
                  width: 4,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [t.primary, t.secondary],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(16),
                      bottomLeft: Radius.circular(16),
                    ),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Reference + date
                        Row(
                          children: [
                            GestureDetector(
                              onTap: onRefTap,
                              child: Text(
                                highlight.verseRef,
                                style: TextStyle(
                                  fontFamily: 'Georgia',
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: t.primary,
                                  decoration: TextDecoration.underline,
                                  decorationColor: t.primary,
                                ),
                              ),
                            ),
                            const Spacer(),
                            Text(
                              dateStr,
                              style: TextStyle(
                                fontFamily: 'Georgia',
                                fontSize: 11,
                                color: t.textHint,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        // Verse text
                        Text(
                          highlight.verseText,
                          style: TextStyle(
                            fontFamily: 'Georgia',
                            fontSize: 15,
                            color: t.textPrimary,
                            height: 1.65,
                          ),
                        ),
                        // Note
                        if (hasNote) ...[
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: t.accentLight,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(Icons.edit_note,
                                    size: 14, color: t.primary),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    highlight.note!,
                                    style: TextStyle(
                                      fontFamily: 'Georgia',
                                      fontSize: 13,
                                      color: t.textSecondary,
                                      height: 1.45,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Add / Edit note
          Divider(height: 1, color: t.cardBorder),
          GestureDetector(
            onTap: onNoteEdit,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  Icon(
                    hasNote ? Icons.edit_outlined : Icons.add,
                    size: 14,
                    color: t.textSecondary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    hasNote ? 'Edit note' : 'Add a note',
                    style: TextStyle(
                      fontFamily: 'Georgia',
                      fontSize: 12,
                      color: t.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Note edit dialog ──────────────────────────────────────────────────────────

class _NoteEditDialog extends StatefulWidget {
  final VerseHighlight highlight;
  final void Function(String?) onSave;

  const _NoteEditDialog({
    required this.highlight,
    required this.onSave,
  });

  @override
  State<_NoteEditDialog> createState() => _NoteEditDialogState();
}

class _NoteEditDialogState extends State<_NoteEditDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.highlight.note ?? '');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = WaypointTheme.of(context);
    return AlertDialog(
      backgroundColor: t.cardBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(
        widget.highlight.verseRef,
        style: TextStyle(
          fontFamily: 'Georgia',
          fontSize: 15,
          fontWeight: FontWeight.bold,
          color: t.primary,
        ),
      ),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLines: 5,
        style: TextStyle(fontFamily: 'Georgia', color: t.textPrimary),
        decoration: InputDecoration(
          hintText: 'Add a personal note...',
          hintStyle: TextStyle(fontFamily: 'Georgia', color: t.textHint),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(
            'Cancel',
            style: TextStyle(fontFamily: 'Georgia', color: t.textSecondary),
          ),
        ),
        TextButton(
          onPressed: () {
            final note = _controller.text.trim();
            Navigator.pop(context);
            widget.onSave(note.isEmpty ? null : note);
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
    );
  }
}

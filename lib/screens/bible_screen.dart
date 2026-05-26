import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_theme.dart';
import 'bible_chapter_list_screen.dart';

class BibleScreen extends StatelessWidget {
  final SharedPreferences prefs;
  final void Function(String prompt)? onPromptSelected;
  const BibleScreen({super.key, required this.prefs, this.onPromptSelected});

  @override
  Widget build(BuildContext context) {
    final t = WaypointTheme.of(context);
    return Scaffold(
      backgroundColor: t.background,
      appBar: AppBar(
        backgroundColor: t.background,
        centerTitle: true,
        title: Text(
          'Bible',
          style: TextStyle(
            fontFamily: 'Georgia',
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: t.textPrimary,
          ),
        ),
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
              prefs.getString('bible_translation') ?? 'BSB',
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
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
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
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _translationName(prefs.getString('bible_translation') ?? 'BSB'),
                    style: TextStyle(
                      fontFamily: 'Georgia',
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: t.onPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Tap any verse to discuss with your AI companion or add it to your journal.',
                    style: TextStyle(
                      fontFamily: 'Georgia',
                      fontSize: 14,
                      color: t.onPrimary.withValues(alpha: 0.85),
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Search bar
            GestureDetector(
              onTap: () {
                if (onPromptSelected != null) {
                  showDialog(
                    context: context,
                    builder: (_) => _SearchDialog(
                      t: t,
                      onSearch: (query) {
                        Navigator.pop(context);
                        onPromptSelected?.call(
                          'Search the Bible for verses about: "$query". '
                          'Give me the most relevant verses with their references.'
                        );
                      },
                    ),
                  );
                }
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                decoration: BoxDecoration(
                  color: t.cardBg,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: t.cardBorder),
                ),
                child: Row(
                  children: [
                    Icon(Icons.search, color: t.primary, size: 20),
                    const SizedBox(width: 10),
                    Text(
                      'Search Scripture...',
                      style: TextStyle(
                        fontFamily: 'Georgia',
                        fontSize: 14,
                        color: t.textHint,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),
            Text(
              'Old Testament',
              style: TextStyle(
                fontFamily: 'Georgia',
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: t.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            _buildBookGrid(context, t, _oldTestamentBooks),
            const SizedBox(height: 28),
            Text(
              'New Testament',
              style: TextStyle(
                fontFamily: 'Georgia',
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: t.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            _buildBookGrid(context, t, _newTestamentBooks),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildBookGrid(BuildContext context, WaypointThemeData t, List<String> books) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 2.4,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemCount: books.length,
      itemBuilder: (context, index) {
        return GestureDetector(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => BibleChapterListScreen(
                  bookName: books[index],
                  prefs: prefs,
                  onPromptSelected: onPromptSelected,
                ),
              ),
            );
          },
          child: Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: t.cardBg,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: t.cardBorder),
            ),
            child: Text(
              books[index],
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Georgia',
                fontSize: 12,
                color: t.textPrimary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SearchDialog extends StatefulWidget {
  final WaypointThemeData t;
  final void Function(String query) onSearch;
  const _SearchDialog({required this.t, required this.onSearch});

  @override
  State<_SearchDialog> createState() => _SearchDialogState();
}

class _SearchDialogState extends State<_SearchDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    return AlertDialog(
      backgroundColor: t.cardBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(
        'Search Scripture',
        style: TextStyle(fontFamily: 'Georgia', color: t.textPrimary),
      ),
      content: TextField(
        controller: _controller,
        autofocus: true,
        style: TextStyle(fontFamily: 'Georgia', color: t.textPrimary),
        decoration: InputDecoration(
          hintText: 'Topic, feeling, or keyword...',
          hintStyle: TextStyle(fontFamily: 'Georgia', color: t.textHint),
        ),
        onSubmitted: widget.onSearch,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Cancel',
              style: TextStyle(fontFamily: 'Georgia', color: t.textSecondary)),
        ),
        TextButton(
          onPressed: () => widget.onSearch(_controller.text),
          child: Text('Search',
              style: TextStyle(
                  fontFamily: 'Georgia',
                  color: t.primary,
                  fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }
}

String _translationName(String code) {
  switch (code) {
    case 'KJV': return 'King James Version';
    case 'WEB': return 'World English Bible';
    default:    return 'Berean Standard Bible';
  }
}

const List<String> _oldTestamentBooks = [
  'Genesis', 'Exodus', 'Leviticus', 'Numbers', 'Deuteronomy',
  'Joshua', 'Judges', 'Ruth', '1 Samuel', '2 Samuel',
  '1 Kings', '2 Kings', '1 Chronicles', '2 Chronicles', 'Ezra',
  'Nehemiah', 'Esther', 'Job', 'Psalms', 'Proverbs',
  'Ecclesiastes', 'Song of Songs', 'Isaiah', 'Jeremiah', 'Lamentations',
  'Ezekiel', 'Daniel', 'Hosea', 'Joel', 'Amos',
  'Obadiah', 'Jonah', 'Micah', 'Nahum', 'Habakkuk',
  'Zephaniah', 'Haggai', 'Zechariah', 'Malachi',
];

const List<String> _newTestamentBooks = [
  'Matthew', 'Mark', 'Luke', 'John', 'Acts',
  'Romans', '1 Corinthians', '2 Corinthians', 'Galatians', 'Ephesians',
  'Philippians', 'Colossians', '1 Thessalonians', '2 Thessalonians', '1 Timothy',
  '2 Timothy', 'Titus', 'Philemon', 'Hebrews', 'James',
  '1 Peter', '2 Peter', '1 John', '2 John', '3 John',
  'Jude', 'Revelation',
];

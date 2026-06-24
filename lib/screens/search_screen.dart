import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../constants.dart';
import '../theme/app_theme.dart';

const List<String> _suggestions = [
  'anxiety', 'forgiveness', 'hope', 'grief',
  'purpose', 'identity', 'fear', 'faith',
  'love', 'anger', 'loneliness', 'strength',
  'patience', 'wisdom', 'peace', 'gratitude',
];

class VerseResult {
  final String reference;
  final String text;
  final String relevance;

  const VerseResult({
    required this.reference,
    required this.text,
    required this.relevance,
  });

  factory VerseResult.fromJson(Map<String, dynamic> json) {
    return VerseResult(
      reference: json['reference'] as String? ?? '',
      text: json['text'] as String? ?? '',
      relevance: json['relevance'] as String? ?? '',
    );
  }
}

class SearchScreen extends StatefulWidget {
  final SharedPreferences prefs;
  final void Function(String prompt) onPromptSelected;

  const SearchScreen({
    super.key,
    required this.prefs,
    required this.onPromptSelected,
  });

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  List<VerseResult> _results = [];
  bool _loading = false;
  String _error = '';
  String _lastQuery = '';

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _search(String query) async {
    if (query.trim().isEmpty) return;
    _focusNode.unfocus();

    setState(() {
      _loading = true;
      _error = '';
      _results = [];
      _lastQuery = query.trim();
    });

    try {
      final prompt = '''
Search the Bible for verses relevant to the topic or feeling: "$query"

Return ONLY a valid JSON array with 6 results. No other text, no markdown, no explanation outside the JSON.

Format:
[
  {
    "reference": "Book Chapter:Verse",
    "text": "The full verse text",
    "relevance": "One sentence explaining why this verse is relevant to the search"
  }
]

Choose verses that are:
- Directly relevant to the topic
- From a variety of books (Old and New Testament)
- Accessible and meaningful for someone returning to faith
- Include the full verse text accurately
''';

      final response = await http.post(
        Uri.parse(kAnthropicApiUrl),
        headers: {
          'Content-Type': 'application/json',
          'x-api-key': kAnthropicApiKey,
          'anthropic-version': '2023-06-01',
        },
        body: jsonEncode({
          'model': kAnthropicModel,
          'max_tokens': 1500,
          'messages': [
            {'role': 'user', 'content': prompt}
          ],
        }),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final content = data['content'] as List<dynamic>;
        if (content.isNotEmpty && content[0]['type'] == 'text') {
          final raw = content[0]['text'] as String;
          final cleaned = raw
              .replaceAll('```json', '')
              .replaceAll('```', '')
              .trim();
          final parsed = jsonDecode(cleaned) as List<dynamic>;
          setState(() {
            _results = parsed
                .map((e) => VerseResult.fromJson(e as Map<String, dynamic>))
                .where((v) => v.reference.isNotEmpty && v.text.isNotEmpty)
                .toList();
            _loading = false;
          });
        } else {
          // 200 but no usable text block — reset loading instead of spinning forever.
          setState(() {
            _error = 'Something went wrong. Please try again.';
            _loading = false;
          });
        }
      } else {
        setState(() {
          _error = 'Something went wrong. Please try again.';
          _loading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Could not complete search. Please check your connection.';
        _loading = false;
      });
    }
  }

  void _discuss(VerseResult verse) {
    final prompt =
        'I just searched for "$_lastQuery" and found ${verse.reference}. '
        '"${verse.text}" — can you help me go deeper into this verse? '
        'What is the context, what does it mean, and how does it apply to my life?';
    Navigator.of(context).pop();
    widget.onPromptSelected(prompt);
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
          'Search Scripture',
          style: TextStyle(
            fontFamily: 'Georgia',
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: t.textPrimary,
          ),
        ),
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: Container(
              decoration: BoxDecoration(
                color: t.cardBg,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: t.cardBorder),
                boxShadow: [
                  BoxShadow(
                    color: t.primary.withValues(alpha: 0.08),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                textCapitalization: TextCapitalization.sentences,
                style: TextStyle(
                  fontFamily: 'Georgia',
                  fontSize: 15,
                  color: t.textPrimary,
                ),
                decoration: InputDecoration(
                  hintText: 'Search by topic, feeling, or keyword...',
                  hintStyle: TextStyle(
                    fontFamily: 'Georgia',
                    color: t.textHint,
                    fontSize: 14,
                  ),
                  prefixIcon: Icon(Icons.search, color: t.primary),
                  suffixIcon: _controller.text.isNotEmpty
                      ? GestureDetector(
                          onTap: () {
                            _controller.clear();
                            setState(() {
                              _results = [];
                              _error = '';
                              _lastQuery = '';
                            });
                          },
                          child: Icon(Icons.close, color: t.textHint, size: 18),
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 14),
                ),
                onSubmitted: _search,
                onChanged: (val) => setState(() {}),
              ),
            ),
          ),

          const SizedBox(height: 8),

          Expanded(
            child: _loading
                ? _buildLoading(t)
                : _error.isNotEmpty
                    ? _buildError(t)
                    : _results.isNotEmpty
                        ? _buildResults(t)
                        : _buildEmpty(t),
          ),
        ],
      ),
    );
  }

  Widget _buildLoading(WaypointThemeData t) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 32,
            height: 32,
            child: CircularProgressIndicator(
              color: t.primary,
              strokeWidth: 2.5,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Searching Scripture for "$_lastQuery"...',
            style: TextStyle(
              fontFamily: 'Georgia',
              fontSize: 14,
              color: t.textSecondary,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildError(WaypointThemeData t) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.wifi_off_outlined, color: t.textHint, size: 40),
            const SizedBox(height: 12),
            Text(
              _error,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Georgia',
                fontSize: 15,
                color: t.textSecondary,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 20),
            GestureDetector(
              onTap: () => _search(_lastQuery),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 24, vertical: 12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [t.primary, t.secondary],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'Try again',
                  style: TextStyle(
                    fontFamily: 'Georgia',
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: t.onPrimary,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty(WaypointThemeData t) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Try searching for...',
            style: TextStyle(
              fontFamily: 'Georgia',
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: t.textPrimary,
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _suggestions.map((s) {
              return GestureDetector(
                onTap: () {
                  _controller.text = s;
                  _search(s);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 9),
                  decoration: BoxDecoration(
                    color: t.cardBg,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: t.cardBorder),
                    boxShadow: [
                      BoxShadow(
                        color: t.primary.withValues(alpha: 0.05),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Text(
                    s,
                    style: TextStyle(
                      fontFamily: 'Georgia',
                      fontSize: 14,
                      color: t.textPrimary,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 32),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: t.accentLight,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: t.cardBorder.withValues(alpha: 0.5)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.lightbulb_outline, color: t.primary, size: 16),
                    const SizedBox(width: 6),
                    Text(
                      'TIP',
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
                const SizedBox(height: 8),
                Text(
                  'You can search by topic ("forgiveness"), feeling ("I feel lost"), or even a partial verse ("lamp to my feet").',
                  style: TextStyle(
                    fontFamily: 'Georgia',
                    fontSize: 14,
                    color: t.textPrimary,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResults(WaypointThemeData t) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      itemCount: _results.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Text(
              '${_results.length} verses found for "$_lastQuery"',
              style: TextStyle(
                fontFamily: 'Georgia',
                fontSize: 13,
                color: t.textSecondary,
                fontStyle: FontStyle.italic,
              ),
            ),
          );
        }
        final verse = _results[index - 1];
        return _VerseCard(
          verse: verse,
          t: t,
          onDiscuss: () => _discuss(verse),
        );
      },
    );
  }
}

// ── Verse result card ─────────────────────────────────────────────────────────

class _VerseCard extends StatelessWidget {
  final VerseResult verse;
  final WaypointThemeData t;
  final VoidCallback onDiscuss;

  const _VerseCard({required this.verse, required this.t, required this.onDiscuss});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
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
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  bottomLeft: Radius.circular(16),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      verse.reference,
                      style: TextStyle(
                        fontFamily: 'Georgia',
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: t.primary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '"${verse.text}"',
                      style: TextStyle(
                        fontFamily: 'Georgia',
                        fontSize: 15,
                        color: t.textPrimary,
                        height: 1.65,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      verse.relevance,
                      style: TextStyle(
                        fontFamily: 'Georgia',
                        fontSize: 13,
                        color: t.textSecondary,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 12),
                    GestureDetector(
                      onTap: onDiscuss,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 7),
                        decoration: BoxDecoration(
                          color: t.accentLight,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: t.cardBorder),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.chat_bubble_outline,
                                color: t.primary, size: 13),
                            const SizedBox(width: 5),
                            Text(
                              'Discuss',
                              style: TextStyle(
                                fontFamily: 'Georgia',
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: t.primary,
                              ),
                            ),
                          ],
                        ),
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

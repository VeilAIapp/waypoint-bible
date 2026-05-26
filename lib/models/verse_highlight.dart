import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class VerseHighlight {
  final String id;
  final String verseRef;
  final String verseText;
  final DateTime createdAt;
  String? note;

  VerseHighlight({
    required this.id,
    required this.verseRef,
    required this.verseText,
    required this.createdAt,
    this.note,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'verseRef': verseRef,
        'verseText': verseText,
        'createdAt': createdAt.toIso8601String(),
        if (note != null) 'note': note,
      };

  factory VerseHighlight.fromJson(Map<String, dynamic> json) => VerseHighlight(
        id: json['id'] as String,
        verseRef: json['verseRef'] as String,
        verseText: json['verseText'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
        note: json['note'] as String?,
      );
}

List<VerseHighlight> loadHighlights(SharedPreferences prefs) {
  final raw = prefs.getStringList('verse_highlights') ?? [];
  return raw
      .map((s) {
        try {
          return VerseHighlight.fromJson(
              jsonDecode(s) as Map<String, dynamic>);
        } catch (_) {
          return null;
        }
      })
      .whereType<VerseHighlight>()
      .toList();
}

void saveHighlights(SharedPreferences prefs, List<VerseHighlight> highlights) {
  prefs.setStringList(
    'verse_highlights',
    highlights.map((h) => jsonEncode(h.toJson())).toList(),
  );
}

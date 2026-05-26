import 'dart:convert';
import 'package:http/http.dart' as http;

class BibleVerse {
  final int number;
  final String text;
  const BibleVerse({required this.number, required this.text});
}

class BibleChapterData {
  final String bookName;
  final int chapterNumber;
  final bool hasNext;
  final bool hasPrev;
  final List<BibleVerse> verses;

  const BibleChapterData({
    required this.bookName,
    required this.chapterNumber,
    required this.hasNext,
    required this.hasPrev,
    required this.verses,
  });
}

class BibleApiService {
  static const _base = 'https://bolls.life';
  static const defaultTranslation = 'BSB';

  // bolls.life uses 1-based sequential book numbers (Genesis=1 … Revelation=66)
  static const Map<String, int> bookNumbers = {
    'Genesis': 1, 'Exodus': 2, 'Leviticus': 3, 'Numbers': 4,
    'Deuteronomy': 5, 'Joshua': 6, 'Judges': 7, 'Ruth': 8,
    '1 Samuel': 9, '2 Samuel': 10, '1 Kings': 11, '2 Kings': 12,
    '1 Chronicles': 13, '2 Chronicles': 14, 'Ezra': 15, 'Nehemiah': 16,
    'Esther': 17, 'Job': 18, 'Psalms': 19, 'Proverbs': 20,
    'Ecclesiastes': 21, 'Song of Songs': 22, 'Isaiah': 23, 'Jeremiah': 24,
    'Lamentations': 25, 'Ezekiel': 26, 'Daniel': 27, 'Hosea': 28,
    'Joel': 29, 'Amos': 30, 'Obadiah': 31, 'Jonah': 32, 'Micah': 33,
    'Nahum': 34, 'Habakkuk': 35, 'Zephaniah': 36, 'Haggai': 37,
    'Zechariah': 38, 'Malachi': 39, 'Matthew': 40, 'Mark': 41,
    'Luke': 42, 'John': 43, 'Acts': 44, 'Romans': 45,
    '1 Corinthians': 46, '2 Corinthians': 47, 'Galatians': 48,
    'Ephesians': 49, 'Philippians': 50, 'Colossians': 51,
    '1 Thessalonians': 52, '2 Thessalonians': 53, '1 Timothy': 54,
    '2 Timothy': 55, 'Titus': 56, 'Philemon': 57, 'Hebrews': 58,
    'James': 59, '1 Peter': 60, '2 Peter': 61, '1 John': 62,
    '2 John': 63, '3 John': 64, 'Jude': 65, 'Revelation': 66,
  };

  static const Map<String, int> chapterCounts = {
    'Genesis': 50, 'Exodus': 40, 'Leviticus': 27, 'Numbers': 36,
    'Deuteronomy': 34, 'Joshua': 24, 'Judges': 21, 'Ruth': 4,
    '1 Samuel': 31, '2 Samuel': 24, '1 Kings': 22, '2 Kings': 25,
    '1 Chronicles': 29, '2 Chronicles': 36, 'Ezra': 10, 'Nehemiah': 13,
    'Esther': 10, 'Job': 42, 'Psalms': 150, 'Proverbs': 31,
    'Ecclesiastes': 12, 'Song of Songs': 8, 'Isaiah': 66, 'Jeremiah': 52,
    'Lamentations': 5, 'Ezekiel': 48, 'Daniel': 12, 'Hosea': 14,
    'Joel': 3, 'Amos': 9, 'Obadiah': 1, 'Jonah': 4, 'Micah': 7,
    'Nahum': 3, 'Habakkuk': 3, 'Zephaniah': 3, 'Haggai': 2,
    'Zechariah': 14, 'Malachi': 4, 'Matthew': 28, 'Mark': 16, 'Luke': 24,
    'John': 21, 'Acts': 28, 'Romans': 16, '1 Corinthians': 16,
    '2 Corinthians': 13, 'Galatians': 6, 'Ephesians': 6, 'Philippians': 4,
    'Colossians': 4, '1 Thessalonians': 5, '2 Thessalonians': 3,
    '1 Timothy': 6, '2 Timothy': 4, 'Titus': 3, 'Philemon': 1,
    'Hebrews': 13, 'James': 5, '1 Peter': 5, '2 Peter': 3, '1 John': 5,
    '2 John': 1, '3 John': 1, 'Jude': 1, 'Revelation': 22,
  };

  // GET https://bolls.life/get-chapter/{translation}/{bookNumber}/{chapter}/
  // Returns: [{"verse": 1, "text": "..."}, ...]
  static Future<BibleChapterData> fetchChapter(
    String bookName,
    int chapter, {
    String translation = defaultTranslation,
  }) async {
    final bookNum = bookNumbers[bookName] ?? 1;
    final uri = Uri.parse('$_base/get-chapter/$translation/$bookNum/$chapter/');
    final response = await http.get(uri).timeout(const Duration(seconds: 20));

    if (response.statusCode != 200) {
      throw Exception('Server returned ${response.statusCode}');
    }

    final list = jsonDecode(response.body) as List<dynamic>;
    final verses = list
        .map((v) {
              var text = _stripHtml(v['text'] as String);
              if (translation == 'KJV') text = _stripStrongsNumbers(text);
              return BibleVerse(number: v['verse'] as int, text: text);
            })
        .where((v) => v.text.isNotEmpty)
        .toList();

    final total = chapterCounts[bookName] ?? 1;
    return BibleChapterData(
      bookName: bookName,
      chapterNumber: chapter,
      hasNext: chapter < total,
      hasPrev: chapter > 1,
      verses: verses,
    );
  }

  // KJV from bolls.life embeds Strong's numbers after words (e.g. pass935 → pass) and as
  // standalone tokens. KJV spells out all numbers in prose, so stripping all digits is safe.
  static String _stripStrongsNumbers(String text) {
    return text
        .replaceAll(RegExp(r'\d+'), '')
        .replaceAll(RegExp(r' {2,}'), ' ')
        .trim();
  }

  // bolls.life occasionally wraps text in <i> or <a> tags for footnotes
  static String _stripHtml(String html) {
    return html
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .trim();
  }
}

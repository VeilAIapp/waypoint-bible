import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_theme.dart';

class JournalScreen extends StatelessWidget {
  final SharedPreferences prefs;

  const JournalScreen({super.key, required this.prefs});

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
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.book_outlined,
              size: 64,
              color: t.textHint,
            ),
            const SizedBox(height: 16),
            Text(
              'Your journal is empty',
              style: TextStyle(
                fontFamily: 'Georgia',
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: t.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Saved verses and reflections\nwill appear here',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Georgia',
                fontSize: 14,
                color: t.textHint,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
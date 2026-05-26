import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_theme.dart';

class ThemeService extends ChangeNotifier implements ThemeServiceBase {
  static const _key = 'app_theme';

  final SharedPreferences _prefs;
  ThemeName _theme;

  ThemeService(SharedPreferences prefs)
      : _prefs = prefs,
        _theme = _parseTheme(prefs.getString(_key));

  static ThemeName _parseTheme(String? s) => switch (s) {
        'midnight' => ThemeName.midnight,
        'forest' => ThemeName.forest,
        'vespers' => ThemeName.vespers,
        _ => ThemeName.sunrise,
      };

  @override
  ThemeName get currentTheme => _theme;

  @override
  WaypointThemeData get themeData => WaypointThemeData.forName(_theme);

  @override
  Future<void> setTheme(ThemeName theme) async {
    if (_theme == theme) return;
    _theme = theme;
    await _prefs.setString(_key, theme.name);
    notifyListeners();
  }
}

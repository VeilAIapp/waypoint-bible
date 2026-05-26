import 'package:flutter/material.dart';

enum ThemeName { sunrise, midnight, forest, vespers }

class WaypointThemeData {
  final Color primary;
  final Color secondary;
  final Color onPrimary;
  final Color background;
  final Color textPrimary;
  final Color textSecondary;
  final Color textHint;
  final Color cardBg;
  final Color cardBorder;
  final Color navBg;
  final Color inputFill;
  final Color accentLight;
  final Color unearnedBg;
  final Color progressBg;
  final Color gradTop;
  final Color gradMid;
  final Color gradBot;
  final bool isDark;

  const WaypointThemeData({
    required this.primary,
    required this.secondary,
    required this.onPrimary,
    required this.background,
    required this.textPrimary,
    required this.textSecondary,
    required this.textHint,
    required this.cardBg,
    required this.cardBorder,
    required this.navBg,
    required this.inputFill,
    required this.accentLight,
    required this.unearnedBg,
    required this.progressBg,
    required this.gradTop,
    required this.gradMid,
    required this.gradBot,
    required this.isDark,
  });

  // Sunrise — warm cream light theme, coral accent
  static const WaypointThemeData sunrise = WaypointThemeData(
    primary: Color(0xFFE8896A),
    secondary: Color(0xFFF2B880),
    onPrimary: Color(0xFFFFFFFF),
    background: Color(0xFFFDF6F2),
    textPrimary: Color(0xFF3D1209),
    textSecondary: Color(0xFF8A5040),
    textHint: Color(0xFFBBA89E),
    cardBg: Color(0xFFFFFFFF),
    cardBorder: Color(0xFFF0DDD6),
    navBg: Color(0xFFFFF8F5),
    inputFill: Color(0xFFFDF6F2),
    accentLight: Color(0xFFFFF0EB),
    unearnedBg: Color(0xFFF5F0EE),
    progressBg: Color(0xFFF5EDE8),
    gradTop: Color(0xFFFFE0D0),
    gradMid: Color(0xFFFDF6F2),
    gradBot: Color(0xFFFDF0EC),
    isDark: false,
  );

  // Midnight — deep navy dark theme, blue accent
  static const WaypointThemeData midnight = WaypointThemeData(
    primary: Color(0xFF2B6CB0),
    secondary: Color(0xFF4A90D9),
    onPrimary: Color(0xFFFFFFFF),
    background: Color(0xFF0F1F3D),
    textPrimary: Color(0xFFFFFFFF),
    textSecondary: Color(0xFF90A4C8),
    textHint: Color(0xFF4A6FA5),
    cardBg: Color(0xFF1A2F5A),
    cardBorder: Color(0xFF2D4A7A),
    navBg: Color(0xFF0D1B35),
    inputFill: Color(0xFF1A2F5A),
    accentLight: Color(0xFF1E3460),
    unearnedBg: Color(0xFF152745),
    progressBg: Color(0xFF152745),
    gradTop: Color(0xFF0D1B35),
    gradMid: Color(0xFF0F1F3D),
    gradBot: Color(0xFF111F3A),
    isDark: true,
  );

  // Forest — deep charcoal dark theme, green accent
  static const WaypointThemeData forest = WaypointThemeData(
    primary: Color(0xFF7DB87D),
    secondary: Color(0xFF9FCF9F),
    onPrimary: Color(0xFFFFFFFF),
    background: Color(0xFF141414),
    textPrimary: Color(0xFFDDDDDD),
    textSecondary: Color(0xFF999999),
    textHint: Color(0xFF666666),
    cardBg: Color(0xFF222222),
    cardBorder: Color(0xFF333333),
    navBg: Color(0xFF101010),
    inputFill: Color(0xFF1A1A1A),
    accentLight: Color(0xFF1A281A),
    unearnedBg: Color(0xFF2A2A2A),
    progressBg: Color(0xFF2A2A2A),
    gradTop: Color(0xFF0E150E),
    gradMid: Color(0xFF141414),
    gradBot: Color(0xFF121A12),
    isDark: true,
  );

  // Vespers — deep purple dark theme, white accent
  static const WaypointThemeData vespers = WaypointThemeData(
    primary: Color(0xFFFFFFFF),
    secondary: Color(0xFFC8B8F0),
    onPrimary: Color(0xFF120A1E),
    background: Color(0xFF120A1E),
    textPrimary: Color(0xFFE8DFF8),
    textSecondary: Color(0xFFB0A0D0),
    textHint: Color(0xFF6A5A8A),
    cardBg: Color(0xFF231545),
    cardBorder: Color(0xFF3D2A6A),
    navBg: Color(0xFF0E0718),
    inputFill: Color(0xFF1C1030),
    accentLight: Color(0xFF2A1A50),
    unearnedBg: Color(0xFF1E1035),
    progressBg: Color(0xFF1E1035),
    gradTop: Color(0xFF0E0718),
    gradMid: Color(0xFF120A1E),
    gradBot: Color(0xFF100818),
    isDark: true,
  );

  static WaypointThemeData forName(ThemeName name) => switch (name) {
        ThemeName.sunrise => sunrise,
        ThemeName.midnight => midnight,
        ThemeName.forest => forest,
        ThemeName.vespers => vespers,
      };
}

class WaypointTheme extends InheritedWidget {
  final WaypointThemeData data;
  final ThemeServiceBase service;

  const WaypointTheme({
    super.key,
    required this.data,
    required this.service,
    required super.child,
  });

  static WaypointThemeData of(BuildContext context) {
    return context
            .dependOnInheritedWidgetOfExactType<WaypointTheme>()
            ?.data ??
        WaypointThemeData.sunrise;
  }

  static ThemeServiceBase serviceOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<WaypointTheme>()!
        .service;
  }

  @override
  bool updateShouldNotify(WaypointTheme old) => !identical(old.data, data);
}

// Thin interface so app_theme.dart doesn't depend on theme_service.dart
abstract class ThemeServiceBase {
  WaypointThemeData get themeData;
  ThemeName get currentTheme;
  Future<void> setTheme(ThemeName theme);
}

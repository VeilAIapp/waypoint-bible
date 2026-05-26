import 'dart:async';
import 'package:flutter/material.dart';
import 'package:home_widget/home_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'screens/home_screen.dart';
import 'screens/chat_screen.dart';
import 'screens/bible_screen.dart';
import 'screens/hub_screen.dart';
import 'screens/search_screen.dart';
import 'screens/splash_screen.dart';
import 'services/message_limit_service.dart';
import 'services/revenue_cat_service.dart';
import 'services/notification_service.dart';
import 'services/theme_service.dart';
import 'services/widget_update_service.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Write-once: record install date before anything else so the timestamp is
  // as early as possible even if later services are slow to initialise.
  await MessageLimitService.recordFirstOpenIfNeeded();
  final prefs = await SharedPreferences.getInstance();
  runApp(WaypointApp(prefs: prefs));
  _initServices(prefs);
}

Future<void> _initServices(SharedPreferences prefs) async {
  try {
    await NotificationService.initialize();
    await NotificationService.requestPermission();
    final savedTime = prefs.getString('notification_time');
    if (savedTime != null) {
      final (h, m) = NotificationService.parseTimeString(savedTime);
      await NotificationService.scheduleDaily(h, m);
    } else {
      await NotificationService.scheduleDaily(8, 0);
    }
    await NotificationService.showLockScreen();
  } catch (_) {}
  await Future.delayed(const Duration(seconds: 2));
  await RevenueCatService.initialize();
  // Push today's verse, streak, and Pro status to all home screen widgets.
  try {
    await WidgetUpdateService.updateAll(prefs);
  } catch (_) {}
}

final navigatorKey = GlobalKey<NavigatorState>();

class WaypointApp extends StatefulWidget {
  final SharedPreferences prefs;
  const WaypointApp({super.key, required this.prefs});

  @override
  State<WaypointApp> createState() => _WaypointAppState();
}

class _WaypointAppState extends State<WaypointApp> {
  late final ThemeService _themeService;

  @override
  void initState() {
    super.initState();
    _themeService = ThemeService(widget.prefs);
    _themeService.addListener(_onThemeChanged);
  }

  @override
  void dispose() {
    _themeService.removeListener(_onThemeChanged);
    _themeService.dispose();
    super.dispose();
  }

  void _onThemeChanged() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final t = _themeService.themeData;
    return WaypointTheme(
      data: t,
      service: _themeService,
      child: MaterialApp(
        navigatorKey: navigatorKey,
        title: 'Waypoint',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme(
            brightness: t.isDark ? Brightness.dark : Brightness.light,
            primary: t.primary,
            secondary: t.secondary,
            surface: t.background,
            onPrimary: t.onPrimary,
            onSecondary: t.onPrimary,
            onSurface: t.textPrimary,
            error: Colors.red,
            onError: Colors.white,
          ),
          scaffoldBackgroundColor: t.background,
          fontFamily: 'Georgia',
          appBarTheme: AppBarTheme(
            backgroundColor: t.background,
            foregroundColor: t.textPrimary,
            elevation: 0,
            centerTitle: true,
            titleTextStyle: TextStyle(
              fontFamily: 'Georgia',
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: t.textPrimary,
            ),
          ),
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: t.inputFill,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(24),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(24),
              borderSide: BorderSide(color: t.cardBorder, width: 1),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(24),
              borderSide: BorderSide(color: t.primary, width: 1.5),
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            hintStyle: TextStyle(
              fontFamily: 'Georgia',
              color: t.textHint,
              fontSize: 14,
            ),
          ),
          elevatedButtonTheme: ElevatedButtonThemeData(
            style: ElevatedButton.styleFrom(
              backgroundColor: t.primary,
              foregroundColor: t.onPrimary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              padding:
                  const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
              textStyle: const TextStyle(
                fontFamily: 'Georgia',
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        home: SplashScreen(prefs: widget.prefs),
      ),
    );
  }
}

class MainShell extends StatefulWidget {
  final SharedPreferences prefs;
  const MainShell({super.key, required this.prefs});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> with WidgetsBindingObserver {
  int _currentIndex = 0;
  late final List<Widget> _screens;
  final _chatScreenKey = GlobalKey<ChatScreenState>();
  StreamSubscription<Uri?>? _widgetClickedSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _handleWidgetDeepLink();
    _widgetClickedSub = HomeWidget.widgetClicked.listen(_onWidgetUri);
    _screens = [
      HomeScreen(
        prefs: widget.prefs,
        onNavigateToChat: () => _openChat(),
        onNavigateToBible: () => _switchTab(2),
        onNavigateToHub: () => _switchTab(3),
        onPromptSelected: (prompt) => _openChat(prompt),
        onNavigateToSearch: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => SearchScreen(
              prefs: widget.prefs,
              onPromptSelected: (prompt) => _openChat(prompt),
            ),
          ),
        ),
      ),
      ChatScreen(key: _chatScreenKey, prefs: widget.prefs),
      HubScreen(
        prefs: widget.prefs,
        onPromptSelected: (prompt) => _openChat(prompt),
      ),
    ];
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _widgetClickedSub?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshWidgetIfNewDay();
    }
  }

  /// Re-pushes verse + Pro status to all widgets when the calendar date has
  /// changed since the last update (e.g. user left the app open overnight).
  Future<void> _refreshWidgetIfNewDay() async {
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final last = widget.prefs.getString('widget_update_date');
    if (last == today) return;
    await widget.prefs.setString('widget_update_date', today);
    try {
      await Future.wait([
        WidgetUpdateService.updateAll(widget.prefs),
        NotificationService.showLockScreen(),
      ]);
    } catch (_) {}
  }

  void _switchTab(int index) {
    setState(() => _currentIndex = index);
  }

  void _openChat([String? prompt]) {
    if (prompt != null) {
      _switchTabWithPrompt(1, prompt);
    } else {
      setState(() => _currentIndex = 1);
    }
  }

  Future<void> _handleWidgetDeepLink() async {
    try {
      final uri = await HomeWidget.initiallyLaunchedFromHomeWidget();
      _onWidgetUri(uri);
    } catch (_) {}
  }

  void _onWidgetUri(Uri? uri) {
    if (!mounted) return;
    if (uri?.queryParameters['screen'] == 'companion') {
      WidgetsBinding.instance.addPostFrameCallback((_) => _openChat());
    }
  }

  void _switchTabWithPrompt(int index, String prompt) {
    setState(() => _currentIndex = index);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final state = _chatScreenKey.currentState;
        if (state != null) {
          state.sendPrompt(prompt);
        } else {
          Future.delayed(const Duration(milliseconds: 200), () {
            _chatScreenKey.currentState?.sendPrompt(prompt);
          });
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = WaypointTheme.of(context);
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: [
          _screens[0],
          _screens[1],
          BibleScreen(
            prefs: widget.prefs,
            onPromptSelected: (prompt) => _openChat(prompt),
          ),
          _screens[2],
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: t.navBg,
          border: Border(
            top: BorderSide(color: t.cardBorder, width: 1),
          ),
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (i) => i == 1 ? _openChat() : _switchTab(i),
          type: BottomNavigationBarType.fixed,
          backgroundColor: t.navBg,
          selectedItemColor: t.primary,
          unselectedItemColor: t.textHint,
          selectedLabelStyle: const TextStyle(
            fontFamily: 'Georgia',
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
          unselectedLabelStyle: const TextStyle(
            fontFamily: 'Georgia',
            fontSize: 12,
          ),
          elevation: 0,
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.home_outlined),
              activeIcon: Icon(Icons.home),
              label: 'Home',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.chat_bubble_outline),
              activeIcon: Icon(Icons.chat_bubble),
              label: 'Companion',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.menu_book_outlined),
              activeIcon: Icon(Icons.menu_book),
              label: 'Bible',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.grid_view_outlined),
              activeIcon: Icon(Icons.grid_view),
              label: 'My Waypoint',
            ),
          ],
        ),
      ),
    );
  }
}

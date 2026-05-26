import 'package:flutter/material.dart';
import '../services/revenue_cat_service.dart';
import '../theme/app_theme.dart';
import 'paywall_screen.dart';

class ProGateScreen extends StatefulWidget {
  final Widget child;

  const ProGateScreen({super.key, required this.child});

  @override
  State<ProGateScreen> createState() => _ProGateScreenState();
}

class _ProGateScreenState extends State<ProGateScreen> {
  bool _loading = true;
  bool _isPro = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    bool isPro;
    try {
      isPro = await RevenueCatService.isProUser();
    } catch (_) {
      isPro = true; // fail open on network error
    }
    if (mounted) setState(() { _loading = false; _isPro = isPro; });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      final t = WaypointTheme.of(context);
      return Scaffold(
        backgroundColor: t.background,
        body: Center(
          child: CircularProgressIndicator(color: t.primary, strokeWidth: 2.5),
        ),
      );
    }
    if (_isPro) return widget.child;
    // Not pro — show paywall inline. PaywallScreen's onDismiss already calls
    // Navigator.pop() to pop this route. onProUnlocked just rebuilds with child.
    return PaywallScreen(
      onContinueFree: () {},
      onProUnlocked: () => setState(() => _isPro = true),
      popOnProUnlocked: false,
    );
  }
}

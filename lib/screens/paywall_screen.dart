import 'package:flutter/material.dart';
import 'package:purchases_ui_flutter/purchases_ui_flutter.dart';

class PaywallScreen extends StatefulWidget {
  final VoidCallback onContinueFree;
  final VoidCallback? onProUnlocked;
  final bool popOnProUnlocked;

  const PaywallScreen({
    super.key,
    required this.onContinueFree,
    this.onProUnlocked,
    this.popOnProUnlocked = true,
  });

  @override
  State<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends State<PaywallScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _present());
  }

  Future<void> _present() async {
    try {
      final result = await RevenueCatUI.presentPaywall(displayCloseButton: true);
      if (!mounted) return;

      if (result == PaywallResult.purchased || result == PaywallResult.restored) {
        if (widget.onProUnlocked != null) {
          widget.onProUnlocked!();
          if (!widget.popOnProUnlocked) {
            Navigator.of(context).pop();
            return;
          }
        }
        Navigator.of(context).pop();
      } else {
        Navigator.of(context).pop();
        widget.onContinueFree();
      }
    } catch (_) {
      if (mounted) {
        Navigator.of(context).pop();
        widget.onContinueFree();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.transparent,
      body: Center(child: CircularProgressIndicator()),
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:noa/models/app_logic_model.dart' as app;
import 'package:noa/pages/noa.dart';
import 'package:noa/style.dart';
import 'package:noa/util/switch_page.dart';

/// Desktop-only splash screen.
///
/// Bypasses the phone-style login / BLE-pairing gate and navigates directly
/// to [NoaPage] after a short branding pause.  Still fires [Event.init] so
/// that [AppLogicModel] loads persisted settings (tunePrompt, temperature,
/// custom-server flags) from SharedPreferences; the state will land on
/// [State.waitForLogin] since there is no auth token on Windows, which
/// [NoaPage] ignores (it only redirects on BLE-firmware states).
class DesktopSplashPage extends ConsumerWidget {
  const DesktopSplashPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Load persisted app settings (no-op if already loaded).
      ref.read(app.model).triggerEvent(app.Event.init);

      Timer(const Duration(milliseconds: 800), () {
        if (context.mounted) switchPage(context, const NoaPage());
      });
    });

    return const Scaffold(
      backgroundColor: colorWhite,
      body: _DesktopSplashBody(),
    );
  }
}

class _DesktopSplashBody extends StatefulWidget {
  const _DesktopSplashBody();

  @override
  State<_DesktopSplashBody> createState() => _DesktopSplashBodyState();
}

class _DesktopSplashBodyState extends State<_DesktopSplashBody>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..forward();
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeIn);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: FadeTransition(
        opacity: _fade,
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'ARIA',
              style: TextStyle(
                fontFamily: 'SF Pro Display',
                fontSize: 52,
                fontWeight: FontWeight.w900,
                color: colorDark,
                letterSpacing: 14,
              ),
            ),
            SizedBox(height: 6),
            Text(
              'ASSISTANT',
              style: TextStyle(
                fontFamily: 'SF Pro Display',
                fontSize: 13,
                fontWeight: FontWeight.w400,
                color: colorLight,
                letterSpacing: 6,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

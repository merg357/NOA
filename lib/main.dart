import 'dart:io';

import 'package:audio_session/audio_session.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';
import 'package:frame_ble/brilliant_bluetooth.dart';
import 'package:noa/models/productivity_model.dart';
import 'package:noa/pages/desktop_splash.dart';
import 'package:noa/services/vps_service.dart';
import 'package:noa/pages/splash.dart';
import 'package:noa/services/window_service.dart';
import 'package:noa/util/app_log.dart';
import 'package:noa/util/desktop_args.dart';
import 'package:noa/util/foreground_service.dart';
import 'package:noa/util/location.dart';
import 'package:window_manager/window_manager.dart';

final globalPageStorageBucket = PageStorageBucket();

void main() async {
  // Required before any plugin that needs the binding (window_manager, dotenv).
  WidgetsFlutterBinding.ensureInitialized();

  // Load environment variables (.env file in project root / app bundle).
  await dotenv.load();

  // Parse desktop launch flags (--kiosk, --auto-connect, --start-voice-ready).
  if (Platform.isWindows) {
    DesktopArgs.parse();
    await WindowService.initializeWindow(kiosk: DesktopArgs.kiosk);
  }

  // Start logging and pre-warm providers.
  final container = ProviderContainer();
  container.read(appLog);
  // Pre-warm productivity data so it is ready before the user visits Tasks tab.
  container.read(productivityProvider);
  // Pre-warm VPS config so the service connects early.
  container.read(vpsConfigProvider);

  // ── Mobile-only init (skipped on Windows) ────────────────────────────────
  if (!Platform.isWindows) {
    // Android foreground service keeps the app alive in the background.
    initializeForegroundService();

    // Bluetooth permission required before any BLE scan.
    BrilliantBluetooth.requestPermission();

    // Location stream for geo-aware responses.
    Location.startLocationStream();

    // Audio session category required for correct iOS/Android audio routing.
    _setupAudioSession();
  }

  runApp(UncontrolledProviderScope(
    container: container,
    child: MainApp(isDesktop: Platform.isWindows),
  ));
}

void _setupAudioSession() {
  AudioSession.instance.then((audioSession) async {
    await audioSession.configure(const AudioSessionConfiguration(
      avAudioSessionCategory: AVAudioSessionCategory.playback,
      avAudioSessionCategoryOptions:
          AVAudioSessionCategoryOptions.mixWithOthers,
      avAudioSessionMode: AVAudioSessionMode.spokenAudio,
      avAudioSessionRouteSharingPolicy:
          AVAudioSessionRouteSharingPolicy.defaultPolicy,
      avAudioSessionSetActiveOptions: AVAudioSessionSetActiveOptions.none,
      androidAudioAttributes: AndroidAudioAttributes(
        contentType: AndroidAudioContentType.speech,
        flags: AndroidAudioFlags.none,
        usage: AndroidAudioUsage.assistant,
      ),
      androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
      androidWillPauseWhenDucked: true,
    ));
    audioSession.setActive(true);
  });
}

class MainApp extends StatelessWidget {
  final bool isDesktop;

  const MainApp({super.key, required this.isDesktop});

  @override
  Widget build(BuildContext context) {
    if (isDesktop) {
      // Desktop path: no foreground service, no BLE wrapper, direct to ARIA.
      return _DesktopWindowListener(
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          home: const DesktopSplashPage(),
        ),
      );
    }

    // Mobile path: foreground service + BLE task wrapper.
    startForegroundService();
    return const WithForegroundTask(
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        home: SplashPage(),
      ),
    );
  }
}

// ── Desktop window geometry listener ─────────────────────────────────────────

/// Saves window position / size to SharedPreferences whenever the user resizes
/// or moves the window.  Injected as a no-op ancestor widget on mobile.
class _DesktopWindowListener extends StatefulWidget {
  final Widget child;

  const _DesktopWindowListener({required this.child});

  @override
  State<_DesktopWindowListener> createState() => _DesktopWindowListenerState();
}

class _DesktopWindowListenerState extends State<_DesktopWindowListener>
    with WindowListener {
  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowResized() => WindowService.saveGeometry();

  @override
  void onWindowMoved() => WindowService.saveGeometry();

  @override
  Widget build(BuildContext context) => widget.child;
}

import 'dart:io';

import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Parses desktop-specific launch arguments from multiple sources (in priority
/// order): compile-time `--dart-define`, OS environment variables, and the
/// `.env` file.
///
/// Call [DesktopArgs.parse] once in [main] after [dotenv.load].
class DesktopArgs {
  // Private constructor — static-only class.
  DesktopArgs._();

  /// Full-screen kiosk mode.  No window chrome, can't resize or move.
  static bool kiosk = false;

  /// Reserved: auto-connect to the nearest Frame device on launch.
  static bool autoConnect = false;

  /// Start voice recording immediately when the main screen appears.
  static bool startVoiceReady = false;

  /// Parse all launch argument sources.  Must be called after [dotenv.load].
  static void parse() {
    kiosk = _resolveBool(
      dartDefine: const bool.fromEnvironment('DESKTOP_KIOSK'),
      envVar: Platform.environment['ARIA_KIOSK'],
      dotenvKey: 'DESKTOP_KIOSK',
      execArgFlag: '--kiosk',
    );

    autoConnect = _resolveBool(
      dartDefine: const bool.fromEnvironment('DESKTOP_AUTO_CONNECT'),
      envVar: Platform.environment['ARIA_AUTO_CONNECT'],
      dotenvKey: 'DESKTOP_AUTO_CONNECT',
      execArgFlag: '--auto-connect',
    );

    startVoiceReady = _resolveBool(
      dartDefine: const bool.fromEnvironment('DESKTOP_START_VOICE_READY'),
      envVar: Platform.environment['ARIA_START_VOICE_READY'],
      dotenvKey: 'DESKTOP_START_VOICE_READY',
      execArgFlag: '--start-voice-ready',
    );
  }

  // ── Private ───────────────────────────────────────────────────────────────

  static bool _resolveBool({
    required bool dartDefine,
    required String? envVar,
    required String dotenvKey,
    required String execArgFlag,
  }) {
    if (dartDefine) return true;
    if (envVar == 'true' || envVar == '1') return true;
    if ((dotenv.env[dotenvKey] ?? '') == 'true') return true;
    if (_executableArgs.contains(execArgFlag)) return true;
    return false;
  }

  /// Cached executable args — avoids repeated List construction.
  static final List<String> _executableArgs =
      List.unmodifiable(Platform.executableArguments);
}

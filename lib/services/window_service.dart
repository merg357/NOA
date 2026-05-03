import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

/// Manages the Windows desktop window: geometry persistence, always-on-top,
/// borderless / compact mode, and kiosk (full-screen) launch.
///
/// All public methods are safe no-ops on non-desktop platforms.
class WindowService {
  static const _kWinX = 'win_x';
  static const _kWinY = 'win_y';
  static const _kWinW = 'win_w';
  static const _kWinH = 'win_h';
  static const _kAlwaysOnTop = 'win_always_on_top';
  static const _kBorderless = 'win_borderless';

  /// True when running on a desktop OS (Windows, macOS, Linux).
  static bool get isDesktop =>
      Platform.isWindows || Platform.isMacOS || Platform.isLinux;

  // ── Initialization ────────────────────────────────────────────────────────

  /// Call once in [main] after [WidgetsFlutterBinding.ensureInitialized()].
  ///
  /// Restores saved window geometry, applies [kiosk] full-screen if requested,
  /// and shows the window.  No-op on mobile.
  static Future<void> initializeWindow({required bool kiosk}) async {
    if (!isDesktop) return;

    await windowManager.ensureInitialized();

    final prefs = await SharedPreferences.getInstance();
    final savedW = prefs.getDouble(_kWinW);
    final savedH = prefs.getDouble(_kWinH);
    final savedX = prefs.getDouble(_kWinX);
    final savedY = prefs.getDouble(_kWinY);
    final alwaysOnTop = prefs.getBool(_kAlwaysOnTop) ?? false;
    final borderless = prefs.getBool(_kBorderless) ?? false;

    final size = (savedW != null && savedH != null)
        ? Size(savedW, savedH)
        : const Size(420, 720);

    final titleBarStyle =
        (borderless || kiosk) ? TitleBarStyle.hidden : TitleBarStyle.normal;

    final windowOptions = WindowOptions(
      size: size,
      minimumSize: const Size(320, 540),
      center: savedX == null,
      title: 'ARIA Assistant',
      titleBarStyle: titleBarStyle,
      alwaysOnTop: alwaysOnTop,
      skipTaskbar: false,
    );

    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      if (savedX != null && savedY != null) {
        await windowManager.setPosition(Offset(savedX, savedY));
      }
      if (kiosk) {
        await windowManager.setFullScreen(true);
      }
      await windowManager.show();
      await windowManager.focus();
    });
  }

  // ── Geometry persistence ──────────────────────────────────────────────────

  /// Saves current window position and size to [SharedPreferences].
  ///
  /// Call from [WindowListener.onWindowResized] and [onWindowMoved].
  static Future<void> saveGeometry() async {
    if (!isDesktop) return;
    try {
      final pos = await windowManager.getPosition();
      final size = await windowManager.getSize();
      final prefs = await SharedPreferences.getInstance();
      await Future.wait([
        prefs.setDouble(_kWinX, pos.dx),
        prefs.setDouble(_kWinY, pos.dy),
        prefs.setDouble(_kWinW, size.width),
        prefs.setDouble(_kWinH, size.height),
      ]);
    } catch (_) {
      // Non-critical — window geometry save is best-effort.
    }
  }

  // ── Always-on-top ─────────────────────────────────────────────────────────

  static Future<bool> getAlwaysOnTop() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kAlwaysOnTop) ?? false;
  }

  static Future<void> setAlwaysOnTop(bool value) async {
    if (!isDesktop) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kAlwaysOnTop, value);
    await windowManager.setAlwaysOnTop(value);
  }

  // ── Borderless / compact mode ─────────────────────────────────────────────

  static Future<bool> getBorderless() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kBorderless) ?? false;
  }

  static Future<void> setBorderless(bool value) async {
    if (!isDesktop) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kBorderless, value);
    await windowManager.setTitleBarStyle(
      value ? TitleBarStyle.hidden : TitleBarStyle.normal,
      windowButtonVisibility: !value,
    );
  }
}

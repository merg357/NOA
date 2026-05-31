import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:noa/models/audio_route_state.dart';

/// Manages Android communication-audio routing (earbuds / headset / phone).
///
/// Uses a MethodChannel backed by [AudioRoutePlugin.kt] on Android.
/// On other platforms all operations are no-ops and the state reports an
/// empty device list, so callers need not guard with `Platform.isAndroid`.
///
/// # Usage
/// ```dart
/// final svc = ref.read(audioRouteServiceProvider);
/// await svc.refresh();
/// if (svc.state.earbudAvailable) {
///   await svc.selectEarbudIfAvailable();
/// }
/// ```
class AudioRouteService extends ChangeNotifier {
  static final _log = Logger('AudioRouteService');
  static const _channel = MethodChannel('noa/audio_route');

  AudioRouteState _state = AudioRouteState.empty;

  AudioRouteState get state => _state;

  // ── Public API ────────────────────────────────────────────────────────────

  /// Refreshes the list of available devices and the currently selected device.
  ///
  /// Safe to call on non-Android platforms — returns without modifying state.
  Future<void> refresh() async {
    if (!Platform.isAndroid) return;
    try {
      final rawList = await _channel.invokeListMethod<Object>('list_devices');
      final rawCurrent =
          await _channel.invokeMapMethod<dynamic, dynamic>('get_current');

      final available = (rawList ?? [])
          .whereType<Map>()
          .map(AudioRouteDevice.fromMap)
          .toList();
      final selected = rawCurrent != null
          ? AudioRouteDevice.fromMap(rawCurrent)
          : null;

      _state = AudioRouteState(available: available, selected: selected);
      notifyListeners();
      _log.info('[AudioRoute] refreshed — ${available.length} devices, '
          'selected=${selected?.name}');
    } on PlatformException catch (e) {
      _log.warning('[AudioRoute] refresh error: $e');
    } on MissingPluginException catch (_) {
      _log.fine('[AudioRoute] plugin not registered (non-Android?)');
    }
  }

  /// Selects the communication device with the given [deviceId].
  ///
  /// Returns true on success, false on failure or non-Android.
  Future<bool> selectDevice(String deviceId) async {
    if (!Platform.isAndroid) return false;
    try {
      final ok = await _channel
          .invokeMethod<bool>('set_device', {'id': deviceId}) ??
          false;
      if (ok) await refresh();
      return ok;
    } on PlatformException catch (e) {
      _log.warning('[AudioRoute] selectDevice error: $e');
      return false;
    } on MissingPluginException catch (_) {
      return false;
    }
  }

  /// Clears the communication device selection, reverting to system default.
  Future<void> clearDevice() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('clear_device');
      await refresh();
    } on PlatformException catch (e) {
      _log.warning('[AudioRoute] clearDevice error: $e');
    } on MissingPluginException catch (_) {}
  }

  /// Selects the first available Bluetooth device, if any.
  ///
  /// Returns true if a Bluetooth device was found and set, false otherwise.
  Future<bool> selectEarbudIfAvailable() async {
    await refresh();
    final bt = _state.available
        .where((d) => d.type == AudioDeviceType.bluetooth)
        .firstOrNull;
    if (bt == null) {
      _log.info('[AudioRoute] no Bluetooth device available');
      return false;
    }
    _log.info('[AudioRoute] selecting Bluetooth device: ${bt.name}');
    return selectDevice(bt.id);
  }
}

/// Global Riverpod provider for [AudioRouteService].
final audioRouteServiceProvider =
    ChangeNotifierProvider<AudioRouteService>((_) => AudioRouteService());

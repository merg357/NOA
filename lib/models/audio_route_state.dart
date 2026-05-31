/// Audio output device types reported by the Android AudioManager.
enum AudioDeviceType {
  phone,
  wiredHeadset,
  bluetooth,
  speakerphone,
  unknown,
}

extension AudioDeviceTypeExt on AudioDeviceType {
  String get displayName {
    switch (this) {
      case AudioDeviceType.phone:
        return 'Phone earpiece';
      case AudioDeviceType.wiredHeadset:
        return 'Wired headset';
      case AudioDeviceType.bluetooth:
        return 'Bluetooth';
      case AudioDeviceType.speakerphone:
        return 'Speakerphone';
      case AudioDeviceType.unknown:
        return 'Unknown';
    }
  }

  String get icon {
    switch (this) {
      case AudioDeviceType.phone:
        return '📱';
      case AudioDeviceType.wiredHeadset:
        return '🎧';
      case AudioDeviceType.bluetooth:
        return '🎧';
      case AudioDeviceType.speakerphone:
        return '🔊';
      case AudioDeviceType.unknown:
        return '?';
    }
  }
}

/// A single communication-capable audio device.
class AudioRouteDevice {
  final String id;
  final String name;
  final AudioDeviceType type;

  const AudioRouteDevice({
    required this.id,
    required this.name,
    required this.type,
  });

  factory AudioRouteDevice.fromMap(Map<dynamic, dynamic> m) {
    final typeStr = (m['type'] as String?) ?? 'unknown';
    final type = AudioDeviceType.values.firstWhere(
      (t) => t.name == typeStr,
      orElse: () => AudioDeviceType.unknown,
    );
    return AudioRouteDevice(
      id: (m['id'] as String?) ?? '',
      name: (m['name'] as String?) ?? 'Unknown device',
      type: type,
    );
  }

  @override
  String toString() => 'AudioRouteDevice($name, $type)';
}

/// Snapshot of the current audio routing state.
class AudioRouteState {
  /// All communication-capable devices available right now.
  final List<AudioRouteDevice> available;

  /// The device currently set as the communication device, if any.
  final AudioRouteDevice? selected;

  const AudioRouteState({
    required this.available,
    this.selected,
  });

  /// True when a Bluetooth device is available AND selected.
  bool get earbudActive =>
      selected != null && selected!.type == AudioDeviceType.bluetooth;

  /// True when any Bluetooth communication device is available.
  bool get earbudAvailable =>
      available.any((d) => d.type == AudioDeviceType.bluetooth);

  static const AudioRouteState empty =
      AudioRouteState(available: [], selected: null);
}

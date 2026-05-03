import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

final _log = Logger('VoiceController');

/// Manages the phone microphone lifecycle for the push-to-talk voice loop.
///
/// Uses the `record` package (^5.0.4).  Audio is recorded as 16 kHz mono WAV
/// so it can be passed directly to any STT backend (including Whisper).
///
/// Permissions are handled automatically on Android/iOS via [hasPermission].
/// If permission is denied, [startRecording] returns false and the caller
/// should show an explanatory message.
class VoiceController extends ChangeNotifier {
  final AudioRecorder _recorder = AudioRecorder();

  bool _isRecording = false;
  String? _currentPath;

  bool get isRecording => _isRecording;

  /// The path of the audio file currently being recorded (null when idle).
  String? get currentPath => _currentPath;

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Returns true if the microphone permission is already granted.
  Future<bool> hasPermission() => _recorder.hasPermission();

  /// Start recording from the device microphone.
  ///
  /// Returns true on success, false if the microphone permission was denied or
  /// another recording is already in progress.
  Future<bool> startRecording() async {
    if (_isRecording) return false;
    if (!await hasPermission()) {
      _log.warning('Microphone permission denied');
      return false;
    }

    final dir = await getTemporaryDirectory();
    final path =
        '${dir.path}/aria_voice_${DateTime.now().millisecondsSinceEpoch}.wav';

    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.wav,
        sampleRate: 16000,
        numChannels: 1,
        bitRate: 128000,
      ),
      path: path,
    );

    _isRecording = true;
    _currentPath = path;
    _log.info('Recording started → $path');
    notifyListeners();
    return true;
  }

  /// Stop recording and return the path to the saved audio file.
  ///
  /// Returns null if not currently recording.
  Future<String?> stopRecording() async {
    if (!_isRecording) return null;
    final path = await _recorder.stop();
    _isRecording = false;
    _currentPath = null;
    _log.info('Recording stopped → $path');
    notifyListeners();
    return path;
  }

  /// Cancel the current recording and delete the partial file.
  Future<void> cancelRecording() async {
    if (!_isRecording) return;
    final path = _currentPath;
    await _recorder.stop();
    _isRecording = false;
    _currentPath = null;
    notifyListeners();
    await cleanupTempFile(path);
    _log.info('Recording cancelled');
  }

  /// Delete a temporary audio file created by this controller.
  Future<void> cleanupTempFile(String? path) async {
    if (path == null) return;
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (e) {
      _log.warning('Failed to delete temp file $path: $e');
    }
  }

  @override
  void dispose() {
    _recorder.dispose();
    super.dispose();
  }
}

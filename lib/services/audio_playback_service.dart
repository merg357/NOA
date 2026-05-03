import 'package:just_audio/just_audio.dart';
import 'package:logging/logging.dart';

final _log = Logger('AudioPlaybackService');

/// Plays TTS-synthesized audio files using the `just_audio` package
/// (already a dependency of the existing Noa app).
///
/// Playback is optional: if no file path is provided (e.g. mock TTS returns
/// null), calls are silently skipped.
class AudioPlaybackService {
  final AudioPlayer _player = AudioPlayer();

  bool _isPlaying = false;

  bool get isPlaying => _isPlaying;

  /// Play the audio file at [path] and wait for completion.
  ///
  /// No-ops if [path] is null.  Errors are caught and logged without crashing.
  /// A 60-second timeout and an idle-state escape prevent the voice loop
  /// from hanging if the audio player stalls (Bug C fix).
  Future<void> playFile(String? path) async {
    if (path == null) return;
    try {
      _isPlaying = true;
      _log.info('AudioPlayback: loading $path');
      await _player.setFilePath(path);
      await _player.play();
      _log.info('AudioPlayback: playing…');
      // Wait until fully played, idle (error/stop), or 60s timeout.
      await _player.playerStateStream
          .firstWhere((s) =>
              s.processingState == ProcessingState.completed ||
              s.processingState == ProcessingState.idle)
          .timeout(
            const Duration(seconds: 60),
            onTimeout: () {
              _log.warning('AudioPlayback: timed out after 60s — continuing');
              return _player.playerState;
            },
          );
      _log.info('AudioPlayback: done');
    } catch (e) {
      _log.warning('Audio playback error: $e');
    } finally {
      _isPlaying = false;
    }
  }

  Future<void> stop() async {
    try {
      await _player.stop();
    } catch (_) {}
    _isPlaying = false;
  }

  void dispose() {
    _player.dispose();
  }
}

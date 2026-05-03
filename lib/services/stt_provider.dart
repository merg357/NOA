import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';

/// Contract for speech-to-text backends.
///
/// Implement this interface to plug in any transcription service.
/// Set [STT_PROVIDER] in .env and pass the appropriate implementation to
/// [VoiceAssistantService].
///
/// Environment hooks (read via flutter_dotenv):
///   STT_PROVIDER=mock|openai   (default: mock)
///   ENABLE_STT=true|false      (default: true)
///   OPENAI_API_KEY=<key>       (needed only when STT_PROVIDER=openai)
abstract class SttProvider {
  /// Human-readable identifier shown in settings and debug tables.
  String get name;

  /// True when the provider has everything it needs (keys, network, etc.).
  bool get isConfigured;

  /// Transcribe the audio file at [path] and return the plain-text transcript.
  ///
  /// Returns `null` when transcription fails — callers must handle null
  /// gracefully (e.g., show an error state) without crashing.
  Future<String?> transcribeAudioFile(String path);
}

// ── Mock provider ─────────────────────────────────────────────────────────────

/// Cycles through a small set of realistic phrases without any network access.
///
/// Used in demo/offline mode so the full voice loop can be tested on a
/// simulator or device without API credentials.
class MockSttProvider implements SttProvider {
  final List<String> _phrases;
  int _index = 0;

  MockSttProvider({List<String>? phrases})
      : _phrases = phrases ??
            const [
              'What time is it?',
              'Remind me to review the project plan at 3pm.',
              'Show my reminders.',
              'Take a note: follow up with the team tomorrow.',
              'What is on my agenda today?',
              'Switch to focus mode.',
            ];

  @override
  String get name => 'mock';

  @override
  bool get isConfigured => true;

  @override
  Future<String?> transcribeAudioFile(String path) async {
    await Future.delayed(const Duration(milliseconds: 600));
    final phrase = _phrases[_index % _phrases.length];
    _index++;
    return phrase;
  }
}

// ── OpenAI Whisper provider ───────────────────────────────────────────────────

/// Real transcription via OpenAI Whisper API.
///
/// Set STT_PROVIDER=openai and OPENAI_API_KEY in .env to activate.
/// Falls back to null (which the loop treats as a failed transcription) on any
/// network or API error — no crash.
class OpenAiSttProvider implements SttProvider {
  final String apiKey;
  final _log = Logger('OpenAiSttProvider');

  OpenAiSttProvider({required this.apiKey});

  @override
  String get name => 'openai';

  @override
  bool get isConfigured => apiKey.isNotEmpty;

  @override
  Future<String?> transcribeAudioFile(String path) async {
    if (!isConfigured) {
      _log.warning('[STT] OpenAI API key missing — falling back to null');
      return null;
    }

    final file = File(path);
    if (!file.existsSync()) {
      _log.warning('[STT] Audio file not found: $path');
      return null;
    }

    _log.info('[STT] Sending audio to OpenAI Whisper: $path');
    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('https://api.openai.com/v1/audio/transcriptions'),
      );
      request.headers[HttpHeaders.authorizationHeader] = 'Bearer $apiKey';
      request.files.add(
        await http.MultipartFile.fromPath('file', path, filename: 'audio.wav'),
      );
      request.fields['model'] = 'whisper-1';
      request.fields['language'] = 'en';

      final streamed =
          await request.send().timeout(const Duration(seconds: 30));
      final body = await streamed.stream.bytesToString();

      if (streamed.statusCode != 200) {
        _log.warning('[STT] Whisper error ${streamed.statusCode}: $body');
        return null;
      }

      final decoded = jsonDecode(body) as Map<String, dynamic>;
      final text = (decoded['text'] as String?)?.trim();
      _log.info('[STT] Whisper transcript: "$text"');
      return text;
    } catch (e) {
      _log.warning('[STT] Whisper request failed: $e');
      return null;
    }
  }
}

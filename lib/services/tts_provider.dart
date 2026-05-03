import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:path_provider/path_provider.dart';

/// Contract for text-to-speech backends.
///
/// Implement this interface to plug in any TTS service.
/// TTS is entirely optional: if [synthesizeToFile] returns null, or if
/// ENABLE_TTS=false, the rest of the voice loop continues unaffected.
///
/// Environment hooks (read via flutter_dotenv):
///   TTS_PROVIDER=mock|openai   (default: mock)
///   ENABLE_TTS=true|false      (default: false)
///   TTS_VOICE=onyx             (OpenAI voice name; default: onyx)
///   ASSISTANT_PERSONA=calm_executive
abstract class TtsProvider {
  /// Human-readable identifier shown in settings and debug tables.
  String get name;

  /// True when the provider has everything it needs.
  bool get isConfigured;

  /// Synthesize [text] and save the result to a temporary audio file.
  ///
  /// Returns the absolute path to the audio file, or `null` when synthesis is
  /// unavailable or disabled.  Callers must skip playback cleanly when null.
  Future<String?> synthesizeToFile(String text, {String? voice});
}

// ── Mock provider ─────────────────────────────────────────────────────────────

/// Silent mock — returns null so playback is skipped gracefully.
///
/// The full voice loop still runs (recording, STT, assistant, Frame output),
/// only actual audio output is absent.  This lets you test the loop on any
/// device without a speaker or credentials.
class MockTtsProvider implements TtsProvider {
  const MockTtsProvider();

  @override
  String get name => 'mock';

  @override
  bool get isConfigured => true;

  @override
  Future<String?> synthesizeToFile(String text, {String? voice}) async {
    // No-op: returns null → caller skips playback.
    await Future.delayed(const Duration(milliseconds: 50));
    return null;
  }
}

// ── OpenAI TTS provider ───────────────────────────────────────────────────────

/// Real speech synthesis via OpenAI TTS API.
///
/// Set TTS_PROVIDER=openai and OPENAI_API_KEY in .env to activate.
/// Default voice is 'onyx' — a calm, professional tone.
/// Falls back to null (playback skipped) on any network or API error.
class OpenAiTtsProvider implements TtsProvider {
  final String apiKey;
  final String defaultVoice;
  final _log = Logger('OpenAiTtsProvider');

  OpenAiTtsProvider({
    required this.apiKey,
    this.defaultVoice = 'onyx', // calm, authoritative — premium assistant style
  });

  @override
  String get name => 'openai';

  @override
  bool get isConfigured => apiKey.isNotEmpty;

  @override
  Future<String?> synthesizeToFile(String text, {String? voice}) async {
    if (!isConfigured) {
      _log.warning('[TTS] OpenAI API key missing — skipping synthesis');
      return null;
    }

    final effectiveVoice = voice ?? defaultVoice;
    _log.info('[TTS] Synthesizing via OpenAI TTS [voice=$effectiveVoice]: "$text"');
    try {
      final response = await http
          .post(
            Uri.parse('https://api.openai.com/v1/audio/speech'),
            headers: {
              HttpHeaders.authorizationHeader: 'Bearer $apiKey',
              HttpHeaders.contentTypeHeader: 'application/json',
            },
            body: jsonEncode({
              'model': 'tts-1',
              'input': text,
              'voice': effectiveVoice,
            }),
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode != 200) {
        _log.warning('[TTS] OpenAI error ${response.statusCode}: ${response.body}');
        return null;
      }

      final dir = await getTemporaryDirectory();
      final outPath =
          '${dir.path}/aria_tts_${DateTime.now().millisecondsSinceEpoch}.mp3';
      await File(outPath).writeAsBytes(response.bodyBytes);
      _log.info('[TTS] Saved audio to $outPath (${response.bodyBytes.length} bytes)');
      return outPath;
    } catch (e) {
      _log.warning('[TTS] Synthesis request failed: $e');
      return null;
    }
  }
}

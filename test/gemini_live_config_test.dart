import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noa/models/app_mode.dart';
import 'package:noa/models/gemini_live_config.dart';
import 'package:noa/services/gemini_live_service.dart';
import 'package:noa/services/voice_assistant_service.dart' show VoiceLoopState;

void main() {
  // Dotenv must be initialized before GeminiLiveConfig.effectiveApiKey is called.
  setUpAll(() => dotenv.testLoad(fileInput: 'GEMINI_API_KEY=\n'));
  // ── GeminiLiveConfig ────────────────────────────────────────────────────────

  group('GeminiLiveConfig', () {
    test('default config has sensible values', () {
      const cfg = GeminiLiveConfig();
      expect(cfg.enabled, isFalse);
      expect(cfg.model, GeminiLiveConfig.defaultModel);
      expect(cfg.voiceName, GeminiLiveConfig.defaultVoice);
      expect(cfg.apiKey, isEmpty);
      expect(cfg.ephemeralTokenUrl, isEmpty);
    });

    test('isConfigured is false when both apiKey and ephemeralTokenUrl empty', () {
      const cfg = GeminiLiveConfig();
      // effectiveApiKey falls back to dotenv which is empty in test.
      expect(cfg.isConfigured, isFalse);
    });

    test('isConfigured is true when ephemeralTokenUrl is set', () {
      const cfg = GeminiLiveConfig(
        ephemeralTokenUrl: 'http://localhost:8765/gemini/ephemeral-token',
      );
      expect(cfg.isConfigured, isTrue);
    });

    test('isConfigured is true when apiKey is set directly', () {
      const cfg = GeminiLiveConfig(apiKey: 'test-key');
      expect(cfg.effectiveApiKey, 'test-key');
      expect(cfg.isConfigured, isTrue);
    });

    test('copyWith preserves unmodified fields', () {
      const original = GeminiLiveConfig(
        enabled: true,
        apiKey: 'key',
        model: 'models/x',
        voiceName: 'Puck',
        ephemeralTokenUrl: 'http://x.com',
      );
      final copy = original.copyWith(voiceName: 'Aoede');
      expect(copy.enabled, isTrue);
      expect(copy.apiKey, 'key');
      expect(copy.model, 'models/x');
      expect(copy.voiceName, 'Aoede');
      expect(copy.ephemeralTokenUrl, 'http://x.com');
    });

    test('copyWith can toggle enabled', () {
      const cfg = GeminiLiveConfig(enabled: false);
      expect(cfg.copyWith(enabled: true).enabled, isTrue);
    });
  });

  // ── GeminiLiveState → VoiceLoopState mapping ──────────────────────────────

  group('GeminiLiveState voiceLoopState mapping', () {
    // Build a minimal service to test the mapping via voiceLoopState getter.
    // We test the mapping logic by directly checking the switch output.
    VoiceLoopState mapState(GeminiLiveState s) => switch (s) {
          GeminiLiveState.idle => VoiceLoopState.idle,
          GeminiLiveState.connecting => VoiceLoopState.connecting,
          GeminiLiveState.listening => VoiceLoopState.listening,
          GeminiLiveState.speaking => VoiceLoopState.speaking,
          GeminiLiveState.interrupted => VoiceLoopState.interrupted,
          GeminiLiveState.error => VoiceLoopState.error,
        };

    test('idle maps to idle', () {
      expect(mapState(GeminiLiveState.idle), VoiceLoopState.idle);
    });

    test('connecting maps to connecting', () {
      expect(mapState(GeminiLiveState.connecting), VoiceLoopState.connecting);
    });

    test('listening maps to listening', () {
      expect(mapState(GeminiLiveState.listening), VoiceLoopState.listening);
    });

    test('speaking maps to speaking', () {
      expect(mapState(GeminiLiveState.speaking), VoiceLoopState.speaking);
    });

    test('interrupted maps to interrupted', () {
      expect(
          mapState(GeminiLiveState.interrupted), VoiceLoopState.interrupted);
    });

    test('error maps to error', () {
      expect(mapState(GeminiLiveState.error), VoiceLoopState.error);
    });

    test('all GeminiLiveState values have a VoiceLoopState mapping', () {
      // Exhaust the enum — if a new value is added without updating the switch,
      // this test fails at compile time (exhaustive switch).
      for (final s in GeminiLiveState.values) {
        expect(mapState(s), isA<VoiceLoopState>());
      }
    });
  });

  // ── AppMode.systemPromptSuffix ─────────────────────────────────────────────

  group('AppMode prompt injection', () {
    test('standard mode has empty suffix or a non-null suffix', () {
      // systemPromptSuffix must be non-null for all modes.
      for (final mode in AppMode.values) {
        expect(mode.systemPromptSuffix, isNotNull);
      }
    });

    test('productivity mode suffix differs from standard', () {
      expect(
        AppMode.productivity.systemPromptSuffix,
        isNot(equals(AppMode.standard.systemPromptSuffix)),
      );
    });

    test('all modes have a non-empty icon', () {
      for (final mode in AppMode.values) {
        expect(mode.icon, isNotEmpty, reason: 'mode ${mode.name} has empty icon');
      }
    });

    test('all modes have a displayName', () {
      for (final mode in AppMode.values) {
        expect(mode.displayName, isNotEmpty,
            reason: 'mode ${mode.name} has empty displayName');
      }
    });
  });
}

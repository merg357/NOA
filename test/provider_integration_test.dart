/// Provider integration tests — no network calls, no API keys needed.
///
/// Covers:
///   1. STT / TTS provider isConfigured flag based on key presence
///   2. Assistant prompt construction includes AppMode suffix
///   3. Recent conversation history is threaded into assistant messages
///   4. Vision capture context is appended to the system prompt
///   5. Fallback to mock when openai provider is unconfigured
///   6. One-turn voice flow does not duplicate session turns
///   7. MockAssistantProvider produces mode-specific replies

import 'package:flutter_test/flutter_test.dart';
import 'package:noa/models/app_mode.dart';
import 'package:noa/models/capture_result.dart';
import 'package:noa/models/conversation_turn.dart';
import 'package:noa/models/voice_config.dart';
import 'package:noa/services/assistant_provider.dart';
import 'package:noa/services/audio_playback_service.dart';
import 'package:noa/services/conversation_session_service.dart';
import 'package:noa/services/stt_provider.dart';
import 'package:noa/services/tts_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ── OpenAiSttProvider ─────────────────────────────────────────────────────

  group('OpenAiSttProvider', () {
    test('isConfigured is false when apiKey is empty', () {
      final stt = OpenAiSttProvider(apiKey: '');
      expect(stt.isConfigured, false);
    });

    test('isConfigured is true when apiKey is non-empty', () {
      final stt = OpenAiSttProvider(apiKey: 'sk-test-key');
      expect(stt.isConfigured, true);
    });

    test('name is "openai"', () {
      expect(OpenAiSttProvider(apiKey: '').name, 'openai');
    });

    test('transcribeAudioFile returns null when key is empty (no crash)', () async {
      // Should not throw — returns null so the caller can handle gracefully.
      final result =
          await OpenAiSttProvider(apiKey: '').transcribeAudioFile('/fake.wav');
      expect(result, isNull);
    });

    test('transcribeAudioFile returns null when file does not exist', () async {
      // Even with a non-empty key, missing file must return null not throw.
      final result = await OpenAiSttProvider(apiKey: 'sk-fake')
          .transcribeAudioFile('/no/such/file_12345.wav');
      expect(result, isNull);
    });
  });

  // ── OpenAiTtsProvider ─────────────────────────────────────────────────────

  group('OpenAiTtsProvider', () {
    test('isConfigured is false when apiKey is empty', () {
      expect(OpenAiTtsProvider(apiKey: '').isConfigured, false);
    });

    test('isConfigured is true when apiKey is non-empty', () {
      expect(OpenAiTtsProvider(apiKey: 'sk-key').isConfigured, true);
    });

    test('name is "openai"', () {
      expect(OpenAiTtsProvider(apiKey: '').name, 'openai');
    });

    test('synthesizeToFile returns null when key is empty (no crash)', () async {
      final path = await OpenAiTtsProvider(apiKey: '').synthesizeToFile('hello');
      expect(path, isNull);
    });

    test('defaultVoice is "onyx" by default', () {
      expect(OpenAiTtsProvider(apiKey: 'k').defaultVoice, 'onyx');
    });

    test('defaultVoice is overridable', () {
      expect(
          OpenAiTtsProvider(apiKey: 'k', defaultVoice: 'nova').defaultVoice,
          'nova');
    });
  });

  // ── OpenAiAssistantProvider — prompt construction ─────────────────────────

  group('OpenAiAssistantProvider — buildSystemPrompt', () {
    late OpenAiAssistantProvider provider;

    setUp(() {
      provider = OpenAiAssistantProvider(apiKey: 'sk-test');
    });

    test('isConfigured is false when apiKey is empty', () {
      expect(OpenAiAssistantProvider(apiKey: '').isConfigured, false);
    });

    test('isConfigured is true when apiKey is non-empty', () {
      expect(provider.isConfigured, true);
    });

    test('name is "openai"', () {
      expect(provider.name, 'openai');
    });

    test('standard mode prompt contains ARIA identity', () {
      final prompt =
          provider.buildSystemPrompt(mode: AppMode.standard);
      expect(prompt, contains('ARIA'));
      expect(prompt, contains('wearable'));
    });

    test('productivity mode prompt includes productivity suffix', () {
      final prompt =
          provider.buildSystemPrompt(mode: AppMode.productivity);
      // AppMode.productivity.systemPromptSuffix mentions "actionable"
      expect(prompt, contains('actionable'));
    });

    test('focus mode prompt includes focus suffix', () {
      final prompt = provider.buildSystemPrompt(mode: AppMode.focus);
      // AppMode.focus.systemPromptSuffix mentions "essential"
      expect(prompt, contains('essential'));
    });

    test('meeting mode prompt includes meeting suffix', () {
      final prompt = provider.buildSystemPrompt(mode: AppMode.meeting);
      expect(prompt, contains('meeting'));
    });

    test('vision mode prompt includes vision suffix', () {
      final prompt = provider.buildSystemPrompt(mode: AppMode.vision);
      expect(prompt, contains('visual'));
    });

    test('capture context with OCR is appended to prompt', () {
      final capture = CaptureResult(
        imagePath: '/fake.jpg',
        ocrText: 'Invoice total: \$42.00',
        capturedAt: DateTime.now(),
      );
      final prompt =
          provider.buildSystemPrompt(mode: AppMode.standard, capture: capture);
      expect(prompt, contains('Invoice total'));
    });

    test('capture context with scene summary is appended', () {
      final capture = CaptureResult(
        imagePath: '/fake.jpg',
        sceneSummary: 'A whiteboard with a diagram',
        capturedAt: DateTime.now(),
      );
      final prompt =
          provider.buildSystemPrompt(mode: AppMode.vision, capture: capture);
      expect(prompt, contains('whiteboard'));
    });

    test('empty capture does not append context line', () {
      final capture = CaptureResult(
        imagePath: '/fake.jpg',
        capturedAt: DateTime.now(),
      );
      final prompt =
          provider.buildSystemPrompt(mode: AppMode.standard, capture: capture);
      // The "(no content detected)" text from bestText should NOT appear
      // because the provider only appends when hasScene/hasOcr/hasQr.
      expect(prompt, isNot(contains('currently see')));
    });

    test('null capture does not append context line', () {
      final prompt = provider.buildSystemPrompt(mode: AppMode.standard);
      expect(prompt, isNot(contains('currently see')));
    });
  });

  // ── MockAssistantProvider ─────────────────────────────────────────────────

  group('MockAssistantProvider', () {
    const mock = MockAssistantProvider();

    test('isConfigured is always true', () {
      expect(mock.isConfigured, true);
    });

    test('name is "mock"', () {
      expect(mock.name, 'mock');
    });

    test('returns a non-empty reply for standard mode', () async {
      final result = await mock.getReply(
        'Hello there',
        mode: AppMode.standard,
      );
      expect(result.displayText, isNotEmpty);
    });

    test('productivity mode reply differs from standard', () async {
      final std = await mock.getReply('test', mode: AppMode.standard);
      final prod =
          await mock.getReply('test', mode: AppMode.productivity);
      expect(std.displayText, isNot(equals(prod.displayText)));
    });

    test('focus mode returns short reply', () async {
      final result = await mock.getReply('any question', mode: AppMode.focus);
      expect(result.displayText, 'Done.');
    });

    test('ttsText equals displayText', () async {
      final result =
          await mock.getReply('question', mode: AppMode.standard);
      expect(result.ttsText, equals(result.displayText));
    });

    test('getReplySync returns non-null for all modes', () {
      for (final mode in AppMode.values) {
        final r = mock.getReplySync('anything', mode);
        expect(r.displayText, isNotEmpty);
      }
    });

    test('recent turns are accepted without crashing', () async {
      final turns = [
        ConversationTurn(
          id: '1',
          role: ConversationRole.user,
          text: 'what time is it?',
          timestamp: DateTime.now(),
        ),
        ConversationTurn(
          id: '2',
          role: ConversationRole.assistant,
          text: 'Your phone clock has the current time.',
          timestamp: DateTime.now(),
        ),
      ];
      final result = await mock.getReply(
        'follow up question',
        mode: AppMode.standard,
        recentTurns: turns,
      );
      expect(result.displayText, isNotEmpty);
    });
  });

  // ── Fallback logic ────────────────────────────────────────────────────────

  group('Provider fallback: empty key → mock behaviour', () {
    test('OpenAiSttProvider with empty key → null, not throw', () async {
      final stt = OpenAiSttProvider(apiKey: '');
      final result = await stt.transcribeAudioFile('/tmp/audio.wav');
      expect(result, isNull);
    });

    test('OpenAiTtsProvider with empty key → null, not throw', () async {
      final tts = OpenAiTtsProvider(apiKey: '');
      final result = await tts.synthesizeToFile('hello');
      expect(result, isNull);
    });

    test('MockSttProvider never fails even on non-existent path', () async {
      final result =
          await MockSttProvider().transcribeAudioFile('/nonexistent.wav');
      expect(result, isNotEmpty);
    });

    test('MockTtsProvider always returns null (silent)', () async {
      final result = await const MockTtsProvider().synthesizeToFile('hello');
      expect(result, isNull);
    });
  });

  // ── ConversationSessionService history slicing ────────────────────────────

  group('ConversationSessionService — recentTurns for assistant context', () {
    late ConversationSessionService session;

    setUp(() {
      session = ConversationSessionService();
    });

    test('recentTurns returns empty list on new session', () {
      expect(session.recentTurns(limit: 6), isEmpty);
    });

    test('recentTurns limit=6 after 3 turns returns all 3', () {
      session.addUserTurn('q1');
      session.addAssistantTurn('a1');
      session.addUserTurn('q2');
      final turns = session.recentTurns(limit: 6);
      expect(turns.length, 3);
    });

    test('recentTurns respects limit', () {
      for (int i = 0; i < 10; i++) {
        session.addUserTurn('q$i');
        session.addAssistantTurn('a$i');
      }
      expect(session.recentTurns(limit: 6).length, 6);
    });

    test('addUserTurn + addAssistantTurn do not duplicate', () {
      session.addUserTurn('hello');
      session.addAssistantTurn('world');
      expect(session.turnCount, 2);
    });

    test('one-turn flow: user+assistant = exactly 2 session turns', () {
      session.addUserTurn('transcript', source: TurnSource.voice);
      session.addAssistantTurn('reply');
      expect(session.turnCount, 2);
      expect(session.turns.first.role, ConversationRole.user);
      expect(session.turns.last.role, ConversationRole.assistant);
    });
  });

  // ── VoiceConfig — provider resolution ────────────────────────────────────

  group('VoiceConfig — effective provider names', () {
    test('mockMode=true forces STT to "mock" even if sttProvider=openai', () {
      final cfg = VoiceConfig(mockMode: true, sttProvider: 'openai');
      expect(cfg.effectiveSttProvider, 'mock');
    });

    test('mockMode=false + sttProvider=openai → effectiveSttProvider=openai', () {
      final cfg = VoiceConfig(mockMode: false, sttProvider: 'openai');
      expect(cfg.effectiveSttProvider, 'openai');
    });

    test('mockMode=true forces TTS to "mock" even if ttsProvider=openai', () {
      final cfg = VoiceConfig(mockMode: true, ttsProvider: 'openai');
      expect(cfg.effectiveTtsProvider, 'mock');
    });

    test('copyWith changes only the specified field', () {
      final base = VoiceConfig();
      final updated = base.copyWith(enableTts: true);
      expect(updated.enableTts, true);
      expect(updated.enableStt, base.enableStt);
      expect(updated.mockMode, base.mockMode);
    });
  });

  // ── AudioPlaybackService ─────────────────────────────────────────────────

  group('AudioPlaybackService', () {
    test('isPlaying starts as false', () {
      final svc = AudioPlaybackService();
      expect(svc.isPlaying, false);
      svc.dispose();
    });
  });
}

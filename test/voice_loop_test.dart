import 'package:flutter_test/flutter_test.dart';
import 'package:noa/models/app_logic_model.dart';
import 'package:noa/models/app_mode.dart';
import 'package:noa/models/assistant_result.dart';
import 'package:noa/models/wearable_card.dart';
import 'package:noa/services/assistant_provider.dart';
import 'package:noa/services/stt_provider.dart';
import 'package:noa/services/tts_provider.dart';
import 'package:noa/services/voice_assistant_service.dart';
import 'package:noa/services/voice_controller.dart';
import 'package:noa/services/audio_playback_service.dart';
import 'package:noa/services/conversation_session_service.dart';
import 'package:noa/models/voice_config.dart';

void main() {
  // Platform channels (record, just_audio) require the binding before setUp.
  TestWidgetsFlutterBinding.ensureInitialized();
  // ── Provider unit tests ────────────────────────────────────────────────────

  group('MockSttProvider', () {
    test('name is "mock"', () {
      expect(MockSttProvider().name, 'mock');
    });

    test('isConfigured is always true', () {
      expect(MockSttProvider().isConfigured, true);
    });

    test('transcribeAudioFile returns a non-empty string', () async {
      final result = await MockSttProvider().transcribeAudioFile('/fake/path.wav');
      expect(result, isNotEmpty);
    });

    test('cycles through distinct phrases', () async {
      final stt = MockSttProvider();
      final results = <String>[];
      for (int i = 0; i < 6; i++) {
        results.add(await stt.transcribeAudioFile('/fake/path.wav') ?? '');
      }
      // At least two distinct phrases across 6 calls
      expect(results.toSet().length, greaterThan(1));
    });
  });

  group('MockTtsProvider', () {
    test('name is "mock"', () {
      expect(MockTtsProvider().name, 'mock');
    });

    test('isConfigured is always true', () {
      expect(MockTtsProvider().isConfigured, true);
    });

    test('synthesizeToFile returns null (silent mode)', () async {
      final result = await MockTtsProvider().synthesizeToFile('Hello world');
      expect(result, isNull);
    });
  });

  // ── VoiceAssistantService state machine tests ──────────────────────────────

  group('VoiceAssistantService', () {
    late VoiceAssistantService vas;

    setUp(() {
      vas = VoiceAssistantService(
        voiceController: VoiceController(),
        session: ConversationSessionService(),
        playback: AudioPlaybackService(),
        stt: MockSttProvider(),
        tts: MockTtsProvider(),
        assistant: const MockAssistantProvider(),
        config: VoiceConfig(),
      );
    });

    tearDown(() => vas.dispose());

    test('starts in idle state', () {
      expect(vas.voiceState, VoiceLoopState.idle);
    });

    test('isListening is false when idle', () {
      expect(vas.isListening, false);
    });

    test('isBusy is false when idle', () {
      expect(vas.isBusy, false);
    });

    test('resetError clears the error state', () {
      vas.resetError();
      expect(vas.voiceState, VoiceLoopState.idle);
    });

    test('updateProviders does not crash with mock providers', () {
      expect(
        () => vas.updateProviders(
          VoiceConfig(),
          MockSttProvider(),
          MockTtsProvider(),
          const MockAssistantProvider(),
        ),
        returnsNormally,
      );
    });

    // Bug G regression: stopAndProcess must return Future<AssistantResult?>,
    // not Future<void>, so callers can inspect result.data['mode'].
    test('stopAndProcess return type is Future<AssistantResult?>', () {
      // Verify at the Dart type level that the API contract is correct.
      // If the return type reverted to void this line would not compile.
      Future<AssistantResult?> Function({
        required AppLogicModel appModel,
        required Future<AssistantResult?> Function(String) router,
      }) fn = vas.stopAndProcess;
      expect(fn, isNotNull);
    });

    // Bug A regression: stopAndProcess called when not listening returns null.
    test('stopAndProcess in wrong state returns null without crashing', () async {
      expect(vas.voiceState, VoiceLoopState.idle);
      // Should return null immediately, not throw.
      final result = await vas.stopAndProcess(
        appModel: _FakeAppModel(),
        router: (_) async => null,
      );
      expect(result, isNull);
      expect(vas.voiceState, VoiceLoopState.idle);
    });

    // startListening returns false when STT is disabled in config.
    test('startListening returns false when enableStt=false', () async {
      final disabledVas = VoiceAssistantService(
        voiceController: VoiceController(),
        session: ConversationSessionService(),
        playback: AudioPlaybackService(),
        stt: MockSttProvider(),
        tts: MockTtsProvider(),
        assistant: const MockAssistantProvider(),
        config: VoiceConfig(enableStt: false),
      );
      addTearDown(disabledVas.dispose);
      final ok = await disabledVas.startListening();
      expect(ok, false);
      expect(disabledVas.voiceState, VoiceLoopState.idle);
    });
  });

  // ── VoiceConfig tests ──────────────────────────────────────────────────────

  group('VoiceConfig', () {
    test('defaults: enableStt=true, enableTts=false, mockMode=true', () {
      final cfg = VoiceConfig();
      expect(cfg.enableStt, true);
      expect(cfg.enableTts, false);
      expect(cfg.mockMode, true);
    });

    test('copyWith preserves unmodified fields', () {
      final cfg = VoiceConfig();
      final modified = cfg.copyWith(enableTts: true);
      expect(modified.enableTts, true);
      expect(modified.enableStt, cfg.enableStt);
      expect(modified.ttsVoice, cfg.ttsVoice);
    });

    test('effectiveSttProvider returns sttProvider when not in mock mode', () {
      final cfg = VoiceConfig(mockMode: false, sttProvider: 'openai');
      expect(cfg.effectiveSttProvider, 'openai');
    });

    test('effectiveSttProvider returns "mock" when mockMode=true', () {
      final cfg = VoiceConfig(mockMode: true, sttProvider: 'openai');
      expect(cfg.effectiveSttProvider, 'mock');
    });

    test('effectiveTtsProvider returns "mock" when mockMode=true', () {
      final cfg = VoiceConfig(mockMode: true, ttsProvider: 'openai');
      expect(cfg.effectiveTtsProvider, 'mock');
    });
  });
}

// ── Test doubles ──────────────────────────────────────────────────────────────

/// Minimal stub of AppLogicModel for unit tests that avoids BLE/platform deps.
class _FakeAppModel extends AppLogicModel {
  AppMode _mode = AppMode.standard;

  @override
  AppMode get currentAppMode => _mode;

  @override
  void setAppMode(AppMode mode) => _mode = mode;

  @override
  Future<void> sendStatusBannerToFrame(String text) async {/* no-op */}

  @override
  Future<void> sendWearableCardToFrame(WearableCard card) async {/* no-op */}

  @override
  void addVoiceExchangeToChat(String userText, String assistantReply) {/* no-op */}

  @override
  Future<AssistantResult?> processLocalCommand(
    String text,
    Future<AssistantResult?> Function(String) router, {
    bool sendCard = true,
  }) async {
    return router(text);
  }
}

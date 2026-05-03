import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:noa/models/app_mode.dart';
import 'package:noa/models/voice_config.dart';
import 'package:noa/services/assistant_provider.dart';
import 'package:noa/services/audio_playback_service.dart';
import 'package:noa/services/conversation_session_service.dart';
import 'package:noa/services/gemini_live_service.dart';
import 'package:noa/services/persistence_service.dart';
import 'package:noa/services/productivity_service.dart';
import 'package:noa/services/command_router.dart';
import 'package:noa/services/stt_provider.dart';
import 'package:noa/services/tts_provider.dart';
import 'package:noa/services/voice_assistant_service.dart';
import 'package:noa/services/voice_controller.dart';

/// Riverpod provider for the [ProductivityService].
final productivityProvider = ChangeNotifierProvider<ProductivityService>((ref) {
  final svc = ProductivityService();
  svc.load(); // fire-and-forget load from SharedPreferences
  return svc;
});

/// Riverpod provider for [CommandRouter].
final commandRouterProvider = Provider<CommandRouter>((ref) {
  final productivity = ref.watch(productivityProvider);
  return CommandRouter(productivity);
});

/// Persistent app-mode provider backed by SharedPreferences.
final appModeProvider = StateNotifierProvider<AppModeNotifier, AppMode>((ref) {
  return AppModeNotifier();
});

class AppModeNotifier extends StateNotifier<AppMode> {
  final PersistenceService _store = PersistenceService();

  AppModeNotifier() : super(AppMode.standard) {
    _load();
  }

  Future<void> _load() async {
    final saved = await _store.loadAppMode();
    if (saved != null) {
      try {
        state = AppMode.values.firstWhere((m) => m.name == saved);
      } catch (_) {
        state = AppMode.standard;
      }
    }
  }

  Future<void> setMode(AppMode mode) async {
    state = mode;
    await _store.saveAppMode(mode.name);
  }
}

// ── Voice loop providers ───────────────────────────────────────────────────────

/// Stable [ConversationSessionService] provider.
final conversationSessionProvider =
    ChangeNotifierProvider<ConversationSessionService>(
  (_) => ConversationSessionService(),
);

/// Reads OPENAI_API_KEY from the loaded .env; returns empty string when absent.
String _openAiKey() => dotenv.env['OPENAI_API_KEY'] ?? '';

/// Builds the correct [SttProvider] from [VoiceConfig] + .env.
///
/// When [config.effectiveSttProvider] == 'openai' and OPENAI_API_KEY is set,
/// returns [OpenAiSttProvider].  Falls back to [MockSttProvider] when the key
/// is absent so the app never crashes on missing credentials.
SttProvider _buildSttProvider(VoiceConfig config) {
  if (config.effectiveSttProvider == 'openai') {
    final key = _openAiKey();
    if (key.isNotEmpty) {
      return OpenAiSttProvider(apiKey: key);
    }
    // Key missing — fall back to mock so the voice loop still works.
  }
  return MockSttProvider();
}

/// Builds the correct [TtsProvider] from [VoiceConfig] + .env.
///
/// When [config.effectiveTtsProvider] == 'openai' and OPENAI_API_KEY is set,
/// returns [OpenAiTtsProvider].  Falls back to [MockTtsProvider] otherwise.
TtsProvider _buildTtsProvider(VoiceConfig config) {
  if (config.effectiveTtsProvider == 'openai') {
    final key = _openAiKey();
    if (key.isNotEmpty) {
      final voice = dotenv.env['TTS_VOICE'] ?? 'onyx';
      return OpenAiTtsProvider(apiKey: key, defaultVoice: voice);
    }
  }
  return const MockTtsProvider();
}

/// Builds the correct [AssistantProvider] from [VoiceConfig] + .env.
///
/// When ASSISTANT_PROVIDER=openai and OPENAI_API_KEY is set, returns
/// [OpenAiAssistantProvider].  Falls back to [MockAssistantProvider] when
/// the key is absent or VOICE_MOCK_MODE=true.
AssistantProvider _buildAssistantProvider(VoiceConfig config) {
  final providerName = dotenv.env['ASSISTANT_PROVIDER'] ?? 'mock';
  if (!config.mockMode && providerName == 'openai') {
    final key = _openAiKey();
    if (key.isNotEmpty) {
      final model =
          dotenv.env['OPENAI_ASSISTANT_MODEL'] ?? 'gpt-4o-mini';
      return OpenAiAssistantProvider(apiKey: key, model: model);
    }
  }
  return const MockAssistantProvider();
}

/// Stable [VoiceAssistantService] provider.
///
/// Uses [ref.read] for its dependencies so the service instance is never
/// rebuilt mid-session.  Config changes are forwarded via [updateProviders].
final voiceAssistantProvider =
    ChangeNotifierProvider<VoiceAssistantService>((ref) {
  final config = ref.read(voiceConfigProvider);
  final session = ref.read(conversationSessionProvider);
  return VoiceAssistantService(
    voiceController: VoiceController(),
    session: session,
    playback: AudioPlaybackService(),
    stt: _buildSttProvider(config),
    tts: _buildTtsProvider(config),
    assistant: _buildAssistantProvider(config),
    config: config,
  );
});

/// Stable [GeminiLiveService] provider.
///
/// The service owns its own [AudioPlaybackService] so it does not conflict
/// with the fallback [VoiceAssistantService] (only one is active at a time).
final geminiLiveProvider = ChangeNotifierProvider<GeminiLiveService>((ref) {
  final session = ref.read(conversationSessionProvider);
  return GeminiLiveService(
    session: session,
    playback: AudioPlaybackService(),
  );
});

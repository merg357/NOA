import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Immutable configuration for the voice assistant loop.
///
/// Persisted to SharedPreferences by [VoiceConfigNotifier].
/// All fields have safe defaults so the app works out-of-the-box without any
/// API keys (mock-first design).
class VoiceConfig {
  /// Whether push-to-talk mic recording + STT is enabled.
  final bool enableStt;

  /// Whether TTS synthesis + audio playback is enabled.
  final bool enableTts;

  /// STT backend to use: 'mock' | 'openai'.
  final String sttProvider;

  /// TTS backend to use: 'mock' | 'openai'.
  final String ttsProvider;

  /// OpenAI TTS voice name (ignored when ttsProvider != 'openai').
  /// Use only OpenAI-native voice names (e.g. 'onyx', 'nova', 'alloy').
  final String ttsVoice;

  /// Persona style label — informational only; affects the system prompt suffix
  /// in the future.  'calm_executive' is the default premium-assistant style.
  final String assistantPersona;

  /// When true the app uses mock STT/TTS providers regardless of other settings.
  final bool mockMode;

  const VoiceConfig({
    this.enableStt = true,
    this.enableTts = false,
    this.sttProvider = 'mock',
    this.ttsProvider = 'mock',
    this.ttsVoice = 'onyx',
    this.assistantPersona = 'calm_executive',
    this.mockMode = true,
  });

  VoiceConfig copyWith({
    bool? enableStt,
    bool? enableTts,
    String? sttProvider,
    String? ttsProvider,
    String? ttsVoice,
    String? assistantPersona,
    bool? mockMode,
  }) {
    return VoiceConfig(
      enableStt: enableStt ?? this.enableStt,
      enableTts: enableTts ?? this.enableTts,
      sttProvider: sttProvider ?? this.sttProvider,
      ttsProvider: ttsProvider ?? this.ttsProvider,
      ttsVoice: ttsVoice ?? this.ttsVoice,
      assistantPersona: assistantPersona ?? this.assistantPersona,
      mockMode: mockMode ?? this.mockMode,
    );
  }

  /// The effective STT provider name, respecting mockMode override.
  String get effectiveSttProvider => mockMode ? 'mock' : sttProvider;

  /// The effective TTS provider name, respecting mockMode override.
  String get effectiveTtsProvider => mockMode ? 'mock' : ttsProvider;
}

// ── Notifier ──────────────────────────────────────────────────────────────────

class VoiceConfigNotifier extends StateNotifier<VoiceConfig> {
  static const _kEnableStt = 'voice_enable_stt';
  static const _kEnableTts = 'voice_enable_tts';
  static const _kSttProvider = 'voice_stt_provider';
  static const _kTtsProvider = 'voice_tts_provider';
  static const _kTtsVoice = 'voice_tts_voice';
  static const _kPersona = 'voice_persona';
  static const _kMockMode = 'voice_mock_mode';

  VoiceConfigNotifier() : super(const VoiceConfig()) {
    _load();
  }

  Future<void> _load() async {
    final sp = await SharedPreferences.getInstance();
    state = VoiceConfig(
      enableStt: sp.getBool(_kEnableStt) ?? true,
      enableTts: sp.getBool(_kEnableTts) ?? false,
      sttProvider: sp.getString(_kSttProvider) ?? 'mock',
      ttsProvider: sp.getString(_kTtsProvider) ?? 'mock',
      ttsVoice: sp.getString(_kTtsVoice) ?? 'onyx',
      assistantPersona: sp.getString(_kPersona) ?? 'calm_executive',
      mockMode: sp.getBool(_kMockMode) ?? true,
    );
  }

  Future<void> update(VoiceConfig newConfig) async {
    state = newConfig;
    final sp = await SharedPreferences.getInstance();
    await Future.wait([
      sp.setBool(_kEnableStt, newConfig.enableStt),
      sp.setBool(_kEnableTts, newConfig.enableTts),
      sp.setString(_kSttProvider, newConfig.sttProvider),
      sp.setString(_kTtsProvider, newConfig.ttsProvider),
      sp.setString(_kTtsVoice, newConfig.ttsVoice),
      sp.setString(_kPersona, newConfig.assistantPersona),
      sp.setBool(_kMockMode, newConfig.mockMode),
    ]);
  }
}

/// Global Riverpod provider for [VoiceConfig].
final voiceConfigProvider =
    StateNotifierProvider<VoiceConfigNotifier, VoiceConfig>(
  (_) => VoiceConfigNotifier(),
);

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Configuration for the Gemini Live real-time audio session.
///
/// When [enabled] is true, the primary voice path uses a persistent WebSocket
/// session with the Gemini Live API instead of the chained STT → assistant →
/// TTS fallback path.
///
/// **Key resolution order for [effectiveApiKey]:**
/// 1. Value stored in SharedPreferences (set programmatically — not exposed in
///    the settings UI for security; meant for internal / automated tests).
/// 2. `GEMINI_API_KEY` in the `.env` file (recommended for development).
/// 3. Empty string (Gemini Live will refuse to connect and surface an error).
///
/// **Client-side production** should use ephemeral tokens: set
/// [ephemeralTokenUrl] to a server endpoint that returns `{"token":"..."}` and
/// leave [apiKey] blank.  The service fetches a short-lived token before each
/// session so the API key is never transmitted from the client device.
class GeminiLiveConfig {
  /// Whether Gemini Live is the active (primary) voice path.
  final bool enabled;

  /// Stored API key.  Prefer leaving this blank and setting GEMINI_API_KEY in
  /// .env.  [effectiveApiKey] resolves this field → .env fallback.
  final String apiKey;

  /// Gemini Live model identifier.
  ///
  /// Defaults to [defaultModel].  Override via GEMINI_LIVE_MODEL in .env or
  /// directly in the settings page model field.
  final String model;

  /// Pre-built voice for audio output.
  ///
  /// Valid names (May 2025): Puck · Aoede · Charon · Fenrir · Kore.
  final String voiceName;

  /// Optional URL of a server endpoint that returns a short-lived ephemeral
  /// token.  When non-empty the service POSTs to this URL and uses the
  /// returned token instead of [effectiveApiKey].
  final String ephemeralTokenUrl;

  static const String defaultModel = 'models/gemini-2.0-flash-live-001';
  static const String defaultVoice = 'Puck';

  const GeminiLiveConfig({
    this.enabled = false,
    this.apiKey = '',
    this.model = defaultModel,
    this.voiceName = defaultVoice,
    this.ephemeralTokenUrl = '',
  });

  GeminiLiveConfig copyWith({
    bool? enabled,
    String? apiKey,
    String? model,
    String? voiceName,
    String? ephemeralTokenUrl,
  }) =>
      GeminiLiveConfig(
        enabled: enabled ?? this.enabled,
        apiKey: apiKey ?? this.apiKey,
        model: model ?? this.model,
        voiceName: voiceName ?? this.voiceName,
        ephemeralTokenUrl: ephemeralTokenUrl ?? this.ephemeralTokenUrl,
      );

  /// Resolves the effective API key: stored field → GEMINI_API_KEY in .env.
  String get effectiveApiKey {
    if (apiKey.isNotEmpty) return apiKey;
    return dotenv.env['GEMINI_API_KEY'] ?? '';
  }

  /// True when the service can connect (key or ephemeral URL is configured).
  bool get isConfigured =>
      effectiveApiKey.isNotEmpty || ephemeralTokenUrl.isNotEmpty;
}

// ── Notifier ──────────────────────────────────────────────────────────────────

class GeminiLiveConfigNotifier extends StateNotifier<GeminiLiveConfig> {
  static const _kEnabled = 'gemini_live_enabled';
  static const _kApiKey = 'gemini_live_api_key';
  static const _kModel = 'gemini_live_model';
  static const _kVoice = 'gemini_live_voice';
  static const _kEphemeralUrl = 'gemini_live_ephemeral_url';

  GeminiLiveConfigNotifier() : super(const GeminiLiveConfig()) {
    _load();
  }

  Future<void> _load() async {
    final sp = await SharedPreferences.getInstance();
    // .env values are the fallback when no SharedPreferences value is stored.
    final envEnabled = dotenv.env['GEMINI_LIVE_ENABLED'] == 'true';
    state = GeminiLiveConfig(
      enabled: sp.getBool(_kEnabled) ?? envEnabled,
      apiKey: sp.getString(_kApiKey) ?? '',
      model: sp.getString(_kModel) ??
          (dotenv.env['GEMINI_LIVE_MODEL'] ?? GeminiLiveConfig.defaultModel),
      voiceName: sp.getString(_kVoice) ??
          (dotenv.env['GEMINI_LIVE_VOICE'] ?? GeminiLiveConfig.defaultVoice),
      ephemeralTokenUrl: sp.getString(_kEphemeralUrl) ??
          (dotenv.env['GEMINI_LIVE_EPHEMERAL_TOKEN_URL'] ?? ''),
    );
  }

  Future<void> update(GeminiLiveConfig cfg) async {
    state = cfg;
    final sp = await SharedPreferences.getInstance();
    await Future.wait([
      sp.setBool(_kEnabled, cfg.enabled),
      sp.setString(_kApiKey, cfg.apiKey),
      sp.setString(_kModel, cfg.model),
      sp.setString(_kVoice, cfg.voiceName),
      sp.setString(_kEphemeralUrl, cfg.ephemeralTokenUrl),
    ]);
  }
}

/// Global Riverpod provider for [GeminiLiveConfig].
final geminiLiveConfigProvider =
    StateNotifierProvider<GeminiLiveConfigNotifier, GeminiLiveConfig>(
  (_) => GeminiLiveConfigNotifier(),
);

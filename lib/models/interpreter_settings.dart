import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Which direction the interpreter translates.
enum InterpreterDirection {
  /// Detect spoken language automatically and translate to English.
  autoToEnglish,

  /// Accept English speech and produce target-language output.
  englishToTarget,

  /// Auto-detect English or target language; translate in the opposite direction.
  bidirectional,
}

extension InterpreterDirectionExt on InterpreterDirection {
  String get displayName {
    switch (this) {
      case InterpreterDirection.autoToEnglish:
        return 'Any → English';
      case InterpreterDirection.englishToTarget:
        return 'English → Target';
      case InterpreterDirection.bidirectional:
        return 'Bidirectional';
    }
  }

  String get icon {
    switch (this) {
      case InterpreterDirection.autoToEnglish:
        return '🌍→🇬🇧';
      case InterpreterDirection.englishToTarget:
        return '🇬🇧→🌍';
      case InterpreterDirection.bidirectional:
        return '⇄';
    }
  }
}

/// Immutable snapshot of all interpreter-mode preferences.
class InterpreterSettings {
  final bool enabled;
  final InterpreterDirection direction;
  final String targetLanguage;
  final bool autoSpeak;
  final bool showPronunciation;
  final bool earbudMode;

  /// Full list of supported target languages for the picker.
  static const List<String> supportedLanguages = [
    'Arabic',
    'French',
    'German',
    'Hindi',
    'Italian',
    'Japanese',
    'Korean',
    'Mandarin',
    'Portuguese',
    'Russian',
    'Spanish',
    'Turkish',
  ];

  const InterpreterSettings({
    this.enabled = false,
    this.direction = InterpreterDirection.autoToEnglish,
    this.targetLanguage = 'Spanish',
    this.autoSpeak = true,
    this.showPronunciation = true,
    this.earbudMode = false,
  });

  InterpreterSettings copyWith({
    bool? enabled,
    InterpreterDirection? direction,
    String? targetLanguage,
    bool? autoSpeak,
    bool? showPronunciation,
    bool? earbudMode,
  }) =>
      InterpreterSettings(
        enabled: enabled ?? this.enabled,
        direction: direction ?? this.direction,
        targetLanguage: targetLanguage ?? this.targetLanguage,
        autoSpeak: autoSpeak ?? this.autoSpeak,
        showPronunciation: showPronunciation ?? this.showPronunciation,
        earbudMode: earbudMode ?? this.earbudMode,
      );

  // ── Gemini Live system instruction ───────────────────────────────────────

  /// Builds the complete Gemini Live system instruction for interpreter mode.
  ///
  /// The instruction uses a strict template format that [InterpreterResult]
  /// can parse deterministically.
  String buildGeminiInstruction() {
    switch (direction) {
      case InterpreterDirection.autoToEnglish:
        return _autoToEnglishInstruction();
      case InterpreterDirection.englishToTarget:
        return _englishToTargetInstruction(targetLanguage);
      case InterpreterDirection.bidirectional:
        return _bidirectionalInstruction(targetLanguage);
    }
  }

  static String _autoToEnglishInstruction() => '''
You are a real-time spoken-language interpreter. Your ONLY job is:
1. Detect the language of what the user said.
2. Transcribe exactly what was said in the original language.
3. Translate it naturally and concisely into English.

Respond EXACTLY in this format — no other text, no greetings, no commentary:
SOURCE_LANGUAGE: <detected language name in English>
ORIGINAL: <verbatim transcript in the original language>
TRANSLATION: <natural English translation>
PRONUNCIATION: <romanized pronunciation only if non-Latin script, else leave blank>
NOTE: <one very short usage note if genuinely useful, else leave blank>

Keep translations natural and concise. Never add assistant-style commentary.''';

  static String _englishToTargetInstruction(String lang) => '''
You are a real-time interpreter from English into $lang. Your ONLY job is:
1. Accept the English speech from the user.
2. Translate it naturally and concisely into $lang.
3. Provide a short pronunciation guide.

Respond EXACTLY in this format — no other text, no greetings, no commentary:
SOURCE_LANGUAGE: English
ORIGINAL: <verbatim transcript of what the user said in English>
TRANSLATION: <natural $lang translation>
PRONUNCIATION: <pronunciation guide in Latin script>
NOTE: <one very short usage note if genuinely useful, else leave blank>

Keep translations natural and concise. Never add assistant-style commentary.''';

  static String _bidirectionalInstruction(String lang) => '''
You are a real-time bidirectional interpreter between English and $lang. Your ONLY job is:
1. Detect whether the user spoke English or $lang.
2. Translate in the OPPOSITE direction (English→$lang or $lang→English).
3. Label source and output language clearly.

Respond EXACTLY in this format — no other text, no greetings, no commentary:
SOURCE_LANGUAGE: <detected language — "English" or "$lang">
ORIGINAL: <verbatim transcript in the detected language>
TRANSLATION: <translation in the opposite language>
PRONUNCIATION: <pronunciation guide if output is non-Latin or $lang uses non-Latin script, else leave blank>
NOTE: <one very short usage note if genuinely useful, else leave blank>

Keep translations natural and concise. Never add assistant-style commentary.''';
}

// ── StateNotifier ─────────────────────────────────────────────────────────────

class InterpreterSettingsNotifier extends StateNotifier<InterpreterSettings> {
  static const _kEnabled = 'interp_enabled';
  static const _kDirection = 'interp_direction';
  static const _kTargetLang = 'interp_target_lang';
  static const _kAutoSpeak = 'interp_auto_speak';
  static const _kShowPron = 'interp_show_pron';
  static const _kEarbudMode = 'interp_earbud_mode';

  InterpreterSettingsNotifier() : super(const InterpreterSettings()) {
    _load();
  }

  Future<void> _load() async {
    final sp = await SharedPreferences.getInstance();
    final dirIdx = sp.getInt(_kDirection) ?? 0;
    state = InterpreterSettings(
      enabled: sp.getBool(_kEnabled) ?? false,
      direction: InterpreterDirection.values[
          dirIdx.clamp(0, InterpreterDirection.values.length - 1)],
      targetLanguage: sp.getString(_kTargetLang) ?? 'Spanish',
      autoSpeak: sp.getBool(_kAutoSpeak) ?? true,
      showPronunciation: sp.getBool(_kShowPron) ?? true,
      earbudMode: sp.getBool(_kEarbudMode) ?? false,
    );
  }

  Future<void> update(InterpreterSettings s) async {
    state = s;
    final sp = await SharedPreferences.getInstance();
    await Future.wait([
      sp.setBool(_kEnabled, s.enabled),
      sp.setInt(_kDirection, s.direction.index),
      sp.setString(_kTargetLang, s.targetLanguage),
      sp.setBool(_kAutoSpeak, s.autoSpeak),
      sp.setBool(_kShowPron, s.showPronunciation),
      sp.setBool(_kEarbudMode, s.earbudMode),
    ]);
  }
}

/// Global Riverpod provider for interpreter mode settings.
final interpreterSettingsProvider =
    StateNotifierProvider<InterpreterSettingsNotifier, InterpreterSettings>(
  (_) => InterpreterSettingsNotifier(),
);

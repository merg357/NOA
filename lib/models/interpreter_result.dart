import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Parsed result from a single Gemini Live interpreter turn.
///
/// [InterpreterResult.tryParse] extracts structured fields from the strict
/// template that [InterpreterSettings.buildGeminiInstruction] asks Gemini to
/// produce:
///
/// ```
/// SOURCE_LANGUAGE: Spanish
/// ORIGINAL: ¿Cómo estás?
/// TRANSLATION: How are you?
/// PRONUNCIATION:
/// NOTE:
/// ```
class InterpreterResult {
  /// The language Gemini detected (e.g. "Spanish", "Japanese").
  final String? sourceLanguage;

  /// Verbatim transcript in the source language.
  final String? original;

  /// The translated output text.
  final String translation;

  /// Romanized pronunciation guide (populated for non-Latin output scripts).
  final String? pronunciation;

  /// Optional short contextual note.
  final String? note;

  final DateTime timestamp;

  const InterpreterResult({
    this.sourceLanguage,
    this.original,
    required this.translation,
    this.pronunciation,
    this.note,
    required this.timestamp,
  });

  // ── Parser ────────────────────────────────────────────────────────────────

  /// Attempts to extract fields from [text] using the structured template.
  ///
  /// Returns null if the text does not contain a non-empty TRANSLATION field,
  /// so callers can fall through to normal chat handling when Gemini responds
  /// outside interpreter mode format.
  static InterpreterResult? tryParse(String text) {
    // Split into lines and collect key→value pairs.  Blank values are skipped
    // so optional fields like PRONUNCIATION are naturally null when empty.
    final fields = <String, String>{};
    for (final line in text.split('\n')) {
      final colon = line.indexOf(':');
      if (colon < 0) continue;
      final key = line.substring(0, colon).trim();
      final value = line.substring(colon + 1).trim();
      if (key.isNotEmpty && value.isNotEmpty) {
        fields[key] = value;
      }
    }

    final translation = fields['TRANSLATION'];
    if (translation == null) return null;

    return InterpreterResult(
      sourceLanguage: fields['SOURCE_LANGUAGE'],
      original: fields['ORIGINAL'],
      translation: translation,
      pronunciation: fields['PRONUNCIATION'],
      note: fields['NOTE'],
      timestamp: DateTime.now(),
    );
  }

  // ── Display helpers ───────────────────────────────────────────────────────

  /// Human-readable direction label, e.g. "Spanish → English".
  String get directionLabel {
    final from = sourceLanguage ?? '?';
    // Guess the output language: if source is English, output is target; else English.
    final to = from.toLowerCase() == 'english' ? 'target' : 'English';
    return '$from → $to';
  }

  @override
  String toString() => 'InterpreterResult('
      'sourceLanguage=$sourceLanguage, '
      'translation=$translation)';
}

// ── StateNotifier + Provider ──────────────────────────────────────────────────

class InterpreterResultNotifier extends StateNotifier<InterpreterResult?> {
  InterpreterResultNotifier() : super(null);

  void update(InterpreterResult result) => state = result;

  void clear() => state = null;
}

/// Holds the most-recent interpreter result.
///
/// Updated by [GeminiLiveService] via an [onInterpreterResult] callback
/// wired from [NoaPage._handleMicTap].
final interpreterResultProvider =
    StateNotifierProvider<InterpreterResultNotifier, InterpreterResult?>(
  (_) => InterpreterResultNotifier(),
);

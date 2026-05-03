import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:noa/models/app_mode.dart';
import 'package:noa/models/assistant_result.dart';
import 'package:noa/models/capture_result.dart';
import 'package:noa/models/conversation_turn.dart';

/// Contract for conversational AI backends.
///
/// Each implementation takes the user's transcript, the current [AppMode],
/// recent conversation history, and optional vision capture context, and
/// returns a structured [AssistantResult].
///
/// Environment hooks (read via flutter_dotenv):
///   ASSISTANT_PROVIDER=mock|openai   (default: mock)
///   OPENAI_API_KEY=<key>             (needed when ASSISTANT_PROVIDER=openai)
///   OPENAI_ASSISTANT_MODEL=gpt-4o-mini (optional; default: gpt-4o-mini)
abstract class AssistantProvider {
  /// Human-readable identifier shown in settings and debug logs.
  String get name;

  /// True when the provider has all required config (API keys, etc.).
  bool get isConfigured;

  /// Generate a reply for [transcript].
  ///
  /// [mode] shapes the system prompt suffix (e.g. "focus" → 1-word answers).
  /// [recentTurns] are included as conversation history so the assistant has
  /// context from prior exchanges in this session (max 6 turns recommended).
  /// [capture] optionally provides vision context (OCR / scene summary) so the
  /// assistant can refer to what the user is looking at via Frame.
  Future<AssistantResult> getReply(
    String transcript, {
    required AppMode mode,
    List<ConversationTurn> recentTurns = const [],
    CaptureResult? capture,
  });
}

// ── Mock provider ─────────────────────────────────────────────────────────────

/// Mode-aware offline mock.  No network access, no API key needed.
///
/// Used when [ASSISTANT_PROVIDER=mock] (the default) or when the OpenAI key
/// is missing and [VOICE_MOCK_MODE=true].  The reply is deterministic based
/// on the current mode and simple keyword matching against the transcript.
class MockAssistantProvider implements AssistantProvider {
  const MockAssistantProvider();

  @override
  String get name => 'mock';

  @override
  bool get isConfigured => true;

  @override
  Future<AssistantResult> getReply(
    String transcript, {
    required AppMode mode,
    List<ConversationTurn> recentTurns = const [],
    CaptureResult? capture,
  }) async {
    // Simulate a brief processing delay so UI states are visible.
    await Future.delayed(const Duration(milliseconds: 200));
    final reply = _buildReply(transcript, mode);
    return AssistantResult(displayText: reply, ttsText: reply);
  }

  /// Synchronous variant used as an error-fallback in [VoiceAssistantService]
  /// when the primary provider throws — avoids an extra async call.
  AssistantResult getReplySync(String transcript, AppMode mode) {
    final reply = _buildReply(transcript, mode);
    return AssistantResult(displayText: reply, ttsText: reply);
  }

  String _buildReply(String transcript, AppMode mode) {
    final lower = transcript.toLowerCase();
    switch (mode) {
      case AppMode.productivity:
        return "Got it \u2014 I'll help you stay on track with that.";
      case AppMode.vision:
        return 'Scene noted. Let me know what you\'d like to capture next.';
      case AppMode.meeting:
        return 'Noted for the record.';
      case AppMode.focus:
        return 'Done.';
      case AppMode.standard:
        if (lower.contains('time')) {
          return 'Your phone clock has the current time.';
        } else if (lower.contains('weather')) {
          return "I'll need a connected backend to fetch weather.";
        } else if (lower.contains('hello') || lower.contains('hi ')) {
          return 'Hello! How can I assist you today?';
        }
        return "Understood. For full AI responses, connect to a backend.";
    }
  }
}

// ── OpenAI Chat Completions provider ─────────────────────────────────────────

/// Real assistant via OpenAI Chat Completions API.
///
/// Set ASSISTANT_PROVIDER=openai and OPENAI_API_KEY in .env to activate.
///
/// Request shape:
///   POST https://api.openai.com/v1/chat/completions
///   Authorization: Bearer $apiKey
///   Body: {
///     "model": model,
///     "messages": [system, ...history, user],
///     "max_tokens": 256
///   }
///
/// Falls back gracefully: if the API call fails, [getReply] throws so the
/// caller can catch and fall back to the mock provider.
class OpenAiAssistantProvider implements AssistantProvider {
  final String apiKey;
  final String model;
  final _log = Logger('OpenAiAssistantProvider');

  OpenAiAssistantProvider({
    required this.apiKey,
    this.model = 'gpt-4o-mini',
  });

  @override
  String get name => 'openai';

  @override
  bool get isConfigured => apiKey.isNotEmpty;

  @override
  Future<AssistantResult> getReply(
    String transcript, {
    required AppMode mode,
    List<ConversationTurn> recentTurns = const [],
    CaptureResult? capture,
  }) async {
    _log.info(
      '[Assistant] Requesting reply via OpenAI $model '
      '[mode=${mode.name}, history=${recentTurns.length} turns]',
    );

    final systemPrompt = buildSystemPrompt(mode: mode, capture: capture);

    // Build the messages array: system → history → current user turn.
    final messages = <Map<String, String>>[
      {'role': 'system', 'content': systemPrompt},
      ...recentTurns.map((t) => {
            'role': t.role == ConversationRole.user ? 'user' : 'assistant',
            'content': t.text,
          }),
      {'role': 'user', 'content': transcript},
    ];

    _log.info('[Assistant] Sending ${messages.length} messages to OpenAI');

    final response = await http
        .post(
          Uri.parse('https://api.openai.com/v1/chat/completions'),
          headers: {
            HttpHeaders.authorizationHeader: 'Bearer $apiKey',
            HttpHeaders.contentTypeHeader: 'application/json; charset=utf-8',
          },
          body: jsonEncode({
            'model': model,
            'messages': messages,
            'max_tokens': 256,
          }),
        )
        .timeout(const Duration(seconds: 30));

    if (response.statusCode != 200) {
      _log.warning(
          '[Assistant] OpenAI error ${response.statusCode}: ${response.body}');
      throw Exception(
          'OpenAI assistant returned HTTP ${response.statusCode}');
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final content =
        ((body['choices'] as List).first['message']['content'] as String)
            .trim();
    _log.info('[Assistant] Reply: "$content"');
    return AssistantResult(displayText: content, ttsText: content);
  }

  /// Builds the system prompt, incorporating the [AppMode] suffix and any
  /// available vision capture context.
  ///
  /// Exposed as a non-private method so tests can verify prompt construction
  /// without making any network calls.
  String buildSystemPrompt({required AppMode mode, CaptureResult? capture}) {
    final sb = StringBuffer(
      'You are ARIA, a concise wearable AI assistant for Brilliant Labs Frame'
      ' glasses. Answer in 1-2 sentences at most.'
      '${mode.systemPromptSuffix}',
    );
    if (capture != null &&
        (capture.hasScene || capture.hasOcr || capture.hasQr)) {
      sb.write(' The user can currently see: ${capture.bestText}');
    }
    return sb.toString();
  }
}

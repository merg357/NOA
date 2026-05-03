import 'package:noa/models/wearable_card.dart';

/// Structured result returned by the assistant layer (command router or Noa AI).
class AssistantResult {
  /// Text to show in the chat history and Frame HUD.
  final String displayText;

  /// Optional compact card destined for the Frame wearable display.
  final WearableCard? wearableCard;

  /// Text to speak via TTS (may differ from displayText).
  final String? ttsText;

  /// Human-readable description of the action taken (e.g. "Reminder saved").
  final String? actionTaken;

  /// Arbitrary payload for callers that need raw data.
  final Map<String, dynamic>? data;

  /// True when the assistant encountered an error.
  final bool isError;

  const AssistantResult({
    required this.displayText,
    this.wearableCard,
    this.ttsText,
    this.actionTaken,
    this.data,
    this.isError = false,
  });

  factory AssistantResult.error(String message) => AssistantResult(
        displayText: message,
        isError: true,
      );

  factory AssistantResult.plain(String text) =>
      AssistantResult(displayText: text);
}

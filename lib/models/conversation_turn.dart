/// Role of a participant in the conversation.
enum ConversationRole { user, assistant, system }

/// How the turn was produced.
enum TurnSource {
  /// User typed a text command.
  text,

  /// User spoke via the push-to-talk mic.
  voice,

  /// Turn originated from a camera/vision capture.
  vision,

  /// Internal system event (e.g. mode change).
  systemEvent,
}

/// A single turn in the conversational session.
class ConversationTurn {
  final String id;
  final ConversationRole role;
  final String text;
  final DateTime timestamp;
  final TurnSource source;

  const ConversationTurn({
    required this.id,
    required this.role,
    required this.text,
    required this.timestamp,
    this.source = TurnSource.text,
  });
}

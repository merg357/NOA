import 'package:flutter/foundation.dart';
import 'package:noa/models/app_mode.dart';
import 'package:noa/models/capture_result.dart';
import 'package:noa/models/conversation_turn.dart';
import 'package:noa/models/wearable_card.dart';

/// Maintains the stateful context of an ongoing voice/text conversation.
///
/// This service is separate from [AppLogicModel.noaMessages] which drives the
/// on-screen chat display.  [ConversationSessionService] holds the structured
/// turn history that is used to build context for assistant requests and for
/// building [WearableCard]s.
class ConversationSessionService extends ChangeNotifier {
  final List<ConversationTurn> _turns = [];
  static const int _maxTurns = 20;

  AppMode _mode = AppMode.standard;
  CaptureResult? _lastCapture;
  WearableCard? _latestCard;

  // ── Accessors ─────────────────────────────────────────────────────────────

  AppMode get mode => _mode;
  CaptureResult? get lastCapture => _lastCapture;
  WearableCard? get latestCard => _latestCard;
  List<ConversationTurn> get turns => List.unmodifiable(_turns);
  int get turnCount => _turns.length;

  // ── Turn management ───────────────────────────────────────────────────────

  void addUserTurn(String text, {TurnSource source = TurnSource.text}) {
    _addTurn(ConversationRole.user, text, source);
  }

  void addAssistantTurn(String text) {
    _addTurn(ConversationRole.assistant, text, TurnSource.systemEvent);
  }

  /// Returns the [limit] most-recent turns in chronological order.
  List<ConversationTurn> recentTurns({int limit = 6}) {
    if (_turns.length <= limit) return List.unmodifiable(_turns);
    return List.unmodifiable(_turns.sublist(_turns.length - limit));
  }

  void updateMode(AppMode mode) {
    _mode = mode;
    // no listener notification needed — only affects next request
  }

  void updateCapture(CaptureResult? capture) {
    _lastCapture = capture;
    notifyListeners();
  }

  void updateLatestCard(WearableCard? card) {
    _latestCard = card;
    notifyListeners();
  }

  void clearConversation() {
    _turns.clear();
    _latestCard = null;
    notifyListeners();
  }

  // ── Context builder ───────────────────────────────────────────────────────

  /// Returns a short summary of recent turns, suitable for inclusion in a
  /// mode-aware system prompt.
  String buildContextSummary({int limit = 4}) {
    final recent = recentTurns(limit: limit);
    if (recent.isEmpty) return '';
    final lines = recent.map((t) {
      final prefix = t.role == ConversationRole.user ? 'User' : 'Assistant';
      return '$prefix: ${t.text}';
    });
    return 'Recent context:\n${lines.join('\n')}';
  }

  // ── Private ───────────────────────────────────────────────────────────────

  void _addTurn(ConversationRole role, String text, TurnSource source) {
    _turns.add(ConversationTurn(
      id: '${DateTime.now().millisecondsSinceEpoch}_${_turns.length}',
      role: role,
      text: text,
      timestamp: DateTime.now(),
      source: source,
    ));
    if (_turns.length > _maxTurns) {
      _turns.removeRange(0, _turns.length - _maxTurns);
    }
    notifyListeners();
  }
}

import 'package:flutter_test/flutter_test.dart';
import 'package:noa/models/conversation_turn.dart';
import 'package:noa/services/conversation_session_service.dart';

void main() {
  group('ConversationSessionService', () {
    late ConversationSessionService session;

    setUp(() {
      session = ConversationSessionService();
    });

    tearDown(() => session.dispose());

    test('starts with zero turns', () {
      expect(session.turnCount, 0);
      expect(session.turns, isEmpty);
    });

    test('addUserTurn stores a user turn', () {
      session.addUserTurn('Hello');
      expect(session.turnCount, 1);
      expect(session.turns.first.role, ConversationRole.user);
      expect(session.turns.first.text, 'Hello');
    });

    test('addAssistantTurn stores an assistant turn', () {
      session.addAssistantTurn('Hi there');
      expect(session.turnCount, 1);
      expect(session.turns.first.role, ConversationRole.assistant);
      expect(session.turns.first.text, 'Hi there');
    });

    test('voice source is recorded on user turn', () {
      session.addUserTurn('test', source: TurnSource.voice);
      expect(session.turns.first.source, TurnSource.voice);
    });

    test('recentTurns returns limited slice', () {
      for (int i = 0; i < 10; i++) {
        session.addUserTurn('msg $i');
      }
      final recent = session.recentTurns(limit: 3);
      expect(recent.length, 3);
      expect(recent.last.text, 'msg 9');
    });

    test('clearConversation resets to zero', () {
      session.addUserTurn('one');
      session.addAssistantTurn('two');
      session.clearConversation();
      expect(session.turnCount, 0);
    });

    test('buildContextSummary contains all turn texts', () {
      session.addUserTurn('ping');
      session.addAssistantTurn('pong');
      final summary = session.buildContextSummary();
      expect(summary, contains('ping'));
      expect(summary, contains('pong'));
    });

    test('turn count caps at max (20 by default)', () {
      // Add more than the 20-turn cap
      for (int i = 0; i < 25; i++) {
        session.addUserTurn('msg $i');
      }
      // Should not exceed max
      expect(session.turnCount, lessThanOrEqualTo(20));
    });

    test('notifyListeners is called on addUserTurn', () {
      int notifCount = 0;
      session.addListener(() => notifCount++);
      session.addUserTurn('hello');
      expect(notifCount, 1);
    });

    test('notifyListeners is called on clearConversation', () {
      session.addUserTurn('hello');
      int notifCount = 0;
      session.addListener(() => notifCount++);
      session.clearConversation();
      expect(notifCount, 1);
    });
  });
}

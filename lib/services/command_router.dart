import 'package:noa/models/assistant_result.dart';
import 'package:noa/models/app_mode.dart';
import 'package:noa/models/wearable_card.dart';
import 'package:noa/services/productivity_service.dart';

/// Deterministic pattern-match router that handles productivity/assistant
/// text commands BEFORE they reach the Noa AI API.
///
/// Returns `null` when the input does not match any pattern — callers must
/// then fall through to the Noa AI backend.
class CommandRouter {
  final ProductivityService _productivity;

  CommandRouter(this._productivity);

  /// Try to handle [input]. Returns an [AssistantResult] on match, null otherwise.
  Future<AssistantResult?> route(String input) async {
    final text = input.trim();
    final lower = text.toLowerCase();

    // ── Reminders ────────────────────────────────────────────────────────────
    final remindMatch = _remindPattern.firstMatch(lower);
    if (remindMatch != null) {
      final content = _extractGroup(remindMatch, text);
      final reminder = await _productivity.addReminder(content);
      return AssistantResult(
        displayText: 'Reminder saved: "$content"',
        actionTaken: 'Reminder saved',
        wearableCard: WearableCard(
          id: reminder.id,
          title: 'Reminder saved',
          body: content,
          icon: '✓',
          mode: AppMode.productivity,
          timestamp: DateTime.now(),
          cardType: WearableCardType.reminder,
        ),
      );
    }

    if (_showRemindersPattern.hasMatch(lower)) {
      final pending = _productivity.pendingReminders;
      if (pending.isEmpty) {
        return AssistantResult.plain('You have no pending reminders.');
      }
      final list = pending
          .take(5)
          .map((r) => '• ${r.text}')
          .join('\n');
      return AssistantResult(
        displayText: '${pending.length} reminder${pending.length == 1 ? '' : 's'}:\n$list',
        actionTaken: 'Showed reminders',
      );
    }

    // ── Notes ─────────────────────────────────────────────────────────────────
    final noteMatch = _saveNotePattern.firstMatch(lower);
    if (noteMatch != null) {
      final content = _extractGroup(noteMatch, text);
      final title = content.split(' ').take(5).join(' ');
      final note = await _productivity.addNote(title, content);
      return AssistantResult(
        displayText: 'Note saved: "$title"',
        actionTaken: 'Note saved',
        wearableCard: WearableCard(
          id: note.id,
          title: 'Note',
          body: title,
          icon: '📝',
          mode: AppMode.productivity,
          timestamp: DateTime.now(),
          cardType: WearableCardType.note,
        ),
      );
    }

    if (_showNotesPattern.hasMatch(lower)) {
      final notes = _productivity.notes;
      if (notes.isEmpty) {
        return AssistantResult.plain('No notes saved yet.');
      }
      final list = notes
          .take(5)
          .map((n) => '• ${n.title}')
          .join('\n');
      return AssistantResult(
        displayText: '${notes.length} note${notes.length == 1 ? '' : 's'}:\n$list',
        actionTaken: 'Showed notes',
      );
    }

    // ── Memory facts ──────────────────────────────────────────────────────────
    final rememberMatch = _rememberPattern.firstMatch(lower);
    if (rememberMatch != null) {
      final content = _extractGroup(rememberMatch, text);
      // Naive key extraction: first few words
      final parts = content.split(RegExp(r'\s+'));
      final key = parts.take(3).join(' ');
      final value = content;
      await _productivity.saveFact(key, value);
      return AssistantResult(
        displayText: 'Remembered: "$content"',
        actionTaken: 'Memory saved',
      );
    }

    final recallMatch = _recallPattern.firstMatch(lower);
    if (recallMatch != null) {
      final query = _extractGroup(recallMatch, text);
      final found = _productivity.recallFacts(query);
      if (found.isEmpty) {
        return AssistantResult.plain('Nothing remembered about "$query".');
      }
      final list = found.take(3).map((f) => '• ${f.value}').join('\n');
      return AssistantResult(
        displayText: 'I remember:\n$list',
        actionTaken: 'Recalled facts',
      );
    }

    // ── Daily brief ───────────────────────────────────────────────────────────
    if (_dailyBriefPattern.hasMatch(lower)) {
      final brief = _productivity.generateDailyBrief();
      return AssistantResult(
        displayText: brief,
        actionTaken: 'Daily brief',
        wearableCard: WearableCard(
          id: 'brief-${DateTime.now().millisecondsSinceEpoch}',
          title: 'Daily Brief',
          body: brief,
          icon: '◈',
          mode: AppMode.productivity,
          timestamp: DateTime.now(),
          cardType: WearableCardType.dailyBrief,
        ),
      );
    }

    // ── Mode switching ────────────────────────────────────────────────────────
    for (final entry in _modePatterns.entries) {
      if (entry.key.hasMatch(lower)) {
        // Caller must handle the mode switch via the returned data field.
        return AssistantResult(
          displayText: 'Switched to ${entry.value.displayName} mode.',
          actionTaken: 'Mode switched',
          data: {'mode': entry.value.name},
        );
      }
    }

    // No match — fall through to Noa AI
    return null;
  }

  // ── Patterns ──────────────────────────────────────────────────────────────

  static final _remindPattern = RegExp(
    r'^(remind me to|reminder:|add reminder|set reminder for)\s+',
    caseSensitive: false,
  );

  static final _showRemindersPattern = RegExp(
    r'^(show|list|what are) (my )?(reminders?|todos?)',
    caseSensitive: false,
  );

  static final _saveNotePattern = RegExp(
    r'^(save note[:]?|note[:]?|write down|take note[:]?)\s+',
    caseSensitive: false,
  );

  static final _showNotesPattern = RegExp(
    r'^(show|list|what are) (my )?notes?',
    caseSensitive: false,
  );

  static final _rememberPattern = RegExp(
    r'^(remember (that |this )?|save (the )?fact[:]?)\s*',
    caseSensitive: false,
  );

  static final _recallPattern = RegExp(
    r'^(what do you remember about|recall|what did I say about)\s+',
    caseSensitive: false,
  );

  static final _dailyBriefPattern = RegExp(
    r'(daily brief|morning brief|whats? on (my )?plate|status update)',
    caseSensitive: false,
  );

  static final Map<RegExp, AppMode> _modePatterns = {
    RegExp(r'(switch to|set|enable) (standard|normal) mode', caseSensitive: false):
        AppMode.standard,
    RegExp(r'(switch to|set|enable) productivity mode', caseSensitive: false):
        AppMode.productivity,
    RegExp(r'(switch to|set|enable) vision mode', caseSensitive: false):
        AppMode.vision,
    RegExp(r'(switch to|set|enable) meeting mode', caseSensitive: false):
        AppMode.meeting,
    RegExp(r'(switch to|set|enable) focus mode', caseSensitive: false):
        AppMode.focus,
  };

  /// Strips the matched prefix from [original] to get the payload text.
  static String _extractGroup(RegExpMatch match, String original) {
    return original.substring(match.end).trim();
  }
}

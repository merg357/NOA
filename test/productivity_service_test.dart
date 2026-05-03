import 'package:flutter_test/flutter_test.dart';
import 'package:noa/services/persistence_service.dart';
import 'package:noa/services/productivity_service.dart';

// ── In-memory fake ──────────────────────────────────────────────────────────

class _FakePersistence extends PersistenceService {
  String? _reminders;
  String? _notes;
  String? _facts;
  String? _appMode;

  @override
  Future<String?> loadRawReminders() async => _reminders;
  @override
  Future<void> saveRawReminders(String json) async => _reminders = json;
  @override
  Future<String?> loadRawNotes() async => _notes;
  @override
  Future<void> saveRawNotes(String json) async => _notes = json;
  @override
  Future<String?> loadRawFacts() async => _facts;
  @override
  Future<void> saveRawFacts(String json) async => _facts = json;
  @override
  Future<String?> loadAppMode() async => _appMode;
  @override
  Future<void> saveAppMode(String mode) async => _appMode = mode;
}

// ── Helpers ─────────────────────────────────────────────────────────────────

ProductivityService _svc() =>
    ProductivityService(store: _FakePersistence());

// ── Tests ────────────────────────────────────────────────────────────────────

void main() {
  group('ProductivityService — reminders', () {
    test('starts with empty reminders', () {
      final svc = _svc();
      expect(svc.reminders, isEmpty);
      expect(svc.pendingReminders, isEmpty);
    });

    test('addReminder appends and notifies', () async {
      final svc = _svc();
      int notifyCount = 0;
      svc.addListener(() => notifyCount++);

      final r = await svc.addReminder('Buy milk');
      expect(r.text, 'Buy milk');
      expect(r.isDone, isFalse);
      expect(svc.pendingReminders.length, 1);
      expect(notifyCount, 1);
    });

    test('completeReminder marks isDone and removes from pendingReminders', () async {
      final svc = _svc();
      final r = await svc.addReminder('Call dentist');
      await svc.completeReminder(r.id);
      expect(svc.reminders.first.isDone, isTrue);
      expect(svc.pendingReminders, isEmpty);
    });

    test('deleteReminder removes from all reminders', () async {
      final svc = _svc();
      final r = await svc.addReminder('Dentist');
      await svc.deleteReminder(r.id);
      expect(svc.reminders, isEmpty);
    });

    test('deleteReminder on unknown id is a no-op', () async {
      final svc = _svc();
      await svc.addReminder('one');
      await svc.deleteReminder('does-not-exist');
      expect(svc.reminders.length, 1);
    });

    test('pendingReminders sorts soonest-due first', () async {
      final svc = _svc();
      final later = DateTime.now().add(const Duration(days: 7));
      final sooner = DateTime.now().add(const Duration(hours: 1));
      await svc.addReminder('Later', dueAt: later);
      await svc.addReminder('Sooner', dueAt: sooner);
      final pending = svc.pendingReminders;
      expect(pending.first.text, 'Sooner');
    });
  });

  group('ProductivityService — notes', () {
    test('addNote inserts at front of list', () async {
      final svc = _svc();
      await svc.addNote('First', 'body A');
      await svc.addNote('Second', 'body B');
      expect(svc.notes.first.title, 'Second');
    });

    test('deleteNote removes by id', () async {
      final svc = _svc();
      final n = await svc.addNote('T', 'b');
      await svc.deleteNote(n.id);
      expect(svc.notes, isEmpty);
    });
  });

  group('ProductivityService — memory facts', () {
    test('saveFact persists and recallFacts matches key', () async {
      final svc = _svc();
      await svc.saveFact('meeting room', 'The big meeting is in room 4B');
      final hits = svc.recallFacts('meeting');
      expect(hits.isNotEmpty, isTrue);
      expect(hits.first.value, contains('4B'));
    });

    test('recallFacts returns empty for unmatched query', () async {
      final svc = _svc();
      await svc.saveFact('project', 'Alpha project deadline is Friday');
      expect(svc.recallFacts('banana'), isEmpty);
    });
  });

  group('ProductivityService — load / persist round-trip', () {
    test('reminders survive save + load cycle', () async {
      final store = _FakePersistence();
      final svc1 = ProductivityService(store: store);
      await svc1.addReminder('Persist me');

      final svc2 = ProductivityService(store: store);
      await svc2.load();
      expect(svc2.reminders.length, 1);
      expect(svc2.reminders.first.text, 'Persist me');
    });

    test('notes survive save + load cycle', () async {
      final store = _FakePersistence();
      final svc1 = ProductivityService(store: store);
      await svc1.addNote('Durable', 'This note must survive');

      final svc2 = ProductivityService(store: store);
      await svc2.load();
      expect(svc2.notes.length, 1);
      expect(svc2.notes.first.title, 'Durable');
    });
  });

  group('ProductivityService — generateDailyBrief', () {
    test('returns a non-empty string', () async {
      final svc = _svc();
      await svc.addReminder('Morning standup');
      final brief = svc.generateDailyBrief();
      expect(brief.isNotEmpty, isTrue);
    });

    test('mentions pending reminder count', () async {
      final svc = _svc();
      await svc.addReminder('Task 1');
      await svc.addReminder('Task 2');
      final brief = svc.generateDailyBrief();
      expect(brief, contains('2'));
    });
  });
}

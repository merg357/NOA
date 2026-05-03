import 'package:flutter_test/flutter_test.dart';
import 'package:noa/models/app_mode.dart';
import 'package:noa/services/command_router.dart';
import 'package:noa/services/persistence_service.dart';
import 'package:noa/services/productivity_service.dart';

// ── In-memory fake (duplicated to keep tests independent) ───────────────────

class _FakePersistence extends PersistenceService {
  String? _r, _n, _f, _m;
  @override Future<String?> loadRawReminders() async => _r;
  @override Future<void> saveRawReminders(String json) async => _r = json;
  @override Future<String?> loadRawNotes() async => _n;
  @override Future<void> saveRawNotes(String json) async => _n = json;
  @override Future<String?> loadRawFacts() async => _f;
  @override Future<void> saveRawFacts(String json) async => _f = json;
  @override Future<String?> loadAppMode() async => _m;
  @override Future<void> saveAppMode(String mode) async => _m = mode;
}

ProductivityService _svc() =>
    ProductivityService(store: _FakePersistence());

CommandRouter _router(ProductivityService svc) => CommandRouter(svc);

// ── Tests ────────────────────────────────────────────────────────────────────

void main() {
  group('CommandRouter — no match', () {
    test('returns null for arbitrary text', () async {
      final r = _router(_svc());
      expect(await r.route('Hello world!'), isNull);
    });

    test('returns null for empty string', () async {
      final r = _router(_svc());
      expect(await r.route(''), isNull);
    });

    test('returns null for unrelated question', () async {
      final r = _router(_svc());
      expect(await r.route('What is the capital of France?'), isNull);
    });
  });

  group('CommandRouter — reminders', () {
    test('"remind me to buy milk" creates reminder', () async {
      final svc = _svc();
      final r = _router(svc);
      final result = await r.route('remind me to buy milk');
      expect(result, isNotNull);
      expect(result!.displayText, contains('buy milk'));
      expect(svc.reminders.length, 1);
    });

    test('"reminder: call dentist" creates reminder', () async {
      final svc = _svc();
      final result = await _router(svc).route('reminder: call dentist');
      expect(result, isNotNull);
      expect(svc.reminders.length, 1);
    });

    test('"show my reminders" lists pending reminders', () async {
      final svc = _svc();
      await svc.addReminder('one');
      await svc.addReminder('two');
      final result = await _router(svc).route('show my reminders');
      expect(result, isNotNull);
      expect(result!.displayText, contains('one'));
    });

    test('"list reminders" on empty list returns no-pending message', () async {
      final result = await _router(_svc()).route('list reminders');
      expect(result, isNotNull);
      expect(result!.displayText, contains('no pending'));
    });
  });

  group('CommandRouter — notes', () {
    test('"save note: meeting agenda" creates note', () async {
      final svc = _svc();
      final result = await _router(svc).route('save note: meeting agenda');
      expect(result, isNotNull);
      expect(result!.displayText, contains('meeting'));
      expect(svc.notes.length, 1);
    });

    test('"note: quick idea" creates note', () async {
      final svc = _svc();
      final result = await _router(svc).route('note: quick idea');
      expect(result, isNotNull);
      expect(svc.notes.length, 1);
    });

    test('"show notes" lists notes', () async {
      final svc = _svc();
      await svc.addNote('Sprint plan', 'body');
      final result = await _router(svc).route('show notes');
      expect(result, isNotNull);
      expect(result!.displayText, contains('Sprint plan'));
    });

    test('"list my notes" on empty list returns no-notes message', () async {
      final result = await _router(_svc()).route('list my notes');
      expect(result, isNotNull);
      expect(result!.displayText, contains('No notes'));
    });
  });

  group('CommandRouter — memory facts', () {
    test('"remember that the PIN is 1234" saves fact', () async {
      final svc = _svc();
      final result = await _router(svc).route('remember that the PIN is 1234');
      expect(result, isNotNull);
      expect(result!.displayText, contains('Remembered'));
      expect(svc.facts.isNotEmpty, isTrue);
    });

    test('"recall PIN" retrieves saved fact', () async {
      final svc = _svc();
      await _router(svc).route('remember that the PIN is 1234');
      final result = await _router(svc).route('recall PIN');
      expect(result, isNotNull);
      expect(result!.displayText.toLowerCase(), contains('remember'));
    });
  });

  group('CommandRouter — mode switching', () {
    test('"switch to productivity mode" returns mode data', () async {
      final result = await _router(_svc()).route('switch to productivity mode');
      expect(result, isNotNull);
      expect(result!.data?['mode'], 'productivity');
    });

    test('"switch to focus mode" returns focus mode data', () async {
      final result = await _router(_svc()).route('switch to focus mode');
      expect(result, isNotNull);
      expect(result!.data?['mode'], 'focus');
    });

    test('"set normal mode" returns standard mode data', () async {
      final result = await _router(_svc()).route('set normal mode');
      expect(result, isNotNull);
      expect(result!.data?['mode'], AppMode.standard.name);
    });
  });

  group('CommandRouter — daily brief', () {
    test('"daily brief" returns non-empty result', () async {
      final result = await _router(_svc()).route('daily brief');
      expect(result, isNotNull);
      expect(result!.displayText.isNotEmpty, isTrue);
    });

    test('"what is my daily brief" also matches', () async {
      final result = await _router(_svc()).route('what is my daily brief');
      expect(result, isNotNull);
    });
  });
}

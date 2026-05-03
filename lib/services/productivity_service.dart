import 'package:flutter/foundation.dart';
import 'package:noa/models/memory_fact.dart';
import 'package:noa/models/note_model.dart';
import 'package:noa/models/reminder_model.dart';
import 'package:noa/services/persistence_service.dart';

/// Manages reminders, notes and memory facts with JSON-encoded SharedPreferences.
class ProductivityService extends ChangeNotifier {
  final PersistenceService _store;

  List<ReminderModel> _reminders = [];
  List<NoteModel> _notes = [];
  List<MemoryFact> _facts = [];

  List<ReminderModel> get reminders => List.unmodifiable(_reminders);
  List<NoteModel> get notes => List.unmodifiable(_notes);
  List<MemoryFact> get facts => List.unmodifiable(_facts);

  /// Pending (not done) reminders, sorted soonest first.
  List<ReminderModel> get pendingReminders => _reminders
      .where((r) => !r.isDone)
      .toList()
    ..sort((a, b) {
      if (a.dueAt == null && b.dueAt == null) return 0;
      if (a.dueAt == null) return 1;
      if (b.dueAt == null) return -1;
      return a.dueAt!.compareTo(b.dueAt!);
    });

  ProductivityService({PersistenceService? store})
      : _store = store ?? PersistenceService();

  Future<void> load() async {
    final rawR = await _store.loadRawReminders();
    final rawN = await _store.loadRawNotes();
    final rawF = await _store.loadRawFacts();
    if (rawR != null && rawR.isNotEmpty) {
      _reminders = ReminderModel.decodeList(rawR);
    }
    if (rawN != null && rawN.isNotEmpty) {
      _notes = NoteModel.decodeList(rawN);
    }
    if (rawF != null && rawF.isNotEmpty) {
      _facts = MemoryFact.decodeList(rawF);
    }
    notifyListeners();
  }

  // ── Reminders ──────────────────────────────────────────────────────────────

  Future<ReminderModel> addReminder(String text, {DateTime? dueAt}) async {
    final r = ReminderModel(
      id: _uid(),
      text: text,
      dueAt: dueAt,
      createdAt: DateTime.now(),
    );
    _reminders.insert(0, r);
    await _persistReminders();
    notifyListeners();
    return r;
  }

  Future<void> completeReminder(String id) async {
    final idx = _reminders.indexWhere((r) => r.id == id);
    if (idx == -1) return;
    _reminders[idx] = _reminders[idx].copyWith(isDone: true);
    await _persistReminders();
    notifyListeners();
  }

  Future<void> deleteReminder(String id) async {
    _reminders.removeWhere((r) => r.id == id);
    await _persistReminders();
    notifyListeners();
  }

  Future<void> _persistReminders() async =>
      _store.saveRawReminders(ReminderModel.encodeList(_reminders));

  // ── Notes ──────────────────────────────────────────────────────────────────

  Future<NoteModel> addNote(String title, String body) async {
    final n = NoteModel(
      id: _uid(),
      title: title,
      body: body,
      createdAt: DateTime.now(),
    );
    _notes.insert(0, n);
    await _persistNotes();
    notifyListeners();
    return n;
  }

  Future<void> deleteNote(String id) async {
    _notes.removeWhere((n) => n.id == id);
    await _persistNotes();
    notifyListeners();
  }

  Future<void> _persistNotes() async =>
      _store.saveRawNotes(NoteModel.encodeList(_notes));

  // ── Memory facts ───────────────────────────────────────────────────────────

  Future<MemoryFact> saveFact(String key, String value) async {
    // Overwrite if key already exists.
    _facts.removeWhere((f) => f.key.toLowerCase() == key.toLowerCase());
    final f = MemoryFact(
      id: _uid(),
      key: key,
      value: value,
      savedAt: DateTime.now(),
    );
    _facts.insert(0, f);
    await _persistFacts();
    notifyListeners();
    return f;
  }

  List<MemoryFact> recallFacts(String query) {
    final q = query.toLowerCase();
    return _facts
        .where((f) =>
            f.key.toLowerCase().contains(q) ||
            f.value.toLowerCase().contains(q))
        .toList();
  }

  Future<void> deleteFact(String id) async {
    _facts.removeWhere((f) => f.id == id);
    await _persistFacts();
    notifyListeners();
  }

  Future<void> _persistFacts() async =>
      _store.saveRawFacts(MemoryFact.encodeList(_facts));

  // ── Daily brief ────────────────────────────────────────────────────────────

  /// Returns a plain-text daily brief string suitable for Frame display.
  String generateDailyBrief() {
    final now = DateTime.now();
    final pending = pendingReminders;
    final lines = <String>[];

    lines.add('${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')} daily brief');

    if (pending.isEmpty) {
      lines.add('No pending reminders.');
    } else {
      lines.add('${pending.length} reminder${pending.length == 1 ? '' : 's'}:');
      for (final r in pending.take(3)) {
        lines.add('• ${r.text}');
      }
      if (pending.length > 3) lines.add('  … +${pending.length - 3} more');
    }

    if (_notes.isNotEmpty) {
      lines.add('${_notes.length} note${_notes.length == 1 ? '' : 's'} saved.');
    }
    return lines.join('\n');
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  String _uid() =>
      DateTime.now().millisecondsSinceEpoch.toRadixString(36) +
      _randHex(4);

  String _randHex(int len) {
    final buf = StringBuffer();
    final rng = DateTime.now().microsecondsSinceEpoch;
    for (int i = 0; i < len; i++) {
      buf.write(((rng >> (i * 4)) & 0xF).toRadixString(16));
    }
    return buf.toString();
  }
}

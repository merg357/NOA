import 'package:shared_preferences/shared_preferences.dart';

/// Thin wrapper around [SharedPreferences] for JSON-list persistence.
class PersistenceService {
  static const _remindersKey = 'aria_reminders';
  static const _notesKey = 'aria_notes';
  static const _factsKey = 'aria_facts';
  static const _appModeKey = 'aria_app_mode';

  Future<String?> loadRawReminders() async =>
      (await SharedPreferences.getInstance()).getString(_remindersKey);

  Future<void> saveRawReminders(String json) async =>
      (await SharedPreferences.getInstance()).setString(_remindersKey, json);

  Future<String?> loadRawNotes() async =>
      (await SharedPreferences.getInstance()).getString(_notesKey);

  Future<void> saveRawNotes(String json) async =>
      (await SharedPreferences.getInstance()).setString(_notesKey, json);

  Future<String?> loadRawFacts() async =>
      (await SharedPreferences.getInstance()).getString(_factsKey);

  Future<void> saveRawFacts(String json) async =>
      (await SharedPreferences.getInstance()).setString(_factsKey, json);

  Future<String?> loadAppMode() async =>
      (await SharedPreferences.getInstance()).getString(_appModeKey);

  Future<void> saveAppMode(String mode) async =>
      (await SharedPreferences.getInstance()).setString(_appModeKey, mode);
}

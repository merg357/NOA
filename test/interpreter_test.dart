import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noa/models/audio_route_state.dart';
import 'package:noa/models/interpreter_result.dart';
import 'package:noa/models/interpreter_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  // ── InterpreterSettings defaults ────────────────────────────────────────
  group('InterpreterSettings defaults', () {
    test('disabled by default', () {
      const s = InterpreterSettings();
      expect(s.enabled, isFalse);
    });

    test('direction defaults to autoToEnglish', () {
      const s = InterpreterSettings();
      expect(s.direction, InterpreterDirection.autoToEnglish);
    });

    test('targetLanguage defaults to Spanish', () {
      const s = InterpreterSettings();
      expect(s.targetLanguage, 'Spanish');
    });

    test('autoSpeak defaults to true', () {
      const s = InterpreterSettings();
      expect(s.autoSpeak, isTrue);
    });

    test('showPronunciation defaults to true', () {
      const s = InterpreterSettings();
      expect(s.showPronunciation, isTrue);
    });

    test('earbudMode defaults to false', () {
      const s = InterpreterSettings();
      expect(s.earbudMode, isFalse);
    });
  });

  // ── InterpreterSettings.copyWith ────────────────────────────────────────
  group('InterpreterSettings.copyWith', () {
    test('updates enabled only', () {
      const s = InterpreterSettings();
      final s2 = s.copyWith(enabled: true);
      expect(s2.enabled, isTrue);
      expect(s2.direction, s.direction);
      expect(s2.targetLanguage, s.targetLanguage);
    });

    test('updates direction only', () {
      const s = InterpreterSettings();
      final s2 = s.copyWith(direction: InterpreterDirection.englishToTarget);
      expect(s2.direction, InterpreterDirection.englishToTarget);
      expect(s2.enabled, s.enabled);
    });

    test('updates targetLanguage only', () {
      const s = InterpreterSettings();
      final s2 = s.copyWith(targetLanguage: 'Japanese');
      expect(s2.targetLanguage, 'Japanese');
    });

    test('updates earbudMode only', () {
      const s = InterpreterSettings();
      final s2 = s.copyWith(earbudMode: true);
      expect(s2.earbudMode, isTrue);
      expect(s2.enabled, s.enabled);
    });
  });

  // ── InterpreterDirection ────────────────────────────────────────────────
  group('InterpreterDirection', () {
    test('all values have a displayName', () {
      for (final d in InterpreterDirection.values) {
        expect(d.displayName, isNotEmpty);
      }
    });

    test('all values have an icon', () {
      for (final d in InterpreterDirection.values) {
        expect(d.icon, isNotEmpty);
      }
    });
  });

  // ── Gemini instruction composition ──────────────────────────────────────
  group('InterpreterSettings.buildGeminiInstruction', () {
    test('autoToEnglish instruction contains SOURCE_LANGUAGE template', () {
      const s = InterpreterSettings(
          enabled: true, direction: InterpreterDirection.autoToEnglish);
      final instr = s.buildGeminiInstruction();
      expect(instr, contains('SOURCE_LANGUAGE:'));
      expect(instr, contains('TRANSLATION:'));
      expect(instr, contains('PRONUNCIATION:'));
    });

    test('englishToTarget instruction mentions target language', () {
      const s = InterpreterSettings(
        enabled: true,
        direction: InterpreterDirection.englishToTarget,
        targetLanguage: 'French',
      );
      final instr = s.buildGeminiInstruction();
      expect(instr, contains('French'));
      expect(instr, contains('SOURCE_LANGUAGE: English'));
    });

    test('bidirectional instruction mentions both languages', () {
      const s = InterpreterSettings(
        enabled: true,
        direction: InterpreterDirection.bidirectional,
        targetLanguage: 'Korean',
      );
      final instr = s.buildGeminiInstruction();
      expect(instr, contains('Korean'));
      expect(instr, contains('English'));
      expect(instr, contains('TRANSLATION:'));
    });

    test('instruction contains strict NO commentary clause', () {
      for (final dir in InterpreterDirection.values) {
        final s = InterpreterSettings(enabled: true, direction: dir);
        expect(s.buildGeminiInstruction(), contains('no other text'));
      }
    });
  });

  // ── InterpreterResult.tryParse ──────────────────────────────────────────
  group('InterpreterResult.tryParse', () {
    const fullTemplate = '''
SOURCE_LANGUAGE: Spanish
ORIGINAL: ¿Cómo estás?
TRANSLATION: How are you?
PRONUNCIATION: 
NOTE: Informal greeting
''';

    test('parses all fields from full template', () {
      final r = InterpreterResult.tryParse(fullTemplate);
      expect(r, isNotNull);
      expect(r!.sourceLanguage, 'Spanish');
      expect(r.original, '¿Cómo estás?');
      expect(r.translation, 'How are you?');
      expect(r.note, 'Informal greeting');
      expect(r.pronunciation, isNull); // blank line → null
    });

    test('returns null when TRANSLATION is missing', () {
      const text = 'SOURCE_LANGUAGE: French\nORIGINAL: Bonjour\n';
      expect(InterpreterResult.tryParse(text), isNull);
    });

    test('returns null for empty string', () {
      expect(InterpreterResult.tryParse(''), isNull);
    });

    test('parses even without optional fields', () {
      const text = 'TRANSLATION: Hello';
      final r = InterpreterResult.tryParse(text);
      expect(r, isNotNull);
      expect(r!.translation, 'Hello');
      expect(r.sourceLanguage, isNull);
      expect(r.original, isNull);
    });

    test('parses Japanese → English with pronunciation', () {
      const text = '''
SOURCE_LANGUAGE: Japanese
ORIGINAL: ありがとうございます
TRANSLATION: Thank you very much
PRONUNCIATION: Arigatou gozaimasu
NOTE: Formal expression of gratitude
''';
      final r = InterpreterResult.tryParse(text);
      expect(r, isNotNull);
      expect(r!.pronunciation, 'Arigatou gozaimasu');
      expect(r.translation, 'Thank you very much');
    });

    test('timestamp is set on parse', () {
      final before = DateTime.now();
      final r = InterpreterResult.tryParse('TRANSLATION: Hi');
      final after = DateTime.now();
      expect(r!.timestamp.isAfter(before) || r.timestamp.isAtSameMomentAs(before), isTrue);
      expect(r.timestamp.isBefore(after) || r.timestamp.isAtSameMomentAs(after), isTrue);
    });
  });

  // ── InterpreterResult.directionLabel ───────────────────────────────────
  group('InterpreterResult.directionLabel', () {
    test('shows source language when known', () {
      final r = InterpreterResult(
          sourceLanguage: 'Spanish',
          translation: 'Hello',
          timestamp: DateTime.now());
      expect(r.directionLabel, contains('Spanish'));
    });

    test('falls back to ? when source language is null', () {
      final r =
          InterpreterResult(translation: 'Hello', timestamp: DateTime.now());
      expect(r.directionLabel, contains('?'));
    });
  });

  // ── InterpreterResultNotifier ────────────────────────────────────────────
  group('InterpreterResultNotifier', () {
    test('starts as null', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(interpreterResultProvider), isNull);
    });

    test('update sets state', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final r =
          InterpreterResult(translation: 'Bonjour', timestamp: DateTime.now());
      container.read(interpreterResultProvider.notifier).update(r);
      expect(container.read(interpreterResultProvider)?.translation, 'Bonjour');
    });

    test('clear sets state to null', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final r =
          InterpreterResult(translation: 'Bonjour', timestamp: DateTime.now());
      container.read(interpreterResultProvider.notifier).update(r);
      container.read(interpreterResultProvider.notifier).clear();
      expect(container.read(interpreterResultProvider), isNull);
    });
  });

  // ── InterpreterSettingsNotifier ──────────────────────────────────────────
  group('InterpreterSettingsNotifier', () {
    test('update() changes state', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container
          .read(interpreterSettingsProvider.notifier)
          .update(const InterpreterSettings(
            enabled: true,
            direction: InterpreterDirection.englishToTarget,
            targetLanguage: 'German',
          ));
      final s = container.read(interpreterSettingsProvider);
      expect(s.enabled, isTrue);
      expect(s.direction, InterpreterDirection.englishToTarget);
      expect(s.targetLanguage, 'German');
    });
  });

  // ── AudioRouteState ──────────────────────────────────────────────────────
  group('AudioRouteState', () {
    test('earbudActive false when selected is null', () {
      expect(AudioRouteState.empty.earbudActive, isFalse);
    });

    test('earbudActive false when selected is phone', () {
      const device = AudioRouteDevice(
          id: '1', name: 'Phone', type: AudioDeviceType.phone);
      const s = AudioRouteState(available: [device], selected: device);
      expect(s.earbudActive, isFalse);
    });

    test('earbudActive true when selected Bluetooth', () {
      const device = AudioRouteDevice(
          id: '2', name: 'AirPods', type: AudioDeviceType.bluetooth);
      const s = AudioRouteState(available: [device], selected: device);
      expect(s.earbudActive, isTrue);
    });

    test('earbudAvailable false when empty', () {
      expect(AudioRouteState.empty.earbudAvailable, isFalse);
    });

    test('earbudAvailable true when Bluetooth device present', () {
      const device = AudioRouteDevice(
          id: '3', name: 'BT Headset', type: AudioDeviceType.bluetooth);
      const s = AudioRouteState(available: [device]);
      expect(s.earbudAvailable, isTrue);
    });

    test('earbudAvailable false when only wired headset present', () {
      const device = AudioRouteDevice(
          id: '4', name: 'Wired', type: AudioDeviceType.wiredHeadset);
      const s = AudioRouteState(available: [device]);
      expect(s.earbudAvailable, isFalse);
    });
  });

  // ── AudioDeviceType display ──────────────────────────────────────────────
  group('AudioDeviceType', () {
    test('all types have a displayName', () {
      for (final t in AudioDeviceType.values) {
        expect(t.displayName, isNotEmpty);
      }
    });

    test('all types have an icon', () {
      for (final t in AudioDeviceType.values) {
        expect(t.icon, isNotEmpty);
      }
    });
  });
}

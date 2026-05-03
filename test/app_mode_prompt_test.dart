import 'package:flutter_test/flutter_test.dart';
import 'package:noa/models/app_mode.dart';

/// Tests that [AppMode.systemPromptSuffix] values are correct and that
/// [getTunePrompt]-style concatenation works as expected.
///
/// We test the mode suffix values directly rather than instantiating
/// AppLogicModel (which has BLE platform-channel dependencies).
void main() {
  group('AppMode.systemPromptSuffix', () {
    test('standard mode has empty suffix', () {
      expect(AppMode.standard.systemPromptSuffix, isEmpty);
    });

    test('non-standard modes have non-empty suffixes', () {
      for (final mode in AppMode.values) {
        if (mode == AppMode.standard) continue;
        expect(
          mode.systemPromptSuffix.isNotEmpty,
          isTrue,
          reason: '${mode.name} must have a non-empty suffix',
        );
      }
    });

    test('productivity suffix mentions actionable answers', () {
      expect(
        AppMode.productivity.systemPromptSuffix.toLowerCase(),
        contains('actionable'),
      );
    });

    test('focus suffix is shorter than productivity suffix', () {
      // Focus mode should be terse
      expect(
        AppMode.focus.systemPromptSuffix.length,
        lessThan(AppMode.productivity.systemPromptSuffix.length),
      );
    });

    test('vision suffix mentions visual', () {
      expect(
        AppMode.vision.systemPromptSuffix.toLowerCase(),
        contains('visual'),
      );
    });

    test('meeting suffix is present and non-empty', () {
      expect(AppMode.meeting.systemPromptSuffix.isNotEmpty, isTrue);
    });
  });

  group('Prompt construction with mode suffix', () {
    // Simulate what getTunePrompt() does: base prompt + length clause + suffix
    String buildPrompt({
      String base = '',
      String lengthClause = 'Limit responses to 1 to 2 sentences. ',
      AppMode mode = AppMode.standard,
    }) {
      String prompt = '';
      if (base.isNotEmpty) prompt += '$base. ';
      prompt += lengthClause;
      final suffix = mode.systemPromptSuffix;
      if (suffix.isNotEmpty) prompt += suffix.trim();
      return prompt;
    }

    test('standard mode adds no suffix to prompt', () {
      final p = buildPrompt(base: 'Be helpful', mode: AppMode.standard);
      expect(p, 'Be helpful. Limit responses to 1 to 2 sentences. ');
    });

    test('productivity mode appends suffix to base prompt', () {
      final p = buildPrompt(base: 'Be helpful', mode: AppMode.productivity);
      expect(p, contains('Be helpful'));
      expect(p, contains(AppMode.productivity.systemPromptSuffix.trim()));
    });

    test('focus mode prompt is shorter than productivity mode prompt', () {
      final focus = buildPrompt(mode: AppMode.focus);
      final prod = buildPrompt(mode: AppMode.productivity);
      expect(focus.length, lessThan(prod.length));
    });

    test('empty base prompt still produces valid prompt with suffix', () {
      final p = buildPrompt(mode: AppMode.vision);
      expect(p.isNotEmpty, isTrue);
      expect(p, contains(AppMode.vision.systemPromptSuffix.trim()));
    });

    test('all modes produce unique prompts (suffixes differ)', () {
      final prompts = AppMode.values
          .map((m) => buildPrompt(mode: m))
          .toList();
      // No two modes should produce exactly the same prompt
      final unique = prompts.toSet();
      expect(unique.length, AppMode.values.length);
    });
  });

  group('AppMode displayName', () {
    test('all modes have non-empty displayName', () {
      for (final mode in AppMode.values) {
        expect(mode.displayName.isNotEmpty, isTrue);
      }
    });

    test('standard displayName is "Standard"', () {
      expect(AppMode.standard.displayName, 'Standard');
    });
  });

  group('AppMode icon', () {
    test('all modes have non-empty icon', () {
      for (final mode in AppMode.values) {
        expect(mode.icon.isNotEmpty, isTrue);
      }
    });
  });
}

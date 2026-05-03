/// AppMode controls both the default persona and the Frame HUD layout.
enum AppMode {
  standard,
  productivity,
  vision,
  meeting,
  focus,
}

extension AppModeExtension on AppMode {
  String get displayName {
    switch (this) {
      case AppMode.standard:
        return 'Standard';
      case AppMode.productivity:
        return 'Productivity';
      case AppMode.vision:
        return 'Vision';
      case AppMode.meeting:
        return 'Meeting';
      case AppMode.focus:
        return 'Focus';
    }
  }

  String get icon {
    switch (this) {
      case AppMode.standard:
        return '⬡';
      case AppMode.productivity:
        return '✓';
      case AppMode.vision:
        return '◎';
      case AppMode.meeting:
        return '◈';
      case AppMode.focus:
        return '◆';
    }
  }

  String get systemPromptSuffix {
    switch (this) {
      case AppMode.standard:
        return '';
      case AppMode.productivity:
        return ' Prioritize actionable, concise answers. When a reminder or task is mentioned, confirm it was saved.';
      case AppMode.vision:
        return ' Describe visual scenes and text clearly. Focus on what the user can see through their glasses.';
      case AppMode.meeting:
        return ' Give brief, meeting-appropriate answers. Avoid distracting information.';
      case AppMode.focus:
        return ' Give only the most essential answer. No follow-up suggestions.';
    }
  }
}

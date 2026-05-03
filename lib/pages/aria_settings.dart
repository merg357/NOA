import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:noa/models/app_logic_model.dart' as app;
import 'package:noa/models/app_mode.dart';
import 'package:noa/models/gemini_live_config.dart';
import 'package:noa/models/productivity_model.dart';
import 'package:noa/models/voice_config.dart';
import 'package:noa/services/window_service.dart';
import 'package:noa/style.dart';
import 'package:noa/widgets/bottom_nav_bar.dart';
import 'package:noa/widgets/top_title_bar.dart';

/// Extended settings page — covers ARIA-specific settings
/// (persona, mode, Frame diagnostics) without removing Tune page settings.
class AriaSettingsPage extends ConsumerStatefulWidget {
  const AriaSettingsPage({super.key});

  @override
  ConsumerState<AriaSettingsPage> createState() => _AriaSettingsPageState();
}

class _AriaSettingsPageState extends ConsumerState<AriaSettingsPage> {
  late final TextEditingController _personaController;
  // Desktop window settings — loaded once in initState.
  bool _alwaysOnTop = false;
  bool _borderless = false;

  @override
  void initState() {
    super.initState();
    final current = ref.read(app.model).tunePrompt;
    _personaController = TextEditingController(text: current);
    if (Platform.isWindows) _loadWindowPrefs();
  }

  Future<void> _loadWindowPrefs() async {
    final aot = await WindowService.getAlwaysOnTop();
    final bl = await WindowService.getBorderless();
    if (mounted) setState(() { _alwaysOnTop = aot; _borderless = bl; });
  }

  @override
  void dispose() {
    _personaController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appModel = ref.watch(app.model);
    final mode = ref.watch(appModeProvider);
    final productivity = ref.watch(productivityProvider);
    final voiceConfig = ref.watch(voiceConfigProvider);
    final geminiConfig = ref.watch(geminiLiveConfigProvider);
    final session = ref.watch(conversationSessionProvider);

    return Scaffold(
      backgroundColor: colorDark,
      appBar: topTitleBar(context, 'SETTINGS', false, true),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
        children: [
          // ── App mode ────────────────────────────────────────────────────
          _sectionHeader('App Mode'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: AppMode.values
                .map((m) => _ModeChip(
                      mode: m,
                      selected: m == mode,
                      onTap: () =>
                          ref.read(appModeProvider.notifier).setMode(m),
                    ))
                .toList(),
          ),
          const SizedBox(height: 24),

          // ── Persona / system prompt ──────────────────────────────────────
          _sectionHeader('Persona (system prompt)'),
          const SizedBox(height: 8),
          _textArea(
            controller: _personaController,
            hint: 'You are ARIA, a smart wearable AI assistant…',
            onChanged: (v) => appModel.tunePrompt = v,
          ),
          const SizedBox(height: 24),

          // ── Frame status ─────────────────────────────────────────────────
          _sectionHeader('Frame Status'),
          const SizedBox(height: 8),
          _StatusRow(
            label: 'Connection',
            value: _connectionLabel(appModel.state.current),
            good: appModel.state.current == app.State.connected,
          ),
          _StatusRow(
            label: 'Frame state',
            value: appModel.frameState.name,
          ),
          _StatusRow(
            label: 'Device',
            value: appModel.deviceName,
          ),
          const SizedBox(height: 24),

          // ── Productivity stats ────────────────────────────────────────────
          _sectionHeader('Productivity Stats'),
          const SizedBox(height: 8),
          _StatusRow(
            label: 'Pending reminders',
            value: '${productivity.pendingReminders.length}',
          ),
          _StatusRow(
            label: 'Notes saved',
            value: '${productivity.notes.length}',
          ),
          _StatusRow(
            label: 'Memory facts',
            value: '${productivity.facts.length}',
          ),
          const SizedBox(height: 16),
          _dangerButton(
            label: 'Clear all reminders',
            onTap: () async {
              for (final r in productivity.reminders.toList()) {
                await productivity.deleteReminder(r.id);
              }
            },
          ),
          const SizedBox(height: 8),
          _dangerButton(
            label: 'Clear all memory facts',
            onTap: () async {
              for (final f in productivity.facts.toList()) {
                await productivity.deleteFact(f.id);
              }
            },
          ),
          const SizedBox(height: 24),

          // ── Tune / server settings link ───────────────────────────────────
          _sectionHeader('AI Backend'),
          const SizedBox(height: 8),
          Text(
            'API endpoint, token and response length are\nconfigured in the HACK tab.',
            style: textStyleLight,
          ),
          const SizedBox(height: 4),
          Text(
            'Custom server: ${appModel.customServer ? "enabled" : "disabled"}',
            style: textStyleLight,
          ),
          if (appModel.customServer && appModel.apiEndpoint.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Endpoint: ${appModel.apiEndpoint}',
                style: textStyleLight.copyWith(fontSize: 12),
              ),
            ),
          const SizedBox(height: 24),

          // ── Gemini Live ───────────────────────────────────────────────────
          _sectionHeader('Gemini Live'),
          const SizedBox(height: 8),
          _ToggleRow(
            label: 'Enable Gemini Live (replaces STT/TTS)',
            value: geminiConfig.enabled,
            onChanged: (v) => ref
                .read(geminiLiveConfigProvider.notifier)
                .update(geminiConfig.copyWith(enabled: v)),
          ),
          const SizedBox(height: 8),
          _StatusRow(
            label: 'API key',
            value: geminiConfig.effectiveApiKey.isNotEmpty
                ? '✓ set via .env'
                : '✗ not set — add GEMINI_API_KEY to .env',
            good: geminiConfig.effectiveApiKey.isNotEmpty,
          ),
          _StatusRow(label: 'Model', value: geminiConfig.model),
          _StatusRow(label: 'Voice', value: geminiConfig.voiceName),
          if (geminiConfig.ephemeralTokenUrl.isNotEmpty)
            _StatusRow(
              label: 'Ephemeral URL',
              value: geminiConfig.ephemeralTokenUrl,
            ),
          const SizedBox(height: 6),
          Text(
            geminiConfig.enabled
                ? 'Tap mic to start / stop a live session.\n'
                    'Audio: 16 kHz PCM in → 24 kHz PCM out.\n'
                    'Session holds context across turns.'
                : 'When enabled, one tap starts a stateful live\n'
                    'session — no PTT required.',
            style: textStyleLight.copyWith(fontSize: 11),
          ),
          const SizedBox(height: 24),

          // ── Voice settings (STT/TTS fallback) ─────────────────────────────
          _sectionHeader(
            geminiConfig.enabled
                ? 'Voice Settings (fallback — Gemini Live is active)'
                : 'Voice Settings',
          ),
          const SizedBox(height: 8),
          _ToggleRow(
            label: 'Enable mic (STT)',
            value: voiceConfig.enableStt,
            onChanged: (v) => ref
                .read(voiceConfigProvider.notifier)
                .update(voiceConfig.copyWith(enableStt: v)),
          ),
          _ToggleRow(
            label: 'Enable TTS playback',
            value: voiceConfig.enableTts,
            onChanged: (v) => ref
                .read(voiceConfigProvider.notifier)
                .update(voiceConfig.copyWith(enableTts: v)),
          ),
          _ToggleRow(
            label: 'Mock / demo mode',
            value: voiceConfig.mockMode,
            onChanged: (v) => ref
                .read(voiceConfigProvider.notifier)
                .update(voiceConfig.copyWith(mockMode: v)),
          ),
          const SizedBox(height: 8),
          _StatusRow(
            label: 'STT provider',
            value: voiceConfig.effectiveSttProvider,
          ),
          _StatusRow(
            label: 'TTS provider',
            value: voiceConfig.effectiveTtsProvider,
          ),
          _StatusRow(
            label: 'TTS voice',
            value: voiceConfig.ttsVoice,
          ),
          _StatusRow(
            label: 'Persona style',
            value: voiceConfig.assistantPersona,
          ),
          const SizedBox(height: 12),

          // ── Conversation session ─────────────────────────────────────────
          _sectionHeader('Conversation Session'),
          const SizedBox(height: 8),
          _StatusRow(
            label: 'Turns in memory',
            value: '${session.turnCount}',
          ),
          const SizedBox(height: 8),
          _dangerButton(
            label: 'Clear conversation history',
            onTap: () => session.clearConversation(),
          ),
          const SizedBox(height: 24),

          // ── Desktop window settings (Windows only) ───────────────────────
          if (Platform.isWindows) ...[
            _sectionHeader('Desktop Window'),
            const SizedBox(height: 8),
            _ToggleRow(
              label: 'Always on top',
              value: _alwaysOnTop,
              onChanged: (v) async {
                await WindowService.setAlwaysOnTop(v);
                if (mounted) setState(() => _alwaysOnTop = v);
              },
            ),
            _ToggleRow(
              label: 'Borderless / compact mode',
              value: _borderless,
              onChanged: (v) async {
                await WindowService.setBorderless(v);
                if (mounted) setState(() => _borderless = v);
              },
            ),
            const SizedBox(height: 6),
            Text(
              'Window size and position are saved automatically.',
              style: textStyleLight.copyWith(fontSize: 11),
            ),
            const SizedBox(height: 24),
          ],
        ],
      ),
      bottomNavigationBar: bottomNavBar(context, 3, true),
    );
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  Widget _sectionHeader(String title) => Text(title, style: textStyleLightSubHeading);

  Widget _textArea({
    required TextEditingController controller,
    required String hint,
    ValueChanged<String>? onChanged,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: colorLight,
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 6),
      child: TextFormField(
        controller: controller,
        minLines: 4,
        maxLines: null,
        onChanged: onChanged,
        onTapOutside: (_) => FocusScope.of(context).unfocus(),
        style: textStyleDark,
        decoration: InputDecoration.collapsed(
          hintText: hint,
          hintStyle: textStyleDark.copyWith(color: colorDark.withOpacity(0.5)),
          fillColor: colorLight,
          filled: true,
        ),
      ),
    );
  }

  Widget _dangerButton({
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
        decoration: BoxDecoration(
          color: colorRed.withOpacity(0.15),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: colorRed.withOpacity(0.4)),
        ),
        child: Text(label, style: textStyleRed),
      ),
    );
  }

  String _connectionLabel(app.State s) {
    switch (s) {
      case app.State.connected:
        return 'Connected';
      case app.State.disconnected:
        return 'Disconnected';
      case app.State.scanning:
        return 'Scanning…';
      default:
        return s.name;
    }
  }
}

// ── Sub-widgets ────────────────────────────────────────────────────────────

class _ModeChip extends StatelessWidget {
  final AppMode mode;
  final bool selected;
  final VoidCallback onTap;

  const _ModeChip({
    required this.mode,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? colorLight : colorLight.withOpacity(0.2),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? colorWhite : colorLight.withOpacity(0.4),
          ),
        ),
        child: Text(
          '${mode.icon}  ${mode.displayName}',
          style: selected
              ? textStyleDark.copyWith(fontWeight: FontWeight.w700)
              : textStyleLight,
        ),
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  final String label;
  final String value;
  final bool? good; // null = neutral, true = green, false = red

  const _StatusRow({required this.label, required this.value, this.good});

  @override
  Widget build(BuildContext context) {
    Color valueColor = colorLight;
    if (good == true) valueColor = const Color(0xFF4CAF50);
    if (good == false) valueColor = colorRed;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(child: Text(label, style: textStyleLight)),
          Text(value, style: textStyleLight.copyWith(color: valueColor)),
        ],
      ),
    );
  }
}

/// A labeled toggle row for boolean voice settings.
class _ToggleRow extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _ToggleRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Expanded(child: Text(label, style: textStyleLight)),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: colorWhite,
            activeTrackColor: colorLight,
          ),
        ],
      ),
    );
  }
}

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:noa/models/app_logic_model.dart' as app;
import 'package:noa/models/app_mode.dart';
import 'package:noa/models/audio_route_state.dart';
import 'package:noa/models/gemini_live_config.dart';
import 'package:noa/models/interpreter_settings.dart';
import 'package:noa/models/productivity_model.dart';
import 'package:noa/models/voice_config.dart';
import 'package:noa/services/audio_route_service.dart';
import 'package:noa/services/vps_service.dart';
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
  late final TextEditingController _vpsBaseUrlController;
  late final TextEditingController _vpsWsUrlController;
  late final TextEditingController _vpsTokenController;
  // Desktop window settings — loaded once in initState.
  bool _alwaysOnTop = false;
  bool _borderless = false;
  // Subscription to update controllers once the async SharedPreferences load
  // completes (VpsConfigNotifier._load is async, so initState sees empty defaults).
  ProviderSubscription<VpsConfig>? _vpsConfigSub;

  @override
  void initState() {
    super.initState();
    final current = ref.read(app.model).tunePrompt;
    _personaController = TextEditingController(text: current);
    // Initialise with whatever is already loaded (may still be empty defaults).
    final vpsCfg = ref.read(vpsConfigProvider);
    _vpsBaseUrlController = TextEditingController(text: vpsCfg.baseUrl);
    _vpsWsUrlController = TextEditingController(text: vpsCfg.wsUrl);
    _vpsTokenController = TextEditingController(text: vpsCfg.bearerToken);
    // When the async _load() completes the provider notifies; populate any
    // controllers that were still empty at initState time.
    _vpsConfigSub = ref.listenManual<VpsConfig>(vpsConfigProvider, (prev, next) {
      if (_vpsBaseUrlController.text.isEmpty && next.baseUrl.isNotEmpty) {
        _vpsBaseUrlController.text = next.baseUrl;
      }
      if (_vpsWsUrlController.text.isEmpty && next.wsUrl.isNotEmpty) {
        _vpsWsUrlController.text = next.wsUrl;
      }
      if (_vpsTokenController.text.isEmpty && next.bearerToken.isNotEmpty) {
        _vpsTokenController.text = next.bearerToken;
      }
    });
    if (Platform.isWindows) _loadWindowPrefs();
  }

  Future<void> _loadWindowPrefs() async {
    final aot = await WindowService.getAlwaysOnTop();
    final bl = await WindowService.getBorderless();
    if (mounted) setState(() { _alwaysOnTop = aot; _borderless = bl; });
  }

  @override
  void dispose() {
    _vpsConfigSub?.close();
    _personaController.dispose();
    _vpsBaseUrlController.dispose();
    _vpsWsUrlController.dispose();
    _vpsTokenController.dispose();
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
    final vpsConfig = ref.watch(vpsConfigProvider);
    final vpsService = ref.watch(vpsServiceProvider);
    final interpSettings = ref.watch(interpreterSettingsProvider);
    final audioRoute = ref.watch(audioRouteServiceProvider);

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

          // ── Interpreter Mode ──────────────────────────────────────────────
          _sectionHeader('Interpreter Mode'),
          const SizedBox(height: 8),
          _ToggleRow(
            label: 'Enable Interpreter Mode',
            value: interpSettings.enabled,
            onChanged: (v) => ref
                .read(interpreterSettingsProvider.notifier)
                .update(interpSettings.copyWith(enabled: v)),
          ),
          if (interpSettings.enabled) ...[
            const SizedBox(height: 6),
            Text('Direction', style: textStyleLight.copyWith(fontSize: 12)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: InterpreterDirection.values.map((d) {
                final selected = interpSettings.direction == d;
                return GestureDetector(
                  onTap: () => ref
                      .read(interpreterSettingsProvider.notifier)
                      .update(interpSettings.copyWith(direction: d)),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: selected
                          ? colorLight
                          : colorLight.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: selected
                              ? colorWhite
                              : colorLight.withOpacity(0.4)),
                    ),
                    child: Text(
                      d.displayName,
                      style: selected
                          ? textStyleDark.copyWith(
                              fontWeight: FontWeight.w700)
                          : textStyleLight,
                    ),
                  ),
                );
              }).toList(),
            ),
            if (interpSettings.direction !=
                InterpreterDirection.autoToEnglish) ...[
              const SizedBox(height: 10),
              Text('Target language',
                  style: textStyleLight.copyWith(fontSize: 12)),
              const SizedBox(height: 6),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: colorLight.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: colorLight.withOpacity(0.4)),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: interpSettings.targetLanguage,
                    dropdownColor: colorDark,
                    style: textStyleLight,
                    iconEnabledColor: colorLight,
                    isExpanded: true,
                    items: InterpreterSettings.supportedLanguages
                        .map((lang) => DropdownMenuItem(
                              value: lang,
                              child: Text(lang, style: textStyleLight),
                            ))
                        .toList(),
                    onChanged: (lang) {
                      if (lang == null) return;
                      ref
                          .read(interpreterSettingsProvider.notifier)
                          .update(interpSettings.copyWith(
                              targetLanguage: lang));
                    },
                  ),
                ),
              ),
            ],
            const SizedBox(height: 6),
            _ToggleRow(
              label: 'Auto-speak translation',
              value: interpSettings.autoSpeak,
              onChanged: (v) => ref
                  .read(interpreterSettingsProvider.notifier)
                  .update(interpSettings.copyWith(autoSpeak: v)),
            ),
            _ToggleRow(
              label: 'Show pronunciation guide',
              value: interpSettings.showPronunciation,
              onChanged: (v) => ref
                  .read(interpreterSettingsProvider.notifier)
                  .update(interpSettings.copyWith(showPronunciation: v)),
            ),
            const SizedBox(height: 4),
            Text(
              interpSettings.direction == InterpreterDirection.autoToEnglish
                  ? 'Start session → speak in any language → see English translation.'
                  : interpSettings.direction ==
                          InterpreterDirection.englishToTarget
                      ? 'Start session → speak English → see ${interpSettings.targetLanguage} translation.'
                      : 'Start session → speak either language → auto-translates.',
              style: textStyleLight.copyWith(fontSize: 11),
            ),
          ],
          const SizedBox(height: 24),

          // ── Earbud Mode ───────────────────────────────────────────────────
          _sectionHeader('Earbud Mode'),
          const SizedBox(height: 8),
          _ToggleRow(
            label: 'Enable Earbud Mode',
            value: interpSettings.earbudMode,
            onChanged: (v) async {
              ref
                  .read(interpreterSettingsProvider.notifier)
                  .update(interpSettings.copyWith(earbudMode: v));
              final svc = ref.read(audioRouteServiceProvider);
              if (v) {
                await svc.selectEarbudIfAvailable();
              } else {
                await svc.clearDevice();
              }
            },
          ),
          const SizedBox(height: 6),
          Row(children: [
            _actionButton(
              label: 'Refresh devices',
              onTap: () =>
                  ref.read(audioRouteServiceProvider).refresh(),
            ),
          ]),
          const SizedBox(height: 6),
          _StatusRow(
            label: 'Active route',
            value: audioRoute.state.selected?.name ??
                'System default',
            good: audioRoute.state.earbudActive,
          ),
          _StatusRow(
            label: 'Bluetooth available',
            value: audioRoute.state.earbudAvailable ? '✓' : '✗',
            good: audioRoute.state.earbudAvailable,
          ),
          if (audioRoute.state.available.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('Available devices:',
                style: textStyleLight.copyWith(fontSize: 11)),
            ...audioRoute.state.available.map((d) => Padding(
                  padding: const EdgeInsets.only(left: 8, top: 2),
                  child: Text('${d.type.icon} ${d.name}',
                      style: textStyleLight.copyWith(fontSize: 11)),
                )),
          ],
          if (!Platform.isAndroid) ...[
            const SizedBox(height: 4),
            Text(
              'Earbud mode audio routing requires a real Android device.',
              style: textStyleLight.copyWith(
                  fontSize: 10, color: colorLight.withOpacity(0.6)),
            ),
          ],
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

          // ── VPS backend ───────────────────────────────────────────────────
          _sectionHeader('VPS Backend'),
          const SizedBox(height: 8),
          _ToggleRow(
            label: 'Enable VPS connection',
            value: vpsConfig.enabled,
            onChanged: (v) {
              final updated = vpsConfig.copyWith(enabled: v);
              ref.read(vpsConfigProvider.notifier).update(updated);
              if (v && updated.isConfigured) {
                ref.read(vpsServiceProvider).connect(
                  updated,
                  onCardReceived: (card) =>
                      appModel.sendWearableCardToFrame(card),
                  onBannerReceived: (msg) =>
                      appModel.sendStatusBannerToFrame(msg),
                );
              } else if (!v) {
                ref.read(vpsServiceProvider).disconnect();
              }
            },
          ),
          const SizedBox(height: 8),
          _StatusRow(
            label: 'Connection',
            value: _vpsStateLabel(vpsService.connectionState),
            good: vpsService.connectionState == VpsConnectionState.connected,
          ),
          _StatusRow(
            label: 'Device ID',
            value: vpsConfig.deviceId.isNotEmpty
                ? vpsConfig.deviceId.substring(0, 8) + '…'
                : 'auto',
          ),
          const SizedBox(height: 8),
          _inputField(
            controller: _vpsBaseUrlController,
            label: 'REST URL (e.g. http://1.2.3.4:8765)',
            onSubmitted: (v) {
              final updated = vpsConfig.copyWith(baseUrl: v.trim());
              ref.read(vpsConfigProvider.notifier).update(updated);
            },
          ),
          const SizedBox(height: 6),
          _inputField(
            controller: _vpsWsUrlController,
            label: 'WebSocket URL (e.g. ws://1.2.3.4:8765/ws)',
            onSubmitted: (v) {
              final updated = vpsConfig.copyWith(wsUrl: v.trim());
              ref.read(vpsConfigProvider.notifier).update(updated);
            },
          ),
          const SizedBox(height: 6),
          _inputField(
            controller: _vpsTokenController,
            label: 'Bearer token',
            obscure: true,
            onSubmitted: (v) {
              final updated = vpsConfig.copyWith(bearerToken: v.trim());
              ref.read(vpsConfigProvider.notifier).update(updated);
            },
          ),
          const SizedBox(height: 8),
          Row(children: [
            _actionButton(
              label: 'Connect',
              onTap: () {
                final updated = vpsConfig.copyWith(
                  baseUrl: _vpsBaseUrlController.text.trim(),
                  wsUrl: _vpsWsUrlController.text.trim(),
                  bearerToken: _vpsTokenController.text.trim(),
                  enabled: true,
                );
                ref.read(vpsConfigProvider.notifier).update(updated);
                ref.read(vpsServiceProvider).connect(
                  updated,
                  onCardReceived: (card) =>
                      appModel.sendWearableCardToFrame(card),
                  onBannerReceived: (msg) =>
                      appModel.sendStatusBannerToFrame(msg),
                );
              },
            ),
            const SizedBox(width: 8),
            _actionButton(
              label: 'Ping Hermes',
              onTap: () =>
                  ref.read(vpsServiceProvider).triggerHermesTask('ping'),
            ),
            const SizedBox(width: 8),
            _actionButton(
              label: 'Daily Brief',
              onTap: () => ref
                  .read(vpsServiceProvider)
                  .triggerHermesTask('daily_brief'),
            ),
            const SizedBox(width: 8),
            _actionButton(
              label: 'Test Card',
              onTap: () => ref
                  .read(vpsServiceProvider)
                  .triggerHermesTask('test_card'),
            ),
          ]),
          if (vpsService.lastHermesResultText != null) ...[
            const SizedBox(height: 6),
            _StatusRow(
              label: 'Last result',
              value: vpsService.lastHermesResultText!,
              good: vpsService.lastHermesResultText!.contains('✓'),
            ),
          ],
          if (vpsService.errorMessage != null &&
              vpsService.connectionState == VpsConnectionState.error) ...[
            const SizedBox(height: 6),
            _StatusRow(
              label: 'Error',
              value: vpsService.errorMessage!,
              good: false,
            ),
          ],
          const SizedBox(height: 24),

          // ── Desktop window settings (Windows only) ───────────────────────
          if (Platform.isWindows) ...[            _sectionHeader('Desktop Window'),
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

  Widget _inputField({
    required TextEditingController controller,
    required String label,
    bool obscure = false,
    ValueChanged<String>? onSubmitted,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: colorLight,
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      child: TextFormField(
        controller: controller,
        obscureText: obscure,
        onFieldSubmitted: onSubmitted,
        onTapOutside: (_) {
          onSubmitted?.call(controller.text);
          FocusScope.of(context).unfocus();
        },
        style: textStyleDark.copyWith(fontSize: 13),
        decoration: InputDecoration.collapsed(
          hintText: label,
          hintStyle: textStyleDark.copyWith(
              color: colorDark.withOpacity(0.5), fontSize: 13),
        ),
      ),
    );
  }

  Widget _actionButton({
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        decoration: BoxDecoration(
          color: colorLight.withOpacity(0.3),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: colorLight.withOpacity(0.5)),
        ),
        child: Text(label, style: textStyleLight.copyWith(fontSize: 12)),
      ),
    );
  }

  String _vpsStateLabel(VpsConnectionState s) {
    switch (s) {
      case VpsConnectionState.connected:
        return 'Connected';
      case VpsConnectionState.connecting:
        return 'Connecting…';
      case VpsConnectionState.error:
        return 'Error';
      case VpsConnectionState.disconnected:
        return 'Disconnected';
    }
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

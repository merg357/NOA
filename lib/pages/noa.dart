import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';
import 'package:noa/main.dart';
import 'package:noa/models/app_logic_model.dart' as app;
import 'package:noa/models/app_mode.dart';
import 'package:noa/models/gemini_live_config.dart';
import 'package:noa/models/interpreter_result.dart';
import 'package:noa/models/interpreter_settings.dart';
import 'package:noa/models/productivity_model.dart';
import 'package:noa/models/voice_config.dart';
import 'package:noa/noa_api.dart';
import 'package:noa/pages/pairing.dart';
import 'package:noa/services/gemini_live_service.dart';
import 'package:noa/services/voice_assistant_service.dart';
import 'package:noa/services/vps_service.dart';
import 'package:noa/style.dart';
import 'package:noa/util/desktop_args.dart';
import 'package:noa/util/show_toast.dart';
import 'package:noa/util/switch_page.dart';
import 'package:noa/widgets/bottom_nav_bar.dart';
import 'package:noa/widgets/top_title_bar.dart';
import 'package:saver_gallery/saver_gallery.dart';
import 'package:uuid/uuid.dart';

class NoaPage extends ConsumerStatefulWidget {
  const NoaPage({super.key});

  @override
  ConsumerState<NoaPage> createState() => _NoaPageState();
}

class _NoaPageState extends ConsumerState<NoaPage> {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _cmdController = TextEditingController();
  bool _submitting = false;
  // Subscription for VPS config readiness — closed in dispose().
  ProviderSubscription<VpsConfig>? _vpsConfigSub;

  @override
  void initState() {
    super.initState();
    // On Windows, honour --start-voice-ready by triggering the mic after the
    // first frame is rendered and the voice service is ready.
    if (Platform.isWindows && DesktopArgs.startVoiceReady) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _handleMicTap(),
      );
    }
    // VPS auto-connect: try immediately (covers case where SharedPreferences
    // loaded synchronously) and also listen for when the async _load()
    // completes and the config state transitions from empty → configured.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _tryVpsConnect(ref.read(vpsConfigProvider));
    });
    _vpsConfigSub = ref.listenManual<VpsConfig>(
      vpsConfigProvider,
      (prev, next) {
        if (next.enabled && next.isConfigured) _tryVpsConnect(next);
      },
    );
  }

  void _tryVpsConnect(VpsConfig config) {
    if (!config.enabled || !config.isConfigured) return;
    final svc = ref.read(vpsServiceProvider);
    if (svc.isConnected ||
        svc.connectionState == VpsConnectionState.connecting) {
      return;
    }
    final appModel = ref.read(app.model);
    svc.connect(
      config,
      onCardReceived: (card) => appModel.sendWearableCardToFrame(card),
      onBannerReceived: (msg) => appModel.sendStatusBannerToFrame(msg),
    );
  }

  @override
  void dispose() {
    _vpsConfigSub?.close();
    _scrollController.dispose();
    _cmdController.dispose();
    super.dispose();
  }

  Future<void> _submitCommand(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || _submitting) return;
    _cmdController.clear();
    setState(() => _submitting = true);
    try {
      final router = ref.read(commandRouterProvider);
      final appModel = ref.read(app.model);
      final result = await appModel.processLocalCommand(trimmed, router.route);
      if (!mounted) return;
      if (result == null) {
        showToast('Use Frame tap for voice queries', context);
      } else if (result.data?['mode'] != null) {
        final modeName = result.data!['mode'] as String;
        final mode = AppMode.values.firstWhere(
          (m) => m.name == modeName,
          orElse: () => AppMode.standard,
        );
        await ref.read(appModeProvider.notifier).setMode(mode);
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _handleMicTap() async {
    final geminiConfig = ref.read(geminiLiveConfigProvider);

    // ── Gemini Live path (primary) ──────────────────────────────────────────
    if (geminiConfig.enabled) {
      final gemini = ref.read(geminiLiveProvider);
      if (gemini.liveState == GeminiLiveState.error) {
        gemini.resetError();
        return;
      }
      final appModel = ref.read(app.model);
      final mode = ref.read(appModeProvider);
      final interpSettings = ref.read(interpreterSettingsProvider);
      await gemini.toggleSession(
        config: geminiConfig,
        systemInstruction: appModel.tunePrompt,
        mode: mode,
        onFrameBanner: (msg) => appModel.sendStatusBannerToFrame(msg),
        onFrameCard: (card) => appModel.sendWearableCardToFrame(card),
        onAddToChat: (u, a) => appModel.addVoiceExchangeToChat(u, a),
        interpreterSettings: interpSettings,
        onInterpreterResult: (r) =>
            ref.read(interpreterResultProvider.notifier).update(r),
      );
      return;
    }

    // ── Fallback: chained STT → assistant → TTS ───────────────────────────
    final voice = ref.read(voiceAssistantProvider);
    final config = ref.read(voiceConfigProvider);

    if (!config.enableStt) {
      if (mounted) showToast('STT is disabled in settings', context);
      return;
    }

    if (voice.voiceState == VoiceLoopState.error) {
      voice.resetError();
      return;
    }

    if (voice.isListening) {
      // Stop and process
      final appModel = ref.read(app.model);
      final router = ref.read(commandRouterProvider);
      final result = await voice.stopAndProcess(
        appModel: appModel,
        router: router.route,
      );
      // Bug G fix: mode-switch commands return data['mode'] — apply it.
      if (result?.data?['mode'] != null && mounted) {
        final modeName = result!.data!['mode'] as String;
        final mode = AppMode.values.firstWhere(
          (m) => m.name == modeName,
          orElse: () => AppMode.standard,
        );
        await ref.read(appModeProvider.notifier).setMode(mode);
      }
    } else if (!voice.isBusy) {
      // Start listening
      final ok = await voice.startListening();
      if (!ok && mounted) {
        showToast(voice.errorMessage ?? 'Cannot access microphone', context);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Bug D fix: watch (not just listen) so setAppMode is called on every
    // rebuild including the first one, before any user action fires the listener.
    // setAppMode has no side effects so calling it in build() is safe.
    ref.read(app.model).setAppMode(ref.watch(appModeProvider));

    // Determine active voice state from whichever service is the primary path.
    final useGemini = ref.watch(geminiLiveConfigProvider).enabled;
    final interpSettings = ref.watch(interpreterSettingsProvider);
    final interpResult = ref.watch(interpreterResultProvider);
    final VoiceLoopState voiceState;
    final String? voiceError;
    if (useGemini) {
      final gs = ref.watch(geminiLiveProvider);
      voiceState = gs.voiceLoopState;
      voiceError = gs.errorMessage;
    } else {
      voiceState = ref.watch(voiceAssistantProvider).voiceState;
      voiceError = ref.watch(voiceAssistantProvider).errorMessage;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      switch (ref.watch(app.model).state.current) {
        case app.State.stopLuaApp:
        case app.State.checkFirmwareVersion:
        case app.State.uploadMainLua:
        case app.State.uploadGraphicsLua:
        case app.State.uploadStateLua:
        case app.State.triggerUpdate:
        case app.State.updateFirmware:
          switchPage(context, const PairingPage());
          break;
        default:
      }
      Timer(const Duration(milliseconds: 100), () {
        if (context.mounted) {
          ref.watch(app.model.select((value) {
            if (value.noaMessages.length > 6) {
              _scrollController.animateTo(
                _scrollController.position.maxScrollExtent,
                duration: const Duration(milliseconds: 100),
                curve: Curves.easeOut,
              );
            }
          }));
        }
      });
    });

    return Scaffold(
      backgroundColor: colorWhite,
      appBar: topTitleBar(context, 'CHAT', false, false),
      body: Column(
        children: [
          Expanded(
            child: PageStorage(
              bucket: globalPageStorageBucket,
              child: ListView.builder(
                key: const PageStorageKey<String>('noaPage'),
                controller: _scrollController,
                itemCount: ref.watch(app.model).noaMessages.length,
          itemBuilder: (context, index) {
            TextStyle style = textStyleLight;
            if (ref.watch(app.model).noaMessages[index].from == NoaRole.noa) {
              style = textStyleDark;
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (index == 0 ||
                    ref
                            .watch(app.model)
                            .noaMessages[index]
                            .time
                            .difference(ref
                                .watch(app.model)
                                .noaMessages[index - 1]
                                .time)
                            .inSeconds >
                        1700)
                  Container(
                    margin: const EdgeInsets.only(top: 40, left: 42, right: 42),
                    child: Row(
                      children: [
                        Text(
                          "${ref.watch(app.model).noaMessages[index].time.hour.toString().padLeft(2, '0')}:${ref.watch(app.model).noaMessages[index].time.minute.toString().padLeft(2, '0')}",
                          style: const TextStyle(color: colorLight),
                        ),
                        const Flexible(
                          child: Divider(
                            indent: 10,
                            color: colorLight,
                          ),
                        ),
                      ],
                    ),
                  ),
                Container(
                  margin: const EdgeInsets.only(top: 10, left: 65, right: 42),
                  child: Text(
                    ref.watch(app.model).noaMessages[index].message,
                    style: style,
                  ),
                ),
                if (ref.watch(app.model).noaMessages[index].image != null)
                  Container(
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: colorLight,
                        width: 0.5,
                      ),
                      borderRadius: BorderRadius.circular(10.5),
                    ),
                    margin: const EdgeInsets.only(
                        top: 10, bottom: 10, left: 65, right: 65),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: SizedBox.fromSize(
                        child: GestureDetector(
                          onLongPress: () async {
                            if (Platform.isWindows) {
                              // saver_gallery is not available on Windows;
                              // image saving via platform gallery is mobile-only.
                              if (context.mounted) {
                                showToast('Gallery save not supported on PC', context);
                              }
                              return;
                            }
                            await SaverGallery.saveImage(
                                ref.watch(app.model).noaMessages[index].image!,
                                fileName: const Uuid().v1(),
                                skipIfExists: false);
                            if (context.mounted) {
                              showToast("Saved to photos", context);
                            }
                          },
                          child: Image.memory(
                              ref.watch(app.model).noaMessages[index].image!),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
          padding: const EdgeInsets.only(bottom: 20),
        ),
      ),
          ),

          // ── Voice state banner ───────────────────────────────────────────
          if (voiceState != VoiceLoopState.idle)
            _VoiceStateBanner(
              state: voiceState,
              message: voiceState == VoiceLoopState.error ? voiceError : null,
            ),
          // ── Interpreter result panel ──────────────────────────────
          if (interpSettings.enabled && (interpResult != null || voiceState != VoiceLoopState.idle))
            _InterpreterPanel(
              result: interpResult,
              isListening: voiceState == VoiceLoopState.listening,
              settings: interpSettings,
              onSpeak: () {
                final r = interpResult;
                if (r == null) return;
                final gemini = ref.read(geminiLiveProvider);
                if (gemini.isActive) {
                  gemini.sendClientMessage(
                      'Please speak the translation again: ${r.translation}');
                } else {
                  showToast('Start a session to hear translation', context);
                }
              },
              onClear: () =>
                  ref.read(interpreterResultProvider.notifier).clear(),
              onSwapDirection: () {
                final s = ref.read(interpreterSettingsProvider);
                final next = s.direction == InterpreterDirection.autoToEnglish
                    ? InterpreterDirection.englishToTarget
                    : InterpreterDirection.autoToEnglish;
                ref
                    .read(interpreterSettingsProvider.notifier)
                    .update(s.copyWith(direction: next));
              },
            ),
          // ── Input bar ────────────────────────────────────────────────────
          Container(
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: colorLight, width: 0.5)),
              color: colorWhite,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                // Mic button — tap to start/stop listening
                _MicButton(state: voiceState, onTap: _handleMicTap),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _cmdController,
                    style: textStyleDark,
                    decoration: InputDecoration(
                      hintText: 'Type a command…',
                      hintStyle: const TextStyle(color: colorLight),
                      isDense: true,
                      filled: true,
                      fillColor: colorLight,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onSubmitted: _submitCommand,
                    textInputAction: TextInputAction.send,
                  ),
                ),
                const SizedBox(width: 8),
                _submitting
                    ? const SizedBox(
                        width: 24, height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2, color: colorDark))
                    : IconButton(
                        icon: const Icon(Icons.send, color: colorDark),
                        onPressed: () => _submitCommand(_cmdController.text),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: bottomNavBar(context, 0, false),
    );
  }
}

// ── Voice UI sub-widgets ───────────────────────────────────────────────────────

/// Animated mic button that changes appearance based on [VoiceLoopState].
class _MicButton extends StatelessWidget {
  final VoiceLoopState state;
  final VoidCallback onTap;

  const _MicButton({required this.state, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isConnecting = state == VoiceLoopState.connecting;
    final isListening = state == VoiceLoopState.listening;
    final isBusy = state != VoiceLoopState.idle && state != VoiceLoopState.error;
    final isError = state == VoiceLoopState.error;

    Color color;
    IconData icon;
    if (isConnecting) {
      color = colorLight;
      icon = Icons.wifi;
    } else if (isListening) {
      color = Colors.red;
      icon = Icons.stop;
    } else if (isBusy) {
      color = colorLight;
      icon = Icons.mic;
    } else if (isError) {
      color = Colors.orange;
      icon = Icons.mic_off;
    } else {
      color = colorDark;
      icon = Icons.mic;
    }

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: isListening ? Colors.red.withOpacity(0.12) : Colors.transparent,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: color, size: 22),
      ),
    );
  }
}

/// Thin banner below the chat list that shows voice loop state.
class _VoiceStateBanner extends StatelessWidget {  final VoiceLoopState state;
  final String? message;

  const _VoiceStateBanner({required this.state, this.message});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (state) {
      VoiceLoopState.connecting => ('Connecting…', colorDark),
      VoiceLoopState.listening => ('● Listening…', Colors.red),
      VoiceLoopState.transcribing => ('Transcribing…', colorDark),
      VoiceLoopState.thinking => ('Thinking…', colorDark),
      VoiceLoopState.speaking => ('◈ Speaking…', colorDark),
      VoiceLoopState.interrupted => ('Interrupted…', colorDark),
      VoiceLoopState.error => (message ?? 'Error — tap mic to retry', Colors.orange),
      VoiceLoopState.idle => ('', colorDark),
    };

    return Container(
      width: double.infinity,
      color: state == VoiceLoopState.listening
          ? Colors.red.withOpacity(0.06)
          : state == VoiceLoopState.error
              ? Colors.orange.withOpacity(0.08)
              : colorLight.withOpacity(0.15),
      padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 24),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          color: color,
          fontFamily: 'SF Pro Display',
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
}
// ── Interpreter result panel ───────────────────────────────────────────────────

/// Compact panel shown below the voice banner when Interpreter Mode is active.
///
/// Shows the source language, original transcript, translated output,
/// pronunciation guide, and action buttons (swap, copy, speak, clear).
class _InterpreterPanel extends StatelessWidget {
  final InterpreterResult? result;
  final bool isListening;
  final InterpreterSettings settings;
  final VoidCallback onSpeak;
  final VoidCallback onClear;
  final VoidCallback onSwapDirection;

  const _InterpreterPanel({
    required this.result,
    required this.isListening,
    required this.settings,
    required this.onSpeak,
    required this.onClear,
    required this.onSwapDirection,
  });

  @override
  Widget build(BuildContext context) {
    final r = result;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        border: Border(
          top: BorderSide(color: colorLight.withOpacity(0.3)),
          bottom: BorderSide(color: colorLight.withOpacity(0.15)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header bar ────────────────────────────────────────────────
          Container(
            color: colorDark.withOpacity(0.8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(
              children: [
                Text(
                  '🌍 ${settings.direction.displayName}',
                  style: const TextStyle(
                      color: colorLight, fontSize: 11, fontFamily: 'SF Pro Display'),
                ),
                const Spacer(),
                if (isListening)
                  const Text('● interpreting…',
                      style: TextStyle(
                          color: Colors.red,
                          fontSize: 10,
                          fontFamily: 'SF Pro Display'))
                else if (r == null)
                  const Text('tap mic to start',
                      style: TextStyle(
                          color: colorLight,
                          fontSize: 10,
                          fontFamily: 'SF Pro Display')),
              ],
            ),
          ),

          if (r != null) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Source language badge + original
                  if (r.sourceLanguage != null)
                    Text(
                      r.sourceLanguage!.toUpperCase(),
                      style: TextStyle(
                          color: colorLight.withOpacity(0.6),
                          fontSize: 9,
                          letterSpacing: 1.2,
                          fontFamily: 'SF Pro Display'),
                    ),
                  if (r.original != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(
                        r.original!,
                        style: const TextStyle(
                            color: colorLight,
                            fontSize: 12,
                            fontFamily: 'SF Pro Display'),
                      ),
                    ),

                  // Translation (large)
                  Text(
                    r.translation,
                    style: const TextStyle(
                        color: colorWhite,
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'SF Pro Display'),
                  ),

                  // Pronunciation guide
                  if (settings.showPronunciation &&
                      r.pronunciation != null &&
                      r.pronunciation!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(
                        '[${r.pronunciation}]',
                        style: TextStyle(
                            color: colorLight.withOpacity(0.7),
                            fontSize: 11,
                            fontStyle: FontStyle.italic,
                            fontFamily: 'SF Pro Display'),
                      ),
                    ),

                  // Usage note
                  if (r.note != null && r.note!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(
                        r.note!,
                        style: TextStyle(
                            color: colorLight.withOpacity(0.55),
                            fontSize: 10,
                            fontFamily: 'SF Pro Display'),
                      ),
                    ),
                ],
              ),
            ),

            // ── Action buttons ─────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: Row(
                children: [
                  _PanelButton(
                      icon: Icons.swap_horiz,
                      label: 'Swap',
                      onTap: onSwapDirection),
                  _PanelButton(
                    icon: Icons.copy,
                    label: 'Copy',
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: r.translation));
                      showToast('Copied', context);
                    },
                  ),
                  _PanelButton(
                      icon: Icons.volume_up,
                      label: 'Speak',
                      onTap: onSpeak),
                  _PanelButton(
                      icon: Icons.clear,
                      label: 'Clear',
                      onTap: onClear),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PanelButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _PanelButton(
      {required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Column(
          children: [
            Icon(icon, size: 16, color: colorLight),
            const SizedBox(height: 2),
            Text(label,
                style: const TextStyle(
                    color: colorLight, fontSize: 9, fontFamily: 'SF Pro Display')),
          ],
        ),
      ),
    );
  }
}

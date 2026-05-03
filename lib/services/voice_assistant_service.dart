import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:noa/models/app_logic_model.dart';
import 'package:noa/models/app_mode.dart';
import 'package:noa/models/assistant_result.dart';
import 'package:noa/models/conversation_turn.dart';
import 'package:noa/models/voice_config.dart';
import 'package:noa/models/wearable_card.dart';
import 'package:noa/services/assistant_provider.dart';
import 'package:noa/services/audio_playback_service.dart';
import 'package:noa/services/conversation_session_service.dart';
import 'package:noa/services/stt_provider.dart';
import 'package:noa/services/tts_provider.dart';
import 'package:noa/services/voice_controller.dart';

/// States of a single voice turn.
enum VoiceLoopState {
  /// No active recording or processing.
  idle,

  /// Gemini Live: WebSocket is connecting / setup handshake in progress.
  connecting,

  /// Phone mic is recording user speech.
  listening,

  /// Audio captured; waiting for STT transcription.
  transcribing,

  /// Transcript ready; assistant is processing.
  thinking,

  /// Reply ready; TTS is synthesizing / playing.
  speaking,

  /// Gemini Live: model was speaking but user interrupted with new speech.
  interrupted,

  /// A non-fatal error occurred; loop returns to idle on next tap.
  error,
}

/// Connects the push-to-talk recording path to STT, command routing, the
/// assistant, TTS, and Frame output — without touching the existing Frame tap
/// flow in [AppLogicModel].
///
/// # One voice turn
/// 1. User taps mic → [startListening]
/// 2. User taps mic again → [stopAndProcess]
///    a. Stop recording, get audio file path
///    b. Show "Listening…" on Frame (optional)
///    c. Transcribe via [SttProvider]
///    d. Add user turn to [ConversationSessionService]
///    e. Show "Thinking…" on Frame
///    f. Try [AppLogicModel.processLocalCommand] via [CommandRouter]
///    g. If no match, generate a mode-aware mock reply
///    h. Add assistant turn to session
///    i. Send compact [WearableCard] to Frame
///    j. Show "Speaking…" on Frame
///    k. Synthesize reply via [TtsProvider] (if enabled)
///    l. Play audio via [AudioPlaybackService] (if path returned)
///    m. Cleanup temp files → idle
class VoiceAssistantService extends ChangeNotifier {
  final _log = Logger('VoiceAssistantService');

  final VoiceController _voiceController;
  final ConversationSessionService _session;
  final AudioPlaybackService _playback;

  SttProvider _stt;
  TtsProvider _tts;
  AssistantProvider _assistant;
  VoiceConfig _config;

  VoiceLoopState _state = VoiceLoopState.idle;
  String? _errorMessage;
  String? _lastTranscript;
  WearableCard? _lastCard;

  // ── Getters ───────────────────────────────────────────────────────────────

  VoiceLoopState get voiceState => _state;
  String? get errorMessage => _errorMessage;
  String? get lastTranscript => _lastTranscript;
  WearableCard? get lastCard => _lastCard;
  bool get isListening => _state == VoiceLoopState.listening;
  bool get isBusy =>
      _state != VoiceLoopState.idle && _state != VoiceLoopState.error;

  // ── Constructor ───────────────────────────────────────────────────────────

  VoiceAssistantService({
    required VoiceController voiceController,
    required ConversationSessionService session,
    required AudioPlaybackService playback,
    required SttProvider stt,
    required TtsProvider tts,
    required AssistantProvider assistant,
    required VoiceConfig config,
  })  : _voiceController = voiceController,
        _session = session,
        _playback = playback,
        _stt = stt,
        _tts = tts,
        _assistant = assistant,
        _config = config;

  /// Hot-swap providers when [VoiceConfig] changes (e.g. from settings page).
  void updateProviders(
      VoiceConfig config, SttProvider stt, TtsProvider tts, AssistantProvider assistant) {
    _config = config;
    _stt = stt;
    _tts = tts;
    _assistant = assistant;
    // No state change — providers are only used during the next turn.
  }

  // ── Public API ────────────────────────────────────────────────────────────

  /// Start phone-mic recording (push-to-talk step 1).
  ///
  /// Returns false if mic permission was denied or the loop is already busy.
  Future<bool> startListening() async {
    if (isBusy) return false;
    _errorMessage = null;

    if (!_config.enableStt) {
      _log.info('STT disabled — voice input skipped');
      return false;
    }

    final ok = await _voiceController.startRecording();
    if (!ok) {
      _errorMessage = 'Microphone permission denied';
      _setState(VoiceLoopState.error);
      return false;
    }

    _setState(VoiceLoopState.listening);
    return true;
  }

  /// Stop recording and execute the full voice turn (step 2+).
  ///
  /// [appModel] is passed from the UI to avoid creating a circular provider
  /// dependency.  [router] is [CommandRouter.route] for local command handling.
  ///
  /// Returns the final [AssistantResult] so the caller can act on
  /// `result.data['mode']` for mode-switch commands (Bug G fix).
  /// Returns null when the loop is aborted early (wrong state / empty audio).
  Future<AssistantResult?> stopAndProcess({
    required AppLogicModel appModel,
    required Future<AssistantResult?> Function(String) router,
  }) async {
    if (_state != VoiceLoopState.listening) {
      _log.warning('[VoiceLoop] stopAndProcess called in wrong state: $_state');
      return null;
    }

    // ── 1. Stop recording ──────────────────────────────────────────────────
    final audioPath = await _voiceController.stopRecording();
    _log.info('[VoiceLoop] step 1 — recording stopped → path: $audioPath');

    // ── 2. setState + Frame: show transcribing status (Bug A fix) ─────────
    // Note: label was previously "Listening…" which was wrong here —
    // recording has already stopped; label must match actual state.
    _setState(VoiceLoopState.transcribing);
    await appModel.sendStatusBannerToFrame('Transcribing…');
    _log.info('[VoiceLoop] step 2 — state→transcribing, banner sent to Frame');

    // ── 3. Transcribe ──────────────────────────────────────────────────────
    String? transcript;
    if (audioPath != null) {
      try {
        transcript = await _stt.transcribeAudioFile(audioPath);
        _log.info('[VoiceLoop] step 3 — STT(${_stt.name}) → "$transcript"');
      } catch (e) {
        _log.warning('[VoiceLoop] step 3 — STT error: $e');
      }
    } else {
      _log.warning('[VoiceLoop] step 3 — no audio path; STT skipped');
    }

    if (transcript == null || transcript.trim().isEmpty) {
      _log.warning('[VoiceLoop] abort — empty transcript');
      _setError('Could not transcribe audio. Try again.');
      await _voiceController.cleanupTempFile(audioPath);
      return null;
    }

    _lastTranscript = transcript.trim();

    // ── 4. Session: add user turn ──────────────────────────────────────────
    _session.addUserTurn(_lastTranscript!, source: TurnSource.voice);
    _log.info('[VoiceLoop] step 4 — user turn added; session size: ${_session.turnCount}');

    // ── 5. Frame: show thinking status ────────────────────────────────────
    _setState(VoiceLoopState.thinking);
    await appModel.sendStatusBannerToFrame('Thinking…');
    _log.info('[VoiceLoop] step 5 — state→thinking, banner sent');

    // ── 6 & 7. Route locally; fall back to real/mock assistant ────────────
    // sendCard:false so the voice path owns the single card dispatch (Bug B fix).
    AssistantResult? result = await appModel.processLocalCommand(
        _lastTranscript!, router, sendCard: false);
    _log.info('[VoiceLoop] step 6 — router result: ${result == null ? "no match → assistant" : '"${result.displayText}"'}');

    if (result == null) {
      // No command matched — call the assistant provider with session history
      // and any available vision capture context.
      final mode = appModel.currentAppMode;
      final recentTurns = _session.recentTurns(limit: 6);
      final capture = _session.lastCapture;

      _log.info(
        '[VoiceLoop] step 7 — calling ${_assistant.name} assistant '
        '[mode=${mode.name}, history=${recentTurns.length} turns, '
        'capture=${capture != null}]',
      );

      try {
        result = await _assistant.getReply(
          _lastTranscript!,
          mode: mode,
          recentTurns: recentTurns,
          capture: capture,
        );
        _log.info('[VoiceLoop] step 7 — ${_assistant.name} reply: "${result.displayText}"');
      } catch (e) {
        _log.warning('[VoiceLoop] step 7 — assistant error ($e); using mock fallback');
        result = const MockAssistantProvider().getReplySync(_lastTranscript!, mode);
      }

      appModel.addVoiceExchangeToChat(_lastTranscript!, result.displayText);
    }

    // ── 8. Session: add assistant turn ────────────────────────────────────
    _session.addAssistantTurn(result.displayText);
    _log.info('[VoiceLoop] step 8 — assistant turn added; session size: ${_session.turnCount}');

    // ── 9. Build wearable card ────────────────────────────────────────────
    final card = result.wearableCard ??
        _buildReplyCard(result.displayText, appModel.currentAppMode);
    _lastCard = card;
    _session.updateLatestCard(card);
    _log.info('[VoiceLoop] step 9 — card: "${card.toFrameString()}"');

    // ── 10. Frame: send compact reply card (single send — Bug B fix) ───────
    await appModel.sendWearableCardToFrame(card);
    _log.info('[VoiceLoop] step 10 — card dispatched to Frame');

    // ── 11 & 12. TTS + playback ───────────────────────────────────────────
    _setState(VoiceLoopState.speaking);
    await appModel.sendStatusBannerToFrame('Speaking…');
    _log.info('[VoiceLoop] step 11 — state→speaking, TTS enabled: ${_config.enableTts}');

    if (_config.enableTts) {
      String? ttsPath;
      try {
        final ttsText = result.ttsText ?? result.displayText;
        _log.info('[VoiceLoop] step 12 — synthesizing via ${_tts.name}: "$ttsText"');
        ttsPath = await _tts.synthesizeToFile(ttsText, voice: _config.ttsVoice);
        _log.info('[VoiceLoop] step 12 — TTS file: $ttsPath');
      } catch (e) {
        _log.warning('[VoiceLoop] step 12 — TTS error: $e');
      }
      if (ttsPath != null) {
        await _playback.playFile(ttsPath);
        await _voiceController.cleanupTempFile(ttsPath);
      }
    }

    // ── 13. Cleanup ───────────────────────────────────────────────────────
    await _voiceController.cleanupTempFile(audioPath);
    _setState(VoiceLoopState.idle);
    _log.info('[VoiceLoop] step 13 — cleanup done, state→idle');

    return result;
  }

  /// Cancel an in-progress recording without processing.
  Future<void> cancelListening() async {
    if (_state == VoiceLoopState.listening) {
      await _voiceController.cancelRecording();
      _setState(VoiceLoopState.idle);
    }
  }

  /// Dismiss an error state and return to idle.
  void resetError() {
    if (_state == VoiceLoopState.error) _setState(VoiceLoopState.idle);
  }

  // ── Private helpers ───────────────────────────────────────────────────────

  void _setState(VoiceLoopState s) {
    _state = s;
    notifyListeners();
  }

  void _setError(String msg) {
    _errorMessage = msg;
    _log.warning(msg);
    _setState(VoiceLoopState.error);
  }

  WearableCard _buildReplyCard(String reply, AppMode mode) {
    final body = reply.length > 160 ? '${reply.substring(0, 157)}…' : reply;
    return WearableCard(
      id: 'voice-${DateTime.now().millisecondsSinceEpoch}',
      title: mode.displayName,
      body: body,
      icon: '◈',
      mode: mode,
      timestamp: DateTime.now(),
      cardType: WearableCardType.info,
    );
  }

  @override
  void dispose() {
    _voiceController.dispose();
    _playback.dispose();
    super.dispose();
  }
}

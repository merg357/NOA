import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:noa/models/app_mode.dart';
import 'package:noa/models/conversation_turn.dart';
import 'package:noa/models/gemini_live_config.dart';
import 'package:noa/models/wearable_card.dart';
import 'package:noa/services/audio_playback_service.dart';
import 'package:noa/services/conversation_session_service.dart';
import 'package:noa/services/voice_assistant_service.dart' show VoiceLoopState;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as ws_status;

/// Live session state — maps 1-to-1 with [VoiceLoopState] for the UI.
enum GeminiLiveState {
  /// No active session.
  idle,

  /// WebSocket connecting / setup handshake in progress.
  connecting,

  /// Session open, mic streaming to Gemini, waiting for model to respond.
  listening,

  /// Gemini is generating audio; buffering / playing the response.
  speaking,

  /// Model was speaking but user's new speech interrupted it.
  interrupted,

  /// A non-fatal error occurred; call [resetError] or [stopSession] to recover.
  error,
}

/// Manages a persistent Gemini Live WebSocket session for real-time voice
/// conversations.
///
/// # Constraints (Gemini Live, May 2025)
/// - Input: 16-bit PCM mono 16 kHz streamed as base64 chunks.
/// - Output: 16-bit PCM mono 24 kHz returned as base64 chunks per turn.
/// - One response modality per session (we use AUDIO).
/// - Stateful: the session holds conversation context across turns.
/// - Production: use [GeminiLiveConfig.ephemeralTokenUrl] so the API key is
///   never sent from the client device.
///
/// # Session lifecycle
/// ```
/// idle ──[startSession]──> connecting ──[setupComplete]──> listening
///        ──[user speaks]──> speaking ──[turn complete]──> listening
///        ──[interrupt]──> listening
///        ──[stopSession/error]──> idle
/// ```
///
/// # Frame side-channel
/// The caller supplies optional callbacks for status banners and wearable cards
/// at [startSession] time, avoiding circular provider dependencies.
class GeminiLiveService extends ChangeNotifier {
  static final _log = Logger('GeminiLiveService');

  final ConversationSessionService _session;
  final AudioPlaybackService _playback;
  final AudioRecorder _recorder = AudioRecorder();

  GeminiLiveState _state = GeminiLiveState.idle;
  String? _errorMessage;

  // In-flight transcript accumulators.
  String? _pendingUserText;
  String? _pendingModelText;

  // WebSocket.
  WebSocketChannel? _ws;
  StreamSubscription<dynamic>? _wsSub;

  // Mic stream subscription.
  StreamSubscription<Uint8List>? _micSub;

  // Accumulates PCM bytes for the current model turn (24 kHz mono 16-bit).
  final List<int> _pcmBuffer = [];

  // Callbacks wired by the UI at startSession() time.
  Future<void> Function(String)? _onFrameBanner;
  Future<void> Function(WearableCard)? _onFrameCard;
  void Function(String userText, String modelText)? _onAddToChat;

  // ── Getters ───────────────────────────────────────────────────────────────

  GeminiLiveState get liveState => _state;
  String? get errorMessage => _errorMessage;

  bool get isActive =>
      _state != GeminiLiveState.idle && _state != GeminiLiveState.error;

  /// Maps [GeminiLiveState] → [VoiceLoopState] so noa.dart can render a
  /// unified voice-state banner without knowing which service is active.
  VoiceLoopState get voiceLoopState => switch (_state) {
        GeminiLiveState.idle => VoiceLoopState.idle,
        GeminiLiveState.connecting => VoiceLoopState.connecting,
        GeminiLiveState.listening => VoiceLoopState.listening,
        GeminiLiveState.speaking => VoiceLoopState.speaking,
        GeminiLiveState.interrupted => VoiceLoopState.interrupted,
        GeminiLiveState.error => VoiceLoopState.error,
      };

  // ── Constructor ───────────────────────────────────────────────────────────

  GeminiLiveService({
    required ConversationSessionService session,
    required AudioPlaybackService playback,
  })  : _session = session,
        _playback = playback;

  // ── Public API ────────────────────────────────────────────────────────────

  /// Start a Gemini Live session.
  ///
  /// [systemInstruction] is the base persona prompt (e.g. from
  /// `AppLogicModel.tunePrompt`).  [mode.systemPromptSuffix] is appended
  /// automatically so the session reflects the current app mode.
  ///
  /// [onFrameBanner], [onFrameCard], and [onAddToChat] are optional
  /// callbacks wired from the UI layer to avoid circular provider deps.
  Future<void> startSession({
    required GeminiLiveConfig config,
    required String systemInstruction,
    required AppMode mode,
    Future<void> Function(String)? onFrameBanner,
    Future<void> Function(WearableCard)? onFrameCard,
    void Function(String userText, String modelText)? onAddToChat,
  }) async {
    if (isActive) {
      _log.warning('[GeminiLive] startSession called while already active');
      return;
    }

    _onFrameBanner = onFrameBanner;
    _onFrameCard = onFrameCard;
    _onAddToChat = onAddToChat;
    _pcmBuffer.clear();
    _pendingUserText = null;
    _pendingModelText = null;
    _errorMessage = null;

    _setState(GeminiLiveState.connecting);
    _onFrameBanner?.call('Connecting…');

    if (!config.isConfigured) {
      _setError(
        'Gemini Live is not configured. '
        'Set GEMINI_API_KEY in .env or provide an ephemeral token URL.',
      );
      return;
    }

    // ── Resolve key / ephemeral token ──────────────────────────────────────
    String wsKey = config.effectiveApiKey;
    if (config.ephemeralTokenUrl.isNotEmpty) {
      try {
        wsKey = await _fetchEphemeralToken(
          config.ephemeralTokenUrl,
          config.effectiveApiKey,
        );
        _log.info('[GeminiLive] ephemeral token acquired');
      } catch (e) {
        _log.warning(
            '[GeminiLive] ephemeral token fetch failed: $e — falling back to API key');
      }
    }

    try {
      final uri = Uri.parse(
        'wss://generativelanguage.googleapis.com/ws/'
        'google.ai.generativelanguage.v1alpha.GenerativeService'
        '.BidiGenerateContent?key=$wsKey',
      );
      _ws = WebSocketChannel.connect(uri);
      await _ws!.ready;

      // ── Send BidiGenerateContentSetup ──────────────────────────────────
      final basePrompt = systemInstruction.isNotEmpty
          ? systemInstruction
          : 'You are ARIA, a smart wearable AI assistant.';
      final fullPrompt = basePrompt + mode.systemPromptSuffix;

      final setup = {
        'setup': {
          'model': config.model,
          'generationConfig': {
            'responseModalities': ['AUDIO'],
            'speechConfig': {
              'voiceConfig': {
                'prebuiltVoiceConfig': {
                  'voiceName': config.voiceName,
                }
              }
            },
            // Request text transcripts of both input (what the user said) and
            // output (what the model said) so we can update session history.
            'inputAudioTranscription': {},
            'outputAudioTranscription': {},
          },
          'systemInstruction': {
            'parts': [
              {'text': fullPrompt}
            ]
          }
        }
      };

      _ws!.sink.add(jsonEncode(setup));
      _log.info(
          '[GeminiLive] setup sent: model=${config.model} voice=${config.voiceName}');

      _wsSub = _ws!.stream.listen(
        _onServerMessage,
        onError: _onWsError,
        onDone: _onWsDone,
      );
    } catch (e) {
      _setError('Could not connect to Gemini Live: $e');
    }
  }

  /// Convenience toggle: starts the session when idle/error, stops it when
  /// active.  Used by the mic-button tap handler in noa.dart.
  Future<void> toggleSession({
    required GeminiLiveConfig config,
    required String systemInstruction,
    required AppMode mode,
    Future<void> Function(String)? onFrameBanner,
    Future<void> Function(WearableCard)? onFrameCard,
    void Function(String, String)? onAddToChat,
  }) async {
    if (isActive) {
      await stopSession();
    } else {
      await startSession(
        config: config,
        systemInstruction: systemInstruction,
        mode: mode,
        onFrameBanner: onFrameBanner,
        onFrameCard: onFrameCard,
        onAddToChat: onAddToChat,
      );
    }
  }

  /// Cleanly ends the session, stops the microphone, and stops audio playback.
  Future<void> stopSession() async {
    _log.info('[GeminiLive] stopSession');
    await _stopMicStream();
    await _playback.stop();
    await _closeWebSocket();
    _pcmBuffer.clear();
    _setState(GeminiLiveState.idle);
    _onFrameBanner?.call('Session ended');
  }

  /// Dismiss an error and return to idle so the mic button becomes tappable.
  void resetError() {
    if (_state == GeminiLiveState.error) _setState(GeminiLiveState.idle);
  }

  // ── Server message handling ───────────────────────────────────────────────

  void _onServerMessage(dynamic raw) {
    if (raw is! String) return;
    Map<String, dynamic> msg;
    try {
      msg = jsonDecode(raw) as Map<String, dynamic>;
    } catch (e) {
      _log.warning('[GeminiLive] JSON parse error: $e');
      return;
    }

    _log.finest('[GeminiLive] server keys: ${msg.keys}');

    if (msg.containsKey('setupComplete')) {
      _log.info('[GeminiLive] setup complete — starting mic stream');
      _startMicStream();
      _setState(GeminiLiveState.listening);
      _onFrameBanner?.call('Listening…');
      return;
    }

    if (msg.containsKey('serverContent')) {
      _handleServerContent(msg['serverContent'] as Map<String, dynamic>);
      return;
    }

    // toolCall, usageMetadata, etc. — log and ignore.
    _log.fine('[GeminiLive] unhandled server message: ${msg.keys}');
  }

  void _handleServerContent(Map<String, dynamic> content) {
    // ── Interruption ───────────────────────────────────────────────────────
    if (content['interrupted'] == true) {
      _log.info('[GeminiLive] model interrupted by user');
      _pcmBuffer.clear();
      _pendingModelText = null;
      _playback.stop();
      _setState(GeminiLiveState.interrupted);
      // Return to listening after a brief pause so the state banner is visible.
      Future<void>.delayed(const Duration(milliseconds: 300), () {
        if (_state == GeminiLiveState.interrupted) {
          _setState(GeminiLiveState.listening);
          _onFrameBanner?.call('Listening…');
        }
      });
      return;
    }

    // ── Model turn — accumulate audio + text ───────────────────────────────
    final modelTurn = content['modelTurn'] as Map<String, dynamic>?;
    if (modelTurn != null) {
      if (_state != GeminiLiveState.speaking) {
        _setState(GeminiLiveState.speaking);
        _onFrameBanner?.call('Speaking…');
      }
      for (final raw in (modelTurn['parts'] as List<dynamic>?) ?? []) {
        final part = raw as Map<String, dynamic>;

        // Audio chunk (PCM 24 kHz mono 16-bit, base64-encoded).
        final inlineData = part['inlineData'] as Map<String, dynamic>?;
        if (inlineData != null) {
          final mime = inlineData['mimeType'] as String? ?? '';
          if (mime.startsWith('audio/pcm')) {
            _pcmBuffer.addAll(base64Decode(inlineData['data'] as String));
          }
        }

        // Inline text (rare alongside AUDIO modality, but handled defensively).
        final text = part['text'] as String?;
        if (text != null && text.isNotEmpty) {
          _pendingModelText = ((_pendingModelText ?? '') + text).trim();
        }
      }
    }

    // ── Input transcription (what the user said) ──────────────────────────
    final inputTx = content['inputTranscription'] as Map<String, dynamic>?;
    if (inputTx != null) {
      final text = (inputTx['text'] as String? ?? '').trim();
      if (text.isNotEmpty) {
        _pendingUserText = text;
        _session.addUserTurn(text, source: TurnSource.voice);
        _log.info('[GeminiLive] input transcript: "$text"');
      }
    }

    // ── Output transcription (what the model said) ────────────────────────
    final outputTx = content['outputTranscription'] as Map<String, dynamic>?;
    if (outputTx != null) {
      final text = (outputTx['text'] as String? ?? '').trim();
      if (text.isNotEmpty) _pendingModelText = text;
    }

    // ── Turn complete ─────────────────────────────────────────────────────
    if (content['turnComplete'] == true) {
      _log.info(
          '[GeminiLive] turn complete — pcm=${_pcmBuffer.length}B text=${_pendingModelText != null}');

      if (_pcmBuffer.isNotEmpty) {
        final pcmSnapshot = List<int>.from(_pcmBuffer);
        _pcmBuffer.clear();
        // Play asynchronously — fire-and-forget with explicit error logging.
        _playPcmBuffer(pcmSnapshot);
      } else {
        _setState(GeminiLiveState.listening);
        _onFrameBanner?.call('Listening…');
      }

      // Commit the completed exchange to session + chat.
      final modelText = _pendingModelText;
      _pendingModelText = null;
      if (modelText != null && modelText.isNotEmpty) {
        _session.addAssistantTurn(modelText);
        final userText = _pendingUserText ?? '';
        _pendingUserText = null;
        _onAddToChat?.call(userText, modelText);

        // Send a compact wearable card to Frame.
        final card = _buildReplyCard(modelText, _session.mode);
        _session.updateLatestCard(card);
        _onFrameCard?.call(card);
      }
    }
  }

  // ── Audio playback ────────────────────────────────────────────────────────

  // ignore: unawaited_futures
  void _playPcmBuffer(List<int> pcmBytes) {
    _playPcmBufferAsync(pcmBytes).catchError((Object e) {
      _log.warning('[GeminiLive] playback error: $e');
    });
  }

  Future<void> _playPcmBufferAsync(List<int> pcmBytes) async {
    try {
      final dir = await getTemporaryDirectory();
      final path =
          '${dir.path}/gemini_${DateTime.now().millisecondsSinceEpoch}.wav';
      final wav = _buildWav(pcmBytes, sampleRate: 24000);
      await File(path).writeAsBytes(wav);
      _log.info('[GeminiLive] playing ${wav.length}B WAV → $path');
      await _playback.playFile(path);
      // Best-effort delete.
      File(path).delete().catchError((_) => File(path));
    } finally {
      if (_state == GeminiLiveState.speaking) {
        _setState(GeminiLiveState.listening);
        _onFrameBanner?.call('Listening…');
      }
    }
  }

  // ── Mic streaming ─────────────────────────────────────────────────────────

  Future<void> _startMicStream() async {
    if (!await _recorder.hasPermission()) {
      _setError('Microphone permission denied');
      return;
    }
    try {
      final stream = await _recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 16000,
          numChannels: 1,
        ),
      );
      _micSub = stream.listen(
        _onMicChunk,
        onError: (Object e) =>
            _log.warning('[GeminiLive] mic stream error: $e'),
      );
      _log.info('[GeminiLive] mic streaming started (PCM 16 kHz mono 16-bit)');
    } catch (e) {
      _setError('Could not start microphone stream: $e');
    }
  }

  void _onMicChunk(Uint8List chunk) {
    if (_ws == null || !isActive) return;
    final msg = {
      'realtimeInput': {
        'mediaChunks': [
          {
            'mimeType': 'audio/pcm;rate=16000',
            'data': base64Encode(chunk),
          }
        ]
      }
    };
    try {
      _ws!.sink.add(jsonEncode(msg));
    } catch (_) {
      // WebSocket is closing — ignore transient write errors.
    }
  }

  Future<void> _stopMicStream() async {
    await _micSub?.cancel();
    _micSub = null;
    try {
      if (await _recorder.isRecording()) await _recorder.stop();
    } catch (_) {}
  }

  // ── Ephemeral token ───────────────────────────────────────────────────────

  /// Fetches a short-lived token from [url].
  ///
  /// Expects the server to return `{"token": "..."}` as JSON.
  /// The [apiKey] is included in the request body so the server can call
  /// the Google token-vending endpoint on the client's behalf.
  Future<String> _fetchEphemeralToken(String url, String apiKey) async {
    final client = HttpClient();
    try {
      final request = await client.postUrl(Uri.parse(url));
      request.headers.set('Content-Type', 'application/json');
      request.write(jsonEncode({'apiKey': apiKey}));
      final response = await request.close();
      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}');
      }
      final body = await response.transform(utf8.decoder).join();
      final json = jsonDecode(body) as Map<String, dynamic>;
      final token = json['token'] as String?;
      if (token == null || token.isEmpty) {
        throw Exception('Server returned empty token');
      }
      return token;
    } finally {
      client.close();
    }
  }

  // ── WebSocket lifecycle ───────────────────────────────────────────────────

  void _onWsError(dynamic error) {
    _log.warning('[GeminiLive] WebSocket error: $error');
    _setError('Connection error: $error');
  }

  void _onWsDone() {
    _log.info('[GeminiLive] WebSocket closed by server');
    _stopMicStream();
    if (isActive) _setState(GeminiLiveState.idle);
  }

  Future<void> _closeWebSocket() async {
    await _wsSub?.cancel();
    _wsSub = null;
    try {
      await _ws?.sink.close(ws_status.normalClosure);
    } catch (_) {}
    _ws = null;
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  WearableCard _buildReplyCard(String reply, AppMode mode) {
    final body = reply.length > 160 ? '${reply.substring(0, 157)}…' : reply;
    return WearableCard(
      id: 'gemini-${DateTime.now().millisecondsSinceEpoch}',
      title: '${mode.icon} ${mode.displayName}',
      body: body,
      icon: '◈',
      mode: mode,
      timestamp: DateTime.now(),
      cardType: WearableCardType.info,
    );
  }

  /// Builds a minimal 44-byte WAV header and appends [pcmBytes].
  ///
  /// [sampleRate] must match the source — pass 24000 for Gemini Live output.
  /// Assumes mono 16-bit PCM.
  static Uint8List _buildWav(List<int> pcmBytes, {required int sampleRate}) {
    const numChannels = 1;
    const bitsPerSample = 16;
    final byteRate = sampleRate * numChannels * (bitsPerSample ~/ 8);
    const blockAlign = numChannels * (bitsPerSample ~/ 8);
    final dataSize = pcmBytes.length;
    final chunkSize = 36 + dataSize;

    final buf = ByteData(44 + dataSize);
    int o = 0;

    void writeStr(String s) {
      for (final c in s.codeUnits) {
        buf.setUint8(o++, c);
      }
    }

    void writeU32(int v) {
      buf.setUint32(o, v, Endian.little);
      o += 4;
    }

    void writeU16(int v) {
      buf.setUint16(o, v, Endian.little);
      o += 2;
    }

    writeStr('RIFF');
    writeU32(chunkSize);
    writeStr('WAVE');
    writeStr('fmt ');
    writeU32(16); // PCM sub-chunk size
    writeU16(1); // PCM format
    writeU16(numChannels);
    writeU32(sampleRate);
    writeU32(byteRate);
    writeU16(blockAlign);
    writeU16(bitsPerSample);
    writeStr('data');
    writeU32(dataSize);
    for (int i = 0; i < pcmBytes.length; i++) {
      buf.setUint8(o++, pcmBytes[i]);
    }

    return buf.buffer.asUint8List();
  }

  void _setState(GeminiLiveState s) {
    _state = s;
    notifyListeners();
  }

  void _setError(String msg) {
    _errorMessage = msg;
    _log.warning('[GeminiLive] $msg');
    _stopMicStream();
    _closeWebSocket();
    _setState(GeminiLiveState.error);
  }

  @override
  void dispose() {
    _stopMicStream();
    _closeWebSocket();
    _recorder.dispose();
    _playback.dispose();
    super.dispose();
  }
}

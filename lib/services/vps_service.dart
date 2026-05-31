import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:noa/models/wearable_card.dart';
import 'package:noa/models/app_mode.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as ws_status;

// ── VPS Connection State ───────────────────────────────────────────────────────

enum VpsConnectionState {
  disconnected,
  connecting,
  connected,
  error,
}

// ── VPS Config ────────────────────────────────────────────────────────────────

class VpsConfig {
  final String baseUrl;
  final String wsUrl;
  final String bearerToken;
  final String deviceId;
  final bool enabled;

  const VpsConfig({
    this.baseUrl = '',
    this.wsUrl = '',
    this.bearerToken = '',
    this.deviceId = '',
    this.enabled = false,
  });

  VpsConfig copyWith({
    String? baseUrl,
    String? wsUrl,
    String? bearerToken,
    String? deviceId,
    bool? enabled,
  }) =>
      VpsConfig(
        baseUrl: baseUrl ?? this.baseUrl,
        wsUrl: wsUrl ?? this.wsUrl,
        bearerToken: bearerToken ?? this.bearerToken,
        deviceId: deviceId ?? this.deviceId,
        enabled: enabled ?? this.enabled,
      );

  bool get isConfigured => baseUrl.isNotEmpty && wsUrl.isNotEmpty;
}

// ── VPS Config Notifier ───────────────────────────────────────────────────────

class VpsConfigNotifier extends StateNotifier<VpsConfig> {
  static const _kBaseUrl = 'vps_base_url';
  static const _kWsUrl = 'vps_ws_url';
  static const _kToken = 'vps_bearer_token';
  static const _kDeviceId = 'vps_device_id';
  static const _kEnabled = 'vps_enabled';

  VpsConfigNotifier() : super(const VpsConfig()) {
    _load();
  }

  Future<void> _load() async {
    final sp = await SharedPreferences.getInstance();
    final envBaseUrl = dotenv.env['VPS_BASE_URL'] ?? '';
    final envWsUrl = dotenv.env['VPS_WS_URL'] ?? '';
    final envToken = dotenv.env['VPS_BEARER_TOKEN'] ?? '';
    var deviceId = sp.getString(_kDeviceId) ??
        dotenv.env['VPS_DEVICE_ID'] ??
        '';
    if (deviceId.isEmpty) {
      deviceId = const Uuid().v4();
      await sp.setString(_kDeviceId, deviceId);
    }
    state = VpsConfig(
      baseUrl: sp.getString(_kBaseUrl) ?? envBaseUrl,
      wsUrl: sp.getString(_kWsUrl) ?? envWsUrl,
      bearerToken: sp.getString(_kToken) ?? envToken,
      deviceId: deviceId,
      enabled: sp.getBool(_kEnabled) ?? envBaseUrl.isNotEmpty,
    );
  }

  Future<void> update(VpsConfig cfg) async {
    state = cfg;
    final sp = await SharedPreferences.getInstance();
    await Future.wait([
      sp.setString(_kBaseUrl, cfg.baseUrl),
      sp.setString(_kWsUrl, cfg.wsUrl),
      sp.setString(_kToken, cfg.bearerToken),
      sp.setString(_kDeviceId, cfg.deviceId),
      sp.setBool(_kEnabled, cfg.enabled),
    ]);
  }
}

final vpsConfigProvider =
    StateNotifierProvider<VpsConfigNotifier, VpsConfig>(
  (_) => VpsConfigNotifier(),
);

// ── VPS Service ───────────────────────────────────────────────────────────────

/// Manages the WebSocket connection from the mobile app to the Jarvis VPS.
///
/// # Protocol
/// All messages are JSON.  Incoming message types:
///   `connected`     — VPS acknowledged the connection
///   `pong`          — response to a client `ping`
///   `wearable_card` — push a card to Frame / app UI
///   `status_banner` — push a short text to Frame HUD
///   `hermes_result` — result of a triggered Hermes task
///
/// The service is a [ChangeNotifier] so the UI can watch connection state.
class VpsService extends ChangeNotifier {
  static final _log = Logger('VpsService');

  VpsConnectionState _connectionState = VpsConnectionState.disconnected;
  String? _errorMessage;
  WearableCard? _lastReceivedCard;
  String? _lastHermesResultText;

  // Last config used for connect — stored so reconnect can reuse it.
  VpsConfig? _lastConfig;

  // Callbacks wired by the UI.
  Future<void> Function(WearableCard)? _onCardReceived;
  Future<void> Function(String)? _onBannerReceived;

  WebSocketChannel? _ws;
  StreamSubscription<dynamic>? _wsSub;
  Timer? _reconnectTimer;
  Timer? _pingTimer;
  bool _disposed = false;

  // ── Getters ───────────────────────────────────────────────────────────────

  VpsConnectionState get connectionState => _connectionState;
  String? get errorMessage => _errorMessage;
  WearableCard? get lastReceivedCard => _lastReceivedCard;
  /// Human-readable text from the most recent hermes_result message.
  String? get lastHermesResultText => _lastHermesResultText;
  bool get isConnected => _connectionState == VpsConnectionState.connected;

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  Future<void> connect(
    VpsConfig config, {
    Future<void> Function(WearableCard)? onCardReceived,
    Future<void> Function(String)? onBannerReceived,
  }) async {
    if (!config.isConfigured || !config.enabled) {
      _log.info('[VPS] Not configured or disabled — skipping connect');
      return;
    }
    if (_connectionState == VpsConnectionState.connecting ||
        _connectionState == VpsConnectionState.connected) {
      return;
    }

    _lastConfig = config;
    _onCardReceived = onCardReceived;
    _onBannerReceived = onBannerReceived;
    _errorMessage = null;
    _setState(VpsConnectionState.connecting);

    try {
      final uri = Uri.parse(
        '${config.wsUrl}?device_id=${config.deviceId}'
        '&token=${config.bearerToken}',
      );
      _ws = WebSocketChannel.connect(uri);
      await _ws!.ready;

      _wsSub = _ws!.stream.listen(
        _onMessage,
        onError: _onWsError,
        onDone: _onWsDone,
      );

      // Heartbeat ping every 30 seconds.
      _pingTimer?.cancel();
      _pingTimer = Timer.periodic(const Duration(seconds: 30), (_) {
        if (isConnected) {
          _ws?.sink.add(jsonEncode({'type': 'ping'}));
        }
      });

      _setState(VpsConnectionState.connected);
      // Log connected URL (token excluded for security).
      final safeUri = Uri.parse('${config.wsUrl}?device_id=${config.deviceId}');
      _log.info('[VPS] WebSocket connected → $safeUri');
    } catch (e) {
      _log.warning('[VPS] Connection failed: $e');
      _errorMessage = e.toString();
      _setState(VpsConnectionState.error);
      _scheduleReconnect(config);
    }
  }

  Future<void> disconnect() async {
    _reconnectTimer?.cancel();
    _pingTimer?.cancel();
    await _wsSub?.cancel();
    _wsSub = null;
    try {
      await _ws?.sink.close(ws_status.normalClosure);
    } catch (_) {}
    _ws = null;
    if (!_disposed) _setState(VpsConnectionState.disconnected);
  }

  /// Send a Hermes task trigger via WebSocket.
  void triggerHermesTask(String task, {Map<String, dynamic> params = const {}}) {
    if (!isConnected) {
      _log.warning('[VPS] triggerHermesTask called but not connected');
      return;
    }
    _ws?.sink.add(jsonEncode({
      'type': 'hermes_trigger',
      'task': task,
      'params': params,
    }));
  }

  // ── Message handling ──────────────────────────────────────────────────────

  void _onMessage(dynamic raw) {
    if (raw is! String) return;
    Map<String, dynamic> msg;
    try {
      msg = jsonDecode(raw) as Map<String, dynamic>;
    } catch (e) {
      _log.warning('[VPS] JSON parse error: $e');
      return;
    }

    final type = msg['type'] as String? ?? '';
    _log.fine('[VPS] received: $type');

    switch (type) {
      case 'connected':
        _setState(VpsConnectionState.connected);
        break;

      case 'pong':
        _log.finest('[VPS] pong ts=${msg['ts']}');
        break;

      case 'wearable_card':
        final cardMap = msg['card'] as Map<String, dynamic>?;
        if (cardMap != null) {
          final card = _parseCard(cardMap);
          _log.info('[VPS] card received: id=${card.id} title="${card.title}"');
          _lastReceivedCard = card;
          _onCardReceived?.call(card);
          notifyListeners();
        }
        break;

      case 'status_banner':
        final banner = msg['message'] as String? ?? '';
        if (banner.isNotEmpty) _onBannerReceived?.call(banner);
        break;

      case 'hermes_result':
        final task = msg['task'] as String? ?? '';
        final result = msg['result'] as Map<String, dynamic>?;
        _log.info('[VPS] hermes_result task=$task: $result');
        // Build a human-readable summary for the settings page.
        _lastHermesResultText = _summariseHermesResult(task, result);
        // If the result contains an inline card payload, surface it.
        if (result != null && result.containsKey('card')) {
          final card = _parseCard(result['card'] as Map<String, dynamic>);
          _lastReceivedCard = card;
          _onCardReceived?.call(card);
        }
        notifyListeners();
        break;

      case 'error':
        _log.warning('[VPS] server error: ${msg['detail']}');
        break;
    }
  }

  /// Format a hermes_result for the settings page status row.
  String _summariseHermesResult(String task, Map<String, dynamic>? result) {
    if (result == null) return '$task: no result';
    switch (task) {
      case 'ping':
        final available = result['hermes_available'] as bool? ?? false;
        final version = result['hermes_version'] as String? ?? '';
        return available
            ? 'Hermes $version ✓'
            : 'Hermes not found ✗';
      case 'test_card':
        return result['status'] == 'ok' ? 'Test card sent ✓' : 'Card failed ✗';
      case 'daily_brief':
        return result['status'] == 'ok' ? 'Daily brief sent ✓' : 'Brief failed ✗';
      default:
        return '$task: ${result['status'] ?? 'done'}';
    }
  }

  WearableCard _parseCard(Map<String, dynamic> m) {
    final modeStr = m['mode'] as String? ?? 'standard';
    final mode = AppMode.values.firstWhere(
      (e) => e.name == modeStr,
      orElse: () => AppMode.standard,
    );
    final cardTypeStr = (m['card_type'] ?? m['cardType']) as String? ?? 'info';
    final cardType = WearableCardType.values.firstWhere(
      (e) => e.name == cardTypeStr,
      orElse: () => WearableCardType.info,
    );
    return WearableCard(
      id: m['id'] as String? ?? 'vps-${DateTime.now().millisecondsSinceEpoch}',
      title: m['title'] as String? ?? 'VPS',
      body: m['body'] as String? ?? '',
      icon: m['icon'] as String? ?? '◈',
      priority: (m['priority'] as num?)?.toInt() ?? 0,
      mode: mode,
      timestamp: DateTime.now(),
      cardType: cardType,
    );
  }

  void _onWsError(dynamic error) {
    _log.warning('[VPS] WebSocket error: $error');
    final msg = error.toString();
    _errorMessage = msg;
    _setState(VpsConnectionState.error);
    // Do not reconnect when the server rejected auth (close code 4001).
    // This avoids an infinite retry loop with a bad token.
    if (msg.contains('4001') || msg.toLowerCase().contains('unauthorized')) {
      _log.warning('[VPS] Auth rejected — not reconnecting. Check bearer token.');
      _errorMessage = 'Authentication failed. Check bearer token.';
      return;
    }
    if (!_disposed && _lastConfig != null) _scheduleReconnect(_lastConfig!);
  }

  void _onWsDone() {
    if (_disposed) return;
    _log.info('[VPS] WebSocket closed by server');
    // _onWsError already fired for abnormal closes; skip to avoid
    // double-scheduling the reconnect timer.
    if (_connectionState == VpsConnectionState.error) return;
    _setState(VpsConnectionState.disconnected);
    if (_lastConfig != null) _scheduleReconnect(_lastConfig!);
  }

  void _scheduleReconnect(VpsConfig config) {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 10), () {
      if (!_disposed && !isConnected) {
        _log.info('[VPS] Attempting reconnect...');
        connect(
          config,
          onCardReceived: _onCardReceived,
          onBannerReceived: _onBannerReceived,
        );
      }
    });
  }

  void _setState(VpsConnectionState s) {
    _connectionState = s;
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(disconnect());
    super.dispose();
  }
}

// ── Riverpod provider ─────────────────────────────────────────────────────────

final vpsServiceProvider = ChangeNotifierProvider<VpsService>(
  (_) => VpsService(),
);

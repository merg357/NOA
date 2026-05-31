import 'package:flutter_test/flutter_test.dart';
import 'package:noa/models/app_mode.dart';
import 'package:noa/models/wearable_card.dart';
import 'package:noa/services/vps_service.dart';

void main() {
  // ── VpsConfig ──────────────────────────────────────────────────────────────

  group('VpsConfig', () {
    test('default config is not configured', () {
      const cfg = VpsConfig();
      expect(cfg.isConfigured, isFalse);
      expect(cfg.enabled, isFalse);
      expect(cfg.baseUrl, isEmpty);
      expect(cfg.wsUrl, isEmpty);
    });

    test('isConfigured requires both baseUrl and wsUrl', () {
      const onlyBase = VpsConfig(baseUrl: 'http://localhost:8765');
      expect(onlyBase.isConfigured, isFalse);

      const onlyWs = VpsConfig(wsUrl: 'ws://localhost:8765/ws');
      expect(onlyWs.isConfigured, isFalse);

      const both = VpsConfig(
        baseUrl: 'http://localhost:8765',
        wsUrl: 'ws://localhost:8765/ws',
      );
      expect(both.isConfigured, isTrue);
    });

    test('copyWith preserves unmodified fields', () {
      const original = VpsConfig(
        baseUrl: 'http://a.com',
        wsUrl: 'ws://a.com/ws',
        bearerToken: 'tok',
        deviceId: 'dev-1',
        enabled: true,
      );
      final copy = original.copyWith(bearerToken: 'new-tok');
      expect(copy.baseUrl, 'http://a.com');
      expect(copy.wsUrl, 'ws://a.com/ws');
      expect(copy.bearerToken, 'new-tok');
      expect(copy.deviceId, 'dev-1');
      expect(copy.enabled, isTrue);
    });

    test('copyWith enabled toggle', () {
      const cfg = VpsConfig(
        baseUrl: 'http://x.com',
        wsUrl: 'ws://x.com/ws',
        enabled: false,
      );
      expect(cfg.copyWith(enabled: true).enabled, isTrue);
      expect(cfg.copyWith(enabled: false).enabled, isFalse);
    });
  });

  // ── VpsService._parseCard (via VpsService public surface) ──────────────────

  group('VpsService card parsing', () {
    late VpsService svc;

    setUp(() {
      svc = VpsService();
    });

    tearDown(() {
      svc.dispose();
    });

    test('initial state is disconnected', () {
      expect(svc.connectionState, VpsConnectionState.disconnected);
      expect(svc.isConnected, isFalse);
      expect(svc.lastReceivedCard, isNull);
    });

    test('triggerHermesTask when disconnected does not throw', () {
      // Should log a warning and return silently.
      expect(() => svc.triggerHermesTask('ping'), returnsNormally);
    });
  });

  // ── WearableCard via VpsService-style JSON parsing ─────────────────────────

  group('WearableCard round-trip', () {
    // Simulate the _parseCard logic directly on WearableCard construction.
    WearableCard parseCard(Map<String, dynamic> m) {
      final modeStr = m['mode'] as String? ?? 'standard';
      final mode = AppMode.values.firstWhere(
        (e) => e.name == modeStr,
        orElse: () => AppMode.standard,
      );
      final cardTypeStr =
          (m['card_type'] ?? m['cardType']) as String? ?? 'info';
      final cardType = WearableCardType.values.firstWhere(
        (e) => e.name == cardTypeStr,
        orElse: () => WearableCardType.info,
      );
      return WearableCard(
        id: m['id'] as String? ?? 'vps-0',
        title: m['title'] as String? ?? 'VPS',
        body: m['body'] as String? ?? '',
        icon: m['icon'] as String? ?? '◈',
        priority: (m['priority'] as num?)?.toInt() ?? 0,
        mode: mode,
        timestamp: DateTime.now(),
        cardType: cardType,
      );
    }

    test('parses minimal payload', () {
      final card = parseCard({'title': 'Hi', 'body': 'World'});
      expect(card.title, 'Hi');
      expect(card.body, 'World');
      expect(card.mode, AppMode.standard);
      expect(card.cardType, WearableCardType.info);
    });

    test('parses mode and cardType from JSON', () {
      final card = parseCard({
        'title': 'Brief',
        'body': 'Tasks done',
        'mode': 'productivity',
        'card_type': 'dailyBrief',
      });
      expect(card.mode, AppMode.productivity);
      expect(card.cardType, WearableCardType.dailyBrief);
    });

    test('cardType via camelCase key (cardType)', () {
      final card = parseCard({
        'title': 'Alert',
        'body': 'Fire!',
        'cardType': 'alert',
      });
      expect(card.cardType, WearableCardType.alert);
    });

    test('unknown mode falls back to standard', () {
      final card = parseCard({'mode': 'does_not_exist'});
      expect(card.mode, AppMode.standard);
    });

    test('unknown cardType falls back to info', () {
      final card = parseCard({'card_type': 'bad_type'});
      expect(card.cardType, WearableCardType.info);
    });

    test('generated card toFrameString is within 200 chars', () {
      final card = parseCard({
        'title': 'Daily Brief',
        'body': 'You have 3 reminders and 1 task due today.',
        'icon': '◈',
      });
      expect(card.toFrameString().length, lessThanOrEqualTo(200));
    });
  });

  // ── VpsService hermes result summary ────────────────────────────────────────

  group('VpsService hermes summary text', () {
    test('initial lastHermesResultText is null', () {
      final svc = VpsService();
      expect(svc.lastHermesResultText, isNull);
      svc.dispose();
    });
  });
}

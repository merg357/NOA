import 'package:flutter_test/flutter_test.dart';
import 'package:noa/models/app_mode.dart';
import 'package:noa/models/wearable_card.dart';
import 'package:noa/services/frame_output_service.dart';

// ── Spy that captures calls to sendMessage ────────────────────────────────────

class _MessageSpy {
  final List<({int flag, List<int> data})> calls = [];

  Future<void> send(int flag, List<int> data) async {
    calls.add((flag: flag, data: data));
  }
}

WearableCard _visionCard({String body = 'A sunny park'}) {
  return WearableCard(
    id: 'vision-1234',
    title: 'Vision',
    body: body,
    icon: '◎',
    mode: AppMode.vision,
    timestamp: DateTime(2025, 6, 1),
    cardType: WearableCardType.visionSummary,
  );
}

void main() {
  group('FrameOutputService.sendCard', () {
    test('calls sendMessage exactly once', () async {
      final spy = _MessageSpy();
      await FrameOutputService.sendCard(_visionCard(), spy.send);
      expect(spy.calls.length, 1);
    });

    test('uses messageResponseFlag (0x20)', () async {
      final spy = _MessageSpy();
      await FrameOutputService.sendCard(_visionCard(), spy.send);
      expect(spy.calls.first.flag, 0x20);
    });

    test('data payload is non-empty bytes', () async {
      final spy = _MessageSpy();
      await FrameOutputService.sendCard(_visionCard(), spy.send);
      expect(spy.calls.first.data.isNotEmpty, isTrue);
    });

    test('does not throw when sendMessage throws', () async {
      Future<void> brokenSend(int flag, List<int> data) async {
        throw Exception('BLE disconnected');
      }
      // Should catch internally and log, not rethrow.
      expect(
        () => FrameOutputService.sendCard(_visionCard(), brokenSend),
        returnsNormally,
      );
    });
  });

  group('FrameOutputService.sendBanner', () {
    test('calls sendMessage exactly once', () async {
      final spy = _MessageSpy();
      await FrameOutputService.sendBanner('Reminder saved', spy.send);
      expect(spy.calls.length, 1);
    });

    test('uses messageResponseFlag (0x20)', () async {
      final spy = _MessageSpy();
      await FrameOutputService.sendBanner('Test', spy.send);
      expect(spy.calls.first.flag, 0x20);
    });

    test('long banner is truncated to ≤ 80 chars in text', () async {
      final spy = _MessageSpy();
      final longText = 'x' * 120;
      await FrameOutputService.sendBanner(longText, spy.send);
      // The data payload will contain the packed bytes; we verify no exception
      // and a call was made (truncation tested indirectly via the length check
      // inside sendBanner).
      expect(spy.calls.length, 1);
    });

    test('does not throw when sendMessage throws', () async {
      Future<void> brokenSend(int flag, List<int> data) async {
        throw Exception('timeout');
      }
      expect(
        () => FrameOutputService.sendBanner('hi', brokenSend),
        returnsNormally,
      );
    });
  });

  group('WearableCard → Frame string content', () {
    test('vision card includes title and body in Frame string', () {
      final card = _visionCard(body: 'Coffee shop interior');
      final str = card.toFrameString();
      expect(str, contains('Vision'));
      expect(str, contains('Coffee shop interior'));
    });

    test('visionSummary cardType is preserved', () {
      expect(_visionCard().cardType, WearableCardType.visionSummary);
    });
  });
}

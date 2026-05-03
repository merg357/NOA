import 'package:flutter_test/flutter_test.dart';
import 'package:noa/models/app_mode.dart';
import 'package:noa/models/wearable_card.dart';

void main() {
  final ts = DateTime(2024, 1, 1);

  WearableCard makeCard({String body = 'body', String title = 'title', String icon = '⬡'}) {
    return WearableCard(
      id: 'id-1',
      title: title,
      body: body,
      icon: icon,
      timestamp: ts,
    );
  }

  group('WearableCard.toFrameString', () {
    test('short content passes through unchanged', () {
      final c = makeCard(title: 'Hello', body: 'World');
      expect(c.toFrameString(), '⬡ Hello\nWorld');
    });

    test('content exactly 200 chars passes through unchanged', () {
      // '⬡ T\n' = 4 chars prefix, body = 196 chars → total 200
      final body = 'x' * 196;
      final c = makeCard(title: 'T', body: body, icon: '⬡');
      final result = c.toFrameString();
      expect(result.length, 200);
      expect(result.endsWith(body), isTrue);
    });

    test('content over 200 chars is truncated with ellipsis', () {
      final body = 'y' * 300;
      final c = makeCard(title: 'T', body: body);
      final result = c.toFrameString();
      expect(result.length, 200);
      expect(result.endsWith('...'), isTrue);
    });

    test('empty icon skips prefix', () {
      final c = makeCard(title: 'Note', body: 'text', icon: '');
      expect(c.toFrameString(), 'Note\ntext');
    });
  });

  group('WearableCard.copyWith', () {
    test('unmodified fields keep original values', () {
      final original = makeCard(title: 'orig', body: 'b', icon: '★');
      final copy = original.copyWith();
      expect(copy.title, 'orig');
      expect(copy.body, 'b');
      expect(copy.icon, '★');
    });

    test('specified fields are updated', () {
      final original = makeCard(title: 'orig', body: 'old');
      final copy = original.copyWith(title: 'new', body: 'updated');
      expect(copy.title, 'new');
      expect(copy.body, 'updated');
      expect(copy.id, original.id);
    });

    test('priority can be overridden', () {
      final c = makeCard().copyWith(priority: 2);
      expect(c.priority, 2);
    });

    test('mode can be overridden', () {
      final c = makeCard().copyWith(mode: AppMode.productivity);
      expect(c.mode, AppMode.productivity);
    });

    test('cardType defaults to info', () {
      expect(makeCard().cardType, WearableCardType.info);
    });

    test('cardType can be overridden via copyWith', () {
      final c = makeCard().copyWith(cardType: WearableCardType.reminder);
      expect(c.cardType, WearableCardType.reminder);
    });
  });
}

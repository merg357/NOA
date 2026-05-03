import 'package:flutter_test/flutter_test.dart';
import 'package:noa/models/app_mode.dart';
import 'package:noa/models/capture_result.dart';
import 'package:noa/models/wearable_card.dart';
import 'package:noa/services/vision_analysis_provider.dart';

// ── Helper: build a WearableCard from a CaptureResult (mirrors vision.dart) ──

WearableCard cardFromCapture(CaptureResult capture) {
  return WearableCard(
    id: 'vision-${capture.capturedAt.millisecondsSinceEpoch}',
    title: 'Vision',
    body: capture.bestText,
    icon: '◎',
    mode: AppMode.vision,
    timestamp: capture.capturedAt,
    cardType: WearableCardType.visionSummary,
  );
}

void main() {
  group('MockVisionProvider', () {
    const provider = MockVisionProvider();

    test('name is "mock"', () {
      expect(provider.name, 'mock');
    });

    test('returns a non-null CaptureResult', () async {
      final result = await provider.analyze('/fake/path.jpg');
      expect(result, isNotNull);
    });

    test('returned path matches input path', () async {
      const path = '/tmp/test_image.jpg';
      final result = await provider.analyze(path);
      expect(result.imagePath, path);
    });

    test('has a non-empty sceneSummary', () async {
      final result = await provider.analyze('/fake/path.jpg');
      expect(result.sceneSummary.isNotEmpty, isTrue);
    });

    test('ocrText and qrText are empty in mock', () async {
      final result = await provider.analyze('/fake/path.jpg');
      expect(result.ocrText, isEmpty);
      expect(result.qrText, isEmpty);
    });

    test('capturedAt is recent', () async {
      final before = DateTime.now();
      final result = await provider.analyze('/fake/path.jpg');
      expect(result.capturedAt.isAfter(before.subtract(const Duration(seconds: 1))), isTrue);
    });
  });

  group('CaptureResult → WearableCard mapping', () {
    final ts = DateTime(2025, 6, 1, 12, 0);

    test('card mode is always vision', () {
      final capture = CaptureResult(
        imagePath: '/img.jpg',
        sceneSummary: 'A coffee shop interior',
        capturedAt: ts,
      );
      final card = cardFromCapture(capture);
      expect(card.mode, AppMode.vision);
    });

    test('card cardType is visionSummary', () {
      final capture = CaptureResult(imagePath: '/img.jpg', capturedAt: ts);
      final card = cardFromCapture(capture);
      expect(card.cardType, WearableCardType.visionSummary);
    });

    test('card title is "Vision"', () {
      final capture = CaptureResult(imagePath: '/img.jpg', capturedAt: ts);
      final card = cardFromCapture(capture);
      expect(card.title, 'Vision');
    });

    test('card body uses QR text when available (bestText priority)', () {
      final capture = CaptureResult(
        imagePath: '/img.jpg',
        qrText: 'https://example.com',
        capturedAt: ts,
      );
      expect(capture.bestText, 'QR: https://example.com');
      final card = cardFromCapture(capture);
      expect(card.body, contains('example.com'));
    });

    test('card body uses OCR when no QR', () {
      final capture = CaptureResult(
        imagePath: '/img.jpg',
        ocrText: 'Hello World',
        capturedAt: ts,
      );
      expect(capture.bestText, 'Hello World');
      final card = cardFromCapture(capture);
      expect(card.body, 'Hello World');
    });

    test('card body uses scene summary when no QR/OCR', () {
      final capture = CaptureResult(
        imagePath: '/img.jpg',
        sceneSummary: 'A bright outdoor scene',
        capturedAt: ts,
      );
      final card = cardFromCapture(capture);
      expect(card.body, 'A bright outdoor scene');
    });

    test('card body falls back to "(no content detected)" when all empty', () {
      final capture = CaptureResult(imagePath: '/img.jpg', capturedAt: ts);
      final card = cardFromCapture(capture);
      expect(card.body, '(no content detected)');
    });

    test('toFrameString includes Vision title and body', () {
      final capture = CaptureResult(
        imagePath: '/img.jpg',
        sceneSummary: 'Sunny park',
        capturedAt: ts,
      );
      final card = cardFromCapture(capture);
      final frameStr = card.toFrameString();
      expect(frameStr, contains('Vision'));
      expect(frameStr, contains('Sunny park'));
    });

    test('id embeds capture timestamp millis', () {
      final capture = CaptureResult(imagePath: '/img.jpg', capturedAt: ts);
      final card = cardFromCapture(capture);
      expect(card.id, 'vision-${ts.millisecondsSinceEpoch}');
    });
  });

  group('VisionAnalysisProvider contract', () {
    test('MockVisionProvider satisfies VisionAnalysisProvider interface', () {
      expect(const MockVisionProvider(), isA<VisionAnalysisProvider>());
    });

    test('custom provider can override analysis', () async {
      // Verify a custom provider implementation is respected by the interface.
      final custom = _FixedResultProvider(
        CaptureResult(
          imagePath: '/custom.jpg',
          ocrText: 'OPEN 24H',
          capturedAt: DateTime(2025),
        ),
      );
      final result = await custom.analyze('/anything.jpg');
      expect(result.ocrText, 'OPEN 24H');
    });
  });
}

// ── Test double ───────────────────────────────────────────────────────────────

class _FixedResultProvider implements VisionAnalysisProvider {
  final CaptureResult _fixed;
  const _FixedResultProvider(this._fixed);

  @override
  String get name => 'fixed';

  @override
  Future<CaptureResult> analyze(String imagePath) async => _fixed;
}

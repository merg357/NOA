import 'package:noa/models/capture_result.dart';

/// Contract that all vision analysis back-ends must implement.
///
/// Inject a concrete implementation into [VisionService] at construction time.
/// When no API keys or network are available the [MockVisionProvider] is used
/// automatically as a graceful fallback.
abstract class VisionAnalysisProvider {
  /// Human-readable name shown in debug/README tables.
  String get name;

  /// Analyse the image at [imagePath] and return structured results.
  ///
  /// Never throws — implementations must catch errors internally and return a
  /// [CaptureResult] with an appropriate [CaptureResult.sceneSummary] error
  /// message so the UI can surface it without crashing.
  Future<CaptureResult> analyze(String imagePath);
}

/// Default no-API fallback.  Returns a placeholder scene summary so the app
/// functions in demo / offline mode.
class MockVisionProvider implements VisionAnalysisProvider {
  const MockVisionProvider();

  @override
  String get name => 'mock';

  @override
  Future<CaptureResult> analyze(String imagePath) async {
    // Simulate a short processing delay so the UI spinner is visible.
    await Future.delayed(const Duration(milliseconds: 800));
    return CaptureResult(
      imagePath: imagePath,
      ocrText: '',
      qrText: '',
      sceneSummary: 'Scene captured. Connect a vision backend to analyze.',
      capturedAt: DateTime.now(),
    );
  }
}

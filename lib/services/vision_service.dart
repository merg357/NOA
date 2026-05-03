import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:noa/models/capture_result.dart';
import 'package:noa/services/vision_analysis_provider.dart';

enum VisionState { idle, capturing, analyzing, done, error }

/// Handles phone-camera capture and pluggable OCR/QR/scene analysis.
///
/// Pass a [VisionAnalysisProvider] at construction time.  If none is given the
/// [MockVisionProvider] is used so the app works without any API credentials.
class VisionService extends ChangeNotifier {
  final ImagePicker _picker;
  final VisionAnalysisProvider _analysisProvider;

  VisionState _state = VisionState.idle;
  CaptureResult? _lastCapture;
  String _errorMessage = '';

  VisionState get state => _state;
  CaptureResult? get lastCapture => _lastCapture;
  String get errorMessage => _errorMessage;

  VisionService({ImagePicker? picker, VisionAnalysisProvider? analysisProvider})
      : _picker = picker ?? ImagePicker(),
        _analysisProvider = analysisProvider ?? const MockVisionProvider();

  /// Captures a photo from the phone camera and runs mock analysis.
  Future<CaptureResult?> captureAndAnalyze() async {
    _setState(VisionState.capturing);
    try {
      final file = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
        maxWidth: 1280,
        maxHeight: 960,
      );
      if (file == null) {
        _setState(VisionState.idle);
        return null;
      }
      _setState(VisionState.analyzing);
      final result = await _analysisProvider.analyze(file.path);
      _lastCapture = result;
      _setState(VisionState.done);
      return result;
    } catch (e) {
      _errorMessage = e.toString();
      _setState(VisionState.error);
      return null;
    }
  }

  /// Pick an image from gallery and analyze.
  Future<CaptureResult?> pickAndAnalyze() async {
    _setState(VisionState.capturing);
    try {
      final file = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 1280,
        maxHeight: 960,
      );
      if (file == null) {
        _setState(VisionState.idle);
        return null;
      }
      _setState(VisionState.analyzing);
      final result = await _analysisProvider.analyze(file.path);
      _lastCapture = result;
      _setState(VisionState.done);
      return result;
    } catch (e) {
      _errorMessage = e.toString();
      _setState(VisionState.error);
      return null;
    }
  }

  void reset() {
    _state = VisionState.idle;
    _errorMessage = '';
    notifyListeners();
  }

  void _setState(VisionState s) {
    _state = s;
    notifyListeners();
  }

  /// Active analysis provider name — useful for debug / README display.
  String get providerName => _analysisProvider.name;
}

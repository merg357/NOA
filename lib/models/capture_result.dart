/// Result of a phone-camera or Frame-camera capture with analysis.
class CaptureResult {
  final String imagePath;
  final String ocrText;
  final String qrText;
  final String sceneSummary;
  final DateTime capturedAt;

  const CaptureResult({
    required this.imagePath,
    this.ocrText = '',
    this.qrText = '',
    this.sceneSummary = '',
    required this.capturedAt,
  });

  bool get hasOcr => ocrText.isNotEmpty;
  bool get hasQr => qrText.isNotEmpty;
  bool get hasScene => sceneSummary.isNotEmpty;

  /// Returns the most relevant text for display / Frame output.
  String get bestText {
    if (hasQr) return 'QR: $qrText';
    if (hasOcr) return ocrText;
    if (hasScene) return sceneSummary;
    return '(no content detected)';
  }

  CaptureResult copyWith({
    String? imagePath,
    String? ocrText,
    String? qrText,
    String? sceneSummary,
    DateTime? capturedAt,
  }) {
    return CaptureResult(
      imagePath: imagePath ?? this.imagePath,
      ocrText: ocrText ?? this.ocrText,
      qrText: qrText ?? this.qrText,
      sceneSummary: sceneSummary ?? this.sceneSummary,
      capturedAt: capturedAt ?? this.capturedAt,
    );
  }
}

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:noa/services/vision_service.dart';

/// Riverpod provider for the [VisionService].
final visionProvider = ChangeNotifierProvider<VisionService>((ref) {
  return VisionService();
});

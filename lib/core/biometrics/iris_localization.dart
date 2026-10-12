/// Coordinates of an eye landmark point in normalized coordinates [0.0, 1.0]
class EyeLandmark {
  final double x;
  final double y;
  final double? z;

  const EyeLandmark({required this.x, required this.y, this.z});
}

/// Boundary definition for an eye component
class IrisBoundaryCircle {
  final double centerX;
  final double centerY;
  final double radius;

  const IrisBoundaryCircle({
    required this.centerX,
    required this.centerY,
    required this.radius,
  });
}

/// Iris localization output (Pupil circle, Limbus circle, and eyelids)
/// NOTE: This provides GEOMETRIC LOCALIZATION ONLY, NOT A BIOMETRIC IDENTITY TEMPLATE.
class IrisLocalizationResult {
  final bool isDetected;
  final IrisBoundaryCircle? pupilCircle;
  final IrisBoundaryCircle? irisLimbusCircle;
  final List<EyeLandmark> upperEyelidContour;
  final List<EyeLandmark> lowerEyelidContour;
  final double confidence;
  final String modelSource;

  const IrisLocalizationResult({
    required this.isDetected,
    this.pupilCircle,
    this.irisLimbusCircle,
    this.upperEyelidContour = const [],
    this.lowerEyelidContour = const [],
    this.confidence = 0.0,
    this.modelSource = 'MediaPipe Iris / Geometric Landmark Detector',
  });

  /// Factory for when no eye is present in the frame
  factory IrisLocalizationResult.notDetected() {
    return const IrisLocalizationResult(
      isDetected: false,
      pupilCircle: null,
      irisLimbusCircle: null,
      confidence: 0.0,
    );
  }
}

/// Abstract contract for Iris Landmark Localization
abstract class IrisLocalizer {
  Future<IrisLocalizationResult> localizeIris({
    required List<int> imageBytes,
    required int width,
    required int height,
  });
}

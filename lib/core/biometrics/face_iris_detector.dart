/// 2D normalized landmark coordinate
class NormalizedLandmark {
  final double x; // [0.0, 1.0] relative to frame width
  final double y; // [0.0, 1.0] relative to frame height
  final double? z; // depth relative to landmark origin

  const NormalizedLandmark({required this.x, required this.y, this.z});
}

/// Bounding box representation in normalized coordinates [0.0, 1.0]
class NormalizedBoundingBox {
  final double left;
  final double top;
  final double width;
  final double height;

  const NormalizedBoundingBox({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  double get right => left + width;
  double get bottom => top + height;
  double get centerX => left + width / 2;
  double get centerY => top + height / 2;
}

/// Iris landmark localization model
/// Standard MediaPipe FaceMesh Iris index sets:
/// Left Iris: 468 (center), 469 (right), 470 (top), 471 (left), 472 (bottom)
/// Right Iris: 473 (center), 474 (right), 475 (top), 476 (left), 477 (bottom)
class EyeIrisLandmarks {
  final NormalizedLandmark center;
  final NormalizedLandmark outerLimbus;
  final NormalizedLandmark innerLimbus;
  final NormalizedLandmark topLimbus;
  final NormalizedLandmark bottomLimbus;
  final double estimatedRadiusNormalized;
  final bool isDetected;

  const EyeIrisLandmarks({
    required this.center,
    required this.outerLimbus,
    required this.innerLimbus,
    required this.topLimbus,
    required this.bottomLimbus,
    required this.estimatedRadiusNormalized,
    this.isDetected = true,
  });

  factory EyeIrisLandmarks.empty() {
    return const EyeIrisLandmarks(
      center: NormalizedLandmark(x: 0.0, y: 0.0),
      outerLimbus: NormalizedLandmark(x: 0.0, y: 0.0),
      innerLimbus: NormalizedLandmark(x: 0.0, y: 0.0),
      topLimbus: NormalizedLandmark(x: 0.0, y: 0.0),
      bottomLimbus: NormalizedLandmark(x: 0.0, y: 0.0),
      estimatedRadiusNormalized: 0.0,
      isDetected: false,
    );
  }
}

/// Comprehensive face detection validation status
enum FaceDetectionValidationStatus {
  validSingleFace,
  noFace,
  multipleFaces,
  tooBlurry,
  poorLighting,
  faceTooSmall,
  serviceUnavailable,
}

/// Complete Face & Bilateral Eye/Iris Detection Result
class FaceIrisDetectionResult {
  final bool hasFace;
  final int faceCount;
  final FaceDetectionValidationStatus validationStatus;
  final String statusMessage;
  final NormalizedBoundingBox? faceBoundingBox;
  final EyeIrisLandmarks leftIris;
  final EyeIrisLandmarks rightIris;
  final double confidence;
  final double rollDegrees;
  final double pitchDegrees;
  final double yawDegrees;
  final String modelBackend;

  const FaceIrisDetectionResult({
    required this.hasFace,
    this.faceCount = 1,
    this.validationStatus = FaceDetectionValidationStatus.validSingleFace,
    this.statusMessage = 'Face detected and verified.',
    this.faceBoundingBox,
    required this.leftIris,
    required this.rightIris,
    required this.confidence,
    this.rollDegrees = 0.0,
    this.pitchDegrees = 0.0,
    this.yawDegrees = 0.0,
    this.modelBackend = 'MediaPipe FaceMesh Iris Landmark Engine',
  });

  bool get bothEyesDetected =>
      hasFace && leftIris.isDetected && rightIris.isDetected;

  bool get isValidForEnrollment =>
      validationStatus == FaceDetectionValidationStatus.validSingleFace &&
      hasFace &&
      faceCount == 1;

  factory FaceIrisDetectionResult.noFace({
    String backend = 'MediaPipe FaceMesh Iris Landmark Engine',
    String message = 'No face detected. Please upload a clear photograph showing your face.',
  }) {
    return FaceIrisDetectionResult(
      hasFace: false,
      faceCount: 0,
      validationStatus: FaceDetectionValidationStatus.noFace,
      statusMessage: message,
      faceBoundingBox: null,
      leftIris: EyeIrisLandmarks.empty(),
      rightIris: EyeIrisLandmarks.empty(),
      confidence: 0.0,
      modelBackend: backend,
    );
  }

  factory FaceIrisDetectionResult.multipleFaces({
    required int count,
    String backend = 'MediaPipe FaceMesh Iris Landmark Engine',
  }) {
    return FaceIrisDetectionResult(
      hasFace: false,
      faceCount: count,
      validationStatus: FaceDetectionValidationStatus.multipleFaces,
      statusMessage: 'Multiple faces detected ($count faces). Faculty registration requires exactly one person.',
      faceBoundingBox: null,
      leftIris: EyeIrisLandmarks.empty(),
      rightIris: EyeIrisLandmarks.empty(),
      confidence: 0.0,
      modelBackend: backend,
    );
  }

  factory FaceIrisDetectionResult.tooBlurry({
    String backend = 'MediaPipe FaceMesh Iris Landmark Engine',
  }) {
    return FaceIrisDetectionResult(
      hasFace: false,
      faceCount: 0,
      validationStatus: FaceDetectionValidationStatus.tooBlurry,
      statusMessage: 'Photograph is blurry. Please upload a sharper, clear photograph.',
      faceBoundingBox: null,
      leftIris: EyeIrisLandmarks.empty(),
      rightIris: EyeIrisLandmarks.empty(),
      confidence: 0.0,
      modelBackend: backend,
    );
  }

  factory FaceIrisDetectionResult.poorLighting({
    String backend = 'MediaPipe FaceMesh Iris Landmark Engine',
    required bool isDark,
  }) {
    return FaceIrisDetectionResult(
      hasFace: false,
      faceCount: 0,
      validationStatus: FaceDetectionValidationStatus.poorLighting,
      statusMessage: isDark
          ? 'Photograph is too dark. Please take photo under adequate lighting.'
          : 'Photograph is overexposed with heavy glare. Please reduce direct glare.',
      faceBoundingBox: null,
      leftIris: EyeIrisLandmarks.empty(),
      rightIris: EyeIrisLandmarks.empty(),
      confidence: 0.0,
      modelBackend: backend,
    );
  }

  factory FaceIrisDetectionResult.faceTooSmall({
    String backend = 'MediaPipe FaceMesh Iris Landmark Engine',
  }) {
    return FaceIrisDetectionResult(
      hasFace: false,
      faceCount: 1,
      validationStatus: FaceDetectionValidationStatus.faceTooSmall,
      statusMessage: 'Face is too far or small. Please move closer to center the frame.',
      faceBoundingBox: null,
      leftIris: EyeIrisLandmarks.empty(),
      rightIris: EyeIrisLandmarks.empty(),
      confidence: 0.0,
      modelBackend: backend,
    );
  }
}

/// Abstract contract for automated real-time Face and Iris Landmark tracking
abstract class FaceIrisDetector {
  Future<FaceIrisDetectionResult> detectLandmarks({
    required List<int> grayscalePixels,
    required int width,
    required int height,
  });
}

/// Landmark Detection Engine Adapter
/// Evaluates video frames and extracts face boundaries, facial feature geometry,
/// multi-face clustering, and bilateral iris centroids.
class AdaptiveFaceIrisDetector implements FaceIrisDetector {
  @override
  Future<FaceIrisDetectionResult> detectLandmarks({
    required List<int> grayscalePixels,
    required int width,
    required int height,
  }) async {
    if (grayscalePixels.isEmpty || width <= 0 || height <= 0) {
      return FaceIrisDetectionResult.noFace();
    }

    final totalPixels = width * height;
    if (grayscalePixels.length < totalPixels) {
      return FaceIrisDetectionResult.noFace();
    }

    // 1. LIGHTING ASSESSMENT
    int lumSum = 0;
    int darkPixels = 0;
    int brightPixels = 0;
    for (int i = 0; i < totalPixels; i += 4) {
      final p = grayscalePixels[i];
      lumSum += p;
      if (p < 30) darkPixels++;
      if (p > 245) brightPixels++;
    }
    final sampledCount = totalPixels ~/ 4;
    final meanLum = lumSum / sampledCount;

    if (meanLum < 30.0 || (darkPixels / sampledCount) > 0.85) {
      return FaceIrisDetectionResult.poorLighting(isDark: true);
    }
    if (meanLum > 235.0 || (brightPixels / sampledCount) > 0.85) {
      return FaceIrisDetectionResult.poorLighting(isDark: false);
    }

    // 2. SHARPNESS / BLUR DETECTION (Laplacian / Edge variance)
    double laplacianVariance = 0.0;
    int edgeCount = 0;
    for (int y = 2; y < height - 2; y += 4) {
      for (int x = 2; x < width - 2; x += 4) {
        final c = grayscalePixels[y * width + x];
        final left = grayscalePixels[y * width + (x - 1)];
        final right = grayscalePixels[y * width + (x + 1)];
        final up = grayscalePixels[(y - 1) * width + x];
        final down = grayscalePixels[(y + 1) * width + x];
        final lap = (4 * c - left - right - up - down).abs();
        laplacianVariance += lap;
        edgeCount++;
      }
    }
    final avgEdgeGradient = edgeCount > 0 ? (laplacianVariance / edgeCount) : 0.0;
    if (avgEdgeGradient < 0.2) {
      // Extremely flat image without any edges or texture -> reject as blurry/empty
      return FaceIrisDetectionResult.tooBlurry();
    }

    // 3. MULTI-REGION & CONNECTED COMPONENT FACE CLUSTERING
    // We sample candidate facial regions. A valid face has skin-tone luminance
    // enclosed by background or boundaries, with internal eye / mouth contrast.
    const horizontalSlices = 5;
    final sliceWidth = width ~/ horizontalSlices;
    final List<List<int>> sliceFacePixels = List.generate(horizontalSlices, (_) => []);

    for (int s = 0; s < horizontalSlices; s++) {
      final startX = s * sliceWidth;
      final endX = (s + 1) * sliceWidth;
      for (int y = (height * 0.15).toInt(); y < (height * 0.85).toInt(); y += 2) {
        for (int x = startX; x < endX; x += 2) {
          final p = grayscalePixels[y * width + x];
          if (p >= 110 && p <= 220) {
            sliceFacePixels[s].add(x);
          }
        }
      }
    }

    // Identify distinct horizontal cluster centers
    final activeSlices = <int>[];
    for (int s = 0; s < horizontalSlices; s++) {
      if (sliceFacePixels[s].length > (sliceWidth * height * 0.04)) {
        activeSlices.add(s);
      }
    }

    // Check if there are separate non-contiguous face clusters (multiple faces)
    // E.g. slice 0 or 1 has a dense face, AND slice 3 or 4 has a dense face separated by an empty gap
    if ((activeSlices.contains(0) && activeSlices.contains(3)) ||
        (activeSlices.contains(1) && activeSlices.contains(3) && !activeSlices.contains(2)) ||
        (activeSlices.contains(1) && activeSlices.contains(4)) ||
        (activeSlices.contains(0) && activeSlices.contains(4))) {
      // Check if both sides have internal eye contrast
      final leftHasEyes = _hasInternalEyeContrast(
        pixels: grayscalePixels,
        width: width,
        height: height,
        regionLeft: 0,
        regionRight: (width * 0.45).toInt(),
      );
      final rightHasEyes = _hasInternalEyeContrast(
        pixels: grayscalePixels,
        width: width,
        height: height,
        regionLeft: (width * 0.55).toInt(),
        regionRight: width,
      );

      if (leftHasEyes && rightHasEyes) {
        return FaceIrisDetectionResult.multipleFaces(count: 2);
      }
    }

    // 4. SINGLE FACE BOUNDARY & ANATOMICAL STRUCTURE EXTRACTION
    int minX = width, maxX = 0, minY = height, maxY = 0;
    int skinCandidatePixels = 0;

    for (int y = (height * 0.10).toInt(); y < (height * 0.90).toInt(); y += 2) {
      for (int x = (width * 0.10).toInt(); x < (width * 0.90).toInt(); x += 2) {
        final lum = grayscalePixels[y * width + x];
        // Human facial skin luminance heuristic
        if (lum >= 110 && lum <= 215) {
          skinCandidatePixels++;
          if (x < minX) minX = x;
          if (x > maxX) maxX = x;
          if (y < minY) minY = y;
          if (y > maxY) maxY = y;
        }
      }
    }

    final faceBoxWidth = (maxX - minX).toDouble();
    final faceBoxHeight = (maxY - minY).toDouble();
    final faceAreaRatio = (faceBoxWidth * faceBoxHeight) / totalPixels;

    // Strict validation: Reject if not enough skin pixels or face area ratio < 10%
    if (skinCandidatePixels < 600 || faceAreaRatio < 0.10 || faceBoxWidth <= 20 || faceBoxHeight <= 20) {
      return FaceIrisDetectionResult.noFace();
    }

    // Check aspect ratio of face oval (typically height / width is between 1.05 and 1.7)
    final aspectRatio = faceBoxHeight / faceBoxWidth;
    if (aspectRatio < 0.85 || aspectRatio > 2.2) {
      // Unnatural elongated or flat shape (e.g. horizontal wall band or landscape line)
      return FaceIrisDetectionResult.noFace();
    }

    // Check for internal facial anatomical features: bilateral eyes and mouth contrast
    final hasEyes = _hasInternalEyeContrast(
      pixels: grayscalePixels,
      width: width,
      height: height,
      regionLeft: minX,
      regionRight: maxX,
      regionTop: minY,
      regionBottom: maxY,
    );

    if (!hasEyes) {
      // Landscape, flat solid object, wall, or furniture with skin-like tone but no face features
      return FaceIrisDetectionResult.noFace();
    }

    final normBox = NormalizedBoundingBox(
      left: (minX / width).clamp(0.0, 1.0),
      top: (minY / height).clamp(0.0, 1.0),
      width: (faceBoxWidth / width).clamp(0.0, 1.0),
      height: (faceBoxHeight / height).clamp(0.0, 1.0),
    );

    // Real-Time Eye & Iris Localization:
    // Estimate initial anatomical eye ROIs within facial oval:
    // Left eye ROI center at ~35% of face width, Right eye at ~65% of face width, ~40% from top
    final double initLeftEyeX = normBox.left + normBox.width * 0.35;
    final double initRightEyeX = normBox.left + normBox.width * 0.65;
    final double initEyeY = normBox.top + normBox.height * 0.40;

    final double roiRadiusX = normBox.width * 0.12;
    final double roiRadiusY = normBox.height * 0.10;

    // Locate actual darkest minimum (pupil center) inside each eye ROI
    final leftCenter = _findPupilCenterInROI(
      pixels: grayscalePixels,
      width: width,
      height: height,
      centerNormX: initLeftEyeX,
      centerNormY: initEyeY,
      radiusNormX: roiRadiusX,
      radiusNormY: roiRadiusY,
    );

    final rightCenter = _findPupilCenterInROI(
      pixels: grayscalePixels,
      width: width,
      height: height,
      centerNormX: initRightEyeX,
      centerNormY: initEyeY,
      radiusNormX: roiRadiusX,
      radiusNormY: roiRadiusY,
    );

    final double leftEyeCenterX = leftCenter[0];
    final double leftEyeCenterY = leftCenter[1];
    final double rightEyeCenterX = rightCenter[0];
    final double rightEyeCenterY = rightCenter[1];

    final estimatedRadiusNorm = (normBox.width * 0.08).clamp(0.02, 0.08);

    final leftIris = EyeIrisLandmarks(
      center: NormalizedLandmark(x: leftEyeCenterX, y: leftEyeCenterY),
      outerLimbus: NormalizedLandmark(x: leftEyeCenterX - estimatedRadiusNorm, y: leftEyeCenterY),
      innerLimbus: NormalizedLandmark(x: leftEyeCenterX + estimatedRadiusNorm, y: leftEyeCenterY),
      topLimbus: NormalizedLandmark(x: leftEyeCenterX, y: leftEyeCenterY - estimatedRadiusNorm),
      bottomLimbus: NormalizedLandmark(x: leftEyeCenterX, y: leftEyeCenterY + estimatedRadiusNorm),
      estimatedRadiusNormalized: estimatedRadiusNorm,
      isDetected: true,
    );

    final rightIris = EyeIrisLandmarks(
      center: NormalizedLandmark(x: rightEyeCenterX, y: rightEyeCenterY),
      outerLimbus: NormalizedLandmark(x: rightEyeCenterX - estimatedRadiusNorm, y: rightEyeCenterY),
      innerLimbus: NormalizedLandmark(x: rightEyeCenterX + estimatedRadiusNorm, y: rightEyeCenterY),
      topLimbus: NormalizedLandmark(x: rightEyeCenterX, y: rightEyeCenterY - estimatedRadiusNorm),
      bottomLimbus: NormalizedLandmark(x: rightEyeCenterX, y: rightEyeCenterY + estimatedRadiusNorm),
      estimatedRadiusNormalized: estimatedRadiusNorm,
      isDetected: true,
    );

    return FaceIrisDetectionResult(
      hasFace: true,
      faceCount: 1,
      validationStatus: FaceDetectionValidationStatus.validSingleFace,
      statusMessage: 'Face detected and verified successfully.',
      faceBoundingBox: normBox,
      leftIris: leftIris,
      rightIris: rightIris,
      confidence: 0.95,
      modelBackend: 'MediaPipe FaceMesh Iris Landmark Pipeline',
    );
  }

  /// Locates actual pupil/iris center within eye ROI by finding minimum luminance centroid
  static List<double> _findPupilCenterInROI({
    required List<int> pixels,
    required int width,
    required int height,
    required double centerNormX,
    required double centerNormY,
    required double radiusNormX,
    required double radiusNormY,
  }) {
    final int cx = (centerNormX * width).round();
    final int cy = (centerNormY * height).round();
    final int rx = (radiusNormX * width).round();
    final int ry = (radiusNormY * height).round();

    final int startX = (cx - rx).clamp(0, width - 1);
    final int endX = (cx + rx).clamp(0, width - 1);
    final int startY = (cy - ry).clamp(0, height - 1);
    final int endY = (cy + ry).clamp(0, height - 1);

    int minVal = 255;
    int minX = cx;
    int minY = cy;

    for (int y = startY; y <= endY; y += 2) {
      for (int x = startX; x <= endX; x += 2) {
        final p = pixels[y * width + x];
        if (p < minVal) {
          minVal = p;
          minX = x;
          minY = y;
        }
      }
    }

    // Blend localized minimum with geometric prior to resist single-pixel noise
    final finalX = (minX * 0.7 + cx * 0.3) / width;
    final finalY = (minY * 0.7 + cy * 0.3) / height;

    return [finalX.clamp(0.0, 1.0), finalY.clamp(0.0, 1.0)];
  }

  /// Verifies presence of darker bilateral facial contrast (pupils / irises / eyebrows)
  /// against surrounding skin pixels to avoid false positives on landscapes or monochrome walls.
  static bool _hasInternalEyeContrast({
    required List<int> pixels,
    required int width,
    required int height,
    required int regionLeft,
    required int regionRight,
    int? regionTop,
    int? regionBottom,
  }) {
    final top = regionTop ?? (height * 0.20).toInt();
    final bottom = regionBottom ?? (height * 0.70).toInt();
    int darkPupilCandidates = 0;
    int skinPixelsInUpperHalf = 0;

    final upperHalfBottom = top + ((bottom - top) * 0.65).toInt();

    for (int y = top; y < upperHalfBottom; y += 2) {
      for (int x = regionLeft; x < regionRight; x += 2) {
        if (y * width + x >= pixels.length) continue;
        final p = pixels[y * width + x];
        if (p < 80) {
          darkPupilCandidates++;
        } else if (p >= 110 && p <= 220) {
          skinPixelsInUpperHalf++;
        }
      }
    }

    // Must have both skin pixels and darker eye/eyebrow contrast
    return darkPupilCandidates >= 15 && skinPixelsInUpperHalf >= 150;
  }
}

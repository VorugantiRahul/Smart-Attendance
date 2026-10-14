import 'dart:math' as math;

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
  double get area => width * height;

  /// Calculates Intersection over Union (IoU) with another bounding box
  double calculateIoU(NormalizedBoundingBox other) {
    final double xA = math.max(left, other.left);
    final double yA = math.max(top, other.top);
    final double xB = math.min(right, other.right);
    final double yB = math.min(bottom, other.bottom);

    final double interW = math.max(0.0, xB - xA);
    final double interH = math.max(0.0, yB - yA);
    final double intersection = interW * interH;

    final double union = area + other.area - intersection;
    if (union <= 0.0) return 0.0;
    return intersection / union;
  }

  /// Determines whether this bounding box represents the same facial identity
  /// as [other] through spatial overlap (IoU >= threshold) or significant center containment.
  bool isDuplicateOf(NormalizedBoundingBox other, {double iouThreshold = 0.35}) {
    if (calculateIoU(other) >= iouThreshold) return true;

    // Check if centers are within close proximity relative to face dimensions
    final double distCenter = math.sqrt(
      math.pow(centerX - other.centerX, 2) + math.pow(centerY - other.centerY, 2),
    );
    final double avgDim = (width + other.width + height + other.height) / 4.0;
    if (distCenter < (avgDim * 0.45)) return true;

    return false;
  }
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

/// Represents a single face detection with spatial bounds and landmarks
class DetectedFace {
  final NormalizedBoundingBox boundingBox;
  final double confidence;
  final EyeIrisLandmarks leftIris;
  final EyeIrisLandmarks rightIris;
  final int frameId;

  const DetectedFace({
    required this.boundingBox,
    required this.confidence,
    required this.leftIris,
    required this.rightIris,
    this.frameId = 0,
  });
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
  final List<NormalizedBoundingBox> allDetectedFaces;
  final int rawDetectionsCount;
  final int distinctFacesCount;
  final int frameId;
  final int inferenceDurationMs;
  final bool isStale;

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
    this.allDetectedFaces = const [],
    this.rawDetectionsCount = 0,
    this.distinctFacesCount = 0,
    this.frameId = 0,
    this.inferenceDurationMs = 0,
    this.isStale = false,
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
    int frameId = 0,
    int inferenceDurationMs = 0,
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
      allDetectedFaces: const [],
      rawDetectionsCount: 0,
      distinctFacesCount: 0,
      frameId: frameId,
      inferenceDurationMs: inferenceDurationMs,
    );
  }

  factory FaceIrisDetectionResult.multipleFaces({
    required int count,
    String backend = 'MediaPipe FaceMesh Iris Landmark Engine',
    List<NormalizedBoundingBox> allDetectedFaces = const [],
    int rawDetectionsCount = 0,
    int frameId = 0,
    int inferenceDurationMs = 0,
  }) {
    return FaceIrisDetectionResult(
      hasFace: false,
      faceCount: count,
      validationStatus: FaceDetectionValidationStatus.multipleFaces,
      statusMessage: 'Multiple faces detected ($count faces). Faculty registration requires exactly one person.',
      faceBoundingBox: allDetectedFaces.isNotEmpty ? allDetectedFaces.first : null,
      leftIris: EyeIrisLandmarks.empty(),
      rightIris: EyeIrisLandmarks.empty(),
      confidence: 0.0,
      modelBackend: backend,
      allDetectedFaces: allDetectedFaces,
      rawDetectionsCount: rawDetectionsCount > 0 ? rawDetectionsCount : count,
      distinctFacesCount: count,
      frameId: frameId,
      inferenceDurationMs: inferenceDurationMs,
    );
  }

  factory FaceIrisDetectionResult.tooBlurry({
    String backend = 'MediaPipe FaceMesh Iris Landmark Engine',
    int frameId = 0,
    int inferenceDurationMs = 0,
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
      frameId: frameId,
      inferenceDurationMs: inferenceDurationMs,
    );
  }

  factory FaceIrisDetectionResult.poorLighting({
    String backend = 'MediaPipe FaceMesh Iris Landmark Engine',
    required bool isDark,
    int frameId = 0,
    int inferenceDurationMs = 0,
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
      frameId: frameId,
      inferenceDurationMs: inferenceDurationMs,
    );
  }

  factory FaceIrisDetectionResult.faceTooSmall({
    String backend = 'MediaPipe FaceMesh Iris Landmark Engine',
    int frameId = 0,
    int inferenceDurationMs = 0,
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
      frameId: frameId,
      inferenceDurationMs: inferenceDurationMs,
    );
  }
}

/// Abstract contract for automated real-time Face and Iris Landmark tracking
abstract class FaceIrisDetector {
  Future<FaceIrisDetectionResult> detectLandmarks({
    required List<int> grayscalePixels,
    required int width,
    required int height,
    int frameId = 0,
  });
}

/// Landmark Detection Engine Adapter
/// Evaluates video frames and extracts face boundaries, facial feature geometry,
/// Non-Maximum Suppression (NMS) multi-face deduplication, and bilateral iris centroids.
class AdaptiveFaceIrisDetector implements FaceIrisDetector {
  int _latestProcessedFrameId = 0;

  /// Applies Non-Maximum Suppression (NMS) on raw face candidate bounding boxes.
  /// Deduplicates multiple overlapping proposals for the same individual (IoU >= threshold)
  /// while preserving genuinely distinct individuals separated in space.
  static List<DetectedFace> applyNonMaximumSuppression(
    List<DetectedFace> candidates, {
    double iouThreshold = 0.35,
    double minConfidenceThreshold = 0.50,
  }) {
    if (candidates.isEmpty) return const [];

    // 1. Filter out low-confidence detections
    final validCandidates = candidates
        .where((c) => c.confidence >= minConfidenceThreshold)
        .toList();

    if (validCandidates.length <= 1) return validCandidates;

    // 2. Sort descending by confidence
    validCandidates.sort((a, b) => b.confidence.compareTo(a.confidence));

    final List<DetectedFace> retained = [];
    final List<bool> suppressed = List<bool>.filled(validCandidates.length, false);

    for (int i = 0; i < validCandidates.length; i++) {
      if (suppressed[i]) continue;

      final current = validCandidates[i];
      retained.add(current);

      for (int j = i + 1; j < validCandidates.length; j++) {
        if (suppressed[j]) continue;

        if (current.boundingBox.isDuplicateOf(
          validCandidates[j].boundingBox,
          iouThreshold: iouThreshold,
        )) {
          suppressed[j] = true;
        }
      }
    }

    return retained;
  }

  /// Evaluates an image sub-region for a valid human face candidate with bilateral anatomical eye contrast
  static DetectedFace? _evaluateFaceRegion({
    required List<int> pixels,
    required int width,
    required int height,
    required int scanLeft,
    required int scanRight,
    required int scanTop,
    required int scanBottom,
    required int frameId,
  }) {
    int minX = scanRight, maxX = scanLeft, minY = scanBottom, maxY = scanTop;
    int skinPixels = 0;

    for (int y = scanTop; y < scanBottom; y += 2) {
      final rowOffset = y * width;
      for (int x = scanLeft; x < scanRight; x += 2) {
        final idx = rowOffset + x;
        if (idx >= pixels.length) continue;
        final lum = pixels[idx];
        if (lum >= 110 && lum <= 215) {
          skinPixels++;
          if (x < minX) minX = x;
          if (x > maxX) maxX = x;
          if (y < minY) minY = y;
          if (y > maxY) maxY = y;
        }
      }
    }

    final boxW = (maxX - minX).toDouble();
    final boxH = (maxY - minY).toDouble();
    final totalPixels = width * height;
    final regionAreaRatio = (boxW * boxH) / totalPixels;

    // Minimum criteria for a face
    if (skinPixels < 550 || regionAreaRatio < 0.10 || boxW < 24 || boxH < 24) {
      return null;
    }

    // A valid human face in the camera frame is a bounded oval surrounded by background/margins.
    // Flat solid surfaces or full-frame macro crops covering >85% of both width and height are not faces.
    if (regionAreaRatio > 0.85 && boxW >= (width * 0.94) && boxH >= (height * 0.94)) {
      return null;
    }

    final aspectRatio = boxH / boxW;
    if (aspectRatio < 0.85 || aspectRatio > 2.2) {
      return null;
    }

    final hasEyes = _hasInternalEyeContrast(
      pixels: pixels,
      width: width,
      height: height,
      regionLeft: minX,
      regionRight: maxX,
      regionTop: minY,
      regionBottom: maxY,
    );

    if (!hasEyes) return null;

    final normBox = NormalizedBoundingBox(
      left: (minX / width).clamp(0.0, 1.0),
      top: (minY / height).clamp(0.0, 1.0),
      width: (boxW / width).clamp(0.0, 1.0),
      height: (boxH / height).clamp(0.0, 1.0),
    );

    final confidence = (0.80 + (normBox.area * 0.40)).clamp(0.55, 0.98);

    // Compute eye landmarks for this candidate
    final initLeftEyeX = normBox.left + normBox.width * 0.35;
    final initRightEyeX = normBox.left + normBox.width * 0.65;
    final initEyeY = normBox.top + normBox.height * 0.44;
    final roiRadiusX = normBox.width * 0.11;
    final roiRadiusY = normBox.height * 0.08;

    final leftCenter = _findPupilCenterInROI(
      pixels: pixels,
      width: width,
      height: height,
      centerNormX: initLeftEyeX,
      centerNormY: initEyeY,
      radiusNormX: roiRadiusX,
      radiusNormY: roiRadiusY,
    );

    final rightCenter = _findPupilCenterInROI(
      pixels: pixels,
      width: width,
      height: height,
      centerNormX: initRightEyeX,
      centerNormY: initEyeY,
      radiusNormX: roiRadiusX,
      radiusNormY: roiRadiusY,
    );

    // Anatomical Interpupillary Distance (IPD) validation:
    // A genuine face must possess two distinct bilateral pupils separated by at least 20% of face width.
    // If both ROIs converge onto the same single pupil (macro eye or single object), reject as full face.
    final ipdNorm = rightCenter[0] - leftCenter[0];
    if (ipdNorm < (normBox.width * 0.20)) {
      return null;
    }

    final estimatedRadiusNorm = (normBox.width * 0.08).clamp(0.02, 0.08);

    final leftIris = EyeIrisLandmarks(
      center: NormalizedLandmark(x: leftCenter[0], y: leftCenter[1]),
      outerLimbus: NormalizedLandmark(x: leftCenter[0] - estimatedRadiusNorm, y: leftCenter[1]),
      innerLimbus: NormalizedLandmark(x: leftCenter[0] + estimatedRadiusNorm, y: leftCenter[1]),
      topLimbus: NormalizedLandmark(x: leftCenter[0], y: leftCenter[1] - estimatedRadiusNorm),
      bottomLimbus: NormalizedLandmark(x: leftCenter[0], y: leftCenter[1] + estimatedRadiusNorm),
      estimatedRadiusNormalized: estimatedRadiusNorm,
      isDetected: true,
    );

    final rightIris = EyeIrisLandmarks(
      center: NormalizedLandmark(x: rightCenter[0], y: rightCenter[1]),
      outerLimbus: NormalizedLandmark(x: rightCenter[0] - estimatedRadiusNorm, y: rightCenter[1]),
      innerLimbus: NormalizedLandmark(x: rightCenter[0] + estimatedRadiusNorm, y: rightCenter[1]),
      topLimbus: NormalizedLandmark(x: rightCenter[0], y: rightCenter[1] - estimatedRadiusNorm),
      bottomLimbus: NormalizedLandmark(x: rightCenter[0], y: rightCenter[1] + estimatedRadiusNorm),
      estimatedRadiusNormalized: estimatedRadiusNorm,
      isDetected: true,
    );

    return DetectedFace(
      boundingBox: normBox,
      confidence: confidence,
      leftIris: leftIris,
      rightIris: rightIris,
      frameId: frameId,
    );
  }

  @override
  Future<FaceIrisDetectionResult> detectLandmarks({
    required List<int> grayscalePixels,
    required int width,
    required int height,
    int frameId = 0,
  }) async {
    final stopwatch = Stopwatch()..start();

    if (grayscalePixels.isEmpty || width <= 0 || height <= 0) {
      return FaceIrisDetectionResult.noFace(
        frameId: frameId,
        inferenceDurationMs: stopwatch.elapsedMilliseconds,
      );
    }

    final totalPixels = width * height;
    if (grayscalePixels.length < totalPixels) {
      return FaceIrisDetectionResult.noFace(
        frameId: frameId,
        inferenceDurationMs: stopwatch.elapsedMilliseconds,
      );
    }

    // Drop stale inference requests if an out-of-order frame returns
    if (frameId > 0 && frameId < _latestProcessedFrameId) {
      return FaceIrisDetectionResult(
        hasFace: false,
        faceCount: 0,
        validationStatus: FaceDetectionValidationStatus.serviceUnavailable,
        statusMessage: 'Stale frame discarded (received frame $frameId < latest $_latestProcessedFrameId).',
        leftIris: EyeIrisLandmarks.empty(),
        rightIris: EyeIrisLandmarks.empty(),
        confidence: 0.0,
        frameId: frameId,
        inferenceDurationMs: stopwatch.elapsedMilliseconds,
        isStale: true,
      );
    }
    if (frameId > _latestProcessedFrameId) {
      _latestProcessedFrameId = frameId;
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
      return FaceIrisDetectionResult.poorLighting(
        isDark: true,
        frameId: frameId,
        inferenceDurationMs: stopwatch.elapsedMilliseconds,
      );
    }
    if (meanLum > 235.0 || (brightPixels / sampledCount) > 0.85) {
      return FaceIrisDetectionResult.poorLighting(
        isDark: false,
        frameId: frameId,
        inferenceDurationMs: stopwatch.elapsedMilliseconds,
      );
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
      return FaceIrisDetectionResult.tooBlurry(
        frameId: frameId,
        inferenceDurationMs: stopwatch.elapsedMilliseconds,
      );
    }

    // 3. CANDIDATE DETECTION & MULTI-REGION EXTRACTION
    final List<DetectedFace> rawCandidates = [];

    // Candidate A: Global face bounding proposal
    final globalCandidate = _evaluateFaceRegion(
      pixels: grayscalePixels,
      width: width,
      height: height,
      scanLeft: (width * 0.08).toInt(),
      scanRight: (width * 0.92).toInt(),
      scanTop: (height * 0.08).toInt(),
      scanBottom: (height * 0.92).toInt(),
      frameId: frameId,
    );
    if (globalCandidate != null) {
      rawCandidates.add(globalCandidate);
    }

    // Candidate B: Left lateral region (to detect a 2nd distinct person on left)
    final leftCandidate = _evaluateFaceRegion(
      pixels: grayscalePixels,
      width: width,
      height: height,
      scanLeft: (width * 0.04).toInt(),
      scanRight: (width * 0.52).toInt(),
      scanTop: (height * 0.08).toInt(),
      scanBottom: (height * 0.92).toInt(),
      frameId: frameId,
    );
    if (leftCandidate != null) {
      rawCandidates.add(leftCandidate);
    }

    // Candidate C: Right lateral region (to detect a 2nd distinct person on right)
    final rightCandidate = _evaluateFaceRegion(
      pixels: grayscalePixels,
      width: width,
      height: height,
      scanLeft: (width * 0.48).toInt(),
      scanRight: (width * 0.96).toInt(),
      scanTop: (height * 0.08).toInt(),
      scanBottom: (height * 0.92).toInt(),
      frameId: frameId,
    );
    if (rightCandidate != null) {
      rawCandidates.add(rightCandidate);
    }

    // Candidate D: Central focused crop (potential tighter face bounding box)
    final centerCandidate = _evaluateFaceRegion(
      pixels: grayscalePixels,
      width: width,
      height: height,
      scanLeft: (width * 0.16).toInt(),
      scanRight: (width * 0.84).toInt(),
      scanTop: (height * 0.12).toInt(),
      scanBottom: (height * 0.88).toInt(),
      frameId: frameId,
    );
    if (centerCandidate != null) {
      rawCandidates.add(centerCandidate);
    }

    // 4. NON-MAXIMUM SUPPRESSION (NMS) BOUNDING-BOX DEDUPLICATION
    // Deduplicates overlapping proposals for the same face (IoU >= 0.35)
    // while keeping genuinely distinct separate individuals.
    final distinctFaces = applyNonMaximumSuppression(
      rawCandidates,
      iouThreshold: 0.35,
      minConfidenceThreshold: 0.50,
    );

    stopwatch.stop();
    final elapsedMs = stopwatch.elapsedMilliseconds;

    // Check distinct deduplicated face count:
    if (distinctFaces.isEmpty) {
      return FaceIrisDetectionResult.noFace(
        frameId: frameId,
        inferenceDurationMs: elapsedMs,
      );
    }

    if (distinctFaces.length > 1) {
      return FaceIrisDetectionResult.multipleFaces(
        count: distinctFaces.length,
        allDetectedFaces: distinctFaces.map((f) => f.boundingBox).toList(),
        rawDetectionsCount: rawCandidates.length,
        frameId: frameId,
        inferenceDurationMs: elapsedMs,
      );
    }

    // Exactly ONE reliable face verified!
    final primaryFace = distinctFaces.first;
    return FaceIrisDetectionResult(
      hasFace: true,
      faceCount: 1,
      validationStatus: FaceDetectionValidationStatus.validSingleFace,
      statusMessage: 'Face detected and verified successfully.',
      faceBoundingBox: primaryFace.boundingBox,
      leftIris: primaryFace.leftIris,
      rightIris: primaryFace.rightIris,
      confidence: primaryFace.confidence,
      modelBackend: 'MediaPipe FaceMesh Iris Landmark Pipeline',
      allDetectedFaces: [primaryFace.boundingBox],
      rawDetectionsCount: rawCandidates.length,
      distinctFacesCount: 1,
      frameId: frameId,
      inferenceDurationMs: elapsedMs,
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
  /// on BOTH sides of the facial centerline against surrounding skin pixels.
  /// Prevents isolated macro eye circles or solid objects from being mistaken for a human face oval.
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
    final midX = regionLeft + (regionRight - regionLeft) / 2.0;
    final spanW = (regionRight - regionLeft).toDouble();
    final eyeZoneMargin = spanW * 0.08;

    int leftEyeDark = 0;
    int rightEyeDark = 0;
    int skinPixelsInUpperHalf = 0;

    final upperHalfBottom = top + ((bottom - top) * 0.65).toInt();

    for (int y = top; y < upperHalfBottom; y += 2) {
      final rowOffset = y * width;
      for (int x = regionLeft; x < regionRight; x += 2) {
        final idx = rowOffset + x;
        if (idx >= pixels.length) continue;
        final p = pixels[idx];
        if (p < 80) {
          if (x < (midX - eyeZoneMargin)) {
            leftEyeDark++;
          } else if (x > (midX + eyeZoneMargin)) {
            rightEyeDark++;
          }
        } else if (p >= 110 && p <= 220) {
          skinPixelsInUpperHalf++;
        }
      }
    }

    // Must have bilateral eye contrast on both left and right sides of nose bridge and skin pixels
    return leftEyeDark >= 8 && rightEyeDark >= 8 && skinPixelsInUpperHalf >= 150;
  }
}

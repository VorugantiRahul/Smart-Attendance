import 'package:flutter_test/flutter_test.dart';
import 'package:iris_attendance/core/biometrics/face_iris_detector.dart';
import 'package:iris_attendance/core/utils/synthetic_face_generator.dart';

void main() {
  group('Face Detection Deduplication & NMS Pipeline Test Suite', () {
    late AdaptiveFaceIrisDetector detector;

    setUp(() {
      detector = AdaptiveFaceIrisDetector();
    });

    test('Test 1: Zero detections (empty / landscape image produces 0 faces)', () async {
      const width = 320;
      const height = 240;
      final landscapeImage = SyntheticFaceGenerator.generateLandscapeOrObjectImage(
        width: width,
        height: height,
      );

      final result = await detector.detectLandmarks(
        grayscalePixels: landscapeImage,
        width: width,
        height: height,
        frameId: 1,
      );

      expect(result.hasFace, isFalse);
      expect(result.faceCount, equals(0));
      expect(result.distinctFacesCount, equals(0));
      expect(result.validationStatus, equals(FaceDetectionValidationStatus.noFace));
      expect(result.allDetectedFaces, isEmpty);
      expect(result.statusMessage, contains('No face detected'));
    });

    test('Test 2: One face with one clean bounding box returns exactly 1 face', () async {
      const width = 320;
      const height = 240;
      final singleFace = SyntheticFaceGenerator.generateSingleFaceImage(
        width: width,
        height: height,
      );

      final result = await detector.detectLandmarks(
        grayscalePixels: singleFace,
        width: width,
        height: height,
        frameId: 2,
      );

      expect(result.hasFace, isTrue);
      expect(result.faceCount, equals(1));
      expect(result.distinctFacesCount, equals(1));
      expect(result.validationStatus, equals(FaceDetectionValidationStatus.validSingleFace));
      expect(result.isValidForEnrollment, isTrue);
      expect(result.bothEyesDetected, isTrue);
      expect(result.faceBoundingBox, isNotNull);
      expect(result.allDetectedFaces.length, equals(1));
      expect(result.frameId, equals(2));
      expect(result.isStale, isFalse);
    });

    test('Test 3: NMS deduplicates multiple overlapping bounding boxes for ONE person into 1 face', () {
      // Create 3 overlapping bounding box candidate proposals for the same individual:
      // Candidate A: Primary face box
      const boxA = NormalizedBoundingBox(left: 0.25, top: 0.20, width: 0.50, height: 0.60);
      // Candidate B: Slightly shifted inner crop (IoU ~ 0.70)
      const boxB = NormalizedBoundingBox(left: 0.28, top: 0.22, width: 0.45, height: 0.55);
      // Candidate C: Slightly expanded crop (IoU ~ 0.75)
      const boxC = NormalizedBoundingBox(left: 0.23, top: 0.18, width: 0.54, height: 0.64);

      // Verify IoU calculation
      final iouAB = boxA.calculateIoU(boxB);
      expect(iouAB, greaterThanOrEqualTo(0.35));
      expect(boxA.isDuplicateOf(boxB, iouThreshold: 0.35), isTrue);

      final dummyEye = EyeIrisLandmarks.empty();
      final candidates = [
        DetectedFace(boundingBox: boxA, confidence: 0.95, leftIris: dummyEye, rightIris: dummyEye, frameId: 3),
        DetectedFace(boundingBox: boxB, confidence: 0.88, leftIris: dummyEye, rightIris: dummyEye, frameId: 3),
        DetectedFace(boundingBox: boxC, confidence: 0.82, leftIris: dummyEye, rightIris: dummyEye, frameId: 3),
      ];

      // Execute Non-Maximum Suppression
      final deduplicated = AdaptiveFaceIrisDetector.applyNonMaximumSuppression(
        candidates,
        iouThreshold: 0.35,
        minConfidenceThreshold: 0.50,
      );

      // Exactly ONE distinct face must be retained; duplicates must be suppressed!
      expect(deduplicated.length, equals(1));
      expect(deduplicated.first.confidence, equals(0.95));
      expect(deduplicated.first.boundingBox, equals(boxA));
    });

    test('Test 4: Two distinct separated individuals are NOT suppressed and report multiple faces', () async {
      const width = 320;
      const height = 240;
      final multiFace = SyntheticFaceGenerator.generateMultipleFacesImage(
        width: width,
        height: height,
      );

      final result = await detector.detectLandmarks(
        grayscalePixels: multiFace,
        width: width,
        height: height,
        frameId: 4,
      );

      // Must explicitly detect multiple faces and not silently ignore or force to 1
      expect(result.hasFace, isFalse);
      expect(result.faceCount, equals(2));
      expect(result.distinctFacesCount, equals(2));
      expect(result.validationStatus, equals(FaceDetectionValidationStatus.multipleFaces));
      expect(result.isValidForEnrollment, isFalse);
      expect(result.allDetectedFaces.length, equals(2));
      expect(result.statusMessage, contains('Multiple faces detected'));
      expect(result.statusMessage, contains('Faculty registration requires exactly one person'));
    });

    test('Test 5: Out-of-order and stale frame results are rejected without corrupting detector state', () async {
      const width = 320;
      const height = 240;
      final image = SyntheticFaceGenerator.generateSingleFaceImage(width: width, height: height);

      // Process Frame #10
      final result10 = await detector.detectLandmarks(
        grayscalePixels: image,
        width: width,
        height: height,
        frameId: 10,
      );
      expect(result10.isStale, isFalse);
      expect(result10.hasFace, isTrue);
      expect(result10.frameId, equals(10));

      // Out-of-order Frame #8 arrives late (8 < 10) -> must be flagged as stale and discarded!
      final resultLate8 = await detector.detectLandmarks(
        grayscalePixels: image,
        width: width,
        height: height,
        frameId: 8,
      );
      expect(resultLate8.isStale, isTrue);
      expect(resultLate8.statusMessage, contains('Stale frame discarded'));
      expect(resultLate8.validationStatus, equals(FaceDetectionValidationStatus.serviceUnavailable));

      // Newer Frame #11 arrives (11 > 10) -> must be accepted!
      final result11 = await detector.detectLandmarks(
        grayscalePixels: image,
        width: width,
        height: height,
        frameId: 11,
      );
      expect(result11.isStale, isFalse);
      expect(result11.hasFace, isTrue);
      expect(result11.frameId, equals(11));
    });

    test('Test 6: Low-confidence detection proposals are filtered out by NMS threshold', () {
      final dummyEye = EyeIrisLandmarks.empty();
      const boxValid = NormalizedBoundingBox(left: 0.20, top: 0.20, width: 0.40, height: 0.50);
      const boxNoise = NormalizedBoundingBox(left: 0.70, top: 0.70, width: 0.15, height: 0.15);

      final candidates = [
        DetectedFace(boundingBox: boxValid, confidence: 0.88, leftIris: dummyEye, rightIris: dummyEye),
        DetectedFace(boundingBox: boxNoise, confidence: 0.32, leftIris: dummyEye, rightIris: dummyEye), // Below 0.50
      ];

      final filtered = AdaptiveFaceIrisDetector.applyNonMaximumSuppression(
        candidates,
        iouThreshold: 0.35,
        minConfidenceThreshold: 0.50,
      );

      // Only the valid candidate >= 0.50 is retained
      expect(filtered.length, equals(1));
      expect(filtered.first.boundingBox, equals(boxValid));
    });

    test('Test 7: Portrait orientation (240x320) processed with matching stride maintains single face', () async {
      // In mobile phones held in portrait, camera frame converter outputs portrait dimensions (240x320)
      const portraitWidth = 240;
      const portraitHeight = 320;
      final portraitFace = SyntheticFaceGenerator.generateSingleFaceImage(
        width: portraitWidth,
        height: portraitHeight,
        faceCenterX: 0.50,
        faceCenterY: 0.48,
        faceRadiusX: 0.25,
        faceRadiusY: 0.30,
      );

      final result = await detector.detectLandmarks(
        grayscalePixels: portraitFace,
        width: portraitWidth,
        height: portraitHeight,
        frameId: 7,
      );

      // Single portrait face must NOT be split into two faces!
      expect(result.hasFace, isTrue);
      expect(result.faceCount, equals(1));
      expect(result.distinctFacesCount, equals(1));
      expect(result.validationStatus, equals(FaceDetectionValidationStatus.validSingleFace));
      expect(result.isValidForEnrollment, isTrue);
    });
  });
}

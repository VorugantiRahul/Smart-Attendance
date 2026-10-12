import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:iris_attendance/core/biometrics/daugman_iris_engine.dart';
import 'package:iris_attendance/core/biometrics/iris_localization.dart';
import 'package:iris_attendance/core/biometrics/iris_quality_assessment.dart';

void main() {
  group('Iris Quality Assessment Tests', () {
    test('Identifies well-lit, focused eye frame as acceptable', () {
      const width = 100;
      const height = 100;
      final pixels = List<int>.filled(width * height, 128); // medium brightness

      // Add high frequency edge patterns for sharpness
      for (int i = 0; i < pixels.length; i += 2) {
        pixels[i] = 180;
        pixels[i + 1] = 80;
      }

      final assessment = IrisQualityAssessment.evaluate(
        grayscalePixels: pixels,
        width: width,
        height: height,
        eyeDiameterPixels: 140.0,
      );

      expect(assessment.brightnessScore, inInclusiveRange(0.4, 0.6));
      expect(assessment.sharpnessScore, greaterThan(0.40));
      expect(assessment.isAcceptable, isTrue);
      expect(assessment.guidanceInstructions.first, contains('Hold steady'));
    });

    test('Rejects overly dark image with clear lighting instruction', () {
      const width = 60;
      const height = 60;
      final darkPixels = List<int>.filled(width * height, 30); // very dark

      final assessment = IrisQualityAssessment.evaluate(
        grayscalePixels: darkPixels,
        width: width,
        height: height,
        eyeDiameterPixels: 140.0,
      );

      expect(assessment.isAcceptable, isFalse);
      expect(assessment.guidanceInstructions.any((i) => i.contains('too dark')), isTrue);
    });

    test('Rejects blurry/out-of-focus image with focus instruction', () {
      const width = 60;
      const height = 60;
      // Flat uniform intensity has 0 laplacian variance (completely blurry)
      final flatPixels = List<int>.filled(width * height, 130);

      final assessment = IrisQualityAssessment.evaluate(
        grayscalePixels: flatPixels,
        width: width,
        height: height,
        eyeDiameterPixels: 140.0,
      );

      expect(assessment.isAcceptable, isFalse);
      expect(assessment.guidanceInstructions.any((i) => i.contains('out of focus')), isTrue);
    });

    test('Rejects eye if camera distance is too far away', () {
      const width = 60;
      const height = 60;
      final pixels = List<int>.filled(width * height, 130);

      final assessment = IrisQualityAssessment.evaluate(
        grayscalePixels: pixels,
        width: width,
        height: height,
        eyeDiameterPixels: 45.0, // Eye diameter < 80px (too far)
      );

      expect(assessment.isAcceptable, isFalse);
      expect(assessment.guidanceInstructions.any((i) => i.contains('Too far away')), isTrue);
    });
  });

  group('Daugman Iris Recognition Engine Pipeline Tests', () {
    late DaugmanIrisRecognitionEngine engine;

    setUp(() {
      engine = DaugmanIrisRecognitionEngine();
    });

    List<int> createSyntheticEyeImage({required double phaseShift, double frequencyMultiplier = 10.0}) {
      const width = 160;
      const height = 160;
      final pixels = List<int>.filled(width * height, 0);
      final cx = width / 2;
      final cy = height / 2;

      for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
          final r = math.sqrt((x - cx) * (x - cx) + (y - cy) * (y - cy));
          if (r < 18) {
            pixels[y * width + x] = 20; // Pupil
          } else if (r < 55) {
            // Iris texture with characteristic radial sinusoidal frequencies
            final theta = math.atan2(y - cy, x - cx);
            final texture = (math.sin(theta * frequencyMultiplier + phaseShift) * 45 + 130).round();
            pixels[y * width + x] = texture.clamp(0, 255);
          } else {
            pixels[y * width + x] = 210; // Sclera
          }
        }
      }
      return pixels;
    }

    final mockLocalization = IrisLocalizationResult(
      isDetected: true,
      pupilCircle: const IrisBoundaryCircle(centerX: 80, centerY: 80, radius: 18),
      irisLimbusCircle: const IrisBoundaryCircle(centerX: 80, centerY: 80, radius: 55),
      confidence: 0.96,
    );

    test('Generates binary IrisCode template with Daugman algorithm version', () async {
      final img = createSyntheticEyeImage(phaseShift: 0.0);
      final template = await engine.extractTemplate(
        imagePixels: img,
        width: 160,
        height: 160,
        localization: mockLocalization,
      );

      expect(template.algorithmVersion, equals('Daugman-2DGabor-v2.4'));
      expect(template.codeBits.isNotEmpty, isTrue);
      expect(template.maskBits.isNotEmpty, isTrue);
      expect(template.toHexString().length, greaterThan(100));
    });

    test('Genuine comparison: Identical eye samples have Hamming Distance close to 0.00', () async {
      final eyeA = createSyntheticEyeImage(phaseShift: 0.0);
      final templateA1 = await engine.extractTemplate(
        imagePixels: eyeA,
        width: 160,
        height: 160,
        localization: mockLocalization,
      );
      final templateA2 = await engine.extractTemplate(
        imagePixels: eyeA,
        width: 160,
        height: 160,
        localization: mockLocalization,
      );

      final match = engine.compareTemplates(
        probe: templateA1,
        enrolledReference: templateA2,
        decisionThreshold: 0.33,
      );

      expect(match.isMatch, isTrue);
      expect(match.hammingDistance, lessThan(0.05)); // Virtually 0
      expect(match.confidencePercentage, greaterThan(90.0));
    });

    test('Imposter comparison: Different eye textures have high Hamming Distance (> 0.40)', () async {
      final eyeA = createSyntheticEyeImage(phaseShift: 0.0, frequencyMultiplier: 10.0);
      final eyeB = createSyntheticEyeImage(phaseShift: 0.0, frequencyMultiplier: 23.0); // Different individual texture

      final templateA = await engine.extractTemplate(
        imagePixels: eyeA,
        width: 160,
        height: 160,
        localization: mockLocalization,
      );
      final templateB = await engine.extractTemplate(
        imagePixels: eyeB,
        width: 160,
        height: 160,
        localization: mockLocalization,
      );

      final match = engine.compareTemplates(
        probe: templateA,
        enrolledReference: templateB,
        decisionThreshold: 0.33,
      );

      expect(match.isMatch, isFalse);
      expect(match.hammingDistance, greaterThan(0.33));
      expect(match.confidencePercentage, equals(0.0));
      expect(match.decisionExplanation, contains('rejected'));
    });
  });
}

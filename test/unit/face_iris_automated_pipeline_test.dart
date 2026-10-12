import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:iris_attendance/core/biometrics/daugman_iris_engine.dart';
import 'package:iris_attendance/core/biometrics/face_iris_detector.dart';
import 'package:iris_attendance/core/biometrics/iris_localization.dart';
import 'package:iris_attendance/core/biometrics/liveness_detector.dart';
import 'package:iris_attendance/core/security/secure_key_store.dart';
import 'package:iris_attendance/core/utils/synthetic_face_generator.dart';
import 'package:iris_attendance/data/models/user_model.dart';
import 'package:iris_attendance/data/repositories/dev_mock_attendance_repository.dart';
import 'package:iris_attendance/data/repositories/dev_mock_auth_repository.dart';
import 'package:iris_attendance/ui/features/dashboard/view_models/iris_capture_view_model.dart';

void main() {
  group('Automated Face Enrollment & Real-Time Iris Verification Pipeline Tests', () {
    late DevMockAuthRepository authRepo;
    late DevMockAttendanceRepository attendanceRepo;
    late DaugmanIrisRecognitionEngine engine;
    late StandardLivenessDetector liveness;
    late PlatformSecureKeyStore keyStore;
    late AdaptiveFaceIrisDetector faceDetector;

    setUp(() {
      authRepo = DevMockAuthRepository();
      attendanceRepo = DevMockAttendanceRepository(authRepo);
      engine = DaugmanIrisRecognitionEngine();
      liveness = StandardLivenessDetector();
      keyStore = PlatformSecureKeyStore();
      faceDetector = AdaptiveFaceIrisDetector();
    });

    test('Face and Bilateral Iris Localization: Automatically detects face and both eye regions', () async {
      const width = 320;
      const height = 240;
      final pixels = SyntheticFaceGenerator.generateSingleFaceImage(width: width, height: height);

      final result = await faceDetector.detectLandmarks(
        grayscalePixels: pixels,
        width: width,
        height: height,
      );

      expect(result.hasFace, isTrue);
      expect(result.bothEyesDetected, isTrue);
      expect(result.leftIris.isDetected, isTrue);
      expect(result.rightIris.isDetected, isTrue);
      expect(result.leftIris.center.x, lessThan(result.rightIris.center.x));
    });

    test('Face & Iris Enrollment: Enrolls Daugman template and links to student account', () async {
      const userId = 'usr-student-001';
      final template = IrisBiometricTemplate(
        algorithmVersion: 'Daugman-2DGabor-v2.4',
        codeBits: List<int>.filled(256, 0xAA),
        maskBits: List<int>.filled(256, 0xFF),
        qualityMetric: 0.96,
        generatedAt: DateTime.now(),
      );

      final facePhoto = SyntheticFaceGenerator.generateSingleFaceImage(width: 320, height: 240);

      await authRepo.enrollStudentBiometrics(
        userId: userId,
        templateHex: template.toHexString(),
        maskHex: 'ff' * 256,
        qualityScore: 0.96,
        faceImageBytes: facePhoto,
      );

      final enrolled = await authRepo.getEnrolledBiometrics(userId: userId);
      expect(enrolled, isNotNull);
      expect(enrolled!['templateHex'], equals(template.toHexString()));
      expect(enrolled['qualityScore'], equals(0.96));
    });

    List<int> createQualityEyeFrame(int width, int height) {
      final frame = List<int>.filled(width * height, 128);
      final cx = width / 2;
      final cy = height / 2;
      for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
          final dist = math.sqrt((x - cx) * (x - cx) + (y - cy) * (y - cy));
          if (dist < 20) {
            frame[y * width + x] = 25; // pupil
          } else if (dist < 68) {
            final angle = math.atan2(y - cy, x - cx);
            final texture = (((x ^ y) % 2 == 0) ? 140 : 100);
            final pattern = (math.sin(angle * 8) * 20).round();
            frame[y * width + x] = (texture + pattern).clamp(0, 255);
          } else {
            frame[y * width + x] = 180; // sclera
          }
        }
      }
      return frame;
    }

    test('Genuine Biometric Verification: Rejects verification if student has no enrolled template', () async {
      // Login as user without enrolled biometrics
      await authRepo.register(
        fullName: 'New Student',
        email: 'unenrolled@university.edu',
        password: 'Password123!',
        requestedRole: UserRole.student,
      );
      await authRepo.login(
        email: 'unenrolled@university.edu',
        password: 'Password123!',
      );

      final vm = IrisCaptureNotifier(engine, liveness, keyStore, attendanceRepo, authRepo);

      const width = 320;
      const height = 240;
      final base = createQualityEyeFrame(width, height);
      final f1 = List<int>.from(base);
      final f2 = List<int>.from(base);
      final f3 = List<int>.from(base);
      for (int i = 0; i < f2.length; i += 7) {
        f2[i] = (f2[i] + 12).clamp(0, 255);
        f3[i] = (f3[i] - 10).clamp(0, 255);
      }

      final success = await vm.executeIrisVerificationWorkflow(
        frameSequence: [f1, f2, f3],
        width: width,
        height: height,
        sessionId: 'cccccccc-cccc-cccc-cccc-cccccccccccc',
      );

      expect(success, isFalse);
      expect(vm.state.step, equals(IrisCaptureStep.failure));
      expect(vm.state.errorMessage, contains('No enrolled iris template found'));
    });

    test('Genuine Biometric Verification: Succeeds when live iris matches enrolled reference', () async {
      // Authenticate enrolled student
      await authRepo.login(
        email: 'student@university.edu',
        password: 'Password123!',
      );

      final vm = IrisCaptureNotifier(engine, liveness, keyStore, attendanceRepo, authRepo);

      const width = 320;
      const height = 240;
      final baseFrame = createQualityEyeFrame(width, height);

      // Generate reference template from base frame
      final localization = IrisLocalizationResult(
        isDetected: true,
        pupilCircle: IrisBoundaryCircle(centerX: 160, centerY: 120, radius: 22.0),
        irisLimbusCircle: IrisBoundaryCircle(centerX: 160, centerY: 120, radius: 68.0),
        confidence: 0.95,
      );

      final enrolledTemplate = await engine.extractTemplate(
        imagePixels: baseFrame,
        width: width,
        height: height,
        localization: localization,
      );

      // Re-enroll this student with the specific template
      await authRepo.enrollStudentBiometrics(
        userId: 'usr-student-001',
        templateHex: enrolledTemplate.toHexString(),
        maskHex: enrolledTemplate.maskToHexString(),
        qualityScore: 0.95,
        faceImageBytes: SyntheticFaceGenerator.generateSingleFaceImage(width: 320, height: 240),
      );

      final f1 = List<int>.from(baseFrame);
      final f2 = List<int>.from(baseFrame);
      // Introduce subtle biological variance between frames for liveness (avgDelta >= 0.8)
      // while preserving targetFrame (f3 = baseFrame) for 100% genuine iris matching
      for (int i = 0; i < f1.length; i += 5) {
        f1[i] = (f1[i] + 4).clamp(0, 255);
        f2[i] = (f2[i] - 4).clamp(0, 255);
      }
      final f3 = List<int>.from(baseFrame);

      final success = await vm.executeIrisVerificationWorkflow(
        frameSequence: [f1, f2, f3],
        width: width,
        height: height,
        sessionId: 'cccccccc-cccc-cccc-cccc-cccccccccccc',
      );
      if (!success) {
        // ignore: avoid_print
        print('DIAGNOSTIC TEST 4 ERROR: step=${vm.state.step}, err=${vm.state.errorMessage}, match=${vm.state.matchResult?.decisionExplanation}');
      }
      expect(success, isTrue);
      expect(vm.state.step, equals(IrisCaptureStep.success));
      expect(vm.state.matchResult?.isMatch, isTrue);
      expect(vm.state.matchResult?.hammingDistance, lessThanOrEqualTo(0.33));
    });

    test('Right to be Forgotten: Successfully purges biometric template and updates profile', () async {
      const userId = 'usr-student-001';
      expect(await authRepo.getEnrolledBiometrics(userId: userId), isNotNull);

      await authRepo.deleteStudentBiometrics(userId: userId);

      expect(await authRepo.getEnrolledBiometrics(userId: userId), isNull);
    });
  });
}

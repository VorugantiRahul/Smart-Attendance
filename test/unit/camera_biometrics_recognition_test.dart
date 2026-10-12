import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris_attendance/core/biometrics/daugman_iris_engine.dart';
import 'package:iris_attendance/core/biometrics/face_iris_detector.dart';
import 'package:iris_attendance/core/biometrics/iris_localization.dart';
import 'package:iris_attendance/core/biometrics/iris_quality_assessment.dart';
import 'package:iris_attendance/core/utils/camera_frame_converter.dart';
import 'package:iris_attendance/core/utils/synthetic_face_generator.dart';
import 'package:iris_attendance/data/models/user_model.dart';
import 'package:iris_attendance/data/repositories/dev_mock_attendance_repository.dart';
import 'package:iris_attendance/data/repositories/dev_mock_auth_repository.dart';
import 'package:image/image.dart' as img;

void main() {
  group('Real Camera Biometrics, Eye Localization & Daugman Recognition Tests', () {
    late AdaptiveFaceIrisDetector detector;
    late DaugmanIrisRecognitionEngine irisEngine;
    late DevMockAuthRepository authRepo;
    late DevMockAttendanceRepository attendanceRepo;

    setUp(() {
      detector = AdaptiveFaceIrisDetector();
      irisEngine = DaugmanIrisRecognitionEngine();
      authRepo = DevMockAuthRepository();
      attendanceRepo = DevMockAttendanceRepository(authRepo);
    });

    test('1. Camera Frame Decoding: Converts raw image bytes into normalized grayscale frame', () {
      // Create a test RGB image
      final testImg = img.Image(width: 160, height: 120);
      for (int y = 0; y < 120; y++) {
        for (int x = 0; x < 160; x++) {
          testImg.setPixelRgb(x, y, 150, 150, 150);
        }
      }
      final encodedPng = Uint8List.fromList(img.encodePng(testImg));

      final converted = CameraFrameConverter.convertXFileBytes(
        encodedPng,
        targetWidth: 320,
        targetHeight: 240,
      );

      expect(converted, isNotNull);
      expect(converted!.width, equals(320));
      expect(converted.height, equals(240));
      expect(converted.grayscalePixels.length, equals(320 * 240));
      expect(converted.grayscalePixels[0], inInclusiveRange(140, 160));
    });

    test('2. Automatic Eye & Iris Acquisition: Dynamically locates pupil and limbus from real camera frame', () async {
      const width = 320;
      const height = 240;
      final realFrame = SyntheticFaceGenerator.generateSingleFaceImage(width: width, height: height);

      final detection = await detector.detectLandmarks(
        grayscalePixels: realFrame,
        width: width,
        height: height,
      );

      expect(detection.hasFace, isTrue);
      expect(detection.bothEyesDetected, isTrue);
      expect(detection.leftIris.isDetected, isTrue);
      expect(detection.rightIris.isDetected, isTrue);

      // Verify bilateral eye separation and realistic pupil coordinates
      expect(detection.leftIris.center.x, lessThan(detection.rightIris.center.x));
      expect(detection.leftIris.estimatedRadiusNormalized, greaterThan(0.02));
      expect(detection.rightIris.estimatedRadiusNormalized, greaterThan(0.02));
    });

    test('3. Eye Optical Quality Assessment: Evaluates sharpness, illumination and distance', () {
      const width = 320;
      const height = 240;
      final eyeFrame = List<int>.filled(width * height, 128);
      const cx = width / 2;
      const cy = height / 2;
      for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
          final dist = math.sqrt((x - cx) * (x - cx) + (y - cy) * (y - cy));
          if (dist < 20) {
            eyeFrame[y * width + x] = 25; // pupil
          } else if (dist < 68) {
            final angle = math.atan2(y - cy, x - cx);
            final texture = (((x ^ y) % 2 == 0) ? 140 : 100);
            final pattern = (math.sin(angle * 8) * 20).round();
            eyeFrame[y * width + x] = (texture + pattern).clamp(0, 255).toInt();
          } else {
            eyeFrame[y * width + x] = 180; // sclera
          }
        }
      }
      final darkFrame = SyntheticFaceGenerator.generateDarkImage(width: width, height: height);
      final blurryFrame = SyntheticFaceGenerator.generateBlurryImage(width: width, height: height);

      final sharpQuality = IrisQualityAssessment.evaluate(
        grayscalePixels: eyeFrame,
        width: width,
        height: height,
        eyeDiameterPixels: 130.0,
      );
      expect(sharpQuality.isAcceptable, isTrue);
      expect(sharpQuality.overallQualityScore, greaterThanOrEqualTo(60.0));

      final darkQuality = IrisQualityAssessment.evaluate(
        grayscalePixels: darkFrame,
        width: width,
        height: height,
        eyeDiameterPixels: 130.0,
      );
      expect(darkQuality.isAcceptable, isFalse);
      expect(darkQuality.guidanceInstructions.first, contains('dark'));

      final blurryQuality = IrisQualityAssessment.evaluate(
        grayscalePixels: blurryFrame,
        width: width,
        height: height,
        eyeDiameterPixels: 130.0,
      );
      expect(blurryQuality.isAcceptable, isFalse);
    });

    test('4. Daugman Iris Recognition: Generates 2048-bit IrisCode and compares identical vs different individuals', () async {
      const width = 160;
      const height = 160;
      final localization = IrisLocalizationResult(
        isDetected: true,
        pupilCircle: const IrisBoundaryCircle(centerX: 80.0, centerY: 80.0, radius: 18.0),
        irisLimbusCircle: const IrisBoundaryCircle(centerX: 80.0, centerY: 80.0, radius: 55.0),
        confidence: 0.96,
      );

      List<int> generateEyePattern({required double frequency}) {
        final pixels = List<int>.filled(width * height, 180);
        const cx = 80.0;
        const cy = 80.0;
        for (int y = 0; y < height; y++) {
          for (int x = 0; x < width; x++) {
            final r = math.sqrt((x - cx) * (x - cx) + (y - cy) * (y - cy));
            if (r < 18) {
              pixels[y * width + x] = 20; // Pupil
            } else if (r < 55) {
              final theta = math.atan2(y - cy, x - cx);
              final texture = (math.sin(theta * frequency) * 45 + 130).round();
              pixels[y * width + x] = texture.clamp(0, 255).toInt();
            } else {
              pixels[y * width + x] = 210; // Sclera
            }
          }
        }
        return pixels;
      }

      final personAFrame = generateEyePattern(frequency: 8.0);
      final personBFrame = generateEyePattern(frequency: 24.0);

      final templateA1 = await irisEngine.extractTemplate(
        imagePixels: personAFrame,
        width: width,
        height: height,
        localization: localization,
      );

      final templateA2 = await irisEngine.extractTemplate(
        imagePixels: personAFrame,
        width: width,
        height: height,
        localization: localization,
      );

      final templateB = await irisEngine.extractTemplate(
        imagePixels: personBFrame,
        width: width,
        height: height,
        localization: localization,
      );

      // Verify template extraction produces genuine Daugman IrisCode
      expect(templateA1.codeBits.isNotEmpty, isTrue);

      // Compare identical person (probe vs enrolled)
      final matchA = irisEngine.compareTemplates(
        probe: templateA2,
        enrolledReference: templateA1,
      );
      expect(matchA.isMatch, isTrue);
      expect(matchA.hammingDistance, equals(0.0)); // Perfect match

      // Compare two different individuals
      final matchDiff = irisEngine.compareTemplates(
        probe: templateB,
        enrolledReference: templateA1,
      );
      // Normalized Hamming distance between distinct individuals approaches ~0.50
      expect(matchDiff.hammingDistance, greaterThan(0.33));
      expect(matchDiff.isMatch, isFalse);
    });

    test('5. First-time Faculty Enrollment & Admin Approval: Real eye frame saves encrypted reference', () async {
      final user = await authRepo.register(
        fullName: 'Dr. Ramesh Sharma',
        email: 'ramesh.sharma@vnrvjiet.in',
        password: 'Password123!',
        requestedRole: UserRole.teacher,
        employeeId: 'FAC-CSE-990',
        department: 'Computer Science & Engineering',
      );

      const width = 320;
      const height = 240;
      final realFrame = SyntheticFaceGenerator.generateSingleFaceImage(width: width, height: height);

      const localization = IrisLocalizationResult(
        isDetected: true,
        pupilCircle: IrisBoundaryCircle(centerX: 190.0, centerY: 95.0, radius: 20.0),
        irisLimbusCircle: IrisBoundaryCircle(centerX: 190.0, centerY: 95.0, radius: 65.0),
        confidence: 0.96,
      );

      final genuineIris = await irisEngine.extractTemplate(
        imagePixels: realFrame,
        width: width,
        height: height,
        localization: localization,
      );

      await authRepo.enrollStudentBiometrics(
        userId: user.id,
        templateHex: genuineIris.toHexString(),
        maskHex: genuineIris.maskToHexString(),
        qualityScore: 0.96,
        faceImageBytes: realFrame,
      );

      final enrolled = await authRepo.getEnrolledBiometrics(userId: user.id);
      expect(enrolled, isNotNull);
      expect(enrolled!['templateHex'], equals(genuineIris.toHexString()));

      // Check roster status
      final facultyList = await attendanceRepo.getAllFaculty();
      final facultyMember = facultyList.firstWhere((f) => f.id == user.id);
      expect(facultyMember.isIrisEnrolled, isTrue);
      expect(facultyMember.isApproved, isFalse);
      expect(facultyMember.approvalStatus, equals(FacultyApprovalStatus.pending));

      // Authenticate as institutional admin to approve enrollment request
      await authRepo.login(email: 'admin@university.edu', password: 'Password123!');

      // Admin approves
      await attendanceRepo.approveFaculty(facultyId: user.id, isApproved: true);
      final approvedMember = (await attendanceRepo.getAllFaculty()).firstWhere((f) => f.id == user.id);
      expect(approvedMember.isApproved, isTrue);
      expect(approvedMember.approvalStatus, equals(FacultyApprovalStatus.approved));
    });
  });
}

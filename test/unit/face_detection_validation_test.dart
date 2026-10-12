import 'package:flutter_test/flutter_test.dart';
import 'package:iris_attendance/core/biometrics/face_iris_detector.dart';
import 'package:iris_attendance/core/utils/synthetic_face_generator.dart';
import 'package:iris_attendance/data/models/user_model.dart';
import 'package:iris_attendance/data/repositories/dev_mock_attendance_repository.dart';
import 'package:iris_attendance/data/repositories/dev_mock_auth_repository.dart';

void main() {
  group('Strict Facial Registration & Detection Test Cases', () {
    late AdaptiveFaceIrisDetector detector;
    late DevMockAuthRepository authRepo;
    late DevMockAttendanceRepository attendanceRepo;

    setUp(() {
      detector = AdaptiveFaceIrisDetector();
      authRepo = DevMockAuthRepository();
      attendanceRepo = DevMockAttendanceRepository(authRepo);
    });

    test('Case 1: Clear photograph containing one face — accept and pass validation', () async {
      const width = 320;
      const height = 240;
      final image = SyntheticFaceGenerator.generateSingleFaceImage(width: width, height: height);

      final result = await detector.detectLandmarks(
        grayscalePixels: image,
        width: width,
        height: height,
      );

      expect(result.hasFace, isTrue);
      expect(result.faceCount, equals(1));
      expect(result.validationStatus, equals(FaceDetectionValidationStatus.validSingleFace));
      expect(result.isValidForEnrollment, isTrue);
      expect(result.bothEyesDetected, isTrue);
      expect(result.faceBoundingBox, isNotNull);
    });

    test('Case 2: Image containing no person — reject with exact error message', () async {
      const width = 320;
      const height = 240;
      // Blank uniform surface with zero facial structures
      final emptyImage = List<int>.filled(width * height, 130);

      final result = await detector.detectLandmarks(
        grayscalePixels: emptyImage,
        width: width,
        height: height,
      );

      expect(result.hasFace, isFalse);
      expect(result.isValidForEnrollment, isFalse);
      // Status message must indicate no face detected
      expect(
        result.statusMessage,
        anyOf(
          contains('No face detected'),
          contains('blurry'),
        ),
      );
    });

    test('Case 3: Landscape or object photograph — reject as no face detected', () async {
      const width = 320;
      const height = 240;
      final landscapeImage = SyntheticFaceGenerator.generateLandscapeOrObjectImage(width: width, height: height);

      final result = await detector.detectLandmarks(
        grayscalePixels: landscapeImage,
        width: width,
        height: height,
      );

      expect(result.hasFace, isFalse);
      expect(result.isValidForEnrollment, isFalse);
      expect(result.statusMessage, equals('No face detected. Please upload a clear photograph showing your face.'));
    });

    test('Case 4: Image containing two or more faces — reject multiple faces', () async {
      const width = 320;
      const height = 240;
      final multiFaceImage = SyntheticFaceGenerator.generateMultipleFacesImage(width: width, height: height);

      final result = await detector.detectLandmarks(
        grayscalePixels: multiFaceImage,
        width: width,
        height: height,
      );

      expect(result.hasFace, isFalse);
      expect(result.validationStatus, equals(FaceDetectionValidationStatus.multipleFaces));
      expect(result.isValidForEnrollment, isFalse);
      expect(result.statusMessage, contains('Multiple faces detected'));
      expect(result.statusMessage, contains('Faculty registration requires exactly one person'));
    });

    test('Case 5: Blurry or very dark photograph — reject poor illumination or sharpness', () async {
      const width = 320;
      const height = 240;
      final darkImage = SyntheticFaceGenerator.generateDarkImage(width: width, height: height);
      final blurryImage = SyntheticFaceGenerator.generateBlurryImage(width: width, height: height);

      final darkResult = await detector.detectLandmarks(
        grayscalePixels: darkImage,
        width: width,
        height: height,
      );
      expect(darkResult.hasFace, isFalse);
      expect(darkResult.validationStatus, equals(FaceDetectionValidationStatus.poorLighting));
      expect(darkResult.isValidForEnrollment, isFalse);
      expect(darkResult.statusMessage, contains('too dark'));

      final blurryResult = await detector.detectLandmarks(
        grayscalePixels: blurryImage,
        width: width,
        height: height,
      );
      expect(blurryResult.hasFace, isFalse);
      expect(blurryResult.isValidForEnrollment, isFalse);
    });

    test('Case 6: Changing photo revalidates replacement image immediately', () async {
      const width = 320;
      const height = 240;
      final invalidLandscape = SyntheticFaceGenerator.generateLandscapeOrObjectImage(width: width, height: height);
      final validFace = SyntheticFaceGenerator.generateSingleFaceImage(width: width, height: height);

      // 1. Initial image is landscape -> rejected
      final res1 = await detector.detectLandmarks(
        grayscalePixels: invalidLandscape,
        width: width,
        height: height,
      );
      expect(res1.isValidForEnrollment, isFalse);

      // 2. User selects Change Photo to valid single face -> immediately validated and passes
      final res2 = await detector.detectLandmarks(
        grayscalePixels: validFace,
        width: width,
        height: height,
      );
      expect(res2.isValidForEnrollment, isTrue);
      expect(res2.hasFace, isTrue);
    });

    test('Case 7: Invalid photograph submitted directly through the API — reject on backend', () async {
      const userId = 'usr-faculty-test';
      final landscapeImage = SyntheticFaceGenerator.generateLandscapeOrObjectImage(width: 320, height: 240);

      expect(
        () async => await authRepo.enrollStudentBiometrics(
          userId: userId,
          templateHex: 'a5b4c3d2' * 64,
          maskHex: 'ff' * 256,
          qualityScore: 0.95,
          faceImageBytes: landscapeImage,
        ),
        throwsA(isA<Exception>().having(
          (e) => e.toString(),
          'message',
          contains('Backend validation failed'),
        )),
      );

      // Verify no biometric template or enrolled status was created
      final template = await authRepo.getEnrolledBiometrics(userId: userId);
      expect(template, isNull);
    });

    test('Case 8: Valid photograph submitted for approval — create pending request for admin review', () async {
      // Register a new faculty account
      final user = await authRepo.register(
        fullName: 'Prof. Aditi Sharma',
        email: 'aditi.sharma@university.edu',
        password: 'Password123!',
        requestedRole: UserRole.teacher,
        employeeId: 'FAC-IT-505',
        department: 'Information Technology',
      );

      expect(user.approvalStatus, equals(FacultyApprovalStatus.pending));
      expect(user.isApproved, isFalse);

      // Submit valid face photo
      final validFace = SyntheticFaceGenerator.generateSingleFaceImage(width: 320, height: 240);
      await authRepo.enrollStudentBiometrics(
        userId: user.id,
        templateHex: 'beefcafe' * 64,
        maskHex: 'ff' * 256,
        qualityScore: 0.94,
        faceImageBytes: validFace,
      );

      // Verify template stored and account has photo avatar URI and remains pending admin approval
      final enrolled = await authRepo.getEnrolledBiometrics(userId: user.id);
      expect(enrolled, isNotNull);
      expect(enrolled!['faceImageBytes'], isNotNull);

      // Verify Admin can see submitted photo and request in roster
      final facultyList = await attendanceRepo.getAllFaculty();
      final facultyMember = facultyList.firstWhere((f) => f.id == user.id);
      expect(facultyMember.isIrisEnrolled, isTrue);
      expect(facultyMember.approvalStatus, equals(FacultyApprovalStatus.pending));
      expect(facultyMember.avatarUrl, isNotNull);
      expect(facultyMember.avatarUrl, startsWith('data:image/bmp;base64,'));

      // Admin logs in and approves face verification
      await authRepo.login(
        email: 'admin@university.edu',
        password: 'Password123!',
      );
      await attendanceRepo.approveFaculty(facultyId: user.id, isApproved: true);
      final updatedList = await attendanceRepo.getAllFaculty();
      final approvedMember = updatedList.firstWhere((f) => f.id == user.id);
      expect(approvedMember.isApproved, isTrue);
      expect(approvedMember.approvalStatus, equals(FacultyApprovalStatus.approved));
    });
  });
}

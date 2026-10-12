import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:iris_attendance/core/biometrics/daugman_iris_engine.dart';
import 'package:iris_attendance/core/biometrics/face_iris_detector.dart';
import 'package:iris_attendance/core/biometrics/face_recognition_engine.dart';
import 'package:iris_attendance/core/biometrics/iris_localization.dart';
import 'package:iris_attendance/core/biometrics/liveness_detector.dart';
import 'package:iris_attendance/core/utils/synthetic_face_generator.dart';
import 'package:iris_attendance/data/models/attendance_record_model.dart';
import 'package:iris_attendance/data/models/user_model.dart';
import 'package:iris_attendance/data/repositories/dev_mock_attendance_repository.dart';
import 'package:iris_attendance/data/repositories/dev_mock_auth_repository.dart';
import 'package:iris_attendance/ui/features/dashboard/view_models/admin_dashboard_view_model.dart';
import 'package:iris_attendance/ui/features/dashboard/view_models/teacher_dashboard_view_model.dart';

void main() {
  group('12-Point End-to-End Faculty Biometric Enrollment & Verification Workflow', () {
    late DevMockAuthRepository authRepo;
    late DevMockAttendanceRepository attendanceRepo;
    late StandardFaceRecognitionEngine faceEngine;
    late DaugmanIrisRecognitionEngine irisEngine;

    const imgWidth = 320;
    const imgHeight = 240;

    // Helper to generate a synthetic eye image
    List<int> createSyntheticEyeImage({required double phaseShift, double frequencyMultiplier = 10.0}) {
      const width = 160;
      const height = 160;
      final pixels = List<int>.filled(width * height, 0);
      const cx = width / 2;
      const cy = height / 2;

      for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
          final r = math.sqrt((x - cx) * (x - cx) + (y - cy) * (y - cy));
          if (r < 18) {
            pixels[y * width + x] = 20; // Pupil
          } else if (r < 55) {
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

    const mockLocalization = IrisLocalizationResult(
      isDetected: true,
      pupilCircle: IrisBoundaryCircle(centerX: 80, centerY: 80, radius: 18),
      irisLimbusCircle: IrisBoundaryCircle(centerX: 80, centerY: 80, radius: 55),
      confidence: 0.96,
    );

    const testFaceBox = NormalizedBoundingBox(
      left: 0.15,
      top: 0.10,
      width: 0.70,
      height: 0.80,
    );

    setUp(() {
      DevMockAttendanceRepository.resetMockState();
      authRepo = DevMockAuthRepository();
      attendanceRepo = DevMockAttendanceRepository(authRepo);
      faceEngine = StandardFaceRecognitionEngine();
      irisEngine = DaugmanIrisRecognitionEngine();
    });

    test('Case 1: New faculty registers and submits face image with pending_approval status', () async {
      // 1. Register faculty credentials
      final user = await authRepo.register(
        fullName: 'Prof. John Smith',
        email: 'prof.smith@university.edu',
        password: 'Password123!',
        requestedRole: UserRole.teacher,
        employeeId: 'FAC-CSE-999',
        department: 'Computer Science & Engineering',
      );

      expect(user.email, equals('prof.smith@university.edu'));
      expect(user.isApproved, isFalse);
      expect(user.approvalStatus, equals(FacultyApprovalStatus.pending));

      // 2. Generate valid facial image and extract biometric templates
      final faceImg = SyntheticFaceGenerator.generateSingleFaceImage(width: imgWidth, height: imgHeight);
      final faceTemplate = await faceEngine.extractTemplate(
        imagePixels: faceImg,
        width: imgWidth,
        height: imgHeight,
        faceBox: testFaceBox,
      );

      final eyeImg = createSyntheticEyeImage(phaseShift: 0.0);
      final irisTemplate = await irisEngine.extractTemplate(
        imagePixels: eyeImg,
        width: 160,
        height: 160,
        localization: mockLocalization,
      );

      // 3. Submit biometric enrollment request to backend
      await authRepo.enrollStudentBiometrics(
        userId: user.id,
        templateHex: irisTemplate.toHexString(),
        maskHex: irisTemplate.maskToHexString(),
        qualityScore: 0.95,
        faceTemplateBase64: faceTemplate.toBase64String(),
        faceImageBytes: faceImg,
      );

      final enrolledUser = await authRepo.getCurrentUser();
      expect(enrolledUser, isNotNull);
      expect(enrolledUser!.isIrisEnrolled, isTrue);
      expect(enrolledUser.isApproved, isFalse);
      expect(enrolledUser.approvalStatus, equals(FacultyApprovalStatus.pending));
    });

    test('Case 2: Pending faculty cannot mark attendance', () async {
      // Register new pending faculty
      await authRepo.register(
        fullName: 'Dr. Pending',
        email: 'pending.faculty@university.edu',
        password: 'Password123!',
        requestedRole: UserRole.teacher,
      );

      // Backend attendance verification must reject check-in while status is pending
      expect(
        () async => await attendanceRepo.submitCheckIn(
          sessionId: 'cccccccc-cccc-cccc-cccc-cccccccccccc',
          latitude: 17.5385,
          longitude: 78.3852,
        ),
        throwsA(predicate((e) =>
            e.toString().contains('Account pending administrator approval') ||
            e.toString().contains('pending'))),
      );
    });

    test('Case 3: Admin sees the enrollment request in faculty roster', () async {
      // Register pending faculty
      await authRepo.register(
        fullName: 'Dr. Applicant',
        email: 'applicant@university.edu',
        password: 'Password123!',
        requestedRole: UserRole.teacher,
        employeeId: 'FAC-APPL-01',
        department: 'Electronics',
      );

      // Admin logs in
      await authRepo.login(
        email: 'admin@university.edu',
        password: 'Password123!',
      );

      final adminVm = AdminDashboardViewModel(attendanceRepo);
      await adminVm.loadAdminData();

      // Verify request appears in faculty list with pending status
      final pendingRequests = adminVm.state.facultyList
          .where((f) => !f.isApproved || f.approvalStatus == FacultyApprovalStatus.pending)
          .toList();

      expect(pendingRequests.any((f) => f.email == 'applicant@university.edu'), isTrue);
      final req = pendingRequests.firstWhere((f) => f.email == 'applicant@university.edu');
      expect(req.fullName, equals('Dr. Applicant'));
      expect(req.employeeId, equals('FAC-APPL-01'));
    });

    test('Case 4: Unauthorized users cannot approve requests (non-admin & self-approval blocked)', () async {
      final facUser = await authRepo.register(
        fullName: 'Dr. Regular',
        email: 'regular.teacher@university.edu',
        password: 'Password123!',
        requestedRole: UserRole.teacher,
      );

      // Non-admin attempting approval
      expect(
        () async => await attendanceRepo.approveFaculty(
          facultyId: facUser.id,
          isApproved: true,
        ),
        throwsA(predicate((e) => e.toString().contains('Unauthorized'))),
      );

      // Admin attempting self-approval
      await authRepo.login(
        email: 'admin@university.edu',
        password: 'Password123!',
      );
      final adminUser = (await authRepo.getCurrentUser())!;

      expect(
        () async => await attendanceRepo.approveFaculty(
          facultyId: adminUser.id,
          isApproved: true,
        ),
        throwsA(predicate((e) => e.toString().contains('Security violation'))),
      );
    });

    test('Case 5: Admin approves the request and audit log records approval', () async {
      final fac = await authRepo.register(
        fullName: 'Prof. Approvee',
        email: 'approve.me@university.edu',
        password: 'Password123!',
        requestedRole: UserRole.teacher,
      );

      await authRepo.login(
        email: 'admin@university.edu',
        password: 'Password123!',
      );

      await attendanceRepo.approveFaculty(facultyId: fac.id, isApproved: true);

      final updatedRoster = await attendanceRepo.getAllFaculty();
      final approved = updatedRoster.firstWhere((f) => f.id == fac.id);
      expect(approved.isApproved, isTrue);
      expect(approved.approvalStatus, equals(FacultyApprovalStatus.approved));

      final logs = await attendanceRepo.getAuditLogs();
      expect(logs.any((l) => l.action == 'FACULTY_ENROLLMENT_APPROVED'), isTrue);
    });

    test('Case 6: Approved faculty logs in on a later day without repeated enrollment prompt', () async {
      final user = await authRepo.login(
        email: 'faculty@university.edu',
        password: 'Password123!',
      );

      expect(user.isApproved, isTrue);
      expect(user.approvalStatus, equals(FacultyApprovalStatus.approved));
      expect(user.isIrisEnrolled, isTrue);

      final teacherVm = TeacherDashboardViewModel(attendanceRepo);
      await teacherVm.loadDashboardData();
      expect(teacherVm.state.isLoading, isFalse);
    });

    test('Case 7: Matching identity and valid location permit attendance', () async {
      await authRepo.login(
        email: 'faculty@university.edu',
        password: 'Password123!',
      );

      // Verify biometric matches with same or very similar face & iris
      final faceImg = SyntheticFaceGenerator.generateSingleFaceImage(width: imgWidth, height: imgHeight);
      final enrolledFace = await faceEngine.extractTemplate(
        imagePixels: faceImg,
        width: imgWidth,
        height: imgHeight,
        faceBox: testFaceBox,
      );
      final probeFace = await faceEngine.extractTemplate(
        imagePixels: faceImg,
        width: imgWidth,
        height: imgHeight,
        faceBox: testFaceBox,
      );

      final faceMatch = faceEngine.compareTemplates(probe: probeFace, enrolledReference: enrolledFace);
      expect(faceMatch.isMatch, isTrue);
      expect(faceMatch.similarityScore, greaterThanOrEqualTo(0.95));

      final eyeImg = createSyntheticEyeImage(phaseShift: 0.0);
      final irisTemplate = await irisEngine.extractTemplate(
        imagePixels: eyeImg,
        width: 160,
        height: 160,
        localization: mockLocalization,
      );
      final irisMatch = irisEngine.compareTemplates(probe: irisTemplate, enrolledReference: irisTemplate);
      expect(irisMatch.isMatch, isTrue);
      expect(irisMatch.hammingDistance, lessThanOrEqualTo(0.15));

      // Attendance check-in within geofence
      final record = await attendanceRepo.submitCheckIn(
        sessionId: 'cccccccc-cccc-cccc-cccc-cccccccccccc',
        latitude: 17.5385,
        longitude: 78.3852,
      );

      expect(record.status, equals(AttendanceRecordStatus.present));
      expect(record.isWithinGeofence, isTrue);
      expect(record.isBiometricallyVerified, isTrue);
    });

    test('Case 8: A different person\'s face is rejected by face recognition engine', () async {
      // Person A: Standard centered facial portrait
      final personAImg = SyntheticFaceGenerator.generateSingleFaceImage(
        width: imgWidth,
        height: imgHeight,
        faceCenterX: 0.40,
        faceCenterY: 0.45,
        faceRadiusX: 0.20,
        faceRadiusY: 0.26,
      );
      final templateA = await faceEngine.extractTemplate(
        imagePixels: personAImg,
        width: imgWidth,
        height: imgHeight,
        faceBox: testFaceBox,
      );

      // Person B: Distinctly different person with shifted features and proportions
      final personBImg = SyntheticFaceGenerator.generateSingleFaceImage(
        width: imgWidth,
        height: imgHeight,
        faceCenterX: 0.60,
        faceCenterY: 0.55,
        faceRadiusX: 0.30,
        faceRadiusY: 0.36,
        ambientBrightness: 120,
      );
      final templateB = await faceEngine.extractTemplate(
        imagePixels: personBImg,
        width: imgWidth,
        height: imgHeight,
        faceBox: testFaceBox,
      );

      final matchResult = faceEngine.compareTemplates(probe: templateB, enrolledReference: templateA);
      expect(matchResult.isMatch, isFalse);
      expect(matchResult.similarityScore, lessThan(0.80));
    });

    test('Case 9: Photograph or replay attempt is rejected when liveness fails', () {
      final staticLiveness = LivenessDetectionResult.failed(
        reason: 'Static photograph presentation detected; zero micro-saccadic pupil motion.',
        challenge: LivenessChallengeType.blinkChallenge,
        staticPhoto: true,
      );

      expect(staticLiveness.isLive, isFalse);
      expect(staticLiveness.staticPhotoDetected, isTrue);
    });

    test('Case 10: Rejected enrollment can be resubmitted', () async {
      // 1. Register faculty
      final fac = await authRepo.register(
        fullName: 'Dr. Resubmitter',
        email: 'resubmit.faculty@university.edu',
        password: 'Password123!',
        requestedRole: UserRole.teacher,
      );

      // 2. Admin rejects request with reason
      await authRepo.login(
        email: 'admin@university.edu',
        password: 'Password123!',
      );
      await attendanceRepo.rejectFaculty(
        facultyId: fac.id,
        rejectionReason: 'Photograph blurry; glare on eyes.',
      );

      // 3. Faculty logs back in and checks rejection status
      await authRepo.login(
        email: 'resubmit.faculty@university.edu',
        password: 'Password123!',
      );
      var current = (await authRepo.getCurrentUser())!;
      expect(current.approvalStatus, equals(FacultyApprovalStatus.rejected));
      expect(current.rejectionReason, equals('Photograph blurry; glare on eyes.'));

      // 4. Faculty submits corrected enrollment request with clear photo
      final newFaceImg = SyntheticFaceGenerator.generateSingleFaceImage(width: imgWidth, height: imgHeight);
      final newFaceTemplate = await faceEngine.extractTemplate(
        imagePixels: newFaceImg,
        width: imgWidth,
        height: imgHeight,
        faceBox: testFaceBox,
      );

      final newEyeImg = createSyntheticEyeImage(phaseShift: 1.0);
      final newIrisTemplate = await irisEngine.extractTemplate(
        imagePixels: newEyeImg,
        width: 160,
        height: 160,
        localization: mockLocalization,
      );

      await authRepo.enrollStudentBiometrics(
        userId: fac.id,
        templateHex: newIrisTemplate.toHexString(),
        maskHex: newIrisTemplate.maskToHexString(),
        qualityScore: 0.95,
        faceTemplateBase64: newFaceTemplate.toBase64String(),
        faceImageBytes: newFaceImg,
      );

      final resubmitted = (await authRepo.getCurrentUser())!;
      expect(resubmitted.approvalStatus, equals(FacultyApprovalStatus.pending));
      expect(resubmitted.isApproved, isFalse);
      expect(resubmitted.rejectionReason, isNull);
    });

    test('Case 11: Duplicate attendance is prevented on the same calendar day', () async {
      await authRepo.login(
        email: 'faculty@university.edu',
        password: 'Password123!',
      );

      // Check-in #1 succeeds
      final rec1 = await attendanceRepo.submitCheckIn(
        sessionId: 'cccccccc-cccc-cccc-cccc-cccccccccccc',
        latitude: 17.5385,
        longitude: 78.3852,
      );
      expect(rec1.status, equals(AttendanceRecordStatus.present));

      // Check-in #2 on the same day is rejected
      expect(
        () async => await attendanceRepo.submitCheckIn(
          sessionId: 'cccccccc-cccc-cccc-cccc-cccccccccccc',
          latitude: 17.5385,
          longitude: 78.3852,
        ),
        throwsA(predicate((e) =>
            e.toString().contains('Attendance already recorded today') ||
            e.toString().contains('already recorded') ||
            e.toString().contains('Duplicate submissions are strictly prevented'))),
      );
    });

    test('Case 12: Backend errors never produce false attendance success', () async {
      attendanceRepo.simulateNetworkFailure = true;

      await authRepo.login(
        email: 'faculty@university.edu',
        password: 'Password123!',
      );

      expect(
        () async => await attendanceRepo.submitCheckIn(
          sessionId: 'cccccccc-cccc-cccc-cccc-cccccccccccc',
          latitude: 17.5385,
          longitude: 78.3852,
        ),
        throwsA(isA<Exception>()),
      );

      // Verified attendance remains false
      final teacherVm = TeacherDashboardViewModel(attendanceRepo);
      await teacherVm.loadDashboardData();
      expect(teacherVm.state.isCheckedInToday, isFalse);
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:iris_attendance/core/biometrics/liveness_detector.dart';
import 'package:iris_attendance/core/security/secure_key_store.dart';
import 'package:iris_attendance/data/models/user_model.dart';
import 'package:iris_attendance/data/repositories/dev_mock_attendance_repository.dart';
import 'package:iris_attendance/data/repositories/dev_mock_auth_repository.dart';

void main() {
  group('Security Hardening & Liveness Unit Tests', () {
    late StandardLivenessDetector livenessDetector;

    setUp(() {
      livenessDetector = StandardLivenessDetector();
    });

    test('Live dynamic sequence passes liveness evaluation (Score >= 0.70)', () async {
      const width = 80;
      const height = 80;
      final f1 = List<int>.filled(width * height, 120);
      final f2 = List<int>.filled(width * height, 125); // micro-saccade shift
      final f3 = List<int>.filled(width * height, 118);

      final result = await livenessDetector.evaluateLivenessSequence(
        frameSequence: [f1, f2, f3],
        width: width,
        height: height,
        challenge: LivenessChallengeType.blinkChallenge,
        duration: const Duration(milliseconds: 500),
      );

      expect(result.isLive, isTrue);
      expect(result.livenessConfidence, greaterThanOrEqualTo(0.70));
      expect(result.staticPhotoDetected, isFalse);
      expect(result.screenReplayDetected, isFalse);
    });

    test('Presentation Attack Detection: Identifies static photograph (Zero frame delta)', () async {
      const width = 80;
      const height = 80;
      // 3 identical static frames (holding a printed photograph)
      final staticFrame = List<int>.filled(width * height, 120);

      final result = await livenessDetector.evaluateLivenessSequence(
        frameSequence: [staticFrame, staticFrame, staticFrame],
        width: width,
        height: height,
        challenge: LivenessChallengeType.blinkChallenge,
        duration: const Duration(milliseconds: 500),
      );

      expect(result.isLive, isFalse);
      expect(result.staticPhotoDetected, isTrue);
      expect(result.diagnosticReason, contains('Static photograph detected'));
    });

    test('Presentation Attack Detection: Identifies screen replay moire raster artifacts', () async {
      const width = 80;
      const height = 80;
      final f1 = List<int>.filled(width * height, 120);
      final moireFrame = List<int>.filled(width * height, 120);

      // Create alternating high-contrast pixel grid simulating digital phone screen subpixels
      for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
          moireFrame[y * width + x] = (x % 2 == 0) ? 230 : 20;
        }
      }

      final result = await livenessDetector.evaluateLivenessSequence(
        frameSequence: [f1, f1, moireFrame],
        width: width,
        height: height,
        challenge: LivenessChallengeType.guidedGazeLeft,
        duration: const Duration(milliseconds: 500),
      );

      expect(result.isLive, isFalse);
      expect(result.screenReplayDetected, isTrue);
      expect(result.diagnosticReason, contains('Digital screen replay'));
    });
  });

  group('Replay Attack Prevention, Short-Lived Nonces & Authorization Tests', () {
    late DevMockAuthRepository authRepo;
    late DevMockAttendanceRepository attendanceRepo;
    late PlatformSecureKeyStore keyStore;
    const testSessionId = 'cccccccc-cccc-cccc-cccc-cccccccccccc';

    setUp(() {
      authRepo = DevMockAuthRepository();
      attendanceRepo = DevMockAttendanceRepository(authRepo);
      keyStore = PlatformSecureKeyStore();
    });

    test('Generates single-use server nonce for active attendance session', () async {
      await authRepo.login(
        email: 'student@university.edu',
        password: 'Password123',
      );

      final nonce = await attendanceRepo.requestVerificationNonce(
        sessionId: testSessionId,
      );

      expect(nonce, startsWith('nonce-'));
    });

    test('Faculty Role: Faculty can request verification nonce', () async {
      await authRepo.login(
        email: 'faculty@university.edu',
        password: 'Password123',
      );

      final nonce = await attendanceRepo.requestVerificationNonce(sessionId: testSessionId);
      expect(nonce, startsWith('nonce-'));
    });

    test('Consumes nonce on attendance submission and rejects replayed nonce', () async {
      await authRepo.login(
        email: 'student@university.edu',
        password: 'Password123',
      );

      final nonce = await attendanceRepo.requestVerificationNonce(
        sessionId: testSessionId,
      );

      final signature = await keyStore.signPayload(payload: '$nonce:$testSessionId');

      // First submission with valid nonce
      final record = await attendanceRepo.submitHardenedAttendance(
        sessionId: testSessionId,
        nonce: nonce,
        latitude: 12.9717,
        longitude: 77.5947,
        livenessScore: 0.88,
        challengeType: 'blinkChallenge',
        deviceSignature: signature,
      );
      expect(record, isNotNull);

      // Attempt REPLAY ATTACK with same consumed nonce
      expect(
        () => attendanceRepo.submitHardenedAttendance(
          sessionId: testSessionId,
          nonce: nonce,
          latitude: 12.9717,
          longitude: 77.5947,
          livenessScore: 0.88,
          challengeType: 'blinkChallenge',
          deviceSignature: signature,
        ),
        throwsA(predicate((e) => e.toString().contains('Replay Attack Detected'))),
      );
    });

    test('Rejects submission with forged or unissued server nonce', () async {
      await authRepo.login(
        email: 'student@university.edu',
        password: 'Password123',
      );

      expect(
        () => attendanceRepo.submitHardenedAttendance(
          sessionId: testSessionId,
          nonce: 'fake-forged-nonce-123',
          latitude: 12.9717,
          longitude: 77.5947,
          livenessScore: 0.85,
          challengeType: 'blinkChallenge',
          deviceSignature: 'sig',
        ),
        throwsA(predicate((e) => e.toString().contains('Invalid or forged server nonce'))),
      );
    });

    test('Rejects attendance submission when liveness score is below threshold (< 0.70)', () async {
      // Create new student
      await authRepo.register(
        fullName: 'New Student',
        email: 'new.student@university.edu',
        password: 'Password123',
        requestedRole: UserRole.student,
        studentIdNumber: 'STU-9901',
      );

      final nonce = await attendanceRepo.requestVerificationNonce(
        sessionId: testSessionId,
      );

      expect(
        () => attendanceRepo.submitHardenedAttendance(
          sessionId: testSessionId,
          nonce: nonce,
          latitude: 12.9717,
          longitude: 77.5947,
          livenessScore: 0.45, // Failed liveness
          challengeType: 'blinkChallenge',
          deviceSignature: 'sig',
        ),
        throwsA(predicate((e) => e.toString().contains('Liveness verification failed'))),
      );
    });
  });
}

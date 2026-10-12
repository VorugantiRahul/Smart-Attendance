import 'package:flutter_test/flutter_test.dart';
import 'package:iris_attendance/data/models/attendance_record_model.dart';
import 'package:iris_attendance/data/models/user_model.dart';
import 'package:iris_attendance/data/repositories/dev_mock_attendance_repository.dart';
import 'package:iris_attendance/data/repositories/dev_mock_auth_repository.dart';

void main() {
  group('Backend & Database Logic Tests: Access Control, Duplicate Submissions & Geofencing', () {
    late DevMockAuthRepository authRepo;
    late DevMockAttendanceRepository attendanceRepo;

    setUp(() {
      authRepo = DevMockAuthRepository();
      attendanceRepo = DevMockAttendanceRepository(authRepo);
    });

    test('Access Control: Unauthenticated check-in is rejected', () async {
      expect(
        () => attendanceRepo.submitCheckIn(
          sessionId: 'cccccccc-cccc-cccc-cccc-cccccccccccc',
          latitude: 12.9716,
          longitude: 77.5946,
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('Access Control: Authenticated faculty can submit check-in', () async {
      await authRepo.login(
        email: 'faculty@university.edu',
        password: 'Password123',
      );

      final record = await attendanceRepo.submitCheckIn(
        sessionId: 'cccccccc-cccc-cccc-cccc-cccccccccccc',
        latitude: 17.5385,
        longitude: 78.3852,
      );
      expect(record.status, equals(AttendanceRecordStatus.present));
      expect(record.isWithinGeofence, isTrue);
    });

    test('Geofence Validation: Faculty within campus perimeter is verified present', () async {
      // Authenticate as faculty
      await authRepo.login(
        email: 'faculty@university.edu',
        password: 'Password123',
      );

      final records = await attendanceRepo.getAttendanceRecords();
      expect(records, isNotEmpty);
      expect(records.first.isWithinGeofence, isTrue);
    });

    test('Duplicate Submission: Submitting attendance twice on same day is rejected', () async {
      await authRepo.login(
        email: 'faculty@university.edu',
        password: 'Password123',
      );

      // Attempt another check-in on the same day
      expect(
        () => attendanceRepo.submitCheckIn(
          sessionId: 'cccccccc-cccc-cccc-cccc-cccccccccccc',
          latitude: 17.5385,
          longitude: 78.3852,
        ),
        throwsA(predicate((e) => e.toString().contains('already recorded today') || e.toString().contains('Duplicate'))),
      );
    });

    test('Geofence Violation: Student far away is flagged_outside_geofence', () async {
      // Create new session for testing breach
      await authRepo.login(
        email: 'admin@university.edu',
        password: 'Password123',
      );

      final newSession = await attendanceRepo.createSession(
        courseId: 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
        locationId: 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
        sessionTitle: 'Off-campus test session',
        startTime: DateTime.now().subtract(const Duration(minutes: 2)),
        endTime: DateTime.now().add(const Duration(minutes: 40)),
      );

      // Login another student
      await authRepo.register(
        fullName: 'Remote Student',
        email: 'remote@university.edu',
        password: 'Password123',
        requestedRole: UserRole.student,
        studentIdNumber: 'STU-9999',
      );

      // Submit coordinates 2 km outside campus
      final record = await attendanceRepo.submitCheckIn(
        sessionId: newSession.id,
        latitude: 12.9900,
        longitude: 77.6200,
      );

      expect(record.isWithinGeofence, isFalse);
      expect(record.status, equals(AttendanceRecordStatus.flaggedOutsideGeofence));
      expect(record.isBiometricallyVerified, isFalse);
    });

    test('Access Control: Students can view ONLY their own attendance records', () async {
      await authRepo.login(
        email: 'student@university.edu',
        password: 'Password123',
      );

      final records = await attendanceRepo.getAttendanceRecords();
      for (final r in records) {
        expect(r.studentId, equals('usr-student-001'));
      }
    });

    test('Access Control: Students cannot create attendance sessions', () async {
      await authRepo.login(
        email: 'student@university.edu',
        password: 'Password123',
      );

      expect(
        () => attendanceRepo.createSession(
          courseId: 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
          locationId: 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
          sessionTitle: 'Unauthorized Session',
          startTime: DateTime.now(),
          endTime: DateTime.now().add(const Duration(hours: 1)),
        ),
        throwsA(predicate((e) => e.toString().contains('Unauthorized'))),
      );
    });
  });
}

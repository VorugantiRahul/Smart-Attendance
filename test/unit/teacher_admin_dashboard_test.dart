import 'package:flutter_test/flutter_test.dart';
import 'package:iris_attendance/data/models/attendance_record_model.dart';
import 'package:iris_attendance/data/repositories/dev_mock_attendance_repository.dart';
import 'package:iris_attendance/data/repositories/dev_mock_auth_repository.dart';
import 'package:iris_attendance/ui/features/dashboard/view_models/teacher_dashboard_view_model.dart';

void main() {
  group('Teacher & Administrator Dashboard Suite', () {
    late DevMockAuthRepository mockAuthRepo;
    late DevMockAttendanceRepository mockAttendanceRepo;

    setUp(() {
      mockAuthRepo = DevMockAuthRepository();
      mockAttendanceRepo = DevMockAttendanceRepository(mockAuthRepo);
    });

    test('Teacher Dashboard: RBAC allows teacher to view assigned sessions', () async {
      // Login as Teacher
      await mockAuthRepo.login(
        email: 'faculty@university.edu',
        password: 'Password123!',
      );

      final vm = TeacherDashboardViewModel(mockAttendanceRepo);
      await vm.loadDashboardData();

      expect(vm.state.isLoading, isFalse);
      expect(vm.state.sessions, isNotEmpty);
      expect(vm.state.sessions.first.courseCode, equals('FAC-DUTY'));
    });

    test('Teacher Dashboard: Filter logic by status and search query works correctly', () {
      final state = TeacherDashboardState(
        records: [
          AttendanceRecord(
            id: 'rec-1',
            sessionId: 'sess-1',
            studentId: 'stu-1',
            studentName: 'Alice Springs',
            studentRollNumber: 'CS-001',
            status: AttendanceRecordStatus.present,
            latitude: 12.9716,
            longitude: 77.5946,
            isWithinGeofence: true,
            recordedAt: DateTime.now(),
          ),
          AttendanceRecord(
            id: 'rec-2',
            sessionId: 'sess-1',
            studentId: 'stu-2',
            studentName: 'Bob Vance',
            studentRollNumber: 'CS-002',
            status: AttendanceRecordStatus.flaggedOutsideGeofence,
            latitude: 12.9800,
            longitude: 77.6000,
            isWithinGeofence: false,
            recordedAt: DateTime.now(),
          ),
        ],
      );

      // No filter: total 2
      expect(state.filteredRecords.length, equals(2));

      // Filter by status Present
      final filteredState = state.copyWith(statusFilter: AttendanceRecordStatus.present);
      expect(filteredState.filteredRecords.length, equals(1));
      expect(filteredState.filteredRecords.first.studentName, equals('Alice Springs'));

      // Filter by search query 'Bob'
      final searchState = state.copyWith(searchQuery: 'Bob');
      expect(searchState.filteredRecords.length, equals(1));
      expect(searchState.filteredRecords.first.studentRollNumber, equals('CS-002'));
    });

    test('Audited Attendance Correction: Requires reason and updates record', () async {
      // 1. Submit check-in as student
      await mockAuthRepo.login(
        email: 'student@university.edu',
        password: 'Password123!',
      );
      final record = await mockAttendanceRepo.submitCheckIn(
        sessionId: 'cccccccc-cccc-cccc-cccc-cccccccccccc',
        latitude: 17.5385,
        longitude: 78.3852,
      );

      // 2. Switch to Teacher
      await mockAuthRepo.login(
        email: 'faculty@university.edu',
        password: 'Password123!',
      );

      // Fails without justification reason
      expect(
        () async => await mockAttendanceRepo.submitAttendanceCorrection(
          recordId: record.id,
          newStatus: AttendanceRecordStatus.present,
          justificationReason: '   ',
        ),
        throwsA(isA<Exception>()),
      );

      // Succeeds with valid audit reason
      await mockAttendanceRepo.submitAttendanceCorrection(
        recordId: record.id,
        newStatus: AttendanceRecordStatus.present,
        justificationReason: 'Verified physical presence during lab hours.',
      );

      final records = await mockAttendanceRepo.getAttendanceRecords(sessionId: 'cccccccc-cccc-cccc-cccc-cccccccccccc');
      final corrected = records.firstWhere((r) => r.id == record.id);
      expect(corrected.status, equals(AttendanceRecordStatus.present));
      expect(corrected.correctionReason, equals('Verified physical presence during lab hours.'));
      expect(corrected.correctedBy, equals('faculty@university.edu'));
    });

    test('CSV Export: Generates RFC-compliant formatted attendance report', () async {
      await mockAuthRepo.login(
        email: 'faculty@university.edu',
        password: 'Password123!',
      );

      final csv = await mockAttendanceRepo.exportAttendanceReportToCsv();
      expect(csv, contains('Record ID,Session ID,Student ID,Student Name'));
      expect(csv, contains('Within Geofence'));
    });

    test('Admin Dashboard: Can update campus geofence coordinates and buffer radius', () async {
      await mockAuthRepo.login(
        email: 'admin@university.edu',
        password: 'Password123!',
      );

      final locations = await mockAttendanceRepo.getCampusLocations();
      final targetLoc = locations.first;

      await mockAttendanceRepo.updateCampusBoundary(
        locationId: targetLoc.id,
        centerLatitude: 12.9750,
        centerLongitude: 77.5980,
        bufferRadiusMeters: 150.0,
      );

      final updatedLocations = await mockAttendanceRepo.getCampusLocations();
      final updated = updatedLocations.firstWhere((l) => l.id == targetLoc.id);
      expect(updated.centerLatitude, equals(12.9750));
      expect(updated.centerLongitude, equals(77.5980));
      expect(updated.bufferRadiusMeters, equals(150.0));
    });

    test('Admin Dashboard: Student cannot access Admin Audit Logs (RBAC enforcement)', () async {
      await mockAuthRepo.login(
        email: 'student@university.edu',
        password: 'Password123!',
      );

      expect(
        () async => await mockAttendanceRepo.getAuditLogs(),
        throwsA(isA<Exception>()),
      );
    });

    test('Biometric Template Deletion: Compliance with Right to be Forgotten logs audit purge', () async {
      await mockAuthRepo.login(
        email: 'admin@university.edu',
        password: 'Password123!',
      );

      await mockAttendanceRepo.requestBiometricTemplateDeletion(userId: 'usr-student-001');

      final logs = await mockAttendanceRepo.getAuditLogs();
      final purgeLog = logs.firstWhere((l) => l.action == 'BIOMETRIC_TEMPLATE_DELETION_PURGED');
      expect(purgeLog.actorEmail, equals('admin@university.edu'));
      expect(purgeLog.resourceType, equals('biometric_template'));
      expect(purgeLog.details['regulatory_policy'], contains('Right to be Forgotten'));
    });
  });
}

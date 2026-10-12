import '../../core/utils/geo_utils.dart';
import '../models/attendance_policy_model.dart';
import '../models/attendance_record_model.dart';
import '../models/attendance_session_model.dart';
import '../models/audit_event_model.dart';
import '../models/campus_location_model.dart';
import '../models/user_model.dart';
import 'attendance_repository.dart';
import 'auth_repository.dart';
import 'dev_mock_auth_repository.dart';

/// Development Mock Attendance Repository
/// Enforces server-side rules for Faculty Daily Attendance:
/// - One valid check-in per faculty member per day
/// - Campus boundary geofence evaluation (VNR VJIET Bachupally Campus)
/// - Configurable college attendance policy (working hours, grace period, late arrival)
/// - Prevents duplicate submissions with exact check-in time notification
class DevMockAttendanceRepository implements AttendanceRepository {
  final AuthRepository _authRepo;

  DevMockAttendanceRepository(this._authRepo);

  // In-memory seeded database (Default: VNR VJIET Bachupally Campus & Gandimaisamma Hostel)
  static final List<CampusLocation> _locations = [
    const CampusLocation(
      id: 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
      code: 'VNRVJIET-MAIN',
      name: 'VNR Vignana Jyothi Institute of Engineering & Technology',
      description: 'Main Campus & Academic Complex (Accepts past VNR circle, >100m inside Main Gate)',
      centerLatitude: 17.538500,
      centerLongitude: 78.385200,
      bufferRadiusMeters: 350.0,
      isActive: true,
    ),
    const CampusLocation(
      id: 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
      code: 'ATITHI-HOSTEL-GM',
      name: 'Atithi Boys Hostel (Near Tryit Shop, Gandimaisamma)',
      description: 'Authorized Faculty Residence / Satellite Campus Zone near Tryit Shop, Gandimaisamma',
      centerLatitude: 17.578900,
      centerLongitude: 78.426900,
      bufferRadiusMeters: 500.0,
      isActive: true,
    ),
  ];

  static AttendancePolicy _policy = const AttendancePolicy(
    workdayStartHour: 9,
    workdayStartMinute: 0,
    gracePeriodMinutes: 15,
    workdayEndHour: 22,
    workdayEndMinute: 0,
    maxCheckInsPerDay: 1,
    allowedGpsAccuracyMeters: 35.0,
  );

  static final List<User> _mockFacultyRoster = [
    const User(
      id: '22222222-2222-2222-2222-222222222222',
      fullName: 'Prof. Evelyn Reed',
      email: 'teacher@university.edu',
      role: UserRole.teacher,
      employeeId: 'FAC-CSE-102',
      studentIdNumber: 'FAC-CSE-102',
      designation: 'Associate Professor',
      department: 'Computer Science & Engineering',
      isIrisEnrolled: true,
      isApproved: true,
    ),
    const User(
      id: 'usr-fac-101',
      fullName: 'Dr. Rajesh Kumar',
      email: 'rajesh.kumar@vnrvjiet.in',
      role: UserRole.teacher,
      employeeId: 'FAC-CSE-101',
      studentIdNumber: 'FAC-CSE-101',
      designation: 'Professor & HOD',
      department: 'Computer Science & Engineering',
      isIrisEnrolled: true,
      isApproved: true,
    ),
    const User(
      id: 'usr-fac-201',
      fullName: 'Dr. Suresh Varma',
      email: 'suresh.v@vnrvjiet.in',
      role: UserRole.teacher,
      employeeId: 'FAC-ECE-201',
      studentIdNumber: 'FAC-ECE-201',
      designation: 'Professor',
      department: 'Electronics & Communication',
      isIrisEnrolled: true,
      isApproved: true,
    ),
    const User(
      id: 'usr-fac-301',
      fullName: 'Dr. Ananya Roy',
      email: 'ananya.roy@vnrvjiet.in',
      role: UserRole.teacher,
      employeeId: 'FAC-IT-301',
      studentIdNumber: 'FAC-IT-301',
      designation: 'Assistant Professor',
      department: 'Information Technology',
      isIrisEnrolled: false,
      isApproved: true,
    ),
    const User(
      id: 'usr-fac-401',
      fullName: 'Dr. K. Srinivas',
      email: 'srinivas.k@vnrvjiet.in',
      role: UserRole.teacher,
      employeeId: 'FAC-MECH-401',
      studentIdNumber: 'FAC-MECH-401',
      designation: 'Associate Professor',
      department: 'Mechanical Engineering',
      isIrisEnrolled: true,
      isApproved: false,
    ),
  ];

  static final List<AttendanceSession> _sessions = [
    AttendanceSession(
      id: 'cccccccc-cccc-cccc-cccc-cccccccccccc',
      courseId: 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
      courseName: 'Faculty Daily Campus Duty',
      courseCode: 'FAC-DUTY',
      instructorId: '22222222-2222-2222-2222-222222222222',
      locationId: 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
      sessionTitle: 'Daily Faculty Campus Duty - VNR VJIET',
      status: SessionStatus.active,
      startTime: DateTime.now().subtract(const Duration(hours: 3)),
      endTime: DateTime.now().add(const Duration(hours: 9)),
      verificationWindowMinutes: 720,
    ),
  ];

  static final List<AttendanceRecord> _records = [
    // Pre-populate realistic historical records for faculty
    AttendanceRecord(
      id: 'rec-hist-1',
      sessionId: 'cccccccc-cccc-cccc-cccc-cccccccccccc',
      studentId: '22222222-2222-2222-2222-222222222222',
      studentName: 'Prof. Evelyn Reed',
      studentRollNumber: 'FAC-CSE-102',
      status: AttendanceRecordStatus.present,
      latitude: 17.53852,
      longitude: 78.38521,
      distanceFromCenterMeters: 12.4,
      isWithinGeofence: true,
      irisVerificationHash: 'iris-hash-vnr-9481',
      irisConfidenceScore: 0.96,
      isBiometricallyVerified: true,
      isLate: false,
      recordedAt: DateTime.now().subtract(const Duration(days: 1, hours: 2)),
    ),
    AttendanceRecord(
      id: 'rec-hist-2',
      sessionId: 'cccccccc-cccc-cccc-cccc-cccccccccccc',
      studentId: '22222222-2222-2222-2222-222222222222',
      studentName: 'Prof. Evelyn Reed',
      studentRollNumber: 'FAC-CSE-102',
      status: AttendanceRecordStatus.present,
      latitude: 17.53848,
      longitude: 78.38519,
      distanceFromCenterMeters: 18.2,
      isWithinGeofence: true,
      irisVerificationHash: 'iris-hash-vnr-9482',
      irisConfidenceScore: 0.94,
      isBiometricallyVerified: true,
      isLate: true,
      recordedAt: DateTime.now().subtract(const Duration(days: 2, hours: 1)),
    ),
    AttendanceRecord(
      id: 'rec-hist-3',
      sessionId: 'cccccccc-cccc-cccc-cccc-cccccccccccc',
      studentId: 'usr-fac-101',
      studentName: 'Dr. Rajesh Kumar',
      studentRollNumber: 'FAC-CSE-101',
      status: AttendanceRecordStatus.present,
      latitude: 17.53851,
      longitude: 78.38520,
      distanceFromCenterMeters: 8.5,
      isWithinGeofence: true,
      irisVerificationHash: 'iris-hash-vnr-9483',
      irisConfidenceScore: 0.98,
      isBiometricallyVerified: true,
      isLate: false,
      recordedAt: DateTime.now().subtract(const Duration(hours: 1)),
    ),
  ];

  @override
  Future<List<CampusLocation>> getCampusLocations() async {
    await Future.delayed(const Duration(milliseconds: 200));
    return List.unmodifiable(_locations);
  }

  @override
  Future<List<AttendanceSession>> getActiveSessions() async {
    await Future.delayed(const Duration(milliseconds: 250));
    final currentUser = await _authRepo.getCurrentUser();
    if (currentUser == null) throw Exception('Unauthenticated');
    return List.unmodifiable(_sessions.where((s) => s.status == SessionStatus.active).toList());
  }

  @override
  Future<List<AttendanceRecord>> getAttendanceRecords({String? sessionId}) async {
    await Future.delayed(const Duration(milliseconds: 200));
    final currentUser = await _authRepo.getCurrentUser();
    if (currentUser == null) throw Exception('Unauthenticated');

    if (currentUser.role == UserRole.teacher) {
      if (sessionId != null) {
        return _records.where((r) => r.sessionId == sessionId).toList();
      }
      // Return this faculty member's personal attendance history
      return _records.where((r) => r.studentId == currentUser.id).toList();
    } else if (currentUser.role == UserRole.student) {
      return _records.where((r) => r.studentId == currentUser.id).toList();
    } else {
      // Admins access all faculty attendance records
      if (sessionId != null) {
        return _records.where((r) => r.sessionId == sessionId).toList();
      }
      return List.unmodifiable(_records);
    }
  }

  static void resetMockState() {
    _records.removeWhere((r) {
      final now = DateTime.now();
      return r.recordedAt.year == now.year &&
          r.recordedAt.month == now.month &&
          r.recordedAt.day == now.day;
    });
  }

  bool simulateNetworkFailure = false;

  @override
  Future<AttendanceRecord> submitCheckIn({
    required String sessionId,
    required double latitude,
    required double longitude,
    Map<String, dynamic>? deviceMetadata,
  }) async {
    if (simulateNetworkFailure) {
      throw Exception('Database connection timeout: Unable to reach attendance backend service.');
    }
    await Future.delayed(const Duration(milliseconds: 350));
    final currentUser = await _authRepo.getCurrentUser();
    if (currentUser == null) throw Exception('Unauthenticated request');

    // SERVER-SIDE ACCOUNT & APPROVAL AUTHORIZATION CHECK
    if (currentUser.accountStatus == 'suspended') {
      throw Exception('Faculty account has been suspended by an administrator.');
    }

    if (currentUser.accountStatus == 'inactive') {
      throw Exception('Faculty account is deactivated.');
    }

    if (currentUser.role == UserRole.teacher && (!currentUser.isApproved || currentUser.approvalStatus != FacultyApprovalStatus.approved)) {
      throw Exception('Account pending administrator approval. Please contact the administrator to authorize your faculty account.');
    }

    // SERVER-SIDE ATTENDANCE POLICY: Max 1 check-in per faculty member per day
    final now = DateTime.now();
    final hasCheckedInToday = _records.any(
      (r) =>
          r.studentId == currentUser.id &&
          r.recordedAt.year == now.year &&
          r.recordedAt.month == now.month &&
          r.recordedAt.day == now.day &&
          r.status == AttendanceRecordStatus.present,
    );

    if (hasCheckedInToday) {
      final existing = _records.firstWhere(
        (r) =>
            r.studentId == currentUser.id &&
            r.recordedAt.year == now.year &&
            r.recordedAt.month == now.month &&
            r.recordedAt.day == now.day,
      );
      final timeStr =
          '${existing.recordedAt.hour.toString().padLeft(2, "0")}:${existing.recordedAt.minute.toString().padLeft(2, "0")}';
      throw Exception('Attendance already recorded today at $timeStr. Duplicate submissions are strictly prevented.');
    }

    // Check user coordinates against ANY active campus / hostel location
    CampusLocation matchedLocation = _locations.first;
    double minDistance = double.infinity;
    bool isWithinGeofence = false;

    for (final loc in _locations.where((l) => l.isActive)) {
      final dist = GeoUtils.calculateDistanceInMeters(
        startLatitude: latitude,
        startLongitude: longitude,
        endLatitude: loc.centerLatitude,
        endLongitude: loc.centerLongitude,
      );
      if (dist < minDistance) {
        minDistance = dist;
        matchedLocation = loc;
      }
      if (dist <= loc.bufferRadiusMeters) {
        isWithinGeofence = true;
        matchedLocation = loc;
        minDistance = dist;
        break;
      }
    }

    final isLate = _policy.isLateArrival(now);

    final record = AttendanceRecord(
      id: 'rec-${DateTime.now().millisecondsSinceEpoch}',
      sessionId: sessionId,
      studentId: currentUser.id,
      studentName: currentUser.fullName,
      studentRollNumber: currentUser.employeeId ?? currentUser.studentIdNumber ?? 'FAC-CSE-102',
      status: isWithinGeofence
          ? AttendanceRecordStatus.present
          : AttendanceRecordStatus.flaggedOutsideGeofence,
      latitude: latitude,
      longitude: longitude,
      distanceFromCenterMeters: minDistance,
      isWithinGeofence: isWithinGeofence,
      irisVerificationHash: 'iris-sha256-verified',
      irisConfidenceScore: 0.95,
      isBiometricallyVerified: isWithinGeofence,
      isLate: isLate,
      recordedAt: now,
    );

    _records.insert(0, record);
    return record;
  }

  // Active in-memory single-use nonces: { nonceString: { 'userId': id, 'sessionId': sid, 'expiresAt': time, 'isConsumed': bool } }
  static final Map<String, Map<String, dynamic>> _nonces = {};

  @override
  Future<String> requestVerificationNonce({required String sessionId}) async {
    await Future.delayed(const Duration(milliseconds: 150));
    final currentUser = await _authRepo.getCurrentUser();
    if (currentUser == null) throw Exception('Unauthenticated');

    final nonce = 'nonce-${DateTime.now().microsecondsSinceEpoch}';
    _nonces[nonce] = {
      'userId': currentUser.id,
      'sessionId': sessionId,
      'expiresAt': DateTime.now().add(const Duration(seconds: 90)),
      'isConsumed': false,
    };
    return nonce;
  }

  @override
  Future<AttendanceRecord> submitHardenedAttendance({
    required String sessionId,
    required String nonce,
    required double latitude,
    required double longitude,
    required double livenessScore,
    required String challengeType,
    required String deviceSignature,
    Map<String, dynamic>? deviceMetadata,
  }) async {
    await Future.delayed(const Duration(milliseconds: 300));
    final currentUser = await _authRepo.getCurrentUser();
    if (currentUser == null) throw Exception('Unauthenticated request');

    // 1. NONCE VALIDATION & REPLAY DEFENSE
    final nonceData = _nonces[nonce];
    if (nonceData == null || nonceData['userId'] != currentUser.id) {
      throw Exception('Security Rejection: Invalid or forged server nonce.');
    }

    if (nonceData['isConsumed'] == true) {
      throw Exception('Replay Attack Detected: Nonce has already been consumed.');
    }

    if (DateTime.now().isAfter(nonceData['expiresAt'] as DateTime)) {
      throw Exception('Expired Request: Nonce validity window (90s) timed out.');
    }

    // Invalidate nonce immediately (single-use)
    nonceData['isConsumed'] = true;

    // 2. LIVENESS SCORE DEFENSE (Must be >= 0.70)
    if (livenessScore < 0.70) {
      throw Exception('Biometric Security Rejection: Liveness verification failed (Score: $livenessScore). Possible presentation attack.');
    }

    // 3. PROCEED TO SUBMIT ATTENDANCE (Checks duplicate submission and geofencing)
    return await submitCheckIn(
      sessionId: sessionId,
      latitude: latitude,
      longitude: longitude,
      deviceMetadata: {
        ...?deviceMetadata,
        'liveness_score': livenessScore,
        'challenge_type': challengeType,
        'device_signature': deviceSignature,
        'nonce_used': nonce,
      },
    );
  }

  @override
  Future<AttendanceSession> createSession({
    required String courseId,
    required String locationId,
    required String sessionTitle,
    required DateTime startTime,
    required DateTime endTime,
    int verificationWindowMinutes = 15,
  }) async {
    await Future.delayed(const Duration(milliseconds: 350));
    final currentUser = await _authRepo.getCurrentUser();
    if (currentUser == null || currentUser.role == UserRole.student) {
      throw Exception('Unauthorized: Only teachers and administrators can create sessions.');
    }

    final newSession = AttendanceSession(
      id: 'sess-${DateTime.now().millisecondsSinceEpoch}',
      courseId: courseId,
      courseName: 'CS-402: Distributed Systems',
      courseCode: 'CS-402',
      instructorId: currentUser.id,
      locationId: locationId,
      sessionTitle: sessionTitle,
      status: SessionStatus.active,
      startTime: startTime,
      endTime: endTime,
      verificationWindowMinutes: verificationWindowMinutes,
    );

    _sessions.add(newSession);
    return newSession;
  }

  @override
  Future<void> updateSessionStatus({
    required String sessionId,
    required SessionStatus status,
  }) async {
    await Future.delayed(const Duration(milliseconds: 250));
    final idx = _sessions.indexWhere((s) => s.id == sessionId);
    if (idx != -1) {
      final old = _sessions[idx];
      _sessions[idx] = AttendanceSession(
        id: old.id,
        courseId: old.courseId,
        courseName: old.courseName,
        courseCode: old.courseCode,
        instructorId: old.instructorId,
        locationId: old.locationId,
        sessionTitle: old.sessionTitle,
        status: status,
        startTime: old.startTime,
        endTime: old.endTime,
        verificationWindowMinutes: old.verificationWindowMinutes,
      );
    }
  }

  // In-memory audit log store
  static final List<AuditEvent> _auditLogs = [
    AuditEvent(
      id: 'audit-init-001',
      actorId: 'usr-admin-001',
      actorEmail: 'admin@university.edu',
      action: 'SYSTEM_BOOT',
      resourceType: 'system',
      details: {'message': 'Iris Attendance Security Engine Initialized with PostGIS and Edge Biometrics.'},
      timestamp: DateTime.now().subtract(const Duration(hours: 12)),
    ),
  ];

  @override
  Future<void> submitAttendanceCorrection({
    required String recordId,
    required AttendanceRecordStatus newStatus,
    required String justificationReason,
  }) async {
    await Future.delayed(const Duration(milliseconds: 300));
    final currentUser = await _authRepo.getCurrentUser();
    if (currentUser == null) throw Exception('Unauthenticated request');

    if (currentUser.role != UserRole.teacher && currentUser.role != UserRole.admin) {
      throw Exception('Unauthorized: Only teachers and administrators can perform attendance corrections.');
    }

    if (justificationReason.trim().isEmpty) {
      throw Exception('Audit Compliance Violation: A clear justification reason is strictly required for attendance corrections.');
    }

    final index = _records.indexWhere((r) => r.id == recordId);
    if (index == -1) {
      throw Exception('Record Not Found: Attendance record with id $recordId does not exist.');
    }

    final oldRecord = _records[index];
    final updatedRecord = oldRecord.copyWith(
      status: newStatus,
      correctionReason: justificationReason,
      correctedBy: currentUser.email,
    );
    _records[index] = updatedRecord;

    // Log audited event
    _auditLogs.insert(
      0,
      AuditEvent(
        id: 'audit-${DateTime.now().millisecondsSinceEpoch}',
        actorId: currentUser.id,
        actorEmail: currentUser.email,
        action: 'ATTENDANCE_MANUAL_CORRECTION',
        resourceType: 'attendance_record',
        resourceId: recordId,
        details: {
          'previous_status': oldRecord.status.name,
          'new_status': newStatus.name,
          'student_id': oldRecord.studentId,
          'session_id': oldRecord.sessionId,
          'justification': justificationReason,
          'operator_role': currentUser.role.name,
        },
        timestamp: DateTime.now(),
      ),
    );
  }

  @override
  Future<List<AuditEvent>> getAuditLogs({int limit = 50}) async {
    await Future.delayed(const Duration(milliseconds: 250));
    final currentUser = await _authRepo.getCurrentUser();
    if (currentUser == null) throw Exception('Unauthenticated request');

    if (currentUser.role != UserRole.admin) {
      throw Exception('Unauthorized: System audit logs are restricted to Administrator accounts.');
    }

    return List.unmodifiable(_auditLogs.take(limit).toList());
  }

  @override
  Future<void> updateCampusBoundary({
    required String locationId,
    required double centerLatitude,
    required double centerLongitude,
    required double bufferRadiusMeters,
  }) async {
    await Future.delayed(const Duration(milliseconds: 300));
    final currentUser = await _authRepo.getCurrentUser();
    if (currentUser == null) throw Exception('Unauthenticated request');

    if (currentUser.role != UserRole.admin) {
      throw Exception('Unauthorized: Modifying campus geofence perimeters requires Administrator credentials.');
    }

    final index = _locations.indexWhere((l) => l.id == locationId);
    if (index == -1) {
      throw Exception('Location Not Found: Campus location $locationId does not exist.');
    }

    final oldLoc = _locations[index];
    _locations[index] = CampusLocation(
      id: oldLoc.id,
      code: oldLoc.code,
      name: oldLoc.name,
      description: oldLoc.description,
      centerLatitude: centerLatitude,
      centerLongitude: centerLongitude,
      bufferRadiusMeters: bufferRadiusMeters,
      boundaryPolygon: oldLoc.boundaryPolygon,
      isActive: oldLoc.isActive,
    );

    // Audit log boundary change
    _auditLogs.insert(
      0,
      AuditEvent(
        id: 'audit-${DateTime.now().millisecondsSinceEpoch}',
        actorId: currentUser.id,
        actorEmail: currentUser.email,
        action: 'CAMPUS_BOUNDARY_UPDATED',
        resourceType: 'campus_location',
        resourceId: locationId,
        details: {
          'location_name': oldLoc.name,
          'new_center_lat': centerLatitude,
          'new_center_lng': centerLongitude,
          'new_buffer_radius_meters': bufferRadiusMeters,
        },
        timestamp: DateTime.now(),
      ),
    );
  }

  @override
  Future<void> requestBiometricTemplateDeletion({required String userId}) async {
    await Future.delayed(const Duration(milliseconds: 350));
    final currentUser = await _authRepo.getCurrentUser();
    if (currentUser == null) throw Exception('Unauthenticated request');

    if (currentUser.role != UserRole.admin && currentUser.id != userId) {
      throw Exception('Unauthorized: You can only request deletion of your own biometric template or require Admin permissions.');
    }

    // Audit log biometric template deletion under GDPR / DPDP right to be forgotten
    _auditLogs.insert(
      0,
      AuditEvent(
        id: 'audit-${DateTime.now().millisecondsSinceEpoch}',
        actorId: currentUser.id,
        actorEmail: currentUser.email,
        action: 'BIOMETRIC_TEMPLATE_DELETION_PURGED',
        resourceType: 'biometric_template',
        resourceId: userId,
        details: {
          'target_user_id': userId,
          'regulatory_policy': 'Right to be Forgotten (GDPR Art. 17 / DPDP)',
          'status': 'SECURELY_ERASED',
        },
        timestamp: DateTime.now(),
      ),
    );
  }

  @override
  Future<String> exportAttendanceReportToCsv({String? sessionId}) async {
    await Future.delayed(const Duration(milliseconds: 300));
    final currentUser = await _authRepo.getCurrentUser();
    if (currentUser == null) throw Exception('Unauthenticated request');

    if (currentUser.role != UserRole.teacher && currentUser.role != UserRole.admin) {
      throw Exception('Unauthorized: Exporting attendance reports is restricted to Teachers and Administrators.');
    }

    final records = await getAttendanceRecords(sessionId: sessionId);
    final buffer = StringBuffer();
    // CSV Header
    buffer.writeln('Record ID,Session ID,Student ID,Student Name,Roll Number,Status,Recorded At,Latitude,Longitude,Within Geofence,Distance (m),Biometric Verified,Correction Reason,Corrected By');

    for (final r in records) {
      final line = [
        '"${r.id}"',
        '"${r.sessionId}"',
        '"${r.studentId}"',
        '"${r.studentName ?? ""}"',
        '"${r.studentRollNumber ?? ""}"',
        '"${r.status.name}"',
        '"${r.recordedAt.toIso8601String()}"',
        r.latitude.toStringAsFixed(6),
        r.longitude.toStringAsFixed(6),
        r.isWithinGeofence ? 'YES' : 'NO',
        r.distanceFromCenterMeters != null ? r.distanceFromCenterMeters!.toStringAsFixed(2) : 'N/A',
        r.isBiometricallyVerified ? 'YES' : 'NO',
        '"${r.correctionReason ?? ""}"',
        '"${r.correctedBy ?? ""}"',
      ].join(',');
      buffer.writeln(line);
    }

    return buffer.toString();
  }

  @override
  Future<AttendancePolicy> getAttendancePolicy() async {
    await Future.delayed(const Duration(milliseconds: 150));
    return _policy;
  }

  @override
  Future<void> updateAttendancePolicy(AttendancePolicy policy) async {
    await Future.delayed(const Duration(milliseconds: 250));
    final currentUser = await _authRepo.getCurrentUser();
    if (currentUser == null) throw Exception('Unauthenticated request');
    if (currentUser.role != UserRole.admin) {
      throw Exception('Unauthorized: Only administrators can modify institutional attendance policy.');
    }

    _policy = policy;
  }

  @override
  Future<List<User>> getAllFaculty() async {
    await Future.delayed(const Duration(milliseconds: 200));
    final roster = List<User>.from(_mockFacultyRoster);
    for (final u in DevMockAuthRepository.getAllRegisteredUsers()) {
      if (u.role == UserRole.teacher && !roster.any((f) => f.id == u.id || f.email == u.email)) {
        roster.add(u);
      }
    }
    return List.unmodifiable(roster);
  }

  @override
  Future<void> approveFaculty({required String facultyId, required bool isApproved}) async {
    await Future.delayed(const Duration(milliseconds: 200));
    final currentUser = await _authRepo.getCurrentUser();
    if (currentUser == null) throw Exception('Unauthenticated request');

    if (currentUser.role != UserRole.admin) {
      throw Exception('Unauthorized: Only administrators can approve faculty enrollment requests.');
    }

    if (currentUser.id == facultyId) {
      throw Exception('Security violation: Faculty members cannot approve their own biometric enrollment.');
    }

    final idx = _mockFacultyRoster.indexWhere((f) => f.id == facultyId);
    if (idx != -1) {
      _mockFacultyRoster[idx] = _mockFacultyRoster[idx].copyWith(
        isApproved: isApproved,
        approvalStatus: isApproved ? FacultyApprovalStatus.approved : FacultyApprovalStatus.rejected,
        reviewedAt: DateTime.now(),
        rejectionReason: isApproved ? null : 'Approval revoked by administrator.',
      );
    }
    DevMockAuthRepository.setApproval(facultyId, isApproved);

    _auditLogs.insert(
      0,
      AuditEvent(
        id: 'audit-${DateTime.now().millisecondsSinceEpoch}',
        actorId: currentUser.id,
        actorEmail: currentUser.email,
        action: isApproved ? 'FACULTY_ENROLLMENT_APPROVED' : 'FACULTY_ENROLLMENT_REVOKED',
        resourceType: 'profiles',
        resourceId: facultyId,
        details: {
          'target_faculty_id': facultyId,
          'reviewed_by_admin': currentUser.email,
          'action_status': isApproved ? 'APPROVED' : 'REVOKED',
        },
        timestamp: DateTime.now(),
      ),
    );
  }

  @override
  Future<void> rejectFaculty({required String facultyId, required String rejectionReason}) async {
    await Future.delayed(const Duration(milliseconds: 200));
    final currentUser = await _authRepo.getCurrentUser();
    if (currentUser == null) throw Exception('Unauthenticated request');

    if (currentUser.role != UserRole.admin) {
      throw Exception('Unauthorized: Only administrators can reject faculty enrollment requests.');
    }

    final reason = rejectionReason.trim().isEmpty
        ? 'Photograph does not meet facial biometric quality standards.'
        : rejectionReason.trim();

    final idx = _mockFacultyRoster.indexWhere((f) => f.id == facultyId);
    if (idx != -1) {
      _mockFacultyRoster[idx] = _mockFacultyRoster[idx].copyWith(
        isApproved: false,
        approvalStatus: FacultyApprovalStatus.rejected,
        rejectionReason: reason,
        reviewedAt: DateTime.now(),
      );
    }
    DevMockAuthRepository.rejectUser(facultyId, reason);

    _auditLogs.insert(
      0,
      AuditEvent(
        id: 'audit-${DateTime.now().millisecondsSinceEpoch}',
        actorId: currentUser.id,
        actorEmail: currentUser.email,
        action: 'FACULTY_ENROLLMENT_REJECTED',
        resourceType: 'profiles',
        resourceId: facultyId,
        details: {
          'target_faculty_id': facultyId,
          'rejection_reason': reason,
          'reviewed_by_admin': currentUser.email,
          'action_status': 'REJECTED',
        },
        timestamp: DateTime.now(),
      ),
    );
  }

  @override
  Future<void> requestPhotoReEnrollment({required String facultyId}) async {
    await Future.delayed(const Duration(milliseconds: 200));
    final idx = _mockFacultyRoster.indexWhere((f) => f.id == facultyId);
    if (idx != -1) {
      _mockFacultyRoster[idx] = _mockFacultyRoster[idx].copyWith(
        isIrisEnrolled: false,
        isApproved: false,
        approvalStatus: FacultyApprovalStatus.pending,
        rejectionReason: 'Administrator requested fresh face photograph submission.',
        reviewedAt: DateTime.now(),
      );
    }
    DevMockAuthRepository.requestReEnrollment(facultyId);
  }

  @override
  Future<void> updateAccountStatus({required String facultyId, required String accountStatus}) async {
    await Future.delayed(const Duration(milliseconds: 200));
    final idx = _mockFacultyRoster.indexWhere((f) => f.id == facultyId);
    if (idx != -1) {
      _mockFacultyRoster[idx] = _mockFacultyRoster[idx].copyWith(
        accountStatus: accountStatus,
      );
    }
    DevMockAuthRepository.setAccountStatus(facultyId, accountStatus);
  }
}

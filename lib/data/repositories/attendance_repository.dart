import '../models/attendance_policy_model.dart';
import '../models/attendance_record_model.dart';
import '../models/attendance_session_model.dart';
import '../models/audit_event_model.dart';
import '../models/campus_location_model.dart';
import '../models/user_model.dart';

abstract class AttendanceRepository {
  /// Fetch all active sessions accessible to the current user (filtered by enrollment/instruction/admin)
  Future<List<AttendanceSession>> getActiveSessions();

  /// Fetch attendance history for the authenticated student or for a specific session (teachers/admins)
  Future<List<AttendanceRecord>> getAttendanceRecords({String? sessionId});

  /// Request a short-lived single-use verification nonce (Valid for 90s)
  Future<String> requestVerificationNonce({required String sessionId});

  /// Submit geofence check-in for an active session
  /// Enforces server-side geofence calculation and duplicate submission prevention
  Future<AttendanceRecord> submitCheckIn({
    required String sessionId,
    required double latitude,
    required double longitude,
    Map<String, dynamic>? deviceMetadata,
  });

  /// Submit hardened attendance with single-use nonce, liveness score, challenge type, and device key signature
  Future<AttendanceRecord> submitHardenedAttendance({
    required String sessionId,
    required String nonce,
    required double latitude,
    required double longitude,
    required double livenessScore,
    required String challengeType,
    required String deviceSignature,
    Map<String, dynamic>? deviceMetadata,
  });

  /// Fetch campus boundary locations
  Future<List<CampusLocation>> getCampusLocations();

  /// Create a new attendance session (Restricted to assigned faculty & admins)
  Future<AttendanceSession> createSession({
    required String courseId,
    required String locationId,
    required String sessionTitle,
    required DateTime startTime,
    required DateTime endTime,
    int verificationWindowMinutes,
  });

  /// Close or cancel an attendance session
  Future<void> updateSessionStatus({
    required String sessionId,
    required SessionStatus status,
  });

  /// Submit an audited manual attendance correction (Teachers and Admins only)
  Future<void> submitAttendanceCorrection({
    required String recordId,
    required AttendanceRecordStatus newStatus,
    required String justificationReason,
  });

  /// Fetch system audit events (Admin only)
  Future<List<AuditEvent>> getAuditLogs({int limit = 50});

  /// Update campus geofence boundary coordinates (Admin only)
  Future<void> updateCampusBoundary({
    required String locationId,
    required double centerLatitude,
    required double centerLongitude,
    required double bufferRadiusMeters,
  });

  /// Manage biometric template deletion request (Compliance with Right to be Forgotten)
  Future<void> requestBiometricTemplateDeletion({required String userId});

  /// Export attendance report to CSV string
  Future<String> exportAttendanceReportToCsv({String? sessionId});

  /// Get current institutional attendance policy (working hours, grace period, check-in rules)
  Future<AttendancePolicy> getAttendancePolicy();

  /// Update attendance policy (Admin only)
  Future<void> updateAttendancePolicy(AttendancePolicy policy);

  /// Fetch all faculty profiles for admin roster management
  Future<List<User>> getAllFaculty();

  /// Update faculty approval status (Admin only)
  Future<void> approveFaculty({required String facultyId, required bool isApproved});

  /// Reject faculty face verification request with reason (Admin only)
  Future<void> rejectFaculty({required String facultyId, required String rejectionReason});

  /// Request faculty re-submit facial photograph (Admin only)
  Future<void> requestPhotoReEnrollment({required String facultyId});

  /// Update faculty account status (active, suspended, inactive) (Admin only)
  Future<void> updateAccountStatus({required String facultyId, required String accountStatus});
}

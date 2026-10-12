enum AttendanceRecordStatus {
  pendingVerification,
  present,
  absent,
  flaggedOutsideGeofence,
  biometricRejected,
}

class AttendanceRecord {
  final String id;
  final String sessionId;
  final String studentId;
  final String? studentName;
  final String? studentRollNumber;
  final AttendanceRecordStatus status;
  final double latitude;
  final double longitude;
  final double? distanceFromCenterMeters;
  final bool isWithinGeofence;
  final String? irisVerificationHash;
  final double irisConfidenceScore;
  final bool isBiometricallyVerified;
  final String? correctionReason;
  final String? correctedBy;
  final bool isLate;
  final DateTime recordedAt;

  const AttendanceRecord({
    required this.id,
    required this.sessionId,
    required this.studentId,
    this.studentName,
    this.studentRollNumber,
    required this.status,
    required this.latitude,
    required this.longitude,
    this.distanceFromCenterMeters,
    required this.isWithinGeofence,
    this.irisVerificationHash,
    this.irisConfidenceScore = 0.0,
    this.isBiometricallyVerified = false,
    this.correctionReason,
    this.correctedBy,
    this.isLate = false,
    required this.recordedAt,
  });

  /// Faculty domain convenience getters
  String get facultyId => studentId;
  String? get facultyName => studentName;
  String? get employeeId => studentRollNumber;

  factory AttendanceRecord.fromMap(Map<String, dynamic> map) {
    final statusStr = (map['status'] as String?)?.toLowerCase();
    AttendanceRecordStatus status;
    switch (statusStr) {
      case 'present':
        status = AttendanceRecordStatus.present;
        break;
      case 'absent':
        status = AttendanceRecordStatus.absent;
        break;
      case 'flagged_outside_geofence':
        status = AttendanceRecordStatus.flaggedOutsideGeofence;
        break;
      case 'biometric_rejected':
        status = AttendanceRecordStatus.biometricRejected;
        break;
      case 'pending_verification':
      default:
        status = AttendanceRecordStatus.pendingVerification;
        break;
    }

    String? name = map['student_name'] as String? ?? map['faculty_name'] as String?;
    String? roll = map['student_roll_number'] as String? ?? map['employee_id'] as String?;
    if (map['profiles'] is Map) {
      name = (map['profiles']['full_name'] as String?) ?? name;
      roll = (map['profiles']['employee_id'] as String?) ??
          (map['profiles']['student_id_number'] as String?) ??
          roll;
    }

    final recordedAt = DateTime.tryParse(map['recorded_at'] as String? ?? '') ?? DateTime.now();
    final isLateParsed = (map['is_late'] as bool?) ??
        (recordedAt.hour > 9 || (recordedAt.hour == 9 && recordedAt.minute > 15));

    return AttendanceRecord(
      id: map['id'] as String,
      sessionId: map['session_id'] as String,
      studentId: map['student_id'] as String,
      studentName: name,
      studentRollNumber: roll,
      status: status,
      latitude: (map['latitude'] as num?)?.toDouble() ?? 0.0,
      longitude: (map['longitude'] as num?)?.toDouble() ?? 0.0,
      distanceFromCenterMeters: (map['distance_from_center_meters'] as num?)?.toDouble(),
      isWithinGeofence: (map['is_within_geofence'] as bool?) ?? false,
      irisVerificationHash: map['iris_verification_hash'] as String?,
      irisConfidenceScore: (map['iris_confidence_score'] as num?)?.toDouble() ?? 0.0,
      isBiometricallyVerified: (map['is_biometrically_verified'] as bool?) ?? false,
      correctionReason: map['correction_reason'] as String?,
      correctedBy: map['corrected_by'] as String?,
      isLate: isLateParsed,
      recordedAt: recordedAt,
    );
  }

  AttendanceRecord copyWith({
    String? id,
    String? sessionId,
    String? studentId,
    String? studentName,
    String? studentRollNumber,
    AttendanceRecordStatus? status,
    double? latitude,
    double? longitude,
    double? distanceFromCenterMeters,
    bool? isWithinGeofence,
    String? irisVerificationHash,
    double? irisConfidenceScore,
    bool? isBiometricallyVerified,
    String? correctionReason,
    String? correctedBy,
    bool? isLate,
    DateTime? recordedAt,
  }) {
    return AttendanceRecord(
      id: id ?? this.id,
      sessionId: sessionId ?? this.sessionId,
      studentId: studentId ?? this.studentId,
      studentName: studentName ?? this.studentName,
      studentRollNumber: studentRollNumber ?? this.studentRollNumber,
      status: status ?? this.status,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      distanceFromCenterMeters: distanceFromCenterMeters ?? this.distanceFromCenterMeters,
      isWithinGeofence: isWithinGeofence ?? this.isWithinGeofence,
      irisVerificationHash: irisVerificationHash ?? this.irisVerificationHash,
      irisConfidenceScore: irisConfidenceScore ?? this.irisConfidenceScore,
      isBiometricallyVerified: isBiometricallyVerified ?? this.isBiometricallyVerified,
      correctionReason: correctionReason ?? this.correctionReason,
      correctedBy: correctedBy ?? this.correctedBy,
      isLate: isLate ?? this.isLate,
      recordedAt: recordedAt ?? this.recordedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'session_id': sessionId,
      'student_id': studentId,
      'faculty_id': studentId,
      'faculty_name': studentName,
      'employee_id': studentRollNumber,
      'status': status.name,
      'latitude': latitude,
      'longitude': longitude,
      'distance_from_center_meters': distanceFromCenterMeters,
      'is_within_geofence': isWithinGeofence,
      'iris_verification_hash': irisVerificationHash,
      'iris_confidence_score': irisConfidenceScore,
      'is_biometrically_verified': isBiometricallyVerified,
      'correction_reason': correctionReason,
      'corrected_by': correctedBy,
      'is_late': isLate,
      'recorded_at': recordedAt.toIso8601String(),
    };
  }
}

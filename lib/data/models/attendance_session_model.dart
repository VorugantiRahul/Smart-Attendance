enum SessionStatus { scheduled, active, closed, cancelled }

class AttendanceSession {
  final String id;
  final String courseId;
  final String courseName;
  final String courseCode;
  final String instructorId;
  final String locationId;
  final String sessionTitle;
  final SessionStatus status;
  final DateTime startTime;
  final DateTime endTime;
  final int verificationWindowMinutes;

  const AttendanceSession({
    required this.id,
    required this.courseId,
    required this.courseName,
    required this.courseCode,
    required this.instructorId,
    required this.locationId,
    required this.sessionTitle,
    required this.status,
    required this.startTime,
    required this.endTime,
    this.verificationWindowMinutes = 15,
  });

  factory AttendanceSession.fromMap(Map<String, dynamic> map) {
    final statusStr = (map['status'] as String?)?.toLowerCase();
    final status = SessionStatus.values.firstWhere(
      (s) => s.name == statusStr,
      orElse: () => SessionStatus.scheduled,
    );

    return AttendanceSession(
      id: map['id'] as String,
      courseId: map['course_id'] as String,
      courseName: (map['course_name'] as String?) ?? 'Course',
      courseCode: (map['course_code'] as String?) ?? 'CS',
      instructorId: map['instructor_id'] as String,
      locationId: map['location_id'] as String,
      sessionTitle: map['session_title'] as String,
      status: status,
      startTime: DateTime.tryParse(map['start_time'] as String? ?? '') ?? DateTime.now(),
      endTime: DateTime.tryParse(map['end_time'] as String? ?? '') ??
          DateTime.now().add(const Duration(minutes: 60)),
      verificationWindowMinutes: (map['verification_window_minutes'] as int?) ?? 15,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'course_id': courseId,
      'instructor_id': instructorId,
      'location_id': locationId,
      'session_title': sessionTitle,
      'status': status.name,
      'start_time': startTime.toIso8601String(),
      'end_time': endTime.toIso8601String(),
      'verification_window_minutes': verificationWindowMinutes,
    };
  }
}

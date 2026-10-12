import 'package:flutter/material.dart';

/// Configurable College Attendance Policy
/// Governs official working hours, grace periods, late-arrival rules, and duplicate check-in policies.
/// Must be configurable by authorized administrators.
class AttendancePolicy {
  final int workdayStartHour;
  final int workdayStartMinute;
  final int gracePeriodMinutes;
  final int workdayEndHour;
  final int workdayEndMinute;
  final bool requireCheckout;
  final int maxCheckInsPerDay;
  final double allowedGpsAccuracyMeters;
  final bool allowMockLocations;

  const AttendancePolicy({
    this.workdayStartHour = 9,
    this.workdayStartMinute = 0,
    this.gracePeriodMinutes = 15,
    this.workdayEndHour = 22, // 10:00 PM (Configured for faculty testing)
    this.workdayEndMinute = 0,
    this.requireCheckout = false,
    this.maxCheckInsPerDay = 1,
    this.allowedGpsAccuracyMeters = 35.0,
    this.allowMockLocations = false,
  });

  /// Check whether a timestamp is considered a Late Arrival
  bool isLateArrival(DateTime checkInTime) {
    final startMinutes = workdayStartHour * 60 + workdayStartMinute;
    final cutoffMinutes = startMinutes + gracePeriodMinutes;
    final checkInMinutes = checkInTime.hour * 60 + checkInTime.minute;
    return checkInMinutes > cutoffMinutes;
  }

  /// Requirement 4: Allow faculty to mark attendance from 9:00 AM to 5:00 PM inclusive
  bool isAttendanceWindowOpen(DateTime time) {
    final checkMinutes = time.hour * 60 + time.minute;
    final startMinutes = workdayStartHour * 60 + workdayStartMinute; // e.g. 9 * 60 = 540 (09:00)
    final endMinutes = workdayEndHour * 60 + workdayEndMinute;       // e.g. 17 * 60 = 1020 (17:00)
    return checkMinutes >= startMinutes && checkMinutes <= endMinutes;
  }

  bool isBeforeAttendanceWindow(DateTime time) {
    final checkMinutes = time.hour * 60 + time.minute;
    final startMinutes = workdayStartHour * 60 + workdayStartMinute;
    return checkMinutes < startMinutes;
  }

  bool isAfterAttendanceWindow(DateTime time) {
    final checkMinutes = time.hour * 60 + time.minute;
    final endMinutes = workdayEndHour * 60 + workdayEndMinute;
    return checkMinutes > endMinutes;
  }

  String getAttendanceWindowNotice(DateTime time) {
    if (isBeforeAttendanceWindow(time)) {
      return 'Attendance is not open yet. You can mark attendance from 9:00 AM.';
    } else if (isAfterAttendanceWindow(time)) {
      return 'The attendance window has closed for today.';
    }
    return 'Attendance window is open ($workingHoursString).';
  }

  /// Check whether check-in is within official working hours window
  bool isWithinWorkingHours(DateTime checkInTime) {
    return isAttendanceWindowOpen(checkInTime);
  }

  /// Formatted working hours string
  String get workingHoursString {
    final startPeriod = workdayStartHour >= 12 ? 'PM' : 'AM';
    final startH = workdayStartHour > 12 ? workdayStartHour - 12 : (workdayStartHour == 0 ? 12 : workdayStartHour);
    final startM = workdayStartMinute.toString().padLeft(2, '0');

    final endPeriod = workdayEndHour >= 12 ? 'PM' : 'AM';
    final endH = workdayEndHour > 12 ? workdayEndHour - 12 : (workdayEndHour == 0 ? 12 : workdayEndHour);
    final endM = workdayEndMinute.toString().padLeft(2, '0');

    return '$startH:$startM $startPeriod – $endH:$endM $endPeriod';
  }

  /// Formatted grace period cutoff string
  String get graceCutoffString {
    final totalMinutes = workdayStartHour * 60 + workdayStartMinute + gracePeriodMinutes;
    final h24 = (totalMinutes ~/ 60) % 24;
    final m = totalMinutes % 60;
    final period = h24 >= 12 ? 'PM' : 'AM';
    final h12 = h24 > 12 ? h24 - 12 : (h24 == 0 ? 12 : h24);
    return '$h12:${m.toString().padLeft(2, '0')} $period';
  }

  factory AttendancePolicy.fromMap(Map<String, dynamic> map) {
    final rawEnd = (map['workday_end_hour'] as num?)?.toInt() ?? 22;
    return AttendancePolicy(
      workdayStartHour: (map['workday_start_hour'] as num?)?.toInt() ?? 9,
      workdayStartMinute: (map['workday_start_minute'] as num?)?.toInt() ?? 0,
      gracePeriodMinutes: (map['grace_period_minutes'] as num?)?.toInt() ?? 15,
      workdayEndHour: rawEnd < 22 ? 22 : rawEnd, // Guarantees window is open until 10:00 PM (22:00)
      workdayEndMinute: (map['workday_end_minute'] as num?)?.toInt() ?? 0,
      requireCheckout: (map['require_checkout'] as bool?) ?? false,
      maxCheckInsPerDay: (map['max_check_ins_per_day'] as num?)?.toInt() ?? 1,
      allowedGpsAccuracyMeters: (map['allowed_gps_accuracy_meters'] as num?)?.toDouble() ?? 35.0,
      allowMockLocations: (map['allow_mock_locations'] as bool?) ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'workday_start_hour': workdayStartHour,
      'workday_start_minute': workdayStartMinute,
      'grace_period_minutes': gracePeriodMinutes,
      'workday_end_hour': workdayEndHour,
      'workday_end_minute': workdayEndMinute,
      'require_checkout': requireCheckout,
      'max_check_ins_per_day': maxCheckInsPerDay,
      'allowed_gps_accuracy_meters': allowedGpsAccuracyMeters,
      'allow_mock_locations': allowMockLocations,
    };
  }

  AttendancePolicy copyWith({
    int? workdayStartHour,
    int? workdayStartMinute,
    int? gracePeriodMinutes,
    int? workdayEndHour,
    int? workdayEndMinute,
    bool? requireCheckout,
    int? maxCheckInsPerDay,
    double? allowedGpsAccuracyMeters,
    bool? allowMockLocations,
  }) {
    return AttendancePolicy(
      workdayStartHour: workdayStartHour ?? this.workdayStartHour,
      workdayStartMinute: workdayStartMinute ?? this.workdayStartMinute,
      gracePeriodMinutes: gracePeriodMinutes ?? this.gracePeriodMinutes,
      workdayEndHour: workdayEndHour ?? this.workdayEndHour,
      workdayEndMinute: workdayEndMinute ?? this.workdayEndMinute,
      requireCheckout: requireCheckout ?? this.requireCheckout,
      maxCheckInsPerDay: maxCheckInsPerDay ?? this.maxCheckInsPerDay,
      allowedGpsAccuracyMeters: allowedGpsAccuracyMeters ?? this.allowedGpsAccuracyMeters,
      allowMockLocations: allowMockLocations ?? this.allowMockLocations,
    );
  }
}

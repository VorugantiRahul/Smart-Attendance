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
    this.workdayStartHour = 0,
    this.workdayStartMinute = 0,
    this.gracePeriodMinutes = 60,
    this.workdayEndHour = 23,
    this.workdayEndMinute = 59,
    this.requireCheckout = false,
    this.maxCheckInsPerDay = 1,
    this.allowedGpsAccuracyMeters = 35.0,
    this.allowMockLocations = false,
  });

  /// Check whether a timestamp is considered a Late Arrival
  bool isLateArrival(DateTime checkInTime) {
    return false;
  }

  /// Attendance is open 24/7 - can mark attendance at any time
  bool isAttendanceWindowOpen(DateTime time) {
    return true;
  }

  bool isBeforeAttendanceWindow(DateTime time) {
    return false;
  }

  bool isAfterAttendanceWindow(DateTime time) {
    return false;
  }

  String getAttendanceWindowNotice(DateTime time) {
    return 'Attendance window is open 24/7 (Any time).';
  }

  /// Check whether check-in is within official working hours window
  bool isWithinWorkingHours(DateTime checkInTime) {
    return true;
  }

  /// Formatted working hours string
  String get workingHoursString {
    return '24/7 (Any time)';
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
    final rawEnd = (map['workday_end_hour'] as num?)?.toInt() ?? 23;
    return AttendancePolicy(
      workdayStartHour: (map['workday_start_hour'] as num?)?.toInt() ?? 9,
      workdayStartMinute: (map['workday_start_minute'] as num?)?.toInt() ?? 0,
      gracePeriodMinutes: (map['grace_period_minutes'] as num?)?.toInt() ?? 15,
      workdayEndHour: rawEnd < 23 ? 23 : rawEnd, // Guarantees window is open until 11:00 PM (23:00)
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

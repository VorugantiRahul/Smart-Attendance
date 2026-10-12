import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../data/models/attendance_policy_model.dart';
import '../../../../data/models/attendance_record_model.dart';
import '../../../../data/models/attendance_session_model.dart';
import '../../../../data/models/audit_event_model.dart';
import '../../../../data/models/campus_location_model.dart';
import '../../../../data/models/user_model.dart';
import '../../../../data/repositories/attendance_repository.dart';
import '../../../../main.dart';

@immutable
class AdminDashboardState {
  final bool isLoading;
  final String? errorMessage;
  final String? successMessage;
  final List<CampusLocation> locations;
  final List<AttendanceSession> sessions;
  final List<AttendanceRecord> records;
  final List<AuditEvent> auditLogs;
  final List<User> facultyList;
  final AttendancePolicy policy;
  final int selectedTab; // 0: Faculty & Policy, 1: Records & Search, 2: Geofences, 3: Compliance & Audit
  final String searchQuery;
  final String selectedDepartmentFilter;

  const AdminDashboardState({
    this.isLoading = false,
    this.errorMessage,
    this.successMessage,
    this.locations = const [],
    this.sessions = const [],
    this.records = const [],
    this.auditLogs = const [],
    this.facultyList = const [],
    this.policy = const AttendancePolicy(),
    this.selectedTab = 0,
    this.searchQuery = '',
    this.selectedDepartmentFilter = 'ALL',
  });

  AdminDashboardState copyWith({
    bool? isLoading,
    String? errorMessage,
    bool clearError = false,
    String? successMessage,
    bool clearSuccess = false,
    List<CampusLocation>? locations,
    List<AttendanceSession>? sessions,
    List<AttendanceRecord>? records,
    List<AuditEvent>? auditLogs,
    List<User>? facultyList,
    AttendancePolicy? policy,
    int? selectedTab,
    String? searchQuery,
    String? selectedDepartmentFilter,
  }) {
    return AdminDashboardState(
      isLoading: isLoading ?? this.isLoading,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      successMessage: clearSuccess ? null : (successMessage ?? this.successMessage),
      locations: locations ?? this.locations,
      sessions: sessions ?? this.sessions,
      records: records ?? this.records,
      auditLogs: auditLogs ?? this.auditLogs,
      facultyList: facultyList ?? this.facultyList,
      policy: policy ?? this.policy,
      selectedTab: selectedTab ?? this.selectedTab,
      searchQuery: searchQuery ?? this.searchQuery,
      selectedDepartmentFilter: selectedDepartmentFilter ?? this.selectedDepartmentFilter,
    );
  }

  // --- Real-time statistics derived from backend records ---
  int get totalAuthorizedFaculty =>
      facultyList.where((f) => f.isApproved).length;

  List<AttendanceRecord> get todayRecords {
    final now = DateTime.now();
    return records.where((r) {
      return r.recordedAt.year == now.year &&
          r.recordedAt.month == now.month &&
          r.recordedAt.day == now.day;
    }).toList();
  }

  int get todayCompletedCount =>
      todayRecords.where((r) => r.status == AttendanceRecordStatus.present).length;

  int get todayPendingCount =>
      (totalAuthorizedFaculty - todayCompletedCount).clamp(0, 9999);

  int get todayLateCount =>
      todayRecords.where((r) => r.status == AttendanceRecordStatus.present && r.isLate).length;

  int get approvedExceptionsCount =>
      records.where((r) => r.correctionReason != null && r.correctionReason!.isNotEmpty).length;

  int get outsideCount =>
      records.where((r) => r.status == AttendanceRecordStatus.flaggedOutsideGeofence).length;

  int get biometricRejectedCount =>
      records.where((r) => r.status == AttendanceRecordStatus.biometricRejected).length;

  // Department-wise attendance breakdown
  Map<String, int> get departmentWiseTodayCount {
    final map = <String, int>{};
    for (final r in todayRecords.where((r) => r.status == AttendanceRecordStatus.present)) {
      // Find faculty department if available
      final fac = facultyList.firstWhere(
        (f) => f.id == r.studentId,
        orElse: () => const User(
          id: '',
          fullName: '',
          email: '',
          role: UserRole.teacher,
          department: 'General Engineering',
        ),
      );
      final dept = fac.department ?? 'Computer Science & Engineering';
      map[dept] = (map[dept] ?? 0) + 1;
    }
    return map;
  }

  // Filtered records matching search criteria
  List<AttendanceRecord> get filteredRecords {
    return records.where((r) {
      if (searchQuery.trim().isNotEmpty) {
        final q = searchQuery.toLowerCase().trim();
        final name = (r.studentName ?? '').toLowerCase();
        final roll = (r.studentRollNumber ?? '').toLowerCase();
        final id = r.studentId.toLowerCase();
        if (!name.contains(q) && !roll.contains(q) && !id.contains(q)) {
          return false;
        }
      }
      return true;
    }).toList();
  }
}

class AdminDashboardViewModel extends StateNotifier<AdminDashboardState> {
  final AttendanceRepository _repository;

  AdminDashboardViewModel(this._repository) : super(const AdminDashboardState()) {
    loadAdminData();
  }

  Future<void> loadAdminData() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final locations = await _repository.getCampusLocations().catchError((_) => <CampusLocation>[]);
      final sessions = await _repository.getActiveSessions().catchError((_) => <AttendanceSession>[]);
      final records = await _repository.getAttendanceRecords().catchError((_) => <AttendanceRecord>[]);
      final logs = await _repository.getAuditLogs(limit: 50).catchError((_) => <AuditEvent>[]);
      final faculty = await _repository.getAllFaculty().catchError((_) => <User>[]);
      final policy = await _repository.getAttendancePolicy().catchError((_) => state.policy);

      state = state.copyWith(
        isLoading: false,
        locations: locations,
        sessions: sessions,
        records: records,
        auditLogs: logs,
        facultyList: faculty,
        policy: policy,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: e.toString().replaceAll('Exception: ', ''),
      );
    }
  }

  void switchTab(int index) {
    state = state.copyWith(selectedTab: index, clearError: true, clearSuccess: true);
  }

  void setSearchQuery(String query) {
    state = state.copyWith(searchQuery: query);
  }

  void setDepartmentFilter(String dept) {
    state = state.copyWith(selectedDepartmentFilter: dept);
  }

  Future<bool> updatePolicy(AttendancePolicy newPolicy) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      await _repository.updateAttendancePolicy(newPolicy);
      await loadAdminData();
      state = state.copyWith(
        successMessage: 'College attendance policy updated (Working Hours: ${newPolicy.workingHoursString}, Grace: ${newPolicy.gracePeriodMinutes}m).',
      );
      return true;
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: e.toString().replaceAll('Exception: ', ''),
      );
      return false;
    }
  }

  Future<bool> toggleFacultyApproval(String facultyId, bool isApproved) async {
    try {
      await _repository.approveFaculty(facultyId: facultyId, isApproved: isApproved);
      await loadAdminData();
      state = state.copyWith(
        successMessage: isApproved
            ? 'Faculty member face verification approved and authorized for attendance.'
            : 'Faculty member authorization revoked.',
      );
      return true;
    } catch (e) {
      state = state.copyWith(
        errorMessage: e.toString().replaceAll('Exception: ', ''),
      );
      return false;
    }
  }

  Future<bool> rejectFaculty(String facultyId, String rejectionReason) async {
    try {
      await _repository.rejectFaculty(facultyId: facultyId, rejectionReason: rejectionReason);
      await loadAdminData();
      state = state.copyWith(
        successMessage: 'Faculty verification rejected with reason: "$rejectionReason".',
      );
      return true;
    } catch (e) {
      state = state.copyWith(
        errorMessage: e.toString().replaceAll('Exception: ', ''),
      );
      return false;
    }
  }

  Future<bool> requestPhotoReEnrollment(String facultyId) async {
    try {
      await _repository.requestPhotoReEnrollment(facultyId: facultyId);
      await loadAdminData();
      state = state.copyWith(
        successMessage: 'Requested new facial photograph from faculty member.',
      );
      return true;
    } catch (e) {
      state = state.copyWith(
        errorMessage: e.toString().replaceAll('Exception: ', ''),
      );
      return false;
    }
  }

  Future<bool> updateAccountStatus(String facultyId, String accountStatus) async {
    try {
      await _repository.updateAccountStatus(facultyId: facultyId, accountStatus: accountStatus);
      await loadAdminData();
      state = state.copyWith(
        successMessage: 'Faculty account status updated to ${accountStatus.toUpperCase()}.',
      );
      return true;
    } catch (e) {
      state = state.copyWith(
        errorMessage: e.toString().replaceAll('Exception: ', ''),
      );
      return false;
    }
  }

  Future<bool> correctAttendance({
    required String recordId,
    required AttendanceRecordStatus newStatus,
    required String justification,
  }) async {
    try {
      await _repository.submitAttendanceCorrection(
        recordId: recordId,
        newStatus: newStatus,
        justificationReason: justification,
      );
      await loadAdminData();
      state = state.copyWith(
        successMessage: 'Attendance record manually corrected and logged in audit trail.',
      );
      return true;
    } catch (e) {
      state = state.copyWith(
        errorMessage: e.toString().replaceAll('Exception: ', ''),
      );
      return false;
    }
  }

  Future<bool> updateBoundary({
    required String locationId,
    required double lat,
    required double lng,
    required double radius,
  }) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      await _repository.updateCampusBoundary(
        locationId: locationId,
        centerLatitude: lat,
        centerLongitude: lng,
        bufferRadiusMeters: radius,
      );
      await loadAdminData();
      state = state.copyWith(
        successMessage: 'Geofence perimeter parameters updated and re-anchored successfully.',
      );
      return true;
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: e.toString().replaceAll('Exception: ', ''),
      );
      return false;
    }
  }

  Future<bool> deleteBiometricTemplate(String userId) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      await _repository.requestBiometricTemplateDeletion(userId: userId);
      await loadAdminData();
      state = state.copyWith(
        successMessage: 'Biometric template securely erased from system under Right to be Forgotten.',
      );
      return true;
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: e.toString().replaceAll('Exception: ', ''),
      );
      return false;
    }
  }

  Future<String?> exportCsv() async {
    try {
      return await _repository.exportAttendanceReportToCsv();
    } catch (e) {
      state = state.copyWith(
        errorMessage: e.toString().replaceAll('Exception: ', ''),
      );
      return null;
    }
  }
}

final adminDashboardProvider = StateNotifierProvider.autoDispose<AdminDashboardViewModel, AdminDashboardState>((ref) {
  final repo = ref.watch(attendanceRepositoryProvider);
  return AdminDashboardViewModel(repo);
});

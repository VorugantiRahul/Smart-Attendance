import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../data/models/attendance_policy_model.dart';
import '../../../../data/models/attendance_record_model.dart';
import '../../../../data/models/attendance_session_model.dart';
import '../../../../data/repositories/attendance_repository.dart';
import '../../../../main.dart';

@immutable
class TeacherDashboardState {
  final bool isLoading;
  final String? errorMessage;
  final AttendancePolicy policy;
  final List<AttendanceSession> sessions;
  final List<AttendanceRecord> records;
  final String? selectedSessionId;
  final String searchQuery;
  final AttendanceRecordStatus? statusFilter;
  final bool isExporting;
  final String? exportedCsv;

  const TeacherDashboardState({
    this.isLoading = false,
    this.errorMessage,
    this.policy = const AttendancePolicy(),
    this.sessions = const [],
    this.records = const [],
    this.selectedSessionId,
    this.searchQuery = '',
    this.statusFilter,
    this.isExporting = false,
    this.exportedCsv,
  });

  TeacherDashboardState copyWith({
    bool? isLoading,
    String? errorMessage,
    bool clearError = false,
    AttendancePolicy? policy,
    List<AttendanceSession>? sessions,
    List<AttendanceRecord>? records,
    String? selectedSessionId,
    bool clearSelectedSession = false,
    String? searchQuery,
    AttendanceRecordStatus? statusFilter,
    bool clearStatusFilter = false,
    bool? isExporting,
    String? exportedCsv,
  }) {
    return TeacherDashboardState(
      isLoading: isLoading ?? this.isLoading,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      policy: policy ?? this.policy,
      sessions: sessions ?? this.sessions,
      records: records ?? this.records,
      selectedSessionId: clearSelectedSession ? null : (selectedSessionId ?? this.selectedSessionId),
      searchQuery: searchQuery ?? this.searchQuery,
      statusFilter: clearStatusFilter ? null : (statusFilter ?? this.statusFilter),
      isExporting: isExporting ?? this.isExporting,
      exportedCsv: exportedCsv ?? this.exportedCsv,
    );
  }

  /// Today's attendance record for the faculty member
  AttendanceRecord? get todayRecord {
    final now = DateTime.now();
    try {
      return records.firstWhere(
        (r) =>
            r.recordedAt.year == now.year &&
            r.recordedAt.month == now.month &&
            r.recordedAt.day == now.day,
      );
    } catch (_) {
      return null;
    }
  }

  bool get isCheckedInToday =>
      todayRecord != null && todayRecord!.status == AttendanceRecordStatus.present;

  List<AttendanceRecord> get filteredRecords {
    return records.where((r) {
      if (selectedSessionId != null && r.sessionId != selectedSessionId) {
        return false;
      }
      if (statusFilter != null && r.status != statusFilter) {
        return false;
      }
      if (searchQuery.trim().isNotEmpty) {
        final q = searchQuery.toLowerCase().trim();
        final nameMatch = r.studentName?.toLowerCase().contains(q) ?? false;
        final rollMatch = r.studentRollNumber?.toLowerCase().contains(q) ?? false;
        final idMatch = r.studentId.toLowerCase().contains(q);
        if (!nameMatch && !rollMatch && !idMatch) return false;
      }
      return true;
    }).toList();
  }

  // Monthly summary calculations
  int get presentCount => records.where((r) => r.status == AttendanceRecordStatus.present).length;
  int get lateCount => records.where((r) => r.status == AttendanceRecordStatus.present && r.isLate).length;
  int get flaggedCount => records.where((r) => r.status == AttendanceRecordStatus.flaggedOutsideGeofence).length;
  int get totalRecords => records.length;
  double get attendanceRate =>
      totalRecords > 0 ? (presentCount / totalRecords) * 100 : 0.0;
}

class TeacherDashboardViewModel extends StateNotifier<TeacherDashboardState> {
  final AttendanceRepository _repository;

  TeacherDashboardViewModel(this._repository) : super(const TeacherDashboardState()) {
    loadDashboardData();
  }

  Future<void> loadDashboardData() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final policy = await _repository.getAttendancePolicy();
      final sessions = await _repository.getActiveSessions();
      final records = await _repository.getAttendanceRecords();

      state = state.copyWith(
        isLoading: false,
        policy: policy,
        sessions: sessions,
        records: records,
        selectedSessionId: sessions.isNotEmpty ? sessions.first.id : null,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: e.toString().replaceAll('Exception: ', ''),
      );
    }
  }

  void selectSession(String? sessionId) {
    state = state.copyWith(
      selectedSessionId: sessionId,
      clearSelectedSession: sessionId == null,
    );
  }

  void setStatusFilter(AttendanceRecordStatus? status) {
    state = state.copyWith(
      statusFilter: status,
      clearStatusFilter: status == null,
    );
  }

  void setSearchQuery(String query) {
    state = state.copyWith(searchQuery: query);
  }

  Future<void> toggleSessionStatus(String sessionId, SessionStatus currentStatus) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final newStatus = currentStatus == SessionStatus.active ? SessionStatus.closed : SessionStatus.active;
      await _repository.updateSessionStatus(sessionId: sessionId, status: newStatus);
      await loadDashboardData();
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: e.toString().replaceAll('Exception: ', ''),
      );
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
      await loadDashboardData();
      return true;
    } catch (e) {
      state = state.copyWith(
        errorMessage: e.toString().replaceAll('Exception: ', ''),
      );
      return false;
    }
  }

  Future<String?> exportCsv() async {
    state = state.copyWith(isExporting: true);
    try {
      final csv = await _repository.exportAttendanceReportToCsv(sessionId: state.selectedSessionId);
      state = state.copyWith(isExporting: false, exportedCsv: csv);
      return csv;
    } catch (e) {
      state = state.copyWith(
        isExporting: false,
        errorMessage: e.toString().replaceAll('Exception: ', ''),
      );
      return null;
    }
  }
}

final teacherDashboardProvider = StateNotifierProvider.autoDispose<TeacherDashboardViewModel, TeacherDashboardState>((ref) {
  final repo = ref.watch(attendanceRepositoryProvider);
  return TeacherDashboardViewModel(repo);
});

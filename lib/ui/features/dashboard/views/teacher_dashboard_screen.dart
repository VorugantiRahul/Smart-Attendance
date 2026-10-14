import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../data/models/attendance_record_model.dart';
import '../../../../data/models/user_model.dart';
import '../../auth/view_models/auth_view_model.dart';
import '../view_models/geofence_view_model.dart';
import '../view_models/teacher_dashboard_view_model.dart';
import '../widgets/campus_geofence_map_view.dart';

class TeacherDashboardScreen extends ConsumerWidget {
  const TeacherDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);
    final user = authState.user;
    final dashboardState = ref.watch(teacherDashboardProvider);
    final viewModel = ref.read(teacherDashboardProvider.notifier);
    final geoState = ref.watch(geofenceStateProvider);

    debugPrint('--> TeacherDashboardScreen build() user: ${user?.email}, records: ${dashboardState.records.length}, loading: ${dashboardState.isLoading}');

    try {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Faculty Attendance Console'),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              tooltip: 'Refresh Data',
              onPressed: () => viewModel.loadDashboardData(),
            ),
            IconButton(
              icon: const Icon(Icons.download_rounded),
              tooltip: 'Export CSV',
              onPressed: () => _handleExportCsv(context, ref),
            ),
            IconButton(
              icon: const Icon(Icons.logout_rounded),
              tooltip: 'Logout',
              onPressed: () async {
                await ref.read(authStateProvider.notifier).logout();
                if (context.mounted) {
                  context.go('/login');
                }
              },
            ),
          ],
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Faculty Profile Header Card
                _safe('Profile Card', () => _buildProfileCard(context, user)),
                const SizedBox(height: 16),

                // Error Banner if present
                if (dashboardState.errorMessage != null) ...[
                  _buildErrorBanner(dashboardState.errorMessage!),
                  const SizedBox(height: 16),
                ],

                // ONE-TAP ATTENDANCE HERO CARD (Requirement 5 & 8)
                _safe('Attendance Action Card', () => _buildMarkAttendanceHeroCard(context, ref, dashboardState, user)),
                const SizedBox(height: 16),

                // Today's Attendance Status Detail Card
                _safe('Status Card', () => _buildTodayStatusCard(dashboardState)),
                const SizedBox(height: 16),

                // Monthly Summary Metrics (Live Data)
                _safe('Summary Cards', () => _buildMonthlySummaryCards(dashboardState)),
                const SizedBox(height: 16),

                // Campus Geofence Verification Map Card
                _safe('Geofence Card', () => _buildGeofenceCard(context, ref, geoState)),
                const SizedBox(height: 20),

                // Personal Attendance History List
                _safe('History List', () => _buildPersonalAttendanceHistory(context, dashboardState)),
                const SizedBox(height: 20),

                // Approved Exception & Help Procedure
                _safe('Exception Card', () => _buildExceptionProcedureCard(context)),
                const SizedBox(height: 24),

                // Switch Role / Logout Footer
                OutlinedButton.icon(
                  icon: const Icon(Icons.swap_horiz_rounded, size: 18),
                  label: const Text('Log In As Different Role'),
                  onPressed: () async {
                    await ref.read(authStateProvider.notifier).logout();
                    if (context.mounted) {
                      context.go('/login');
                    }
                  },
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
      );
    } catch (e, stack) {
      return Scaffold(
        appBar: AppBar(title: const Text('Faculty Attendance Console')),
        body: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Center(
            child: Text(
              'Dashboard error: $e\n\n$stack',
              style: const TextStyle(color: Colors.red, fontSize: 13),
            ),
          ),
        ),
      );
    }
  }

  Widget _safe(String name, Widget Function() fn) {
    try {
      return fn();
    } catch (e, stack) {
      return Container(
        padding: const EdgeInsets.all(12),
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: Colors.red.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.red.shade200),
        ),
        child: Text(
          'Error in $name: $e\n$stack',
          style: TextStyle(color: Colors.red.shade900, fontSize: 11),
        ),
      );
    }
    }

  Widget _buildProfileCard(BuildContext context, User? user) {
    final isEnrolled = user?.isIrisEnrolled ?? false;

    return Card(
      color: const Color(0xFF1E293B),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.irisCyan.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    (user?.designation ?? 'Faculty Member').toUpperCase(),
                    style: const TextStyle(
                      color: AppTheme.irisCyan,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: user?.isApproved == true ? AppTheme.statusSuccess : Colors.orange,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      user?.isApproved == true ? 'Admin Approved' : 'Awaiting Admin Approval',
                      style: TextStyle(
                        color: user?.isApproved == true ? AppTheme.statusSuccess : Colors.orangeAccent,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: isEnrolled ? AppTheme.statusSuccess : Colors.amber,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      isEnrolled ? 'Face & Iris Enrolled' : 'Pending Enrollment',
                      style: TextStyle(
                        color: isEnrolled ? AppTheme.statusSuccess : Colors.amberAccent,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              user?.fullName ?? 'Faculty Member',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'ID: ${user?.employeeId ?? user?.studentIdNumber ?? "FAC-CSE-102"}  •  ${user?.department ?? "Computer Science & Engineering"}',
              style: TextStyle(
                color: Colors.white.withOpacity(0.85),
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  style: TextButton.styleFrom(
                    foregroundColor: AppTheme.irisCyan,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  ),
                  icon: const Icon(Icons.camera_alt_outlined, size: 14),
                  label: Text(
                    isEnrolled ? 'Re-enroll Iris Template' : 'Enroll Biometrics Now',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                  ),
                  onPressed: () {
                    context.push('/face-enrollment?reEnroll=true');
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMarkAttendanceHeroCard(
    BuildContext context,
    WidgetRef ref,
    TeacherDashboardState state,
    User? user,
  ) {
    final isCheckedIn = state.isCheckedInToday;
    final today = state.todayRecord;

    if (isCheckedIn && today != null) {
      final timeStr =
          '${today.recordedAt.hour.toString().padLeft(2, "0")}:${today.recordedAt.minute.toString().padLeft(2, "0")}';

      return Card(
        color: const Color(0xFF064E3B),
        child: Padding(
          padding: const EdgeInsets.all(22.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: const BoxDecoration(
                      color: AppTheme.statusSuccess,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.check_rounded, color: Colors.white, size: 28),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'DAILY ATTENDANCE RECORDED',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.8,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Builder(
                          builder: (context) {
                            const months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
                            final rec = today.recordedAt;
                            final dateStr = '${rec.day} ${months[rec.month - 1]} ${rec.year}';
                            final hour12 = rec.hour == 0 ? 12 : (rec.hour > 12 ? rec.hour - 12 : rec.hour);
                            final amPm = rec.hour >= 12 ? 'PM' : 'AM';
                            final timeStrFormatted = '${hour12.toString().padLeft(2, "0")}:${rec.minute.toString().padLeft(2, "0")}:${rec.second.toString().padLeft(2, "0")} $amPm';

                            return Text(
                              'Attendance Marked Successfully! Faculty: ${user?.fullName ?? "Faculty"}. Date: $dateStr. Time: $timeStrFormatted. Verification: Successful.',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.95),
                                fontSize: 12.5,
                                height: 1.35,
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.verified_rounded, color: Colors.tealAccent, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Builder(
                        builder: (context) {
                          final rec = today.recordedAt;
                          final hour12 = rec.hour == 0 ? 12 : (rec.hour > 12 ? rec.hour - 12 : rec.hour);
                          final amPm = rec.hour >= 12 ? 'PM' : 'AM';
                          final timeStrFormatted = '${hour12.toString().padLeft(2, "0")}:${rec.minute.toString().padLeft(2, "0")}:${rec.second.toString().padLeft(2, "0")} $amPm';

                          return Text(
                            'Verified Present (Status: ${today.status.name.toUpperCase()})  •  Time: $timeStrFormatted  •  ${today.isLate ? "Late Arrival" : "On Time"}',
                            style: const TextStyle(color: Colors.white70, fontSize: 11),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Prominent "MARK MY ATTENDANCE" Action Card
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: const LinearGradient(
            colors: [Color(0xFF0F172A), Color(0xFF1E3A8A)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        padding: const EdgeInsets.all(22.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.irisCyan.withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.remove_red_eye_rounded, color: AppTheme.irisCyan, size: 28),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'SMARTPHONE CHECK-IN',
                        style: TextStyle(
                          color: AppTheme.irisCyan,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.0,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Replace Biometric Machine Queue',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            const Text(
              'One-tap smartphone verification replaces waiting in line at the physical terminal. Front camera automatically tracks iris and verifies campus geofence in real time.',
              style: TextStyle(color: Colors.white70, fontSize: 12.5, height: 1.4),
            ),
            const SizedBox(height: 18),

            // The Prominent Button (Section 5)
            if (user?.accountStatus == 'suspended') ...[
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppTheme.statusError.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.statusError.withOpacity(0.5)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.block_rounded, color: AppTheme.statusError, size: 22),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Account Suspended.\nYour faculty account is currently suspended. Please contact the administrator.',
                        style: TextStyle(color: Colors.white, fontSize: 12, height: 1.35),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
            ] else if (user?.approvalStatus == FacultyApprovalStatus.rejected) ...[
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppTheme.statusError.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.statusError.withOpacity(0.5)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.cancel_rounded, color: AppTheme.statusError, size: 22),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Face Verification Rejected.\nReason: ${user?.rejectionReason ?? "Photograph unclear or invalid."}',
                            style: const TextStyle(color: Colors.white, fontSize: 12, height: 1.35),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        style: TextButton.styleFrom(foregroundColor: AppTheme.irisCyan),
                        icon: const Icon(Icons.refresh_rounded, size: 16),
                        label: const Text('Submit New Photo for Verification'),
                        onPressed: () => context.push('/face-enrollment?reEnroll=true'),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
            ] else if (user?.isApproved != true) ...[
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.amber.shade900.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.amber.shade400.withOpacity(0.5)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.hourglass_top_rounded, color: Colors.amberAccent, size: 22),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Account Awaiting Administrator Approval.\nOnce an administrator authorizes your facial registration, smartphone attendance marking will be unlocked.',
                        style: TextStyle(color: Colors.white, fontSize: 12, height: 1.35),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
            ] else if (!(user?.isIrisEnrolled ?? false)) ...[
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.orange.shade900.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.orange.shade400.withOpacity(0.5)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.face_retouching_natural_rounded, color: Colors.orangeAccent, size: 22),
                    SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Biometric Enrollment Incomplete.\nPlease complete your initial facial photograph capture to submit for approval.',
                        style: TextStyle(color: Colors.white, fontSize: 12),
                      ),
                    ),
                    TextButton(
                      onPressed: () => context.push('/face-enrollment?reEnroll=true'),
                      child: const Text('Enroll Now', style: TextStyle(color: AppTheme.irisCyan, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
            ] else if (!state.policy.isAttendanceWindowOpen(DateTime.now())) ...[
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.deepPurple.shade900.withOpacity(0.35),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.deepPurpleAccent.withOpacity(0.5)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.access_time_filled_rounded, color: Colors.deepPurpleAccent, size: 22),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        state.policy.getAttendanceWindowNotice(DateTime.now()),
                        style: const TextStyle(color: Colors.white, fontSize: 12, height: 1.35),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
            ],

            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: (user?.isApproved == true && (user?.isIrisEnrolled ?? false) && user?.accountStatus != 'suspended' && state.policy.isAttendanceWindowOpen(DateTime.now()))
                    ? AppTheme.irisCyan
                    : Colors.grey.shade700,
                foregroundColor: (user?.isApproved == true && (user?.isIrisEnrolled ?? false) && user?.accountStatus != 'suspended' && state.policy.isAttendanceWindowOpen(DateTime.now()))
                    ? const Color(0xFF0F172A)
                    : Colors.white70,
                padding: const EdgeInsets.symmetric(vertical: 18),
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: () {
                final now = DateTime.now();
                if (user?.accountStatus == 'suspended') {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Your faculty account has been suspended by an administrator.'),
                      backgroundColor: AppTheme.statusError,
                    ),
                  );
                  return;
                }
                if (user?.isApproved != true) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Your account is pending administrator approval before you can mark attendance.'),
                      backgroundColor: Colors.amber,
                    ),
                  );
                  return;
                }
                if (!(user?.isIrisEnrolled ?? false)) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Please complete your initial face biometric enrollment first.'),
                      backgroundColor: Colors.orange,
                    ),
                  );
                  return;
                }
                if (!state.policy.isAttendanceWindowOpen(now)) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(state.policy.getAttendanceWindowNotice(now)),
                      backgroundColor: Colors.deepPurpleAccent,
                    ),
                  );
                  return;
                }

                final sessionId = state.sessions.isNotEmpty
                    ? state.sessions.first.id
                    : 'cccccccc-cccc-cccc-cccc-cccccccccccc';
                context.push('/iris-capture?sessionId=$sessionId');
              },
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.camera_alt_rounded, size: 22),
                  SizedBox(width: 10),
                  Text(
                    'MARK MY ATTENDANCE',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.0,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: TextButton.icon(
                onPressed: () => context.push('/biometric-diagnostic'),
                icon: const Icon(Icons.analytics_outlined, size: 16, color: AppTheme.irisCyan),
                label: const Text(
                  'Camera & Biometric Quality Diagnostics',
                  style: TextStyle(color: AppTheme.irisCyan, fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTodayStatusCard(TeacherDashboardState state) {
    final policy = state.policy;
    final today = state.todayRecord;
    final isCheckedIn = state.isCheckedInToday;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  "Today's Attendance Status",
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1E293B),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: isCheckedIn
                        ? AppTheme.statusSuccess.withOpacity(0.12)
                        : Colors.orange.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    isCheckedIn
                        ? (today?.isLate == true ? 'PRESENT (LATE)' : 'PRESENT (ON TIME)')
                        : 'PENDING CHECK-IN',
                    style: TextStyle(
                      color: isCheckedIn
                          ? (today?.isLate == true ? Colors.orange.shade800 : AppTheme.statusSuccess)
                          : Colors.orange.shade800,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Official Hours', style: TextStyle(color: AppTheme.textMuted, fontSize: 11)),
                      const SizedBox(height: 2),
                      Text(policy.workingHoursString, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Grace Cutoff', style: TextStyle(color: AppTheme.textMuted, fontSize: 11)),
                      const SizedBox(height: 2),
                      Text(policy.graceCutoffString, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Campus Boundary', style: TextStyle(color: AppTheme.textMuted, fontSize: 11)),
                      const SizedBox(height: 2),
                      const Text('VNR VJIET', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppTheme.primaryBlue)),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMonthlySummaryCards(TeacherDashboardState state) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Monthly Attendance Summary',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.bold,
            color: AppTheme.primaryBlue,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _StatCard(
                title: 'Days Present',
                value: '${state.presentCount}',
                trend: 'Duty Check-ins',
                color: AppTheme.statusSuccess,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _StatCard(
                title: 'Late Arrivals',
                value: '${state.lateCount}',
                trend: 'Past 09:15 AM',
                color: state.lateCount > 0 ? Colors.amber.shade800 : AppTheme.textMuted,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _StatCard(
                title: 'Attendance Rate',
                value: '${state.attendanceRate.toStringAsFixed(1)}%',
                trend: 'Campus Record',
                color: AppTheme.primaryAccent,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildGeofenceCard(BuildContext context, WidgetRef ref, GeofenceState geoState) {
    final geoNotifier = ref.read(geofenceStateProvider.notifier);
    final campus = geoState.targetLocation;
    final userLoc = geoState.userLocation;
    final eval = geoState.evaluationResult;
    final isInside = eval?.isInside ?? false;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.radar_rounded, color: AppTheme.primaryAccent, size: 22),
                const SizedBox(width: 8),
                const Text(
                  'Campus Geofence Status',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1E293B),
                  ),
                ),
                const Spacer(),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: () => geoNotifier.acquireLocation(),
                  icon: const Icon(Icons.my_location_rounded, size: 14),
                  label: const Text('Refresh GPS', style: TextStyle(fontSize: 11)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                ActionChip(
                  avatar: Icon(Icons.school_rounded, size: 14, color: campus?.code == 'VNRVJIET-MAIN' ? AppTheme.irisCyan : Colors.grey),
                  label: const Text('VNR VJIET Campus', style: TextStyle(fontSize: 11)),
                  backgroundColor: campus?.code == 'VNRVJIET-MAIN' ? AppTheme.irisCyan.withOpacity(0.12) : null,
                  onPressed: () {
                    geoNotifier.setSimulatedLocation(17.538500, 78.385200);
                  },
                ),
                ActionChip(
                  avatar: Icon(Icons.hotel_rounded, size: 14, color: campus?.code == 'ATITHI-HOSTEL-GM' ? AppTheme.irisCyan : Colors.grey),
                  label: const Text('Athithi Hostel (Gandimaisamma)', style: TextStyle(fontSize: 11)),
                  backgroundColor: campus?.code == 'ATITHI-HOSTEL-GM' ? AppTheme.irisCyan.withOpacity(0.12) : null,
                  onPressed: () {
                    geoNotifier.setSimulatedLocation(17.578900, 78.426900);
                  },
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (campus != null) ...[
              CampusGeofenceMapView(
                campus: campus,
                userLocation: userLoc,
                isInside: isInside,
              ),
              const SizedBox(height: 10),
            ],
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isInside
                    ? AppTheme.statusSuccess.withOpacity(0.08)
                    : AppTheme.statusError.withOpacity(0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isInside
                      ? AppTheme.statusSuccess.withOpacity(0.2)
                      : AppTheme.statusError.withOpacity(0.2),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    isInside ? Icons.check_circle_rounded : Icons.info_outline_rounded,
                    color: isInside ? AppTheme.statusSuccess : AppTheme.statusError,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      eval != null
                          ? eval.statusReason
                          : 'GPS location ready. Permitted boundary: VNR VJIET Bachupally Campus (350m buffer).',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: isInside ? const Color(0xFF065F46) : const Color(0xFF991B1B),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPersonalAttendanceHistory(
    BuildContext context,
    TeacherDashboardState state,
  ) {
    final records = state.records;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'My Attendance History',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: AppTheme.primaryBlue,
              ),
            ),
            Text(
              '${records.length} records logged',
              style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (records.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.event_note_rounded, size: 40, color: Colors.grey.shade400),
                    const SizedBox(height: 8),
                    const Text('No attendance records logged yet today.', style: TextStyle(color: AppTheme.textMuted)),
                  ],
                ),
              ),
            ),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: records.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final r = records[index];
              final isPresent = r.status == AttendanceRecordStatus.present;
              final timeStr =
                  '${r.recordedAt.hour.toString().padLeft(2, "0")}:${r.recordedAt.minute.toString().padLeft(2, "0")}';
              final dateStr =
                  '${r.recordedAt.year}-${r.recordedAt.month.toString().padLeft(2, "0")}-${r.recordedAt.day.toString().padLeft(2, "0")}';

              return Card(
                elevation: 0.5,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                child: ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: isPresent
                          ? AppTheme.statusSuccess.withOpacity(0.12)
                          : AppTheme.statusError.withOpacity(0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isPresent ? Icons.verified_user_rounded : Icons.cancel_outlined,
                      color: isPresent ? AppTheme.statusSuccess : AppTheme.statusError,
                      size: 20,
                    ),
                  ),
                  title: Row(
                    children: [
                      Text(
                        dateStr,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        timeStr,
                        style: const TextStyle(color: AppTheme.textMuted, fontSize: 12),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: isPresent
                              ? (r.isLate ? Colors.amber.withOpacity(0.15) : AppTheme.statusSuccess.withOpacity(0.12))
                              : AppTheme.statusError.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          isPresent ? (r.isLate ? 'LATE' : 'ON TIME') : 'FLAGGED',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: isPresent
                                ? (r.isLate ? Colors.amber.shade900 : AppTheme.statusSuccess)
                                : AppTheme.statusError,
                          ),
                        ),
                      ),
                    ],
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 4.0),
                    child: Text(
                      'Iris: ${r.isBiometricallyVerified ? "Daugman Verified" : "Pending"}  •  Campus: ${r.isWithinGeofence ? "Inside (${r.distanceFromCenterMeters?.toStringAsFixed(0)}m)" : "Outside"}',
                      style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                    ),
                  ),
                ),
              );
            },
          ),
      ],
    );
  }

  Widget _buildExceptionProcedureCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFCBD5E1)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.help_outline_rounded, color: AppTheme.primaryBlue, size: 20),
          SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Approved Exception & Correction Procedure',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12.5,
                    color: Color(0xFF1E293B),
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  'If smartphone camera or GPS is unavailable due to hardware failure, contact the Academic Administration Office. Approved manual exceptions are recorded in the audit log.',
                  style: TextStyle(fontSize: 11.5, color: Color(0xFF64748B), height: 1.35),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorBanner(String message) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.statusError.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.statusError.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: AppTheme.statusError, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: AppTheme.statusError, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleExportCsv(BuildContext context, WidgetRef ref) async {
    final csv = await ref.read(teacherDashboardProvider.notifier).exportCsv();
    if (csv != null) {
      await Clipboard.setData(ClipboardData(text: csv));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Attendance records exported and copied to clipboard as CSV.'),
            backgroundColor: AppTheme.statusSuccess,
          ),
        );
      }
    }
  }
}

class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final String trend;
  final Color color;

  const _StatCard({
    required this.title,
    required this.value,
    required this.trend,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
          padding: const EdgeInsets.all(14.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppTheme.textMuted,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                value,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                trend,
                style: const TextStyle(
                  fontSize: 10.5,
                  color: Color(0xFF64748B),
                ),
              ),
            ],
          ),
        ),
      );
    }
}

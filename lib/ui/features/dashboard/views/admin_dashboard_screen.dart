import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../data/models/attendance_policy_model.dart';
import '../../../../data/models/attendance_record_model.dart';
import '../../../../data/models/campus_location_model.dart';
import '../../../../data/models/user_model.dart';
import '../../auth/view_models/auth_view_model.dart';
import '../view_models/admin_dashboard_view_model.dart';

class AdminDashboardScreen extends ConsumerWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);
    final user = authState.user;
    final adminState = ref.watch(adminDashboardProvider);
    final viewModel = ref.read(adminDashboardProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Faculty Attendance Admin Console'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh Telemetry',
            onPressed: () => viewModel.loadAdminData(),
          ),
          IconButton(
            icon: const Icon(Icons.download_rounded),
            tooltip: 'Export CSV Report',
            onPressed: () => _handleExportCsv(context, viewModel),
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
        child: RefreshIndicator(
          onRefresh: () => viewModel.loadAdminData(),
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header Admin Profile Card
                _buildHeaderCard(user),
                const SizedBox(height: 16),

                // Error or Success Banners
                if (adminState.errorMessage != null) ...[
                  _buildMessageBanner(adminState.errorMessage!, isError: true),
                  const SizedBox(height: 14),
                ],
                if (adminState.successMessage != null) ...[
                  _buildMessageBanner(adminState.successMessage!, isError: false),
                  const SizedBox(height: 14),
                ],

                // Real-time Faculty Attendance Metrics Overview
                _buildSystemMetrics(adminState),
                const SizedBox(height: 16),

                // Tab Selector
                SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(
                      value: 0,
                      label: Text('Faculty & Policy'),
                      icon: Icon(Icons.people_alt_rounded),
                    ),
                    ButtonSegment(
                      value: 1,
                      label: Text('Attendance Records'),
                      icon: Icon(Icons.history_edu_rounded),
                    ),
                    ButtonSegment(
                      value: 2,
                      label: Text('Geofences'),
                      icon: Icon(Icons.map_rounded),
                    ),
                    ButtonSegment(
                      value: 3,
                      label: Text('Audit & Compliance'),
                      icon: Icon(Icons.receipt_long_rounded),
                    ),
                  ],
                  selected: {adminState.selectedTab},
                  onSelectionChanged: (set) => viewModel.switchTab(set.first),
                ),
                const SizedBox(height: 16),

                // Tab Content Switcher
                if (adminState.selectedTab == 0)
                  _buildFacultyAndPolicyTab(context, adminState, viewModel, user)
                else if (adminState.selectedTab == 1)
                  _buildRecordsAndSearchTab(context, adminState, viewModel)
                else if (adminState.selectedTab == 2)
                  _buildGeofenceTab(context, adminState, viewModel)
                else
                  _buildAuditLogsTab(context, adminState, viewModel),

                const SizedBox(height: 24),
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
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderCard(User? user) {
    return Card(
      color: const Color(0xFF0F172A),
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
                    color: Colors.amber.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'INSTITUTIONAL ATTENDANCE ADMINISTRATOR',
                    style: TextStyle(
                      color: Colors.amber,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
                const Icon(Icons.admin_panel_settings_rounded, color: Colors.white70, size: 22),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              user?.fullName ?? 'Academic Administrator',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${user?.email ?? "admin@university.edu"}  •  VNR VJIET Faculty Biometric Grid',
              style: TextStyle(
                color: Colors.white.withOpacity(0.8),
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageBanner(String text, {required bool isError}) {
    final color = isError ? AppTheme.statusError : AppTheme.statusSuccess;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Row(
        children: [
          Icon(isError ? Icons.error_outline : Icons.check_circle_outline, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }

  Widget _buildSystemMetrics(AdminDashboardState state) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _AdminMetric(
                title: 'Total Faculty',
                value: '${state.totalAuthorizedFaculty}',
                subtitle: 'Authorized Roster',
                color: AppTheme.primaryBlue,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _AdminMetric(
                title: 'Checked In Today',
                value: '${state.todayCompletedCount}',
                subtitle: 'Verified Present',
                color: AppTheme.statusSuccess,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _AdminMetric(
                title: 'Pending Check-in',
                value: '${state.todayPendingCount}',
                subtitle: 'Awaiting Duty Tap',
                color: Colors.orange.shade800,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _AdminMetric(
                title: 'Late Arrivals',
                value: '${state.todayLateCount}',
                subtitle: 'Past Grace Cutoff',
                color: state.todayLateCount > 0 ? Colors.amber.shade900 : AppTheme.textMuted,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _AdminMetric(
                title: 'Approved Exceptions',
                value: '${state.approvedExceptionsCount}',
                subtitle: 'Manual Corrections',
                color: AppTheme.primaryAccent,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _AdminMetric(
                title: 'Security Flags',
                value: '${state.outsideCount + state.biometricRejectedCount}',
                subtitle: '${state.outsideCount} Outside Geofence',
                color: (state.outsideCount + state.biometricRejectedCount) > 0
                    ? AppTheme.statusError
                    : AppTheme.textMuted,
              ),
            ),
          ],
        ),
      ],
    );
  }

  // TAB 0: Faculty Roster & Policy Configuration
  Widget _buildFacultyAndPolicyTab(
    BuildContext context,
    AdminDashboardState state,
    AdminDashboardViewModel viewModel,
    User? user,
  ) {
    final policy = state.policy;
    final deptBreakdown = state.departmentWiseTodayCount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Configurable Attendance Policy Card (Requirement 6)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.tune_rounded, color: AppTheme.primaryBlue, size: 20),
                        SizedBox(width: 8),
                        Text(
                          'College Attendance Policy',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                      ],
                    ),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        visualDensity: VisualDensity.compact,
                      ),
                      onPressed: () => _showEditPolicyDialog(context, viewModel, policy),
                      icon: const Icon(Icons.edit_rounded, size: 14),
                      label: const Text('Configure Policy', style: TextStyle(fontSize: 12)),
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
                          const Text('Official Working Hours', style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                          const SizedBox(height: 2),
                          Text(policy.workingHoursString, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Grace Period', style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                          const SizedBox(height: 2),
                          Text('${policy.gracePeriodMinutes} mins (Cutoff: ${policy.graceCutoffString})',
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Daily Limit', style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                          const SizedBox(height: 2),
                          const Text('1 Check-in / day', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Dedicated Section: Faculty Enrollment Requests (Requirement 2 & 7)
        Card(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.badge_rounded, color: AppTheme.primaryAccent, size: 22),
                        SizedBox(width: 8),
                        Text(
                          'Faculty Enrollment Requests',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.amber.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${state.facultyList.where((f) => !f.isApproved || f.approvalStatus == FacultyApprovalStatus.pending).length} Pending Review',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Colors.amber.shade900,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'Review faculty submitted biometric enrollment requests, verify identity credentials, and approve or reject attendance access.',
                  style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                ),
                const SizedBox(height: 12),
                if (state.facultyList.where((f) => !f.isApproved || f.approvalStatus == FacultyApprovalStatus.pending).isEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppTheme.statusSuccess.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppTheme.statusSuccess.withOpacity(0.2)),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.check_circle_rounded, color: AppTheme.statusSuccess, size: 20),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'All faculty biometric enrollment requests are processed. No pending requests.',
                            style: TextStyle(fontSize: 12, color: AppTheme.statusSuccess, fontWeight: FontWeight.w500),
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: state.facultyList.where((f) => !f.isApproved || f.approvalStatus == FacultyApprovalStatus.pending).length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final fac = state.facultyList.where((f) => !f.isApproved || f.approvalStatus == FacultyApprovalStatus.pending).toList()[index];
                      final isSelf = user != null && user.id == fac.id;
                      final isPending = fac.approvalStatus == FacultyApprovalStatus.pending || !fac.isApproved;
                      final isRejected = fac.approvalStatus == FacultyApprovalStatus.rejected;
                      final submissionDateStr = _formatSubmissionDate(fac.submittedAt ?? fac.createdAt);

                      return Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: isRejected ? Colors.red.shade200 : const Color(0xFFCBD5E1)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Enrollment image preview (tap to enlarge)
                                InkWell(
                                  onTap: () => _showEnrollmentPhotoPreview(context, fac),
                                  borderRadius: BorderRadius.circular(10),
                                  child: Stack(
                                    children: [
                                      Container(
                                        width: 64,
                                        height: 64,
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(10),
                                          border: Border.all(color: AppTheme.primaryBlue.withOpacity(0.3), width: 1.5),
                                        ),
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(8),
                                          child: _buildFacultyPhotoAvatar(fac),
                                        ),
                                      ),
                                      Positioned(
                                        bottom: 2,
                                        right: 2,
                                        child: Container(
                                          padding: const EdgeInsets.all(2),
                                          decoration: BoxDecoration(
                                            color: Colors.black.withOpacity(0.6),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: const Icon(Icons.zoom_in_rounded, size: 12, color: Colors.white),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Expanded(
                                            child: Text(
                                              fac.fullName,
                                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                            ),
                                          ),
                                          // Approval Status Badge
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: isRejected
                                                  ? AppTheme.statusError.withOpacity(0.12)
                                                  : (fac.isApproved
                                                      ? AppTheme.statusSuccess.withOpacity(0.12)
                                                      : Colors.orange.withOpacity(0.15)),
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              fac.approvalStatus.name.toUpperCase(),
                                              style: TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                                color: isRejected
                                                    ? AppTheme.statusError
                                                    : (fac.isApproved
                                                        ? AppTheme.statusSuccess
                                                        : Colors.orange.shade900),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        'Faculty ID: ${fac.employeeId ?? fac.studentIdNumber ?? fac.id}',
                                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF1E293B)),
                                      ),
                                      Text(
                                        'Official Email: ${fac.email}',
                                        style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
                                      ),
                                      Text(
                                        'Department: ${fac.department ?? "General Engineering"}',
                                        style: const TextStyle(fontSize: 12, color: Color(0xFF475569)),
                                      ),
                                      Text(
                                        'Submission Date: $submissionDateStr',
                                        style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                                      ),
                                      if (fac.rejectionReason != null && fac.rejectionReason!.isNotEmpty) ...[
                                        const SizedBox(height: 4),
                                        Text(
                                          'Rejection Reason: "${fac.rejectionReason}"',
                                          style: const TextStyle(fontSize: 11, color: AppTheme.statusError, fontStyle: FontStyle.italic),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            const Divider(height: 1),
                            const SizedBox(height: 8),
                            if (isSelf)
                              const Padding(
                                padding: EdgeInsets.only(bottom: 6.0),
                                child: Text(
                                  'Security Policy: Administrators cannot approve their own biometric enrollment request.',
                                  style: TextStyle(fontSize: 11, color: Colors.orange, fontWeight: FontWeight.w600),
                                ),
                              ),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    visualDensity: VisualDensity.compact,
                                    foregroundColor: AppTheme.statusError,
                                    side: BorderSide(color: AppTheme.statusError.withOpacity(0.5)),
                                  ),
                                  icon: const Icon(Icons.cancel_rounded, size: 14),
                                  label: const Text('Reject Enrollment', style: TextStyle(fontSize: 12)),
                                  onPressed: () => _showRejectFacultyDialog(context, viewModel, fac),
                                ),
                                const SizedBox(width: 10),
                                ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    visualDensity: VisualDensity.compact,
                                    backgroundColor: AppTheme.statusSuccess,
                                  ),
                                  icon: const Icon(Icons.check_circle_rounded, size: 14),
                                  label: const Text('Approve Enrollment', style: TextStyle(fontSize: 12)),
                                  onPressed: isSelf
                                      ? null
                                      : () => viewModel.toggleFacultyApproval(fac.id, true),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Department-Wise Attendance Today
        const Text(
          'Department-Wise Attendance (Today)',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF1E293B)),
        ),
        const SizedBox(height: 8),
        if (deptBreakdown.isEmpty)
          const Text('No faculty checked in yet today across departments.', style: TextStyle(fontSize: 12, color: AppTheme.textMuted))
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: deptBreakdown.entries.map((e) {
              return Chip(
                avatar: const Icon(Icons.domain_rounded, size: 16, color: AppTheme.primaryBlue),
                label: Text('${e.key}: ${e.value} present', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                backgroundColor: AppTheme.primaryBlue.withOpacity(0.08),
              );
            }).toList(),
          ),
        const SizedBox(height: 16),

        // Faculty Roster Management List
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Authorized Faculty Accounts',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF1E293B)),
            ),
            Text('${state.facultyList.length} faculty registered', style: const TextStyle(fontSize: 12, color: AppTheme.textMuted)),
          ],
        ),
        const SizedBox(height: 10),
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: state.facultyList.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final fac = state.facultyList[index];
            return Card(
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: AppTheme.primaryBlue.withOpacity(0.1),
                  child: Text(
                    fac.fullName.isNotEmpty ? fac.fullName[0].toUpperCase() : 'F',
                    style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primaryBlue),
                  ),
                ),
                title: Row(
                  children: [
                    Text(fac.fullName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: fac.isIrisEnrolled ? AppTheme.statusSuccess.withOpacity(0.12) : Colors.amber.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        fac.isIrisEnrolled ? 'Iris Enrolled' : 'Pending Scan',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: fac.isIrisEnrolled ? AppTheme.statusSuccess : Colors.amber.shade900,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: fac.accountStatus == 'suspended'
                            ? AppTheme.statusError.withOpacity(0.12)
                            : (fac.accountStatus == 'inactive' ? Colors.grey.withOpacity(0.2) : AppTheme.statusSuccess.withOpacity(0.12)),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        (fac.accountStatus ?? 'active').toUpperCase(),
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.bold,
                          color: fac.accountStatus == 'suspended'
                              ? AppTheme.statusError
                              : (fac.accountStatus == 'inactive' ? Colors.grey.shade700 : AppTheme.statusSuccess),
                        ),
                      ),
                    ),
                  ],
                ),
                subtitle: Text(
                  '${fac.employeeId ?? fac.studentIdNumber ?? "FAC"} • ${fac.designation ?? "Faculty"} • ${fac.department ?? "General"}\nPhone: ${fac.phone ?? "N/A"}',
                  style: const TextStyle(fontSize: 11.5, color: AppTheme.textMuted),
                ),
                trailing: PopupMenuButton<String>(
                  icon: Icon(
                    fac.isApproved ? Icons.verified_user_rounded : Icons.gpp_bad_rounded,
                    color: fac.isApproved ? AppTheme.statusSuccess : Colors.amber.shade800,
                  ),
                  tooltip: 'Manage Faculty Account',
                  onSelected: (val) {
                    if (val == 'approve') {
                      viewModel.toggleFacultyApproval(fac.id, true);
                    } else if (val == 'revoke') {
                      viewModel.toggleFacultyApproval(fac.id, false);
                    } else if (val == 'request_photo') {
                      viewModel.requestPhotoReEnrollment(fac.id);
                    } else if (val == 'suspend') {
                      viewModel.updateAccountStatus(fac.id, 'suspended');
                    } else if (val == 'activate') {
                      viewModel.updateAccountStatus(fac.id, 'active');
                    } else if (val == 'deactivate') {
                      viewModel.updateAccountStatus(fac.id, 'inactive');
                    }
                  },
                  itemBuilder: (ctx) => [
                    PopupMenuItem(
                      value: fac.isApproved ? 'revoke' : 'approve',
                      child: Text(fac.isApproved ? 'Revoke Biometric Approval' : 'Approve Face Enrollment'),
                    ),
                    const PopupMenuItem(
                      value: 'request_photo',
                      child: Text('Require New Photo Enrollment'),
                    ),
                    const PopupMenuDivider(),
                    PopupMenuItem(
                      value: fac.accountStatus == 'suspended' ? 'activate' : 'suspend',
                      child: Text(fac.accountStatus == 'suspended' ? 'Re-activate Account' : 'Suspend Account'),
                    ),
                    if (fac.accountStatus != 'inactive')
                      const PopupMenuItem(
                        value: 'deactivate',
                        child: Text('Deactivate Account'),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  // TAB 1: Attendance Records, Search & Manual Exceptions
  Widget _buildRecordsAndSearchTab(
    BuildContext context,
    AdminDashboardState state,
    AdminDashboardViewModel viewModel,
  ) {
    final filtered = state.filteredRecords;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Search bar
        TextField(
          onChanged: (val) => viewModel.setSearchQuery(val),
          decoration: InputDecoration(
            labelText: 'Search by Faculty Name, ID, or Roll Number',
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: state.searchQuery.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear_rounded),
                    onPressed: () => viewModel.setSearchQuery(''),
                  )
                : null,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
        ),
        const SizedBox(height: 14),

        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Showing ${filtered.length} of ${state.records.length} records',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.textMuted),
            ),
            TextButton.icon(
              icon: const Icon(Icons.download_rounded, size: 16),
              label: const Text('Export CSV'),
              onPressed: () => _handleExportCsv(context, viewModel),
            ),
          ],
        ),
        const SizedBox(height: 8),

        if (filtered.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(32.0),
              child: Center(child: Text('No attendance records match your search query.')),
            ),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: filtered.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final r = filtered[index];
              final isPresent = r.status == AttendanceRecordStatus.present;
              final isOutside = r.status == AttendanceRecordStatus.flaggedOutsideGeofence;
              final timeStr =
                  '${r.recordedAt.hour.toString().padLeft(2, "0")}:${r.recordedAt.minute.toString().padLeft(2, "0")}';
              final dateStr =
                  '${r.recordedAt.year}-${r.recordedAt.month.toString().padLeft(2, "0")}-${r.recordedAt.day.toString().padLeft(2, "0")}';

              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(14.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              r.facultyName ?? r.studentName ?? 'Faculty Member',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: isPresent
                                  ? (r.isLate ? Colors.amber.withOpacity(0.15) : AppTheme.statusSuccess.withOpacity(0.12))
                                  : AppTheme.statusError.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              isPresent ? (r.isLate ? 'LATE' : 'PRESENT') : (isOutside ? 'OUTSIDE GEOFENCE' : 'FLAGGED'),
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
                      const SizedBox(height: 4),
                      Text(
                        'ID: ${r.employeeId ?? r.studentRollNumber ?? "FAC"}  •  Date: $dateStr at $timeStr',
                        style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(Icons.verified_rounded, size: 14, color: r.isBiometricallyVerified ? AppTheme.statusSuccess : Colors.grey),
                          const SizedBox(width: 4),
                          Text(
                            r.isBiometricallyVerified ? 'Daugman IrisCode Verified' : 'Iris Verification Pending',
                            style: const TextStyle(fontSize: 11),
                          ),
                          const SizedBox(width: 12),
                          Icon(Icons.radar_rounded, size: 14, color: r.isWithinGeofence ? AppTheme.statusSuccess : AppTheme.statusError),
                          const SizedBox(width: 4),
                          Text(
                            r.isWithinGeofence ? 'Inside Campus' : 'Outside Campus Boundary',
                            style: const TextStyle(fontSize: 11),
                          ),
                        ],
                      ),
                      if (r.correctionReason != null) ...[
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: Colors.amber.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'Approved Exception: ${r.correctionReason} (by ${r.correctedBy ?? "Admin"})',
                            style: TextStyle(fontSize: 11, color: Colors.amber.shade900),
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerRight,
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                          icon: const Icon(Icons.edit_note_rounded, size: 14),
                          label: const Text('Approved Correction', style: TextStyle(fontSize: 11)),
                          onPressed: () => _showCorrectionDialog(context, viewModel, r),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
      ],
    );
  }

  // TAB 2: Geofence Boundaries
  Widget _buildGeofenceTab(
    BuildContext context,
    AdminDashboardState state,
    AdminDashboardViewModel viewModel,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Configured Campus Boundaries (PostGIS Geofences)',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF1E293B)),
        ),
        const SizedBox(height: 10),
        if (state.locations.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(24.0),
              child: Center(child: Text('No campus locations registered.')),
            ),
          )
        else
          ...state.locations.map((loc) {
            return Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(loc.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: loc.isActive ? Colors.green.withOpacity(0.12) : Colors.grey.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            loc.isActive ? 'ACTIVE' : 'INACTIVE',
                            style: TextStyle(
                              color: loc.isActive ? Colors.green : Colors.grey,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text('Code: ${loc.code} • ${loc.description}', style: const TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.my_location_rounded, size: 16, color: AppTheme.primaryBlue),
                        const SizedBox(width: 6),
                        Text(
                          'Center: ${loc.centerLatitude.toStringAsFixed(5)}° N, ${loc.centerLongitude.toStringAsFixed(5)}° E',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.radar_rounded, size: 16, color: Colors.teal),
                        const SizedBox(width: 6),
                        Text(
                          'Radius: ${loc.bufferRadiusMeters.toStringAsFixed(0)} meters (Circular & Polygon Buffer)',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.edit_location_alt_rounded, size: 16),
                      label: const Text('Edit Geofence Parameters'),
                      onPressed: () => _showEditGeofenceDialog(context, viewModel, loc),
                    ),
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }

  // TAB 3: Audit Logs & GDPR/DPDP Template Purge
  Widget _buildAuditLogsTab(
    BuildContext context,
    AdminDashboardState state,
    AdminDashboardViewModel viewModel,
  ) {
    final purgeIdController = TextEditingController();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Biometric deletion under Right to be Forgotten
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.privacy_tip_rounded, color: AppTheme.primaryBlue, size: 20),
                    SizedBox(width: 8),
                    Text('Biometric Data Purge (GDPR / DPDP Compliance)',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'Under institutional data protection policy, faculty may request permanent erasure of enrolled iris feature vectors.',
                  style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: purgeIdController,
                        decoration: const InputDecoration(
                          hintText: 'Enter Faculty ID / UUID to purge',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
                      onPressed: () async {
                        final id = purgeIdController.text.trim();
                        if (id.isNotEmpty) {
                          await viewModel.deleteBiometricTemplate(id);
                          purgeIdController.clear();
                        }
                      },
                      child: const Text('Purge Template'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Audit Trail
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('System Audit Events', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            Text('${state.auditLogs.length} events logged', style: const TextStyle(fontSize: 12, color: AppTheme.textMuted)),
          ],
        ),
        const SizedBox(height: 10),
        if (state.auditLogs.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(24.0),
              child: Center(child: Text('No audit events found.')),
            ),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: state.auditLogs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final log = state.auditLogs[index];
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.blueGrey.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              log.action,
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blueGrey),
                            ),
                          ),
                          Text(
                            log.timestamp.toIso8601String().substring(11, 19),
                            style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text('Actor: ${log.actorEmail ?? log.actorId ?? "System"} • Resource: ${log.resourceType}',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      Text('Details: ${log.details.toString()}',
                          style: const TextStyle(fontSize: 11, color: AppTheme.textMuted, fontFamily: 'monospace')),
                    ],
                  ),
                ),
              );
            },
          ),
      ],
    );
  }

  void _showEditPolicyDialog(
    BuildContext context,
    AdminDashboardViewModel viewModel,
    AttendancePolicy currentPolicy,
  ) {
    int startHour = currentPolicy.workdayStartHour;
    int startMinute = currentPolicy.workdayStartMinute;
    int grace = currentPolicy.gracePeriodMinutes;
    int endHour = currentPolicy.workdayEndHour;
    int endMinute = currentPolicy.workdayEndMinute;

    final graceController = TextEditingController(text: grace.toString());

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Configure College Attendance Policy'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Official Start Time:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 6),
                Row(
                  children: [
                    ElevatedButton(
                      onPressed: () async {
                        final t = await showTimePicker(
                          context: ctx,
                          initialTime: TimeOfDay(hour: startHour, minute: startMinute),
                        );
                        if (t != null) {
                          setDialogState(() {
                            startHour = t.hour;
                            startMinute = t.minute;
                          });
                        }
                      },
                      child: Text(
                        '${startHour.toString().padLeft(2, "0")}:${startMinute.toString().padLeft(2, "0")}',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                const Text('Grace Period (Minutes):', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 6),
                TextField(
                  controller: graceController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    isDense: true,
                    hintText: 'e.g. 15',
                  ),
                ),
                const SizedBox(height: 14),
                const Text('Official End Time:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 6),
                Row(
                  children: [
                    ElevatedButton(
                      onPressed: () async {
                        final t = await showTimePicker(
                          context: ctx,
                          initialTime: TimeOfDay(hour: endHour, minute: endMinute),
                        );
                        if (t != null) {
                          setDialogState(() {
                            endHour = t.hour;
                            endMinute = t.minute;
                          });
                        }
                      },
                      child: Text(
                        '${endHour.toString().padLeft(2, "0")}:${endMinute.toString().padLeft(2, "0")}',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                final g = int.tryParse(graceController.text) ?? 15;
                final updated = currentPolicy.copyWith(
                  workdayStartHour: startHour,
                  workdayStartMinute: startMinute,
                  gracePeriodMinutes: g,
                  workdayEndHour: endHour,
                  workdayEndMinute: endMinute,
                );
                Navigator.of(ctx).pop();
                await viewModel.updatePolicy(updated);
              },
              child: const Text('Save Policy'),
            ),
          ],
        ),
      ),
    );
  }

  void _showCorrectionDialog(
    BuildContext context,
    AdminDashboardViewModel viewModel,
    AttendanceRecord record,
  ) {
    final reasonController = TextEditingController();
    AttendanceRecordStatus selectedStatus = AttendanceRecordStatus.present;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text('Approved Correction: ${record.facultyName ?? record.studentName}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Corrected Status:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(height: 6),
              DropdownButton<AttendanceRecordStatus>(
                value: selectedStatus,
                isExpanded: true,
                items: const [
                  DropdownMenuItem(value: AttendanceRecordStatus.present, child: Text('Present (Approved Duty)')),
                  DropdownMenuItem(value: AttendanceRecordStatus.absent, child: Text('Absent / On Leave')),
                ],
                onChanged: (val) {
                  if (val != null) setDialogState(() => selectedStatus = val);
                },
              ),
              const SizedBox(height: 12),
              const Text('Justification Reason (Logged to Audit Trail):', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(height: 6),
              TextField(
                controller: reasonController,
                decoration: const InputDecoration(
                  hintText: 'e.g. Approved official external duty / On-duty leave',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                final reason = reasonController.text.trim();
                if (reason.isNotEmpty) {
                  Navigator.of(ctx).pop();
                  await viewModel.correctAttendance(
                    recordId: record.id,
                    newStatus: selectedStatus,
                    justification: reason,
                  );
                }
              },
              child: const Text('Submit Correction'),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditGeofenceDialog(
    BuildContext context,
    AdminDashboardViewModel viewModel,
    CampusLocation loc,
  ) {
    final latController = TextEditingController(text: loc.centerLatitude.toString());
    final lngController = TextEditingController(text: loc.centerLongitude.toString());
    final radiusController = TextEditingController(text: loc.bufferRadiusMeters.toString());
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Edit Geofence: ${loc.code}'),
        content: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: latController,
                  decoration: const InputDecoration(labelText: 'Center Latitude (-90 to 90)'),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  validator: (val) {
                    final d = double.tryParse(val ?? '');
                    if (d == null || d < -90 || d > 90) return 'Enter valid latitude (-90 to 90)';
                    return null;
                  },
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: lngController,
                  decoration: const InputDecoration(labelText: 'Center Longitude (-180 to 180)'),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  validator: (val) {
                    final d = double.tryParse(val ?? '');
                    if (d == null || d < -180 || d > 180) return 'Enter valid longitude (-180 to 180)';
                    return null;
                  },
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: radiusController,
                  decoration: const InputDecoration(labelText: 'Buffer Radius (meters)'),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  validator: (val) {
                    final d = double.tryParse(val ?? '');
                    if (d == null || d <= 0 || d > 5000) return 'Enter radius (1 - 5000m)';
                    return null;
                  },
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              if (formKey.currentState?.validate() ?? false) {
                final lat = double.parse(latController.text);
                final lng = double.parse(lngController.text);
                final radius = double.parse(radiusController.text);
                Navigator.of(ctx).pop();
                await viewModel.updateBoundary(
                  locationId: loc.id,
                  lat: lat,
                  lng: lng,
                  radius: radius,
                );
              }
            },
            child: const Text('Save Changes'),
          ),
        ],
      ),
    );
  }

  void _showRejectFacultyDialog(
    BuildContext context,
    AdminDashboardViewModel viewModel,
    User faculty,
  ) {
    final reasonController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Reject Face Verification: ${faculty.fullName}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Specify rejection reason (e.g., photo blur, multiple faces, face partially occluded, invalid angle):',
              style: TextStyle(fontSize: 12.5),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: reasonController,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: 'Enter detailed reason for rejection...',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.statusError),
            onPressed: () async {
              final reason = reasonController.text.trim();
              if (reason.isEmpty) return;
              Navigator.of(ctx).pop();
              await viewModel.rejectFaculty(faculty.id, reason);
            },
            child: const Text('Confirm Rejection'),
          ),
        ],
      ),
    );
  }

  void _showEnrollmentPhotoPreview(BuildContext context, User faculty) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(18.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      'Biometric Enrollment: ${faculty.fullName}',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.of(ctx).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  width: 220,
                  height: 220,
                  color: Colors.black12,
                  child: _buildFacultyPhotoAvatar(faculty),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Faculty ID: ${faculty.employeeId ?? faculty.studentIdNumber ?? faculty.id}',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
              ),
              Text(
                faculty.email,
                style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
              ),
              Text(
                'Department: ${faculty.department ?? "General Engineering"}',
                style: const TextStyle(fontSize: 12, color: Color(0xFF475569)),
              ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: faculty.isApproved
                      ? AppTheme.statusSuccess.withOpacity(0.12)
                      : (faculty.approvalStatus == FacultyApprovalStatus.rejected
                          ? AppTheme.statusError.withOpacity(0.12)
                          : Colors.orange.withOpacity(0.15)),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'STATUS: ${faculty.approvalStatus.name.toUpperCase()}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: faculty.isApproved
                        ? AppTheme.statusSuccess
                        : (faculty.approvalStatus == FacultyApprovalStatus.rejected
                            ? AppTheme.statusError
                            : Colors.orange.shade900),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatSubmissionDate(DateTime? dt) {
    if (dt == null) return 'Pending / Just now';
    final y = dt.year.toString();
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$y-$m-$d $hh:$mm';
  }

  Future<void> _handleExportCsv(BuildContext context, AdminDashboardViewModel viewModel) async {
    final csv = await viewModel.exportCsv();
    if (csv != null && context.mounted) {
      await Clipboard.setData(ClipboardData(text: csv));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Authorized faculty attendance report exported and copied to clipboard as CSV.'),
          backgroundColor: AppTheme.statusSuccess,
        ),
      );
    }
  }
}

class _AdminMetric extends StatelessWidget {
  final String title;
  final String value;
  final String subtitle;
  final Color color;

  const _AdminMetric({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        child: Column(
          children: [
            Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
            const SizedBox(height: 2),
            Text(title, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text(subtitle, style: const TextStyle(fontSize: 9.5, color: AppTheme.textMuted), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

Widget _buildFacultyPhotoAvatar(User fac) {
  if (fac.avatarUrl != null && fac.avatarUrl!.isNotEmpty) {
    if (fac.avatarUrl!.startsWith('data:image')) {
      try {
        final commaIdx = fac.avatarUrl!.indexOf(',');
        if (commaIdx != -1) {
          final base64Str = fac.avatarUrl!.substring(commaIdx + 1);
          final bytes = base64Decode(base64Str);
          return Image.memory(
            bytes,
            fit: BoxFit.cover,
            width: 54,
            height: 54,
            errorBuilder: (_, __, ___) => _fallbackAvatarIcon(fac),
          );
        }
      } catch (_) {}
    } else if (fac.avatarUrl!.startsWith('http')) {
      return Image.network(
        fac.avatarUrl!,
        fit: BoxFit.cover,
        width: 54,
        height: 54,
        errorBuilder: (_, __, ___) => _fallbackAvatarIcon(fac),
      );
    }
  }
  return _fallbackAvatarIcon(fac);
}

Widget _fallbackAvatarIcon(User fac) {
  return Container(
    color: AppTheme.primaryBlue.withOpacity(0.1),
    alignment: Alignment.center,
    child: Text(
      fac.fullName.isNotEmpty ? fac.fullName[0].toUpperCase() : 'F',
      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: AppTheme.primaryBlue),
    ),
  );
}

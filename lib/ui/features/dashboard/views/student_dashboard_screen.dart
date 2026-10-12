import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/services/location_service.dart';
import '../../../../core/theme/app_theme.dart';
import '../../auth/view_models/auth_view_model.dart';
import '../view_models/geofence_view_model.dart';
import '../widgets/campus_geofence_map_view.dart';
import '../../../../main.dart';

class StudentDashboardScreen extends ConsumerWidget {
  const StudentDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);
    final user = authState.user;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Student Portal'),
        actions: [
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
              // Welcome Card
              Card(
                color: AppTheme.primaryBlue,
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.irisCyan.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Text(
                              'STUDENT IDENTIFIER',
                              style: TextStyle(
                                color: AppTheme.irisCyan,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.8,
                              ),
                            ),
                          ),
                          const Icon(
                            Icons.school_rounded,
                            color: Colors.white70,
                            size: 22,
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Text(
                        user?.fullName ?? 'Alex Morgan',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'ID: ${user?.studentIdNumber ?? "STU-2026-9481"}  •  ${user?.department ?? "Computer Science"}',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.8),
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: (user?.isIrisEnrolled ?? false)
                                  ? AppTheme.statusSuccess.withOpacity(0.2)
                                  : Colors.amber.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: (user?.isIrisEnrolled ?? false)
                                    ? AppTheme.statusSuccess
                                    : Colors.amberAccent,
                                width: 0.8,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  (user?.isIrisEnrolled ?? false)
                                      ? Icons.verified_user_rounded
                                      : Icons.warning_amber_rounded,
                                  color: (user?.isIrisEnrolled ?? false)
                                      ? AppTheme.statusSuccess
                                      : Colors.amberAccent,
                                  size: 13,
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  (user?.isIrisEnrolled ?? false)
                                      ? 'BIOMETRICS ENROLLED'
                                      : 'ENROLLMENT PENDING',
                                  style: TextStyle(
                                    color: (user?.isIrisEnrolled ?? false)
                                        ? AppTheme.statusSuccess
                                        : Colors.amberAccent,
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Spacer(),
                          TextButton.icon(
                            style: TextButton.styleFrom(
                              foregroundColor: AppTheme.irisCyan,
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            ),
                            icon: const Icon(Icons.refresh_rounded, size: 14),
                            label: Text(
                              (user?.isIrisEnrolled ?? false) ? 'Re-enroll Face/Iris' : 'Enroll Now',
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
              ),
              const SizedBox(height: 16),

              // Geofence & GPS Verification Section
              _StudentGeofenceAttendanceCard(),
              const SizedBox(height: 16),

              // Attendance Statistics
              const Text(
                'Attendance Summary',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.primaryBlue,
                ),
              ),
              const SizedBox(height: 10),
              FutureBuilder<List<dynamic>>(
                future: ref.read(attendanceRepositoryProvider).getAttendanceRecords(),
                builder: (context, snapshot) {
                  final records = snapshot.data ?? [];
                  final verifiedCount = records.where((r) => r.isBiometricallyVerified || r.status.toString().contains('present')).length;
                  final totalCount = records.length;
                  final rate = totalCount > 0 ? (verifiedCount / totalCount * 100).toStringAsFixed(1) : '0.0';

                  return Row(
                    children: [
                      _StatCard(
                        title: 'Overall Rate',
                        value: '$rate%',
                        trend: totalCount == 0 ? 'No sessions logged yet' : '$verifiedCount of $totalCount verified',
                        color: totalCount == 0 ? AppTheme.textMuted : AppTheme.statusSuccess,
                      ),
                      const SizedBox(width: 12),
                      _StatCard(
                        title: 'Classes Present',
                        value: '$verifiedCount / $totalCount',
                        trend: totalCount == 0 ? 'Fresh Student Account' : 'Mandatory >= 85%',
                        color: totalCount == 0 ? AppTheme.textMuted : AppTheme.primaryAccent,
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 20),

              // Switch Session Action
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
    );
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
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppTheme.textMuted,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                value,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                trend,
                style: const TextStyle(
                  fontSize: 11,
                  color: Color(0xFF64748B),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StudentGeofenceAttendanceCard extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final geoState = ref.watch(geofenceStateProvider);
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
                  'Campus Geofence Verification',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1E293B),
                  ),
                ),
                const Spacer(),
                if (geoState.status == LocationAcquisitionStatus.acquiringGps)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: 12),

            // Map View displaying campus polygon and student GPS point
            if (campus != null) ...[
              CampusGeofenceMapView(
                campus: campus,
                userLocation: userLoc,
                isInside: isInside,
              ),
              const SizedBox(height: 12),
            ],

            // Geofence status banner
            if (eval != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isInside
                      ? AppTheme.statusSuccess.withOpacity(0.08)
                      : AppTheme.statusError.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isInside
                        ? AppTheme.statusSuccess.withOpacity(0.25)
                        : AppTheme.statusError.withOpacity(0.25),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      isInside ? Icons.check_circle_outline : Icons.error_outline,
                      color: isInside ? AppTheme.statusSuccess : AppTheme.statusError,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isInside
                                ? 'Inside Attendance Perimeter'
                                : 'Outside Permitted Boundary',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: isInside
                                  ? const Color(0xFF065F46)
                                  : const Color(0xFF991B1B),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            eval.statusReason,
                            style: TextStyle(
                              fontSize: 12,
                              color: isInside
                                  ? const Color(0xFF047857)
                                  : const Color(0xFFB91C1C),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],

            // Error or warning banner
            if (geoState.errorMessage != null) ...[
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFF59E0B)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded, size: 18, color: Color(0xFFB45309)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        geoState.errorMessage!,
                        style: const TextStyle(fontSize: 12, color: Color(0xFF78350F)),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],

            // Submission Success Banner
            if (geoState.hasSubmitted && geoState.submissionMessage != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.statusSuccess.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  geoState.submissionMessage!,
                  style: const TextStyle(
                    color: Color(0xFF065F46),
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],

            // Action Buttons: Acquire GPS & Submit Check-In
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: geoState.status == LocationAcquisitionStatus.acquiringGps
                        ? null
                        : () => geoNotifier.acquireLocation(),
                    icon: const Icon(Icons.my_location_rounded, size: 18),
                    label: const Text('Update GPS Fix'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: (userLoc == null || geoState.isSubmitting || geoState.hasSubmitted)
                        ? null
                        : () {
                            // Submits to active CS-402 session
                            geoNotifier.submitAttendance(
                              sessionId: 'cccccccc-cccc-cccc-cccc-cccccccccccc',
                            );
                          },
                    icon: geoState.isSubmitting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.send_rounded, size: 18),
                    label: Text(geoState.hasSubmitted ? 'Checked In' : 'Submit Check-In'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryBlue,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                context.push('/iris-capture?sessionId=cccccccc-cccc-cccc-cccc-cccccccccccc');
              },
              icon: const Icon(Icons.camera_alt_rounded),
              label: const Text('Open Biometric Iris Scanner'),
            ),

            // Development-mode edge case testing chips
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                ActionChip(
                  label: const Text('Test Inside VNR Campus', style: TextStyle(fontSize: 10.5)),
                  onPressed: () => geoNotifier.setSimulatedLocation(17.5385, 78.3852),
                ),
                ActionChip(
                  label: const Text('Test At Gate (100m Boundary)', style: TextStyle(fontSize: 10.5)),
                  onPressed: () => geoNotifier.setSimulatedLocation(17.5410, 78.3852),
                ),
                ActionChip(
                  label: const Text('Test Outside (VNR Circle / 1.5 km)', style: TextStyle(fontSize: 10.5)),
                  onPressed: () => geoNotifier.setSimulatedLocation(17.5280, 78.3750),
                ),
                ActionChip(
                  label: const Text('Simulate Mock GPS App', style: TextStyle(fontSize: 10.5)),
                  onPressed: () => geoNotifier.setSimulatedLocation(17.5385, 78.3852, isMock: true),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

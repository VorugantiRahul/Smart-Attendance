import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris_attendance/core/theme/app_theme.dart';
import 'package:iris_attendance/data/models/user_model.dart';
import 'package:iris_attendance/data/repositories/dev_mock_attendance_repository.dart';
import 'package:iris_attendance/data/repositories/dev_mock_auth_repository.dart';
import 'package:iris_attendance/main.dart';
import 'package:iris_attendance/ui/features/auth/view_models/auth_view_model.dart';
import 'package:iris_attendance/ui/features/dashboard/views/teacher_dashboard_screen.dart';

void main() {
  testWidgets('TeacherDashboardScreen renders all cards without error or blank screen',
      (WidgetTester tester) async {
    final devAuthRepo = DevMockAuthRepository();
    final devAttendanceRepo = DevMockAttendanceRepository(devAuthRepo);

    // Seed teacher user
    const teacherUser = User(
      id: 'teacher-101',
      fullName: 'Dr. Sarah Jenkins',
      email: 'teacher@university.edu',
      role: UserRole.teacher,
      employeeId: 'FAC-CSE-102',
      designation: 'Associate Professor',
      department: 'Computer Science & Engineering',
      isIrisEnrolled: true,
      isApproved: true,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(devAuthRepo),
          attendanceRepositoryProvider.overrideWithValue(devAttendanceRepo),
          authStateProvider.overrideWith(
            (ref) => AuthNotifier(devAuthRepo)
              ..state = AuthState(user: teacherUser, isDevMode: true),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: const TeacherDashboardScreen(),
        ),
      ),
    );

    // Initial pump
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // Verify AppBar
    expect(find.text('Faculty Attendance Console'), findsOneWidget);

    // Verify Faculty Name
    expect(find.text('Dr. Sarah Jenkins'), findsOneWidget);

    // Verify Prominent Action Button
    expect(find.text('MARK MY ATTENDANCE'), findsOneWidget);

    // Verify Today Status Card
    expect(find.text("Today's Attendance Status"), findsOneWidget);

    // Verify Monthly Summary Cards
    expect(find.text('Monthly Attendance Summary'), findsOneWidget);
    expect(find.text('Days Present'), findsOneWidget);
    expect(find.text('Late Arrivals'), findsOneWidget);
    expect(find.text('Attendance Rate'), findsOneWidget);

    // Verify Campus Geofence Radar Card
    expect(find.text('Campus Geofence Status'), findsOneWidget);

    // Verify History Header
    expect(find.text('My Attendance History'), findsOneWidget);
  });
}

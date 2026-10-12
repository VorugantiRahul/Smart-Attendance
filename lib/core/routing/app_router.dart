import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../data/models/user_model.dart';
import '../../ui/features/auth/view_models/auth_view_model.dart';
import '../../ui/features/splash/views/splash_screen.dart';
import '../../ui/features/auth/views/welcome_screen.dart';
import '../../ui/features/auth/views/login_screen.dart';
import '../../ui/features/auth/views/register_screen.dart';
import '../../ui/features/auth/views/forgot_password_screen.dart';
import '../../ui/features/auth/views/role_selection_screen.dart';
import '../../ui/features/auth/views/face_enrollment_screen.dart';
import '../../ui/features/auth/views/unauthorized_screen.dart';
import '../../ui/features/dashboard/views/student_dashboard_screen.dart';
import '../../ui/features/dashboard/views/teacher_dashboard_screen.dart';
import '../../ui/features/dashboard/views/admin_dashboard_screen.dart';
import '../../ui/features/dashboard/views/iris_camera_capture_screen.dart';

/// Provider for GoRouter that dynamically evaluates authentication and RBAC guards
final routerProvider = Provider<GoRouter>((ref) {
  final authNotifier = ref.watch(authStateProvider.notifier);

  return GoRouter(
    initialLocation: '/',
    refreshListenable: GoRouterRefreshStream(authNotifier.stream),
    redirect: (context, state) {
      final authState = ref.read(authStateProvider);
      final isLoggedIn = authState.isAuthenticated;
      final currentPath = state.uri.path;

      final publicRoutes = [
        '/',
        '/welcome',
        '/login',
        '/register',
        '/forgot-password',
      ];

      final isPublicRoute = publicRoutes.contains(currentPath);

      // If user is not logged in and attempts to access protected screens
      if (!isLoggedIn && !isPublicRoute) {
        return '/login';
      }

      // If user is logged in and navigates to login/register, route them to their role dashboard
      if (isLoggedIn && (currentPath == '/login' || currentPath == '/register')) {
        final role = authState.user?.role;
        switch (role) {
          case UserRole.student:
            return '/student-dashboard';
          case UserRole.teacher:
            return '/teacher-dashboard';
          case UserRole.admin:
            return '/admin-dashboard';
          case null:
            return '/role-selection';
        }
      }

      // Role-Based Screen Access Guards
      final userRole = authState.user?.role;

      if (currentPath == '/student-dashboard' && userRole != UserRole.student) {
        return '/unauthorized?required=student&current=${userRole?.name}';
      }

      if ((currentPath == '/teacher-dashboard' || currentPath == '/faculty-dashboard') &&
          userRole != UserRole.teacher) {
        return '/unauthorized?required=teacher&current=${userRole?.name}';
      }

      if (currentPath == '/admin-dashboard' && userRole != UserRole.admin) {
        return '/unauthorized?required=admin&current=${userRole?.name}';
      }

      return null;
    },
    routes: [
      GoRoute(
        path: '/',
        name: 'splash',
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: '/welcome',
        name: 'welcome',
        builder: (context, state) => const WelcomeScreen(),
      ),
      GoRoute(
        path: '/login',
        name: 'login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/register',
        name: 'register',
        builder: (context, state) => const RegisterScreen(),
      ),
      GoRoute(
        path: '/forgot-password',
        name: 'forgot-password',
        builder: (context, state) => const ForgotPasswordScreen(),
      ),
      GoRoute(
        path: '/role-selection',
        name: 'role-selection',
        builder: (context, state) => const RoleSelectionScreen(),
      ),
      GoRoute(
        path: '/face-enrollment',
        name: 'face-enrollment',
        builder: (context, state) {
          final isReEnrollment = state.uri.queryParameters['reEnroll'] == 'true';
          return FaceEnrollmentScreen(isReEnrollment: isReEnrollment);
        },
      ),
      GoRoute(
        path: '/student-dashboard',
        name: 'student-dashboard',
        builder: (context, state) => const StudentDashboardScreen(),
      ),
      GoRoute(
        path: '/teacher-dashboard',
        name: 'teacher-dashboard',
        builder: (context, state) => const TeacherDashboardScreen(),
      ),
      GoRoute(
        path: '/faculty-dashboard',
        name: 'faculty-dashboard',
        builder: (context, state) => const TeacherDashboardScreen(),
      ),
      GoRoute(
        path: '/admin-dashboard',
        name: 'admin-dashboard',
        builder: (context, state) => const AdminDashboardScreen(),
      ),
      GoRoute(
        path: '/iris-capture',
        name: 'iris-capture',
        builder: (context, state) {
          final sessionId = state.uri.queryParameters['sessionId'] ?? 'cccccccc-cccc-cccc-cccc-cccccccccccc';
          return IrisCameraCaptureScreen(sessionId: sessionId);
        },
      ),
      GoRoute(
        path: '/unauthorized',
        name: 'unauthorized',
        builder: (context, state) {
          final requiredStr = state.uri.queryParameters['required'];
          final currentStr = state.uri.queryParameters['current'];

          final req = UserRole.values.cast<UserRole?>().firstWhere(
                (r) => r?.name == requiredStr,
                orElse: () => null,
              );
          final curr = UserRole.values.cast<UserRole?>().firstWhere(
                (r) => r?.name == currentStr,
                orElse: () => null,
              );

          return UnauthorizedScreen(
            requiredRole: req,
            currentRole: curr,
          );
        },
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      body: Center(
        child: Text('Page not found: ${state.uri.toString()}'),
      ),
    ),
  );
});

/// Bridge stream events to ChangeNotifier for GoRouter refreshListenable
class GoRouterRefreshStream extends ChangeNotifier {
  GoRouterRefreshStream(Stream<dynamic> stream) {
    notifyListeners();
    _subscription = stream.asBroadcastStream().listen(
      (dynamic _) => notifyListeners(),
    );
  }

  late final dynamic _subscription;

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}

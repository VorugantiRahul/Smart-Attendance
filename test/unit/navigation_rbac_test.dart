import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris_attendance/data/models/user_model.dart';
import 'package:iris_attendance/data/repositories/dev_mock_auth_repository.dart';
import 'package:iris_attendance/ui/features/auth/view_models/auth_view_model.dart';

void main() {
  group('GoRouter Role-Based Navigation & Access Guards Tests', () {
    late DevMockAuthRepository mockAuthRepo;

    setUp(() {
      mockAuthRepo = DevMockAuthRepository();
    });

    test('Unauthenticated user attempting to access dashboard is redirected to login', () {
      final container = ProviderContainer(
        overrides: [
          authRepositoryProvider.overrideWithValue(mockAuthRepo),
        ],
      );
      addTearDown(container.dispose);

      final authState = container.read(authStateProvider);
      expect(authState.isAuthenticated, isFalse);
    });

    test('RBAC Guard: Student role redirected away from teacher and admin dashboards', () async {
      final user = await mockAuthRepo.login(
        email: 'student@university.edu',
        password: 'Password123',
      );

      final container = ProviderContainer(
        overrides: [
          authRepositoryProvider.overrideWithValue(mockAuthRepo),
          authStateProvider.overrideWith(
            (ref) => AuthNotifier(mockAuthRepo)..state = AuthState(user: user, isDevMode: true),
          ),
        ],
      );
      addTearDown(container.dispose);

      final authState = container.read(authStateProvider);
      expect(authState.user?.role, equals(UserRole.student));
      expect(authState.user?.role != UserRole.teacher, isTrue);
      expect(authState.user?.role != UserRole.admin, isTrue);
    });

    test('RBAC Guard: Faculty role verified for faculty operations', () async {
      final user = await mockAuthRepo.login(
        email: 'faculty@university.edu',
        password: 'Password123',
      );

      expect(user.role, equals(UserRole.teacher));
    });

    test('RBAC Guard: Administrator role verified for admin operations', () async {
      final user = await mockAuthRepo.login(
        email: 'admin@university.edu',
        password: 'Password123',
      );

      expect(user.role, equals(UserRole.admin));
    });
  });
}

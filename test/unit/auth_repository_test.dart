import 'package:flutter_test/flutter_test.dart';
import 'package:iris_attendance/data/models/user_model.dart';
import 'package:iris_attendance/data/repositories/auth_repository.dart';
import 'package:iris_attendance/data/repositories/dev_mock_auth_repository.dart';

void main() {
  group('DevMockAuthRepository & RBAC Unit Tests', () {
    late AuthRepository authRepository;

    setUp(() {
      authRepository = DevMockAuthRepository();
    });

    test('login with student credentials resolves student role from backend profile', () async {
      final user = await authRepository.login(
        email: 'student@university.edu',
        password: 'Password123',
      );

      expect(user.email, equals('student@university.edu'));
      expect(user.role, equals(UserRole.student));
      expect(user.studentIdNumber, equals('STU-2026-9481'));
    });

    test('login with faculty credentials resolves teacher role', () async {
      final user = await authRepository.login(
        email: 'faculty@university.edu',
        password: 'Password123',
      );

      expect(user.role, equals(UserRole.teacher));
      expect(user.fullName, equals('Prof. Evelyn Reed'));
    });

    test('login with admin credentials resolves admin role', () async {
      final user = await authRepository.login(
        email: 'admin@university.edu',
        password: 'Password123',
      );

      expect(user.role, equals(UserRole.admin));
      expect(user.fullName, equals('Dr. Arthur Vance'));
    });

    test('register provisions new user profile and stores separately from credentials', () async {
      final user = await authRepository.register(
        fullName: 'Candidate John',
        email: 'c.john@university.edu',
        password: 'StrongPass123',
        requestedRole: UserRole.student,
        studentIdNumber: 'STU-2026-1199',
        department: 'Biotechnology',
      );

      expect(user.fullName, equals('Candidate John'));
      expect(user.role, equals(UserRole.student));
      expect(user.studentIdNumber, equals('STU-2026-1199'));

      // Verify profile can be queried
      final currentUser = await authRepository.getCurrentUser();
      expect(currentUser?.email, equals('c.john@university.edu'));
    });

    test('password reset simulation handles email request gracefully', () async {
      await expectLater(
        authRepository.sendPasswordResetEmail(email: 'student@university.edu'),
        completes,
      );
    });

    test('logout terminates session and emits null auth state', () async {
      await authRepository.login(
        email: 'admin@university.edu',
        password: 'Password123',
      );

      var currentUser = await authRepository.getCurrentUser();
      expect(currentUser, isNotNull);

      await authRepository.logout();
      currentUser = await authRepository.getCurrentUser();
      expect(currentUser, isNull);
    });
  });
}

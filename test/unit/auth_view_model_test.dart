import 'package:flutter_test/flutter_test.dart';
import 'package:iris_attendance/data/models/user_model.dart';
import 'package:iris_attendance/ui/features/auth/view_models/auth_view_model.dart';
import 'package:iris_attendance/data/repositories/dev_mock_auth_repository.dart';

void main() {
  group('AuthNotifier & Role Enforcement Tests', () {
    late DevMockAuthRepository mockRepo;
    late AuthNotifier authNotifier;

    setUp(() {
      mockRepo = DevMockAuthRepository();
      authNotifier = AuthNotifier(mockRepo);
    });

    test('Initial state is unauthenticated with devMode true', () {
      expect(authNotifier.state.isAuthenticated, isFalse);
      expect(authNotifier.state.user, isNull);
      expect(authNotifier.state.isDevMode, isTrue);
    });

    test('Successful login updates state with backend verified user role', () async {
      final success = await authNotifier.login(
        email: 'faculty@university.edu',
        password: 'Password123',
      );

      expect(success, isTrue);
      expect(authNotifier.state.isAuthenticated, isTrue);
      expect(authNotifier.state.user?.role, equals(UserRole.teacher));
    });

    test('Logout clears session completely', () async {
      await authNotifier.login(
        email: 'student@university.edu',
        password: 'Password123',
      );
      expect(authNotifier.state.isAuthenticated, isTrue);

      await authNotifier.logout();
      expect(authNotifier.state.isAuthenticated, isFalse);
      expect(authNotifier.state.user, isNull);
    });

    test('sendPasswordReset sets successMessage', () async {
      final success = await authNotifier.sendPasswordReset(
        email: 'student@university.edu',
      );

      expect(success, isTrue);
      expect(authNotifier.state.successMessage, isNotNull);
    });
  });

  group('UserModel Serialization & Profile Integrity Tests', () {
    test('fromMap parses profile record correctly', () {
      final map = {
        'id': 'uuid-1234',
        'full_name': 'Prof. Alan Turing',
        'email': 'turing@university.edu',
        'role': 'teacher',
        'student_id_number': null,
        'department': 'Computer Science',
        'is_iris_enrolled': true,
      };

      final user = User.fromMap(map);
      expect(user.id, equals('uuid-1234'));
      expect(user.fullName, equals('Prof. Alan Turing'));
      expect(user.role, equals(UserRole.teacher));
      expect(user.isIrisEnrolled, isTrue);
    });

    test('toMap converts user entity to separate profile map', () {
      const user = User(
        id: 'uuid-5678',
        fullName: 'Grace Hopper',
        email: 'hopper@university.edu',
        role: UserRole.admin,
        department: 'Naval Engineering',
      );

      final map = user.toMap();
      expect(map['role'], equals('admin'));
      expect(map['email'], equals('hopper@university.edu'));
      expect(map['id'], equals('uuid-5678'));
    });
  });
}

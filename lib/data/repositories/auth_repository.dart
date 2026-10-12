import 'dart:async';
import '../../data/models/user_model.dart';

abstract class AuthRepository {
  /// Stream of user auth and profile changes
  Stream<User?> get authStateChanges;

  /// Check if the repository is running in real backend or labeled development mode
  bool get isLiveBackend;

  /// Sign in with email and password
  /// Note: The role is validated against the backend profile record, never blindly trusted from client input.
  Future<User> login({
    required String email,
    required String password,
  });

  /// Register a new user credentials and provision institutional profile
  Future<User> register({
    required String fullName,
    required String email,
    required String password,
    required UserRole requestedRole,
    String? studentIdNumber,
    String? employeeId,
    String? phone,
    String? designation,
    String? department,
  });

  /// Request password reset link / email
  Future<void> sendPasswordResetEmail({required String email});

  /// Update password with token
  Future<void> updatePassword({required String newPassword});

  /// Sign out current session
  Future<void> logout();

  /// Retrieve active authenticated user with backend profile
  Future<User?> getCurrentUser();

  /// Enroll or re-enroll student biometric templates (face + Daugman iris template)
  Future<void> enrollStudentBiometrics({
    required String userId,
    required String templateHex,
    required String maskHex,
    required double qualityScore,
    List<int>? faceImageBytes,
    String? faceTemplateBase64,
    Map<String, dynamic>? telemetry,
  });

  /// Retrieve the user's enrolled biometric reference template from secure storage
  Future<Map<String, dynamic>?> getEnrolledBiometrics({required String userId});

  /// Delete student biometric templates (Right to be Forgotten)
  Future<void> deleteStudentBiometrics({required String userId});
}

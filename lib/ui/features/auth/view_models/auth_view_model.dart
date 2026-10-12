import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/config/app_config.dart';
import '../../../../data/models/user_model.dart';
import '../../../../data/repositories/auth_repository.dart';
import '../../../../data/repositories/dev_mock_auth_repository.dart';

final appConfigProvider = Provider<AppConfig>((ref) {
  return AppConfig.fromEnvironment();
});

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  // Can be overridden in main.dart or tests with SupabaseAuthRepository
  return DevMockAuthRepository();
});

@immutable
class AuthState {
  final User? user;
  final bool isLoading;
  final String? errorMessage;
  final String? successMessage;
  final bool isDevMode;

  const AuthState({
    this.user,
    this.isLoading = false,
    this.errorMessage,
    this.successMessage,
    this.isDevMode = true,
  });

  bool get isAuthenticated => user != null;

  AuthState copyWith({
    User? user,
    bool? isLoading,
    String? errorMessage,
    String? successMessage,
    bool? isDevMode,
    bool clearError = false,
    bool clearSuccess = false,
    bool clearUser = false,
  }) {
    return AuthState(
      user: clearUser ? null : (user ?? this.user),
      isLoading: isLoading ?? this.isLoading,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      successMessage: clearSuccess ? null : (successMessage ?? this.successMessage),
      isDevMode: isDevMode ?? this.isDevMode,
    );
  }
}

class AuthNotifier extends StateNotifier<AuthState> {
  final AuthRepository _repository;

  AuthNotifier(this._repository)
      : super(AuthState(isDevMode: !_repository.isLiveBackend)) {
    // Listen for auth state stream updates
    _repository.authStateChanges.listen((user) {
      state = state.copyWith(user: user, clearUser: user == null);
    });
  }

  Future<bool> login({
    required String email,
    required String password,
  }) async {
    state = state.copyWith(
      isLoading: true,
      clearError: true,
      clearSuccess: true,
    );

    try {
      final user = await _repository.login(
        email: email,
        password: password,
      );
      state = state.copyWith(user: user, isLoading: false);
      return true;
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: _cleanErrorMessage(e),
      );
      return false;
    }
  }

  Future<bool> register({
    required String fullName,
    required String email,
    required String password,
    required UserRole requestedRole,
    String? studentIdNumber,
    String? employeeId,
    String? phone,
    String? designation,
    String? department,
  }) async {
    state = state.copyWith(
      isLoading: true,
      clearError: true,
      clearSuccess: true,
    );

    try {
      final user = await _repository.register(
        fullName: fullName,
        email: email,
        password: password,
        requestedRole: requestedRole,
        studentIdNumber: studentIdNumber,
        employeeId: employeeId,
        phone: phone,
        designation: designation,
        department: department,
      );
      state = state.copyWith(user: user, isLoading: false);
      return true;
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: _cleanErrorMessage(e),
      );
      return false;
    }
  }

  Future<bool> sendPasswordReset({required String email}) async {
    state = state.copyWith(
      isLoading: true,
      clearError: true,
      clearSuccess: true,
    );

    try {
      await _repository.sendPasswordResetEmail(email: email);
      state = state.copyWith(
        isLoading: false,
        successMessage: 'Password reset link sent to your institutional email.',
      );
      return true;
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: _cleanErrorMessage(e),
      );
      return false;
    }
  }

  Future<bool> enrollBiometrics({
    required String templateHex,
    required String maskHex,
    required double qualityScore,
    List<int>? faceImageBytes,
    String? faceTemplateBase64,
    Map<String, dynamic>? telemetry,
  }) async {
    final user = state.user;
    if (user == null) {
      state = state.copyWith(errorMessage: 'Authentication required for biometric enrollment.');
      return false;
    }

    state = state.copyWith(isLoading: true, clearError: true);
    try {
      await _repository.enrollStudentBiometrics(
        userId: user.id,
        templateHex: templateHex,
        maskHex: maskHex,
        qualityScore: qualityScore,
        faceImageBytes: faceImageBytes,
        faceTemplateBase64: faceTemplateBase64,
        telemetry: telemetry,
      );
      final updated = user.copyWith(
        isIrisEnrolled: true,
        isApproved: false,
        approvalStatus: FacultyApprovalStatus.pending,
        submittedAt: DateTime.now(),
        rejectionReason: null,
      );
      state = state.copyWith(
        user: updated,
        isLoading: false,
        successMessage: 'Face & Iris biometrics successfully enrolled and submitted for administrator approval.',
      );
      return true;
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: _cleanErrorMessage(e),
      );
      return false;
    }
  }

  Future<bool> deleteBiometrics() async {
    final user = state.user;
    if (user == null) return false;

    state = state.copyWith(isLoading: true, clearError: true);
    try {
      await _repository.deleteStudentBiometrics(userId: user.id);
      final updated = user.copyWith(isIrisEnrolled: false);
      state = state.copyWith(
        user: updated,
        isLoading: false,
        successMessage: 'Biometric template permanently deleted from system.',
      );
      return true;
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: _cleanErrorMessage(e),
      );
      return false;
    }
  }

  Future<void> logout() async {
    state = state.copyWith(isLoading: true);
    await _repository.logout();
    state = AuthState(isDevMode: !_repository.isLiveBackend);
  }

  void clearMessages() {
    state = state.copyWith(clearError: true, clearSuccess: true);
  }

  String _cleanErrorMessage(dynamic error) {
    final str = error.toString();
    if (str.contains('over_email_send_rate_limit') || str.contains('email rate limit exceeded')) {
      return 'Supabase Email Limit Exceeded: In Supabase Dashboard -> Authentication -> Providers -> Email, turn OFF "Confirm email" to allow instant registrations without email sending limits.';
    }
    if (str.startsWith('Exception: ')) {
      return str.replaceFirst('Exception: ', '');
    }
    return str;
  }
}

final authStateProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  final repo = ref.watch(authRepositoryProvider);
  return AuthNotifier(repo);
});

import 'dart:async';
import 'dart:convert';
import '../../core/biometrics/face_iris_detector.dart';
import '../../core/biometrics/face_recognition_engine.dart';
import '../../core/utils/bmp_encoder.dart';
import '../models/user_model.dart';
import 'auth_repository.dart';

/// Explicitly labeled Development Mode Auth Repository
/// Used safely during local development or when Supabase keys are not yet configured.
/// Simulates real network latencies, role enforcement, and session lifecycle.
class DevMockAuthRepository implements AuthRepository {
  final StreamController<User?> _authStateController =
      StreamController<User?>.broadcast();

  // Simulated in-memory profile database
  static final Map<String, User> _mockDatabase = {
    'student@university.edu': const User(
      id: 'usr-student-001',
      fullName: 'Alex Morgan',
      email: 'student@university.edu',
      role: UserRole.student,
      studentIdNumber: 'STU-2026-9481',
      department: 'Computer Science & Engineering',
      isIrisEnrolled: true,
    ),
    'faculty@university.edu': const User(
      id: 'usr-faculty-002',
      fullName: 'Prof. Evelyn Reed',
      email: 'faculty@university.edu',
      role: UserRole.teacher,
      department: 'Computer Science & Engineering',
      isApproved: true,
      approvalStatus: FacultyApprovalStatus.approved,
      isIrisEnrolled: true,
    ),
    'admin@university.edu': const User(
      id: 'usr-admin-003',
      fullName: 'Dr. Arthur Vance',
      email: 'admin@university.edu',
      role: UserRole.admin,
      department: 'Campus Security & Administration',
    ),
  };

  User? _currentUser;

  @override
  bool get isLiveBackend => false;

  @override
  Stream<User?> get authStateChanges => _authStateController.stream;

  @override
  Future<User> login({
    required String email,
    required String password,
  }) async {
    await Future.delayed(const Duration(milliseconds: 600));

    final normalizedEmail = email.trim().toLowerCase();

    // Verify against registered mock database or create deterministic profile
    User user;
    if (_mockDatabase.containsKey(normalizedEmail)) {
      user = _mockDatabase[normalizedEmail]!;
    } else {
      // Deterministic role based on email or default to student
      UserRole assignedRole = UserRole.student;
      if (normalizedEmail.contains('admin')) {
        assignedRole = UserRole.admin;
      } else if (normalizedEmail.contains('prof') ||
          normalizedEmail.contains('faculty') ||
          normalizedEmail.contains('teacher')) {
        assignedRole = UserRole.teacher;
      }

      user = User(
        id: 'usr-dev-${DateTime.now().millisecondsSinceEpoch % 10000}',
        fullName: email.split('@').first.replaceAll('.', ' ').toUpperCase(),
        email: normalizedEmail,
        role: assignedRole,
        studentIdNumber: assignedRole == UserRole.student ? 'STU-2026-0042' : null,
        department: 'Engineering Division',
      );
      _mockDatabase[normalizedEmail] = user;
    }

    _currentUser = user;
    _authStateController.add(user);
    return user;
  }

  @override
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
  }) async {
    await Future.delayed(const Duration(milliseconds: 700));

    final normalizedEmail = email.trim().toLowerCase();
    final effectiveEmpId = employeeId ?? studentIdNumber ?? 'FAC-CSE-101';

    // Server-side security check: client cannot self-grant admin in production
    // (Dev mode logs role enforcement)
    final user = User(
      id: 'usr-dev-${DateTime.now().millisecondsSinceEpoch % 10000}',
      fullName: fullName.trim(),
      email: normalizedEmail,
      role: requestedRole,
      studentIdNumber: effectiveEmpId,
      employeeId: effectiveEmpId,
      phone: phone,
      designation: designation ?? 'Assistant Professor',
      department: department ?? 'Computer Science & Engineering',
      isIrisEnrolled: false,
      isApproved: false, // Must be approved by administrator before marking attendance
      approvalStatus: FacultyApprovalStatus.pending,
    );

    _mockDatabase[normalizedEmail] = user;
    _currentUser = user;
    _authStateController.add(user);
    return user;
  }

  @override
  Future<void> sendPasswordResetEmail({required String email}) async {
    await Future.delayed(const Duration(milliseconds: 500));
    final normalized = email.trim().toLowerCase();
    if (!_mockDatabase.containsKey(normalized)) {
      // For security, don't disclose whether email exists, but simulate dispatch
    }
  }

  @override
  Future<void> updatePassword({required String newPassword}) async {
    await Future.delayed(const Duration(milliseconds: 500));
  }

  @override
  Future<void> logout() async {
    await Future.delayed(const Duration(milliseconds: 200));
    _currentUser = null;
    _authStateController.add(null);
  }

  @override
  Future<User?> getCurrentUser() async {
    return _currentUser;
  }

  // In-memory biometric template vault: { userId: { 'templateHex': ..., 'maskHex': ..., 'qualityScore': ... } }
  static final Map<String, Map<String, dynamic>> _mockBiometrics = {
    'usr-student-001': {
      'templateHex': 'a5b4c3d2e1f0' * 32, // Valid 2048-bit template
      'maskHex': 'ff' * 256,
      'qualityScore': 0.94,
      'enrolledAt': DateTime.now().toIso8601String(),
    },
  };

  @override
  Future<void> enrollStudentBiometrics({
    required String userId,
    required String templateHex,
    required String maskHex,
    required double qualityScore,
    List<int>? faceImageBytes,
    String? faceTemplateBase64,
    Map<String, dynamic>? telemetry,
  }) async {
    await Future.delayed(const Duration(milliseconds: 350));

    // MANDATORY BACKEND VALIDATION: Never accept enrollment without valid single face
    if (faceImageBytes == null || faceImageBytes.isEmpty) {
      throw Exception('Backend validation failed: No face photograph provided for enrollment.');
    }

    final detector = AdaptiveFaceIrisDetector();
    final detection = await detector.detectLandmarks(
      grayscalePixels: faceImageBytes,
      width: 320,
      height: 240,
    );

    if (!detection.isValidForEnrollment) {
      throw Exception('Backend validation failed: ${detection.statusMessage}');
    }

    // Extract genuine face recognition template if not supplied directly
    String? effectiveFaceTemplate = faceTemplateBase64;
    if (effectiveFaceTemplate == null && detection.faceBoundingBox != null) {
      final faceEngine = StandardFaceRecognitionEngine();
      final faceTmpl = await faceEngine.extractTemplate(
        imagePixels: faceImageBytes,
        width: 320,
        height: 240,
        faceBox: detection.faceBoundingBox!,
      );
      effectiveFaceTemplate = faceTmpl.toBase64String();
    }

    _mockBiometrics[userId] = {
      'templateHex': templateHex,
      'maskHex': maskHex,
      'qualityScore': qualityScore,
      'faceTemplateBase64': effectiveFaceTemplate,
      'enrolledAt': DateTime.now().toIso8601String(),
      'faceImageBytes': faceImageBytes,
      'telemetry': telemetry,
    };

    // Update user profile isIrisEnrolled flag, avatarUrl as data URI or identifier
    final avatarDataUri = 'data:image/bmp;base64,' + 
        base64Encode(BmpEncoder.encodeGrayscale(grayscalePixels: faceImageBytes, width: 320, height: 240));

    for (final key in _mockDatabase.keys) {
      if (_mockDatabase[key]?.id == userId) {
        final updated = _mockDatabase[key]!.copyWith(
          isIrisEnrolled: true,
          approvalStatus: FacultyApprovalStatus.pending,
          isApproved: false,
          avatarUrl: avatarDataUri,
          submittedAt: DateTime.now(),
          clearRejectionReason: true,
        );
        _mockDatabase[key] = updated;
        if (_currentUser?.id == userId) {
          _currentUser = updated;
          _authStateController.add(updated);
        }
        break;
      }
    }
  }

  @override
  Future<Map<String, dynamic>?> getEnrolledBiometrics({required String userId}) async {
    await Future.delayed(const Duration(milliseconds: 200));
    return _mockBiometrics[userId];
  }

  @override
  Future<void> deleteStudentBiometrics({required String userId}) async {
    await Future.delayed(const Duration(milliseconds: 250));
    _mockBiometrics.remove(userId);

    for (final key in _mockDatabase.keys) {
      if (_mockDatabase[key]?.id == userId) {
        final updated = _mockDatabase[key]!.copyWith(isIrisEnrolled: false);
        _mockDatabase[key] = updated;
        if (_currentUser?.id == userId) {
          _currentUser = updated;
          _authStateController.add(updated);
        }
        break;
      }
    }
  }

  static List<User> getAllRegisteredUsers() {
    return _mockDatabase.values.toList();
  }

  static void setApproval(String userId, bool isApproved) {
    for (final key in _mockDatabase.keys) {
      if (_mockDatabase[key]?.id == userId) {
        final updated = _mockDatabase[key]!.copyWith(
          isApproved: isApproved,
          approvalStatus: isApproved ? FacultyApprovalStatus.approved : FacultyApprovalStatus.rejected,
          reviewedAt: DateTime.now(),
        );
        _mockDatabase[key] = updated;
        break;
      }
    }
  }

  static void rejectUser(String userId, String reason) {
    for (final key in _mockDatabase.keys) {
      if (_mockDatabase[key]?.id == userId) {
        final updated = _mockDatabase[key]!.copyWith(
          isApproved: false,
          approvalStatus: FacultyApprovalStatus.rejected,
          rejectionReason: reason,
          reviewedAt: DateTime.now(),
        );
        _mockDatabase[key] = updated;
        break;
      }
    }
  }

  static void requestReEnrollment(String userId) {
    for (final key in _mockDatabase.keys) {
      if (_mockDatabase[key]?.id == userId) {
        final updated = _mockDatabase[key]!.copyWith(
          isIrisEnrolled: false,
          isApproved: false,
          approvalStatus: FacultyApprovalStatus.pending,
          rejectionReason: 'Administrator requested fresh face photograph submission.',
          reviewedAt: DateTime.now(),
        );
        _mockDatabase[key] = updated;
        break;
      }
    }
  }

  static void setAccountStatus(String userId, String status) {
    for (final key in _mockDatabase.keys) {
      if (_mockDatabase[key]?.id == userId) {
        final updated = _mockDatabase[key]!.copyWith(
          accountStatus: status,
        );
        _mockDatabase[key] = updated;
        break;
      }
    }
  }
}

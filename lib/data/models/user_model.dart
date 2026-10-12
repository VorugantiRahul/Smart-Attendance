enum UserRole { student, teacher, admin }

enum FacultyApprovalStatus {
  pending,
  approved,
  rejected,
}

class User {
  final String id;
  final String fullName;
  final String email;
  final UserRole role;
  final String? studentIdNumber; // Maintained for backward compatibility
  final String? employeeId;      // Faculty identifier (e.g. FAC-CSE-104)
  final String? phone;           // Contact phone number
  final String? designation;     // e.g. Assistant Professor, HOD
  final String? department;
  final bool isIrisEnrolled;
  final bool isApproved;         // Admin approval flag for institutional onboarding
  final FacultyApprovalStatus approvalStatus; // pending, approved, rejected
  final String? rejectionReason; // Reason if admin rejected face photo/onboarding
  final String? accountStatus;   // active, suspended, inactive
  final String? avatarUrl;
  final DateTime? reviewedAt;
  final DateTime? submittedAt;
  final DateTime? createdAt;

  const User({
    required this.id,
    required this.fullName,
    required this.email,
    required this.role,
    this.studentIdNumber,
    this.employeeId,
    this.phone,
    this.designation,
    this.department,
    this.isIrisEnrolled = false,
    this.isApproved = false,
    this.approvalStatus = FacultyApprovalStatus.pending,
    this.rejectionReason,
    this.accountStatus = 'active',
    this.avatarUrl,
    this.reviewedAt,
    this.submittedAt,
    this.createdAt,
  });

  /// Parse from backend profiles table record
  factory User.fromMap(Map<String, dynamic> map) {
    final roleString = (map['role'] as String?)?.toLowerCase();
    final parsedRole = UserRole.values.firstWhere(
      (r) => r.name.toLowerCase() == roleString,
      orElse: () => UserRole.teacher,
    );

    final approvalStr = (map['approval_status'] as String?)?.toLowerCase();
    final isApprovedBool = map['is_approved'] == true;
    FacultyApprovalStatus approvalStatus;
    if (approvalStr == 'approved' || isApprovedBool) {
      approvalStatus = FacultyApprovalStatus.approved;
    } else if (approvalStr == 'rejected') {
      approvalStatus = FacultyApprovalStatus.rejected;
    } else {
      approvalStatus = FacultyApprovalStatus.pending;
    }

    return User(
      id: map['id'] as String,
      fullName: (map['full_name'] as String?) ?? 'Faculty Member',
      email: (map['email'] as String?) ?? '',
      role: parsedRole,
      studentIdNumber: map['student_id_number'] as String?,
      employeeId: (map['employee_id'] as String?) ?? (map['student_id_number'] as String?),
      phone: map['phone'] as String?,
      designation: (map['designation'] as String?) ?? 'Assistant Professor',
      department: (map['department'] as String?) ?? 'Computer Science & Engineering',
      isIrisEnrolled: (map['is_iris_enrolled'] as bool?) ?? false,
      isApproved: approvalStatus == FacultyApprovalStatus.approved,
      approvalStatus: approvalStatus,
      rejectionReason: map['rejection_reason'] as String?,
      accountStatus: (map['account_status'] as String?) ?? 'active',
      avatarUrl: map['avatar_url'] as String?,
      reviewedAt: DateTime.tryParse(map['reviewed_at'] as String? ?? ''),
      submittedAt: DateTime.tryParse(map['submitted_at'] as String? ?? ''),
      createdAt: DateTime.tryParse(map['created_at'] as String? ?? ''),
    );
  }

  /// Serialize profile data for backend database operations
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'email': email,
      'full_name': fullName,
      'role': role.name,
      'student_id_number': studentIdNumber ?? employeeId,
      'employee_id': employeeId ?? studentIdNumber,
      'phone': phone,
      'designation': designation,
      'department': department,
      'is_iris_enrolled': isIrisEnrolled,
      'is_approved': isApproved,
      'approval_status': approvalStatus.name,
      if (rejectionReason != null) 'rejection_reason': rejectionReason,
      'account_status': accountStatus,
      if (avatarUrl != null) 'avatar_url': avatarUrl,
      if (reviewedAt != null) 'reviewed_at': reviewedAt!.toIso8601String(),
      if (submittedAt != null) 'submitted_at': submittedAt!.toIso8601String(),
      if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
    };
  }

  User copyWith({
    String? id,
    String? fullName,
    String? email,
    UserRole? role,
    String? studentIdNumber,
    String? employeeId,
    String? phone,
    String? designation,
    String? department,
    bool? isIrisEnrolled,
    bool? isApproved,
    FacultyApprovalStatus? approvalStatus,
    String? rejectionReason,
    bool clearRejectionReason = false,
    String? accountStatus,
    String? avatarUrl,
    DateTime? reviewedAt,
    DateTime? submittedAt,
    DateTime? createdAt,
  }) {
    final effectiveApproved = isApproved ?? (approvalStatus == FacultyApprovalStatus.approved ? true : this.isApproved);
    final effectiveStatus = approvalStatus ?? (isApproved != null ? (isApproved ? FacultyApprovalStatus.approved : FacultyApprovalStatus.rejected) : this.approvalStatus);

    return User(
      id: id ?? this.id,
      fullName: fullName ?? this.fullName,
      email: email ?? this.email,
      role: role ?? this.role,
      studentIdNumber: studentIdNumber ?? this.studentIdNumber,
      employeeId: employeeId ?? this.employeeId,
      phone: phone ?? this.phone,
      designation: designation ?? this.designation,
      department: department ?? this.department,
      isIrisEnrolled: isIrisEnrolled ?? this.isIrisEnrolled,
      isApproved: effectiveApproved,
      approvalStatus: effectiveStatus,
      rejectionReason: clearRejectionReason ? null : (rejectionReason ?? this.rejectionReason),
      accountStatus: accountStatus ?? this.accountStatus,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      reviewedAt: reviewedAt ?? this.reviewedAt,
      submittedAt: submittedAt ?? this.submittedAt,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}

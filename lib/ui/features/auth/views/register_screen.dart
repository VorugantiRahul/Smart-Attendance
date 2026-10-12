import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/validators.dart';
import '../../../../data/models/user_model.dart';
import '../view_models/auth_view_model.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _idController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _departmentController = TextEditingController(text: 'Computer Science & Engineering');
  String _selectedDesignation = 'Assistant Professor';

  final List<String> _designationOptions = [
    'Assistant Professor',
    'Associate Professor',
    'Professor',
    'Head of Department (HOD)',
    'Dean / Academic Director',
    'Senior Lecturer',
    'Lab Technical Officer',
  ];

  UserRole _requestedRole = UserRole.teacher;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _idController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _departmentController.dispose();
    super.dispose();
  }

  Future<void> _handleRegister() async {
    if (!_formKey.currentState!.validate()) return;

    final success = await ref.read(authStateProvider.notifier).register(
          fullName: _nameController.text.trim(),
          email: _emailController.text.trim(),
          password: _passwordController.text,
          requestedRole: _requestedRole,
          employeeId: _idController.text.trim(),
          studentIdNumber: _idController.text.trim(),
          phone: _phoneController.text.trim(),
          designation: _selectedDesignation,
          department: _departmentController.text.trim(),
        );

    if (success && mounted) {
      final user = ref.read(authStateProvider).user;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Account provisioned. Assigned institutional role: ${user?.role.name.toUpperCase()}',
          ),
          backgroundColor: AppTheme.statusSuccess,
        ),
      );

      if (user != null) {
        switch (user.role) {
          case UserRole.teacher:
            // Requirement 4: Direct faculty immediately to Biometric Iris Enrollment
            context.go('/face-enrollment');
            break;
          case UserRole.student:
            context.go('/face-enrollment');
            break;
          case UserRole.admin:
            context.go('/admin-dashboard');
            break;
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authStateProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Faculty Onboarding'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Faculty Smart Attendance',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.primaryBlue,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Register your college faculty identity. After registration, you will enroll your biometric iris template to enable queue-free smartphone attendance.',
                  style: TextStyle(fontSize: 14, color: AppTheme.textMuted),
                ),
                const SizedBox(height: 20),

                // Requested Account Type
                const Text(
                  'INSTITUTIONAL ACCOUNT ROLE',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textMuted,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 10),
                SegmentedButton<UserRole>(
                  segments: const [
                    ButtonSegment(
                      value: UserRole.teacher,
                      icon: Icon(Icons.school_outlined),
                      label: Text('Faculty Member'),
                    ),
                    ButtonSegment(
                      value: UserRole.admin,
                      icon: Icon(Icons.admin_panel_settings_outlined),
                      label: Text('Administrator'),
                    ),
                  ],
                  selected: {_requestedRole},
                  onSelectionChanged: (newSelection) {
                    setState(() {
                      _requestedRole = newSelection.first;
                    });
                  },
                ),
                const SizedBox(height: 20),

                // Full Name
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Full Name (with title)',
                    hintText: 'e.g. Dr. A. Sharma / Prof. R. Rao',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                  validator: (v) => Validators.validateRequired(v, 'Full Name'),
                ),
                const SizedBox(height: 16),

                // Official Email
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Official College Email',
                    hintText: 'faculty@vnrvjiet.in',
                    prefixIcon: Icon(Icons.email_outlined),
                  ),
                  validator: Validators.validateEmail,
                ),
                const SizedBox(height: 16),

                // Employee / Faculty ID
                TextFormField(
                  controller: _idController,
                  decoration: InputDecoration(
                    labelText: _requestedRole == UserRole.teacher
                        ? 'Faculty / Employee ID'
                        : 'Admin Staff ID',
                    hintText: 'FAC-CSE-102',
                    prefixIcon: const Icon(Icons.badge_outlined),
                  ),
                  validator: (v) => Validators.validateRequired(
                    v,
                    _requestedRole == UserRole.teacher ? 'Faculty ID' : 'Staff ID',
                  ),
                ),
                const SizedBox(height: 16),

                // Official Phone Number (Requirement 1)
                TextFormField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Phone Number',
                    hintText: '+91 9876543210',
                    prefixIcon: Icon(Icons.phone_outlined),
                  ),
                  validator: (v) => Validators.validateRequired(v, 'Phone Number'),
                ),
                const SizedBox(height: 16),

                // Designation Dropdown for Faculty
                if (_requestedRole == UserRole.teacher) ...[
                  DropdownButtonFormField<String>(
                    value: _selectedDesignation,
                    decoration: const InputDecoration(
                      labelText: 'Academic Designation',
                      prefixIcon: Icon(Icons.military_tech_outlined),
                    ),
                    items: _designationOptions
                        .map(
                          (desig) => DropdownMenuItem(
                            value: desig,
                            child: Text(desig),
                          ),
                        )
                        .toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setState(() => _selectedDesignation = val);
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                ],

                // Department
                TextFormField(
                  controller: _departmentController,
                  decoration: const InputDecoration(
                    labelText: 'Department / Faculty Division',
                    prefixIcon: Icon(Icons.domain_outlined),
                  ),
                  validator: (v) => Validators.validateRequired(v, 'Department'),
                ),
                const SizedBox(height: 16),

                // Password
                TextFormField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    prefixIcon: const Icon(Icons.lock_outline_rounded),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                      onPressed: () {
                        setState(() {
                          _obscurePassword = !_obscurePassword;
                        });
                      },
                    ),
                  ),
                  validator: Validators.validatePassword,
                ),
                const SizedBox(height: 24),

                if (authState.errorMessage != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.statusError.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      authState.errorMessage!,
                      style: const TextStyle(color: AppTheme.statusError, fontSize: 13),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                ElevatedButton(
                  onPressed: authState.isLoading ? null : _handleRegister,
                  child: authState.isLoading
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Text('Register & Proceed to Iris Enrollment'),
                ),
                const SizedBox(height: 16),

                Center(
                  child: GestureDetector(
                    onTap: () => context.pop(),
                    child: const Text(
                      'Already registered? Return to Login',
                      style: TextStyle(
                        color: AppTheme.primaryAccent,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

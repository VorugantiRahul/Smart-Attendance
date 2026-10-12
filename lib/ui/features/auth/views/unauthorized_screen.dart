import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../data/models/user_model.dart';

class UnauthorizedScreen extends StatelessWidget {
  final UserRole? requiredRole;
  final UserRole? currentRole;

  const UnauthorizedScreen({
    super.key,
    this.requiredRole,
    this.currentRole,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Access Denied'),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppTheme.statusError.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.gpp_bad_rounded,
                    color: AppTheme.statusError,
                    size: 64,
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Institutional Access Restricted',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF1E293B),
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  'Your authenticated identity has the role [${currentRole?.name.toUpperCase() ?? "UNKNOWN"}], but this area strictly requires [${requiredRole?.name.toUpperCase() ?? "AUTHORIZED"}] clearance.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppTheme.textMuted,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 32),
                ElevatedButton.icon(
                  onPressed: () {
                    if (currentRole == null) {
                      context.go('/login');
                    } else {
                      switch (currentRole!) {
                        case UserRole.student:
                          context.go('/student-dashboard');
                          break;
                        case UserRole.teacher:
                          context.go('/teacher-dashboard');
                          break;
                        case UserRole.admin:
                          context.go('/admin-dashboard');
                          break;
                      }
                    }
                  },
                  icon: const Icon(Icons.arrow_back_rounded, size: 18),
                  label: const Text('Return to Permitted Workspace'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

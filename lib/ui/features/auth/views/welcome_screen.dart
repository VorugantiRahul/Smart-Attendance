import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_theme.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 20),
              // Hero University & Iris Banner
              Center(
                child: Container(
                  width: size.width * 0.45,
                  height: size.width * 0.45,
                  decoration: BoxDecoration(
                    color: AppTheme.primaryBlue.withOpacity(0.04),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppTheme.primaryAccent.withOpacity(0.2),
                      width: 2,
                    ),
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Icon(
                        Icons.location_on_rounded,
                        size: 90,
                        color: AppTheme.primaryAccent.withOpacity(0.18),
                      ),
                      Container(
                        padding: const EdgeInsets.all(22),
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppTheme.primaryBlue,
                        ),
                        child: const Icon(
                          Icons.visibility_rounded,
                          size: 44,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 36),
              const Text(
                'Faculty Smart Biometric\nAttendance',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.primaryBlue,
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'Skip the biometric queue terminal. Securely mark your daily faculty duty attendance from your smartphone with campus geofencing and Daugman iris authentication.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14.5,
                  color: AppTheme.textMuted,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 32),
              // Highlights cards
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _FeaturePill(
                      icon: Icons.security_rounded,
                      label: 'Zero Proxy',
                    ),
                    Container(width: 1, height: 28, color: const Color(0xFFE2E8F0)),
                    _FeaturePill(
                      icon: Icons.radar_rounded,
                      label: 'Campus Perimeter',
                    ),
                    Container(width: 1, height: 28, color: const Color(0xFFE2E8F0)),
                    _FeaturePill(
                      icon: Icons.bolt_rounded,
                      label: 'Instant Sync',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              // Action Buttons
              ElevatedButton(
                onPressed: () => context.push('/login'),
                child: const Text('Sign In to Account'),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => context.push('/register'),
                child: const Text('Create New Account'),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}

class _FeaturePill extends StatelessWidget {
  final IconData icon;
  final String label;

  const _FeaturePill({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 20, color: AppTheme.primaryAccent),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: Color(0xFF334155),
          ),
        ),
      ],
    );
  }
}

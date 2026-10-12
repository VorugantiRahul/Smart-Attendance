import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/config/app_config.dart';
import 'core/routing/app_router.dart';
import 'core/theme/app_theme.dart';
import 'data/repositories/attendance_repository.dart';
import 'data/repositories/auth_repository.dart';
import 'data/repositories/dev_mock_attendance_repository.dart';
import 'data/repositories/dev_mock_auth_repository.dart';
import 'data/repositories/supabase_attendance_repository.dart';
import 'data/repositories/supabase_auth_repository.dart';
import 'ui/features/auth/view_models/auth_view_model.dart';

final attendanceRepositoryProvider = Provider<AttendanceRepository>((ref) {
  final authRepo = ref.watch(authRepositoryProvider);
  return DevMockAttendanceRepository(authRepo);
});

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load environment-driven configuration
  final config = AppConfig.fromEnvironment();

  AuthRepository authRepository;
  AttendanceRepository attendanceRepository;

  if (config.hasLiveSupabaseConfig) {
    // Initialize live Supabase Client
    await Supabase.initialize(
      url: config.supabaseUrl,
      anonKey: config.supabaseAnonKey,
    );
    authRepository = SupabaseAuthRepository(Supabase.instance.client);
    attendanceRepository = SupabaseAttendanceRepository(Supabase.instance.client);
  } else {
    // Fallback to Development-Safe Mode
    authRepository = DevMockAuthRepository();
    attendanceRepository = DevMockAttendanceRepository(authRepository);
  }

  runApp(
    ProviderScope(
      overrides: [
        appConfigProvider.overrideWithValue(config),
        authRepositoryProvider.overrideWithValue(authRepository),
        attendanceRepositoryProvider.overrideWithValue(attendanceRepository),
      ],
      child: IrisAttendanceApp(config: config),
    ),
  );
}

class IrisAttendanceApp extends ConsumerWidget {
  final AppConfig config;

  const IrisAttendanceApp({super.key, required this.config});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'Iris Geofenced Attendance',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system,
      routerConfig: router,
    );
  }
}

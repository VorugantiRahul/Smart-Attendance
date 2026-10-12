// Campus Geofence and Iris Attendance System Environment Configuration

enum AppEnvironment { dev, staging, prod }

class AppConfig {
  final AppEnvironment environment;
  final String apiBaseUrl;
  final String supabaseUrl;
  final String supabaseAnonKey;
  final String irisEngineVersion;
  final int requestTimeoutMs;
  final double campusLatitude;
  final double campusLongitude;
  final double allowedGeofenceRadiusMeters;

  const AppConfig({
    required this.environment,
    required this.apiBaseUrl,
    required this.supabaseUrl,
    required this.supabaseAnonKey,
    required this.irisEngineVersion,
    this.requestTimeoutMs = 15000,
    required this.campusLatitude,
    required this.campusLongitude,
    this.allowedGeofenceRadiusMeters = 150.0,
  });

  /// Check whether live Supabase backend credentials are configured
  bool get hasLiveSupabaseConfig =>
      supabaseUrl.isNotEmpty &&
      supabaseAnonKey.isNotEmpty &&
      !supabaseUrl.contains('placeholder') &&
      !supabaseAnonKey.contains('placeholder');

  /// Read active configuration from compile-time environment variables or defaults
  factory AppConfig.fromEnvironment() {
    const envString = String.fromEnvironment('ENV', defaultValue: 'dev');
    final env = AppEnvironment.values.firstWhere(
      (e) => e.name.toLowerCase() == envString.toLowerCase(),
      orElse: () => AppEnvironment.dev,
    );

    return AppConfig(
      environment: env,
      apiBaseUrl: const String.fromEnvironment(
        'API_BASE_URL',
        defaultValue: 'https://api-dev.irisattendance.edu/v1',
      ),
      supabaseUrl: const String.fromEnvironment(
        'SUPABASE_URL',
        defaultValue: 'https://fwehznvcvdguyxhsdolq.supabase.co',
      ),
      supabaseAnonKey: const String.fromEnvironment(
        'SUPABASE_ANON_KEY',
        defaultValue:
            'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImZ3ZWh6bnZjdmRndXl4aHNkb2xxIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTE2OTA1MzksImV4cCI6MjEwNzI2NjUzOX0.Zn-Vtw3DBiChd2ae3vG9h4apHfc8lV7bZxfP4AunvaA',
      ),
      irisEngineVersion: const String.fromEnvironment(
        'IRIS_ENGINE_VERSION',
        defaultValue: 'v2.4-edge',
      ),
      campusLatitude: double.tryParse(
            const String.fromEnvironment('CAMPUS_LAT', defaultValue: '17.538500'),
          ) ??
          17.538500,
      campusLongitude: double.tryParse(
            const String.fromEnvironment('CAMPUS_LNG', defaultValue: '78.385200'),
          ) ??
          78.385200,
      allowedGeofenceRadiusMeters: double.tryParse(
            const String.fromEnvironment(
              'GEOFENCE_RADIUS_METERS',
              defaultValue: '350.0',
            ),
          ) ??
          350.0,
    );
  }
}

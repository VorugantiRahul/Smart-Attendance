enum LocationPermissionState {
  initial,
  checking,
  granted,
  denied,
  deniedForever,
  serviceDisabled,
}

enum LocationAcquisitionStatus {
  idle,
  requestingPermission,
  acquiringGps,
  acquired,
  error,
}

class UserLocationData {
  final double latitude;
  final double longitude;
  final double accuracyMeters;
  final double? altitude;
  final double? speed;
  final DateTime timestamp;
  final bool isMockLocation;

  const UserLocationData({
    required this.latitude,
    required this.longitude,
    required this.accuracyMeters,
    this.altitude,
    this.speed,
    required this.timestamp,
    this.isMockLocation = false,
  });

  /// Check whether GPS fix is fresh (< 60 seconds old)
  bool get isFresh =>
      DateTime.now().difference(timestamp).inSeconds < 60;

  /// Check whether accuracy meets university attendance standard (<= 35m)
  bool get hasAcceptableAccuracy => accuracyMeters <= 35.0;

  Map<String, dynamic> toMetadataMap() {
    return {
      'latitude': latitude,
      'longitude': longitude,
      'accuracy_meters': accuracyMeters,
      'altitude': altitude,
      'timestamp': timestamp.toIso8601String(),
      'is_mock_location': isMockLocation,
      'is_fresh': isFresh,
    };
  }
}

abstract class LocationService {
  Future<LocationPermissionState> checkPermission();
  Future<LocationPermissionState> requestPermission();
  Future<bool> isLocationServiceEnabled();
  Future<UserLocationData> getCurrentPosition();
}

import 'dart:async';
import 'location_service.dart';

/// Simulated GPS Location Service
/// Provides deterministic location testing, simulated mock-location detection,
/// stale coordinate simulation, and permission state handling.
class DevLocationService implements LocationService {
  LocationPermissionState _permissionState = LocationPermissionState.granted;
  bool _serviceEnabled = true;

  // Default coordinate: Athithi Boys Hostel (Near Tryit Shop, Gandimaisamma)
  double currentLatitude = 17.578900;
  double currentLongitude = 78.426900;
  double accuracyMeters = 8.5; // High accuracy 8.5 meters
  bool isMockLocation = false;
  Duration simulatedLatency = const Duration(milliseconds: 600);
  DateTime? fixedTimestamp;

  void setSimulatedPosition({
    required double lat,
    required double lng,
    double accuracy = 8.5,
    bool isMock = false,
    DateTime? timestamp,
  }) {
    currentLatitude = lat;
    currentLongitude = lng;
    accuracyMeters = accuracy;
    isMockLocation = isMock;
    fixedTimestamp = timestamp;
  }

  void setServiceEnabled(bool enabled) {
    _serviceEnabled = enabled;
  }

  void setPermissionState(LocationPermissionState state) {
    _permissionState = state;
  }

  @override
  Future<bool> isLocationServiceEnabled() async {
    await Future.delayed(const Duration(milliseconds: 100));
    return _serviceEnabled;
  }

  @override
  Future<LocationPermissionState> checkPermission() async {
    await Future.delayed(const Duration(milliseconds: 100));
    if (!_serviceEnabled) return LocationPermissionState.serviceDisabled;
    return _permissionState;
  }

  @override
  Future<LocationPermissionState> requestPermission() async {
    await Future.delayed(const Duration(milliseconds: 300));
    if (!_serviceEnabled) {
      _permissionState = LocationPermissionState.serviceDisabled;
      return _permissionState;
    }
    if (_permissionState != LocationPermissionState.denied &&
        _permissionState != LocationPermissionState.deniedForever) {
      _permissionState = LocationPermissionState.granted;
    }
    return _permissionState;
  }

  @override
  Future<UserLocationData> getCurrentPosition() async {
    await Future.delayed(simulatedLatency);

    if (!_serviceEnabled) {
      throw Exception('Location Services (GPS) are disabled on your device. Please enable GPS in device settings.');
    }

    if (_permissionState == LocationPermissionState.denied ||
        _permissionState == LocationPermissionState.deniedForever) {
      throw Exception('Location permission denied. University campus verification requires location access.');
    }

    return UserLocationData(
      latitude: currentLatitude,
      longitude: currentLongitude,
      accuracyMeters: accuracyMeters,
      altitude: 920.0,
      speed: 0.0,
      timestamp: fixedTimestamp ?? DateTime.now(),
      isMockLocation: isMockLocation,
    );
  }
}

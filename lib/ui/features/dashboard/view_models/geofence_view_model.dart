import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/services/dev_location_service.dart';
import '../../../../core/services/location_service.dart';
import '../../../../core/utils/geo_utils.dart';
import '../../../../data/models/campus_location_model.dart';
import '../../../../data/repositories/attendance_repository.dart';
import '../../../../main.dart';

final locationServiceProvider = Provider<LocationService>((ref) {
  return DevLocationService();
});

@immutable
class GeofenceState {
  final LocationAcquisitionStatus status;
  final UserLocationData? userLocation;
  final CampusLocation? targetLocation;
  final GeofenceEvaluationResult? evaluationResult;
  final String? errorMessage;
  final bool isSubmitting;
  final bool hasSubmitted;
  final String? submissionMessage;

  const GeofenceState({
    this.status = LocationAcquisitionStatus.idle,
    this.userLocation,
    this.targetLocation,
    this.evaluationResult,
    this.errorMessage,
    this.isSubmitting = false,
    this.hasSubmitted = false,
    this.submissionMessage,
  });

  GeofenceState copyWith({
    LocationAcquisitionStatus? status,
    UserLocationData? userLocation,
    CampusLocation? targetLocation,
    GeofenceEvaluationResult? evaluationResult,
    String? errorMessage,
    bool? isSubmitting,
    bool? hasSubmitted,
    String? submissionMessage,
    bool clearError = false,
  }) {
    return GeofenceState(
      status: status ?? this.status,
      userLocation: userLocation ?? this.userLocation,
      targetLocation: targetLocation ?? this.targetLocation,
      evaluationResult: evaluationResult ?? this.evaluationResult,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      isSubmitting: isSubmitting ?? this.isSubmitting,
      hasSubmitted: hasSubmitted ?? this.hasSubmitted,
      submissionMessage: submissionMessage ?? this.submissionMessage,
    );
  }
}

class GeofenceNotifier extends StateNotifier<GeofenceState> {
  final LocationService _locationService;
  final AttendanceRepository _attendanceRepo;

  GeofenceNotifier(this._locationService, this._attendanceRepo)
      : super(const GeofenceState());

  /// Initialize and load campus perimeter
  Future<void> loadTargetCampus() async {
    try {
      final locations = await _attendanceRepo.getCampusLocations();
      if (locations.isNotEmpty) {
        final target = locations.firstWhere(
          (loc) => loc.code == 'ATITHI-HOSTEL-GM',
          orElse: () => locations.first,
        );
        state = state.copyWith(targetLocation: target);
      }
    } catch (_) {}
  }

  /// Request GPS fix and evaluate geofence against campus boundaries
  Future<void> acquireLocation() async {
    state = state.copyWith(
      status: LocationAcquisitionStatus.requestingPermission,
      clearError: true,
    );

    try {
      final isEnabled = await _locationService.isLocationServiceEnabled();
      if (!isEnabled) {
        state = state.copyWith(
          status: LocationAcquisitionStatus.error,
          errorMessage: 'GPS is turned off. Please enable device location services.',
        );
        return;
      }

      var perm = await _locationService.checkPermission();
      if (perm != LocationPermissionState.granted) {
        perm = await _locationService.requestPermission();
      }

      if (perm == LocationPermissionState.serviceDisabled) {
        state = state.copyWith(
          status: LocationAcquisitionStatus.error,
          errorMessage: 'Device location service is disabled.',
        );
        return;
      } else if (perm == LocationPermissionState.denied ||
          perm == LocationPermissionState.deniedForever) {
        state = state.copyWith(
          status: LocationAcquisitionStatus.error,
          errorMessage: 'Location permission was denied. Camera & GPS permission are required to verify attendance.',
        );
        return;
      }

      state = state.copyWith(status: LocationAcquisitionStatus.acquiringGps);

      final userLoc = await _locationService.getCurrentPosition();

      // Load all authorized locations (VNR Campus & Gandimaisamma Hostel)
      final allLocs = await _attendanceRepo.getCampusLocations();
      CampusLocation? campus = state.targetLocation;
      if (campus == null && allLocs.isNotEmpty) {
        campus = allLocs.first;
      }

      GeofenceEvaluationResult? eval;
      if (allLocs.isNotEmpty) {
        GeofenceEvaluationResult? bestInsideEval;
        CampusLocation? bestInsideCampus;
        GeofenceEvaluationResult? closestEval;
        CampusLocation? closestCampus;
        double minDistance = double.infinity;

        for (final loc in allLocs.where((l) => l.isActive)) {
          final res = GeoUtils.evaluateGeofence(
            userLat: userLoc.latitude,
            userLng: userLoc.longitude,
            campusCenterLat: loc.centerLatitude,
            campusCenterLng: loc.centerLongitude,
            bufferRadiusMeters: loc.bufferRadiusMeters,
            polygonBoundary: loc.boundaryPolygon,
          );

          if (res.isInside) {
            bestInsideEval = res;
            bestInsideCampus = loc;
            break;
          }

          if (res.distanceFromCenterMeters < minDistance) {
            minDistance = res.distanceFromCenterMeters;
            closestEval = res;
            closestCampus = loc;
          }
        }

        eval = bestInsideEval ?? closestEval;
        campus = bestInsideCampus ?? closestCampus ?? allLocs.first;
      }

      // Quality warning checks
      String? qualityWarning;
      if (userLoc.isMockLocation) {
        qualityWarning = 'Warning: Device reported a simulated or mock location provider.';
      } else if (!userLoc.hasAcceptableAccuracy) {
        qualityWarning = 'Weak GPS signal (accuracy ±${userLoc.accuracyMeters.toStringAsFixed(0)}m). Position may fluctuate.';
      } else if (!userLoc.isFresh) {
        qualityWarning = 'Stale GPS fix detected. Refreshing position...';
      }

      state = state.copyWith(
        status: LocationAcquisitionStatus.acquired,
        userLocation: userLoc,
        targetLocation: campus,
        evaluationResult: eval,
        errorMessage: qualityWarning,
      );
    } catch (e) {
      state = state.copyWith(
        status: LocationAcquisitionStatus.error,
        errorMessage: e.toString().replaceFirst('Exception: ', ''),
      );
    }
  }

  /// Submit check-in to server for validation
  Future<bool> submitAttendance({required String sessionId}) async {
    final loc = state.userLocation;
    if (loc == null) {
      state = state.copyWith(errorMessage: 'Please acquire your GPS location first.');
      return false;
    }

    state = state.copyWith(isSubmitting: true, clearError: true);

    try {
      final record = await _attendanceRepo.submitCheckIn(
        sessionId: sessionId,
        latitude: loc.latitude,
        longitude: loc.longitude,
        deviceMetadata: loc.toMetadataMap(),
      );

      final inside = record.isWithinGeofence;
      final msg = inside
          ? 'Check-in recorded within campus perimeter! (Status: Pending iris scan).'
          : 'Attendance flagged: Coordinates are outside the approved campus geofence.';

      state = state.copyWith(
        isSubmitting: false,
        hasSubmitted: true,
        submissionMessage: msg,
      );
      return true;
    } catch (e) {
      state = state.copyWith(
        isSubmitting: false,
        errorMessage: e.toString().replaceFirst('Exception: ', ''),
      );
      return false;
    }
  }

  /// Toggle simulated location for testing edge cases
  void setSimulatedLocation(double lat, double lng, {double accuracy = 8.5, bool isMock = false}) {
    if (_locationService is DevLocationService) {
      (_locationService as DevLocationService).setSimulatedPosition(
        lat: lat,
        lng: lng,
        accuracy: accuracy,
        isMock: isMock,
      );
      acquireLocation();
    }
  }
}

final geofenceStateProvider =
    StateNotifierProvider<GeofenceNotifier, GeofenceState>((ref) {
  final locService = ref.watch(locationServiceProvider);
  final repo = ref.watch(attendanceRepositoryProvider);
  final notifier = GeofenceNotifier(locService, repo);
  notifier.loadTargetCampus();
  return notifier;
});

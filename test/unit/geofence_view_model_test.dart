import 'package:flutter_test/flutter_test.dart';
import 'package:iris_attendance/core/services/dev_location_service.dart';
import 'package:iris_attendance/core/services/location_service.dart';
import 'package:iris_attendance/data/repositories/dev_mock_attendance_repository.dart';
import 'package:iris_attendance/data/repositories/dev_mock_auth_repository.dart';
import 'package:iris_attendance/ui/features/dashboard/view_models/geofence_view_model.dart';

void main() {
  group('GeofenceNotifier Mobile State & GPS Tests', () {
    late DevLocationService mockLocationService;
    late DevMockAuthRepository authRepo;
    late DevMockAttendanceRepository attendanceRepo;
    late GeofenceNotifier notifier;

    setUp(() async {
      mockLocationService = DevLocationService();
      authRepo = DevMockAuthRepository();
      attendanceRepo = DevMockAttendanceRepository(authRepo);
      notifier = GeofenceNotifier(mockLocationService, attendanceRepo);
      await notifier.loadTargetCampus();
    });

    test('Initial state is idle without user location', () {
      expect(notifier.state.status, equals(LocationAcquisitionStatus.idle));
      expect(notifier.state.userLocation, isNull);
    });

    test('Acquires location and evaluates student inside campus successfully', () async {
      // Mock student location at campus center
      mockLocationService.setSimulatedPosition(
        lat: 17.5385,
        lng: 78.3852,
        accuracy: 8.5,
      );

      await notifier.acquireLocation();

      expect(notifier.state.status, equals(LocationAcquisitionStatus.acquired));
      expect(notifier.state.userLocation, isNotNull);
      expect(notifier.state.evaluationResult?.isInside, isTrue);
    });

    test('Handles disabled GPS service with clear error message', () async {
      mockLocationService.setServiceEnabled(false);

      await notifier.acquireLocation();

      expect(notifier.state.status, equals(LocationAcquisitionStatus.error));
      expect(notifier.state.errorMessage, contains('GPS is turned off'));
    });

    test('Handles denied location permission with explanatory guidance', () async {
      mockLocationService.setPermissionState(LocationPermissionState.denied);

      await notifier.acquireLocation();

      expect(notifier.state.status, equals(LocationAcquisitionStatus.error));
      expect(notifier.state.errorMessage, contains('Location permission'));
    });

    test('Detects and warns on mock location provider', () async {
      mockLocationService.setSimulatedPosition(
        lat: 12.9717,
        lng: 77.5947,
        isMock: true,
      );

      await notifier.acquireLocation();

      expect(notifier.state.userLocation?.isMockLocation, isTrue);
      expect(notifier.state.errorMessage, contains('simulated or mock location'));
    });

    test('Warns on poor GPS accuracy (> 35m)', () async {
      mockLocationService.setSimulatedPosition(
        lat: 12.9717,
        lng: 77.5947,
        accuracy: 65.0, // weak satellite fix
      );

      await notifier.acquireLocation();

      expect(notifier.state.userLocation?.hasAcceptableAccuracy, isFalse);
      expect(notifier.state.errorMessage, contains('Weak GPS signal'));
    });

    test('Warns on stale coordinates (> 60s old)', () async {
      mockLocationService.setSimulatedPosition(
        lat: 12.9717,
        lng: 77.5947,
        timestamp: DateTime.now().subtract(const Duration(seconds: 120)),
      );

      await notifier.acquireLocation();

      expect(notifier.state.userLocation?.isFresh, isFalse);
      expect(notifier.state.errorMessage, contains('Stale GPS fix'));
    });
  });
}

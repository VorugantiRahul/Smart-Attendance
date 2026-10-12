import 'package:flutter_test/flutter_test.dart';
import 'package:iris_attendance/core/utils/geo_utils.dart';
import 'package:iris_attendance/core/utils/validators.dart';

void main() {
  group('GeoUtils Haversine Calculation Tests', () {
    // Reference coordinates: Campus Center (Bangalore Tech Campus)
    const campusLat = 12.9716;
    const campusLng = 77.5946;

    test('Distance between identical coordinates is 0 meters', () {
      final distance = GeoUtils.calculateDistanceInMeters(
        startLatitude: campusLat,
        startLongitude: campusLng,
        endLatitude: campusLat,
        endLongitude: campusLng,
      );

      expect(distance, closeTo(0.0, 0.01));
    });

    test('Identifies student inside circular geofence buffer (within 120m)', () {
      const studentLat = 12.9718;
      const studentLng = 77.5948;

      final isInside = GeoUtils.isWithinCircularGeofence(
        userLat: studentLat,
        userLng: studentLng,
        campusLat: campusLat,
        campusLng: campusLng,
        radiusMeters: 120.0,
      );

      expect(isInside, isTrue);
    });

    test('Rejects student outside circular geofence buffer (1.5 km away)', () {
      const outsideLat = 12.9850;
      const outsideLng = 77.6050;

      final isInside = GeoUtils.isWithinCircularGeofence(
        userLat: outsideLat,
        userLng: outsideLng,
        campusLat: campusLat,
        campusLng: campusLng,
        radiusMeters: 120.0,
      );

      expect(isInside, isFalse);
    });
  });

  group('GeoUtils Polygon Boundaries & Ray-Casting Tests', () {
    // A square campus boundary around (12.9716, 77.5946)
    // Corners:
    // SW: (12.9706, 77.5936)
    // SE: (12.9706, 77.5956)
    // NE: (12.9726, 77.5956)
    // NW: (12.9726, 77.5936)
    final campusPolygon = [
      const LatLng(12.9706, 77.5936),
      const LatLng(12.9706, 77.5956),
      const LatLng(12.9726, 77.5956),
      const LatLng(12.9726, 77.5936),
    ];

    test('Point strictly inside polygon is recognized as inside', () {
      final isInside = GeoUtils.isPointInPolygon(
        pointLat: 12.9716,
        pointLng: 77.5946,
        polygon: campusPolygon,
      );
      expect(isInside, isTrue);
    });

    test('Point strictly outside polygon is recognized as outside', () {
      final isInside = GeoUtils.isPointInPolygon(
        pointLat: 12.9850,
        pointLng: 77.6050,
        polygon: campusPolygon,
      );
      expect(isInside, isFalse);
    });

    test('Point directly on north boundary edge is accepted (ST_Covers policy)', () {
      // Exactly on North Edge: lat 12.9726, between 77.5936 and 77.5956
      final isInside = GeoUtils.isPointInPolygon(
        pointLat: 12.9726,
        pointLng: 77.5946,
        polygon: campusPolygon,
      );
      expect(isInside, isTrue);
    });

    test('Point near boundary edge within 1m tolerance is accepted', () {
      // Very close to south edge (12.970601, 77.5946)
      final isInside = GeoUtils.isPointInPolygon(
        pointLat: 12.970601,
        pointLng: 77.5946,
        polygon: campusPolygon,
        edgeToleranceMeters: 2.0,
      );
      expect(isInside, isTrue);
    });

    test('Point on polygon corner vertex is accepted', () {
      // South-West corner vertex
      final isInside = GeoUtils.isPointInPolygon(
        pointLat: 12.9706,
        pointLng: 77.5936,
        polygon: campusPolygon,
      );
      expect(isInside, isTrue);
    });
  });

  group('GeoUtils Numerical Edge Cases & Invalid Coordinates', () {
    test('Rejects NaN and Infinite latitude or longitude values', () {
      expect(GeoUtils.isValidCoordinate(double.nan, 77.5946), isFalse);
      expect(GeoUtils.isValidCoordinate(12.9716, double.infinity), isFalse);
      expect(GeoUtils.isValidCoordinate(null, 77.5946), isFalse);
    });

    test('Rejects out-of-range coordinates (> 90 lat or > 180 lng)', () {
      expect(GeoUtils.isValidCoordinate(91.0, 77.0), isFalse);
      expect(GeoUtils.isValidCoordinate(-91.0, 77.0), isFalse);
      expect(GeoUtils.isValidCoordinate(12.0, 181.0), isFalse);
      expect(GeoUtils.isValidCoordinate(12.0, -181.0), isFalse);
    });

    test('Evaluates empty polygon safely with circular buffer fallback', () {
      final result = GeoUtils.evaluateGeofence(
        userLat: 12.9717,
        userLng: 77.5947,
        campusCenterLat: 12.9716,
        campusCenterLng: 77.5946,
        bufferRadiusMeters: 120.0,
        polygonBoundary: [],
      );

      expect(result.isInside, isTrue);
      expect(result.isWithinCircularBuffer, isTrue);
    });
  });

  group('Validators Unit Tests', () {
    test('validateEmail accepts valid institutional emails', () {
      expect(Validators.validateEmail('student@university.edu'), isNull);
      expect(Validators.validateEmail('prof.smith@college.org'), isNull);
    });

    test('validateEmail rejects empty or invalid email formats', () {
      expect(Validators.validateEmail(''), isNotNull);
      expect(Validators.validateEmail('not-an-email'), isNotNull);
      expect(Validators.validateEmail('student@'), isNotNull);
    });

    test('validatePassword enforces minimum 8 chars and alphanumeric characters', () {
      expect(Validators.validatePassword('weak'), isNotNull);
      expect(Validators.validatePassword('allcharacterslength'), isNotNull);
      expect(Validators.validatePassword('12345678'), isNotNull);
      expect(Validators.validatePassword('ValidPass123'), isNull);
    });

    test('validateStudentId verifies non-empty roll number', () {
      expect(Validators.validateStudentId(''), isNotNull);
      expect(Validators.validateStudentId('AB'), isNotNull);
      expect(Validators.validateStudentId('CS-2026-904'), isNull);
    });
  });
}

import 'dart:math' as math;

/// GPS Coordinate container
class LatLng {
  final double latitude;
  final double longitude;

  const LatLng(this.latitude, this.longitude);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LatLng &&
          runtimeType == other.runtimeType &&
          (latitude - other.latitude).abs() < 1e-9 &&
          (longitude - other.longitude).abs() < 1e-9;

  @override
  int get hashCode => latitude.hashCode ^ longitude.hashCode;

  @override
  String toString() => 'LatLng($latitude, $longitude)';
}

/// Evaluation result for geofence validation
class GeofenceEvaluationResult {
  final bool isInside;
  final double distanceFromCenterMeters;
  final bool isWithinCircularBuffer;
  final bool isInsidePolygon;
  final String statusReason;

  const GeofenceEvaluationResult({
    required this.isInside,
    required this.distanceFromCenterMeters,
    required this.isWithinCircularBuffer,
    required this.isInsidePolygon,
    required this.statusReason,
  });
}

/// Utility class for geofencing and geographical calculations (Haversine formula & Polygon containment)
class GeoUtils {
  GeoUtils._();

  /// Mean Earth radius in meters (WGS84 spherical approximation)
  static const double earthRadiusMeters = 6371000.0;

  /// Check validity of geographic coordinates
  static bool isValidCoordinate(double? lat, double? lng) {
    if (lat == null || lng == null) return false;
    if (lat.isNaN || lng.isNaN || lat.isInfinite || lng.isInfinite) return false;
    return lat >= -90.0 && lat <= 90.0 && lng >= -180.0 && lng <= 180.0;
  }

  /// Calculate great-circle distance between two GPS coordinates using Haversine formula
  static double calculateDistanceInMeters({
    required double startLatitude,
    required double startLongitude,
    required double endLatitude,
    required double endLongitude,
  }) {
    if (!isValidCoordinate(startLatitude, startLongitude) ||
        !isValidCoordinate(endLatitude, endLongitude)) {
      throw ArgumentError('Invalid latitude or longitude supplied to distance calculation.');
    }

    final dLat = _toRadians(endLatitude - startLatitude);
    final dLon = _toRadians(endLongitude - startLongitude);

    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRadians(startLatitude)) *
            math.cos(_toRadians(endLatitude)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);

    final clampedA = a.clamp(0.0, 1.0);
    final c = 2 * math.atan2(math.sqrt(clampedA), math.sqrt(1 - clampedA));
    return earthRadiusMeters * c;
  }

  /// Check if a user's location is inside the defined circular campus perimeter
  static bool isWithinCircularGeofence({
    required double userLat,
    required double userLng,
    required double campusLat,
    required double campusLng,
    required double radiusMeters,
  }) {
    if (!isValidCoordinate(userLat, userLng) ||
        !isValidCoordinate(campusLat, campusLng) ||
        radiusMeters < 0) {
      return false;
    }

    final distance = calculateDistanceInMeters(
      startLatitude: userLat,
      startLongitude: userLng,
      endLatitude: campusLat,
      endLongitude: campusLng,
    );
    return distance <= radiusMeters;
  }

  /// Ray-casting algorithm to test if a point is inside a polygon or on its boundary.
  /// Handles arbitrary convex and concave polygon boundaries.
  static bool isPointInPolygon({
    required double pointLat,
    required double pointLng,
    required List<LatLng> polygon,
    double edgeToleranceMeters = 1.0,
  }) {
    if (!isValidCoordinate(pointLat, pointLng) || polygon.length < 3) {
      return false;
    }

    // First check if the point lies directly on or within small edge tolerance of any segment
    for (int i = 0; i < polygon.length; i++) {
      final p1 = polygon[i];
      final p2 = polygon[(i + 1) % polygon.length];

      if (_isPointOnSegment(
        pointLat,
        pointLng,
        p1.latitude,
        p1.longitude,
        p2.latitude,
        p2.longitude,
        edgeToleranceMeters,
      )) {
        return true; // Point on polygon boundary is treated as inside (ST_Covers policy)
      }
    }

    // Ray casting algorithm
    bool inside = false;
    int j = polygon.length - 1;

    for (int i = 0; i < polygon.length; i++) {
      final xi = polygon[i].longitude;
      final yi = polygon[i].latitude;
      final xj = polygon[j].longitude;
      final yj = polygon[j].latitude;

      final intersect = ((yi > pointLat) != (yj > pointLat)) &&
          (pointLng < (xj - xi) * (pointLat - yi) / (yj - yi + 1e-12) + xi);

      if (intersect) {
        inside = !inside;
      }
      j = i;
    }

    return inside;
  }

  /// Check if point is on line segment within tolerance (in meters)
  static bool _isPointOnSegment(
    double pLat,
    double pLng,
    double aLat,
    double aLng,
    double bLat,
    double bLng,
    double toleranceMeters,
  ) {
    final distAP = calculateDistanceInMeters(
      startLatitude: aLat,
      startLongitude: aLng,
      endLatitude: pLat,
      endLongitude: pLng,
    );
    final distPB = calculateDistanceInMeters(
      startLatitude: pLat,
      startLongitude: pLng,
      endLatitude: bLat,
      endLongitude: bLng,
    );
    final distAB = calculateDistanceInMeters(
      startLatitude: aLat,
      startLongitude: aLng,
      endLatitude: bLat,
      endLongitude: bLng,
    );

    // If dist(A, P) + dist(P, B) is close to dist(A, B) within tolerance
    return (distAP + distPB - distAB).abs() <= toleranceMeters;
  }

  /// Comprehensive evaluation against circular buffer and polygon boundaries
  static GeofenceEvaluationResult evaluateGeofence({
    required double userLat,
    required double userLng,
    required double campusCenterLat,
    required double campusCenterLng,
    required double bufferRadiusMeters,
    required List<LatLng> polygonBoundary,
  }) {
    if (!isValidCoordinate(userLat, userLng)) {
      return const GeofenceEvaluationResult(
        isInside: false,
        distanceFromCenterMeters: double.infinity,
        isWithinCircularBuffer: false,
        isInsidePolygon: false,
        statusReason: 'Invalid GPS coordinates provided',
      );
    }

    final distance = calculateDistanceInMeters(
      startLatitude: userLat,
      startLongitude: userLng,
      endLatitude: campusCenterLat,
      endLongitude: campusCenterLng,
    );

    final isWithinBuffer = distance <= bufferRadiusMeters;
    final isInsidePoly = isPointInPolygon(
      pointLat: userLat,
      pointLng: userLng,
      polygon: polygonBoundary,
    );

    // Policy: User is considered inside if inside polygon or within defined buffer
    final isInside = polygonBoundary.isNotEmpty ? isInsidePoly : isWithinBuffer;

    String reason;
    if (isInside) {
      reason = 'Position confirmed within campus perimeter (${distance.toStringAsFixed(1)}m from center).';
    } else {
      reason = 'Position is ${distance.toStringAsFixed(1)}m from campus center (Allowed radius: ${bufferRadiusMeters.toStringAsFixed(0)}m).';
    }

    return GeofenceEvaluationResult(
      isInside: isInside,
      distanceFromCenterMeters: distance,
      isWithinCircularBuffer: isWithinBuffer,
      isInsidePolygon: isInsidePoly,
      statusReason: reason,
    );
  }

  static double _toRadians(double degree) => degree * math.pi / 180.0;
}

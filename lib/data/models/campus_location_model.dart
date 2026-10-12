import '../../core/utils/geo_utils.dart';

class CampusLocation {
  final String id;
  final String code;
  final String name;
  final String? description;
  final double centerLatitude;
  final double centerLongitude;
  final double bufferRadiusMeters;
  final List<LatLng> boundaryPolygon;
  final bool isActive;

  const CampusLocation({
    required this.id,
    required this.code,
    required this.name,
    this.description,
    required this.centerLatitude,
    required this.centerLongitude,
    this.bufferRadiusMeters = 120.0,
    this.boundaryPolygon = const [],
    this.isActive = true,
  });

  factory CampusLocation.fromMap(Map<String, dynamic> map) {
    List<LatLng> polygon = [];
    if (map['boundary_coordinates'] is List) {
      polygon = (map['boundary_coordinates'] as List).map((pt) {
        if (pt is Map) {
          return LatLng(
            (pt['lat'] as num).toDouble(),
            (pt['lng'] as num).toDouble(),
          );
        } else if (pt is List && pt.length >= 2) {
          // [longitude, latitude] or [latitude, longitude]
          return LatLng(
            (pt[1] as num).toDouble(),
            (pt[0] as num).toDouble(),
          );
        }
        return const LatLng(0, 0);
      }).toList();
    } else {
      // Default to default campus perimeter polygon around center if not given
      final cLat = (map['center_latitude'] as num?)?.toDouble() ?? 12.9716;
      final cLng = (map['center_longitude'] as num?)?.toDouble() ?? 77.5946;
      polygon = [
        LatLng(cLat - 0.0010, cLng - 0.0010),
        LatLng(cLat - 0.0010, cLng + 0.0010),
        LatLng(cLat + 0.0010, cLng + 0.0010),
        LatLng(cLat + 0.0010, cLng - 0.0010),
      ];
    }

    return CampusLocation(
      id: map['id'] as String,
      code: map['code'] as String,
      name: map['name'] as String,
      description: map['description'] as String?,
      centerLatitude: (map['center_latitude'] as num?)?.toDouble() ?? 12.9716,
      centerLongitude: (map['center_longitude'] as num?)?.toDouble() ?? 77.5946,
      bufferRadiusMeters: (map['buffer_radius_meters'] as num?)?.toDouble() ?? 120.0,
      boundaryPolygon: polygon,
      isActive: (map['is_active'] as bool?) ?? true,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'code': code,
      'name': name,
      'description': description,
      'center_latitude': centerLatitude,
      'center_longitude': centerLongitude,
      'buffer_radius_meters': bufferRadiusMeters,
      'boundary_coordinates': boundaryPolygon
          .map((p) => {'lat': p.latitude, 'lng': p.longitude})
          .toList(),
      'is_active': isActive,
    };
  }
}

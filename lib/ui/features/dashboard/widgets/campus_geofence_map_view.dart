import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../data/models/campus_location_model.dart';
import '../../../../core/services/location_service.dart';

/// Interactive vector map widget visualizing campus geofence boundary & user GPS position
class CampusGeofenceMapView extends StatelessWidget {
  final CampusLocation campus;
  final UserLocationData? userLocation;
  final bool isInside;

  const CampusGeofenceMapView({
    super.key,
    required this.campus,
    this.userLocation,
    this.isInside = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 220,
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // Radar grid & Geofence custom painter
          Positioned.fill(
            child: CustomPaint(
              painter: _GeofenceRadarPainter(
                campus: campus,
                userLocation: userLocation,
                isInside: isInside,
              ),
            ),
          ),

          // Map Header Overlay
          Positioned(
            top: 12,
            left: 14,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.65),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white24, width: 0.8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.layers_rounded, color: AppTheme.irisCyan, size: 14),
                  const SizedBox(width: 6),
                  Text(
                    campus.code,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.6,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Geofence status badge
          Positioned(
            top: 12,
            right: 14,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: isInside
                    ? AppTheme.statusSuccess.withOpacity(0.2)
                    : AppTheme.statusError.withOpacity(0.2),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isInside ? AppTheme.statusSuccess : AppTheme.statusError,
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isInside ? Icons.verified_user_rounded : Icons.location_off_rounded,
                    color: isInside ? AppTheme.statusSuccess : AppTheme.statusError,
                    size: 13,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    isInside ? 'INSIDE PERIMETER' : 'OUTSIDE ZONE',
                    style: TextStyle(
                      color: isInside ? AppTheme.statusSuccess : const Color(0xFFFCA5A5),
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.4,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Coordinates & Accuracy Footer
          Positioned(
            bottom: 10,
            left: 14,
            right: 14,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  userLocation != null
                      ? 'GPS: ${userLocation!.latitude.toStringAsFixed(4)}°N, ${userLocation!.longitude.toStringAsFixed(4)}°E'
                      : 'Acquiring GPS fix...',
                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                ),
                if (userLocation != null)
                  Text(
                    'Acc: ±${userLocation!.accuracyMeters.toStringAsFixed(1)}m',
                    style: TextStyle(
                      color: userLocation!.hasAcceptableAccuracy
                          ? Colors.tealAccent
                          : Colors.amberAccent,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GeofenceRadarPainter extends CustomPainter {
  final CampusLocation campus;
  final UserLocationData? userLocation;
  final bool isInside;

  _GeofenceRadarPainter({
    required this.campus,
    required this.userLocation,
    required this.isInside,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final paintGrid = Paint()
      ..color = Colors.white.withOpacity(0.06)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    // Draw concentric radar range rings
    for (double r = 30; r <= size.height * 0.45; r += 35) {
      canvas.drawCircle(center, r, paintGrid);
    }

    // Draw Campus Center Anchor
    final campusPaint = Paint()..color = AppTheme.primaryAccent;
    canvas.drawCircle(center, 5.0, campusPaint);

    // Draw Geofence Boundary Polygon or Buffer Circle
    final polyPaint = Paint()
      ..color = (isInside ? AppTheme.statusSuccess : AppTheme.primaryAccent)
          .withOpacity(0.18)
      ..style = PaintingStyle.fill;

    final polyStroke = Paint()
      ..color = (isInside ? AppTheme.statusSuccess : AppTheme.irisCyan)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    // If campus polygon is available, map relative lat/lng to canvas coordinates
    if (campus.boundaryPolygon.isNotEmpty) {
      final path = Path();
      // Scaling factor: 0.001 degree ~ 111 meters -> map to ~70 pixels
      const scale = 70000.0;

      for (int i = 0; i < campus.boundaryPolygon.length; i++) {
        final pt = campus.boundaryPolygon[i];
        final dx = center.dx + (pt.longitude - campus.centerLongitude) * scale;
        final dy = center.dy - (pt.latitude - campus.centerLatitude) * scale;

        if (i == 0) {
          path.moveTo(dx, dy);
        } else {
          path.lineTo(dx, dy);
        }
      }
      path.close();
      canvas.drawPath(path, polyPaint);
      canvas.drawPath(path, polyStroke);
    } else {
      // Fallback circular buffer
      canvas.drawCircle(center, 65, polyPaint);
      canvas.drawCircle(center, 65, polyStroke);
    }

    // Draw Student Position Marker
    if (userLocation != null) {
      const scale = 70000.0;
      final dx = center.dx + (userLocation!.longitude - campus.centerLongitude) * scale;
      final dy = center.dy - (userLocation!.latitude - campus.centerLatitude) * scale;
      final userOffset = Offset(dx, dy);

      // Accuracy circle
      final accRadius = (userLocation!.accuracyMeters / 120.0 * 65.0).clamp(6.0, 45.0);
      final accPaint = Paint()
        ..color = (isInside ? AppTheme.statusSuccess : AppTheme.statusError).withOpacity(0.2)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(userOffset, accRadius, accPaint);

      // Student pin
      final pinPaint = Paint()
        ..color = isInside ? AppTheme.statusSuccess : AppTheme.statusError;
      canvas.drawCircle(userOffset, 6.0, pinPaint);

      final innerWhite = Paint()..color = Colors.white;
      canvas.drawCircle(userOffset, 2.5, innerWhite);
    }
  }

  @override
  bool shouldRepaint(covariant _GeofenceRadarPainter oldDelegate) => true;
}

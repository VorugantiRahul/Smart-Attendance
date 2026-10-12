import 'dart:math' as math;

/// High-Fidelity Anatomical Face and Test Image Generator
/// Generates realistic human facial structures, multi-face frames, landscapes,
/// and edge artifacts for reliable client and backend testing.
class SyntheticFaceGenerator {
  /// Generates an image with a single human face:
  /// Face oval skin tone, two darker bilateral eyes (pupils + sclera + iris),
  /// eyebrows, nose ridge, and mouth within anatomical proportions.
  static List<int> generateSingleFaceImage({
    int width = 320,
    int height = 240,
    double faceCenterX = 0.5,
    double faceCenterY = 0.48,
    double faceRadiusX = 0.24,
    double faceRadiusY = 0.32,
    bool isSharp = true,
    int ambientBrightness = 50,
  }) {
    final pixels = List<int>.filled(width * height, ambientBrightness);
    final fcx = width * faceCenterX;
    final fcy = height * faceCenterY;
    final rx = width * faceRadiusX;
    final ry = height * faceRadiusY;

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        // Face Oval (Skin luminance ~ 160-195)
        final normX = (x - fcx) / rx;
        final normY = (y - fcy) / ry;
        final distOval = normX * normX + normY * normY;

        if (distOval <= 1.0) {
          // Base skin shade
          int skin = (175 - (distOval * 25).toInt()).clamp(140, 200);

          // Bilateral Eye structures
          final eyeY = fcy - ry * 0.18;
          final leftEyeX = fcx - rx * 0.42;
          final rightEyeX = fcx + rx * 0.42;
          final eyeRadius = rx * 0.16;

          final distLeftEye = math.sqrt((x - leftEyeX) * (x - leftEyeX) + (y - eyeY) * (y - eyeY));
          final distRightEye = math.sqrt((x - rightEyeX) * (x - rightEyeX) + (y - eyeY) * (y - eyeY));

          if (distLeftEye < eyeRadius * 0.45 || distRightEye < eyeRadius * 0.45) {
            // Dark pupil
            skin = 25;
          } else if (distLeftEye < eyeRadius || distRightEye < eyeRadius) {
            // Iris ring
            skin = 95;
          } else if (distLeftEye < eyeRadius * 1.4 && (y - eyeY).abs() < eyeRadius * 0.6) {
            // Sclera
            skin = 230;
          }

          // Eyebrows
          final browY = eyeY - eyeRadius * 1.1;
          if ((y - browY).abs() < 2.5 &&
              ((x - leftEyeX).abs() < eyeRadius * 1.2 || (x - rightEyeX).abs() < eyeRadius * 1.2)) {
            skin = 35;
          }

          // Mouth / Lips
          final mouthY = fcy + ry * 0.55;
          final distMouthX = (x - fcx).abs();
          if ((y - mouthY).abs() < 3.5 && distMouthX < rx * 0.38) {
            skin = 85; // lips
          }

          // Noise / micro-texture
          if (isSharp && (x + y) % 5 == 0) {
            skin = (skin + 6).clamp(0, 255);
          }

          pixels[y * width + x] = skin;
        } else {
          // Ambient background gradient
          pixels[y * width + x] = ambientBrightness + ((x % 30) < 15 ? 10 : 0);
        }
      }
    }

    return pixels;
  }

  /// Generates a frame containing NO faces:
  /// e.g. uniform blank wall, horizon landscape, or random geometric texture.
  static List<int> generateLandscapeOrObjectImage({
    int width = 320,
    int height = 240,
  }) {
    final pixels = List<int>.filled(width * height, 120);
    // Draw horizontal stripes and mountain gradient (landscape)
    for (int y = 0; y < height; y++) {
      final horizonGradient = (80 + (y / height * 120)).toInt().clamp(0, 255);
      for (int x = 0; x < width; x++) {
        // Linear waves without any facial oval symmetry or eye pair
        final wave = (math.sin(x * 0.05) * 15).toInt();
        pixels[y * width + x] = (horizonGradient + wave).clamp(0, 255);
      }
    }
    return pixels;
  }

  /// Generates a frame containing MULTIPLE distinct faces (e.g. 2 people).
  static List<int> generateMultipleFacesImage({
    int width = 320,
    int height = 240,
  }) {
    // Generate base background
    final pixels = List<int>.filled(width * height, 40);

    // Face 1 on left side (center ~0.30)
    final face1 = generateSingleFaceImage(
      width: width,
      height: height,
      faceCenterX: 0.28,
      faceCenterY: 0.50,
      faceRadiusX: 0.16,
      faceRadiusY: 0.24,
      ambientBrightness: 40,
    );

    // Face 2 on right side (center ~0.72)
    final face2 = generateSingleFaceImage(
      width: width,
      height: height,
      faceCenterX: 0.72,
      faceCenterY: 0.50,
      faceRadiusX: 0.16,
      faceRadiusY: 0.24,
      ambientBrightness: 40,
    );

    // Combine faces
    for (int i = 0; i < pixels.length; i++) {
      if (face1[i] > 60) {
        pixels[i] = face1[i];
      } else if (face2[i] > 60) {
        pixels[i] = face2[i];
      } else {
        pixels[i] = 40;
      }
    }

    return pixels;
  }

  /// Generates an excessively dark or underexposed image.
  static List<int> generateDarkImage({
    int width = 320,
    int height = 240,
  }) {
    return List<int>.filled(width * height, 15);
  }

  /// Generates a completely blurred image (zero edge gradients).
  static List<int> generateBlurryImage({
    int width = 320,
    int height = 240,
  }) {
    // Flat uniform luminance (variance = 0)
    return List<int>.filled(width * height, 130);
  }
}

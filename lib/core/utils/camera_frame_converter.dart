import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:image/image.dart' as img;

/// Real Camera Frame Conversion Utility
/// Extracts grayscale luminance and encoded image bytes directly from CameraImage
/// (Android YUV420_888, iOS BGRA8888, or Web NV21/RGBA) or captured XFile frames.
class CameraFrameConverter {
  /// Converts a live streaming [CameraImage] into a normalized 8-bit grayscale pixel buffer.
  /// Ideal for real-time face detection, pupil localization, and Gabor wavelet extraction.
  static ConvertedFrame convertCameraImage(CameraImage image) {
    final int width = image.width;
    final int height = image.height;
    final List<int> grayscalePixels = List<int>.filled(width * height, 0);

    // Plane 0 of YUV420_888 on Android contains pure grayscale luminance (Y channel)
    if (image.format.group == ImageFormatGroup.yuv420) {
      final Plane yPlane = image.planes[0];
      final Uint8List yBytes = yPlane.bytes;
      final int rowStride = yPlane.bytesPerRow;
      final int pixelStride = yPlane.bytesPerPixel ?? 1;

      int destIdx = 0;
      for (int y = 0; y < height; y++) {
        final int rowStart = y * rowStride;
        for (int x = 0; x < width; x++) {
          grayscalePixels[destIdx++] = yBytes[rowStart + x * pixelStride];
        }
      }
    } else if (image.format.group == ImageFormatGroup.bgra8888) {
      // iOS BGRA8888 plane
      final Uint8List bytes = image.planes[0].bytes;
      int destIdx = 0;
      for (int i = 0; i < bytes.length; i += 4) {
        if (destIdx >= grayscalePixels.length) break;
        final int b = bytes[i];
        final int g = bytes[i + 1];
        final int r = bytes[i + 2];
        // Standard Rec. 601 Luma formula
        final int luma = ((0.299 * r) + (0.587 * g) + (0.114 * b)).round().clamp(0, 255);
        grayscalePixels[destIdx++] = luma;
      }
    } else {
      // Generic fallback for other platforms/formats: extract first byte or average
      final Uint8List bytes = image.planes[0].bytes;
      final int stride = (bytes.length / (width * height)).round().clamp(1, 4);
      int destIdx = 0;
      for (int i = 0; i < bytes.length; i += stride) {
        if (destIdx >= grayscalePixels.length) break;
        grayscalePixels[destIdx++] = bytes[i];
      }
    }

    return ConvertedFrame(
      grayscalePixels: grayscalePixels,
      width: width,
      height: height,
    );
  }

  /// Converts captured [XFile] photo bytes into a resized grayscale buffer
  /// suitable for full pipeline verification, localization, and enrollment.
  static ConvertedFrame? convertXFileBytes(Uint8List rawBytes, {int targetWidth = 320, int targetHeight = 240}) {
    try {
      final img.Image? decoded = img.decodeImage(rawBytes);
      if (decoded == null) return null;

      final img.Image resized = img.copyResize(
        decoded,
        width: targetWidth,
        height: targetHeight,
        interpolation: img.Interpolation.linear,
      );

      final List<int> grayscalePixels = List<int>.filled(targetWidth * targetHeight, 0);
      int idx = 0;
      for (int y = 0; y < targetHeight; y++) {
        for (int x = 0; x < targetWidth; x++) {
          final pixel = resized.getPixel(x, y);
          // Rec.601 Luminance
          final luma = ((0.299 * pixel.r) + (0.587 * pixel.g) + (0.114 * pixel.b)).round().clamp(0, 255);
          grayscalePixels[idx++] = luma;
        }
      }

      return ConvertedFrame(
        grayscalePixels: grayscalePixels,
        width: targetWidth,
        height: targetHeight,
        originalImage: decoded,
      );
    } catch (_) {
      return null;
    }
  }
}

class ConvertedFrame {
  final List<int> grayscalePixels;
  final int width;
  final int height;
  final img.Image? originalImage;

  const ConvertedFrame({
    required this.grayscalePixels,
    required this.width,
    required this.height,
    this.originalImage,
  });
}

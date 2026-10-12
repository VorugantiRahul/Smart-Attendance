import 'dart:typed_data';

/// Minimal pure-Dart uncompressed BMP image encoder
/// Wraps 8-bit grayscale pixel buffers into standard BMP format
/// readable by Windows Photo Viewer, Photoshop, Chrome, and any image viewer.
class BmpEncoder {
  static Uint8List encodeGrayscale({
    required List<int> grayscalePixels,
    required int width,
    required int height,
  }) {
    // Row padding to 4-byte boundary
    final rowPadding = (4 - (width % 4)) % 4;
    final pixelDataSize = (width + rowPadding) * height;
    final paletteSize = 256 * 4; // 256 color palette entries (RGBA)
    const fileHeaderSize = 14;
    const infoHeaderSize = 40;
    final totalFileSize = fileHeaderSize + infoHeaderSize + paletteSize + pixelDataSize;

    final bytes = ByteData(totalFileSize);
    int offset = 0;

    // --- BITMAP FILE HEADER (14 bytes) ---
    // 'BM' identifier
    bytes.setUint8(offset++, 0x42);
    bytes.setUint8(offset++, 0x4D);
    // File size
    bytes.setUint32(offset, totalFileSize, Endian.little);
    offset += 4;
    // Reserved
    bytes.setUint16(offset, 0, Endian.little);
    offset += 2;
    bytes.setUint16(offset, 0, Endian.little);
    offset += 2;
    // Offset to pixel data
    final pixelDataOffset = fileHeaderSize + infoHeaderSize + paletteSize;
    bytes.setUint32(offset, pixelDataOffset, Endian.little);
    offset += 4;

    // --- BITMAP INFO HEADER (40 bytes) ---
    bytes.setUint32(offset, infoHeaderSize, Endian.little);
    offset += 4;
    bytes.setInt32(offset, width, Endian.little);
    offset += 4;
    // Positive height means bottom-up (standard BMP)
    bytes.setInt32(offset, height, Endian.little);
    offset += 4;
    // Color planes (1)
    bytes.setUint16(offset, 1, Endian.little);
    offset += 2;
    // Bits per pixel (8-bit indexed)
    bytes.setUint16(offset, 8, Endian.little);
    offset += 2;
    // Compression (0 = BI_RGB uncompressed)
    bytes.setUint32(offset, 0, Endian.little);
    offset += 4;
    // Image size
    bytes.setUint32(offset, pixelDataSize, Endian.little);
    offset += 4;
    // X and Y resolution (pixels per meter, standard 2835 = 72 DPI)
    bytes.setInt32(offset, 2835, Endian.little);
    offset += 4;
    bytes.setInt32(offset, 2835, Endian.little);
    offset += 4;
    // Colors used (256)
    bytes.setUint32(offset, 256, Endian.little);
    offset += 4;
    // Important colors
    bytes.setUint32(offset, 256, Endian.little);
    offset += 4;

    // --- COLOR PALETTE (256 x 4 bytes = 1024 bytes) ---
    // Maps 8-bit index to grayscale (B, G, R, 0)
    for (int i = 0; i < 256; i++) {
      bytes.setUint8(offset++, i); // Blue
      bytes.setUint8(offset++, i); // Green
      bytes.setUint8(offset++, i); // Red
      bytes.setUint8(offset++, 0); // Reserved
    }

    // --- PIXEL ARRAY (Bottom-Up) ---
    for (int y = height - 1; y >= 0; y--) {
      final rowStart = y * width;
      for (int x = 0; x < width; x++) {
        bytes.setUint8(offset++, grayscalePixels[rowStart + x]);
      }
      // Add row padding
      for (int p = 0; p < rowPadding; p++) {
        bytes.setUint8(offset++, 0);
      }
    }

    return bytes.buffer.asUint8List();
  }
}

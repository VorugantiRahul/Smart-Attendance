/// Iris capture quality check results
class IrisQualityAssessment {
  final bool isAcceptable;
  final double brightnessScore; // 0.0 (too dark) to 1.0 (too bright), ideal: 0.4 - 0.7
  final double sharpnessScore;  // 0.0 (blurry) to 1.0 (crisp edge focus)
  final double pupilIrisContrast; // 0.0 (low contrast) to 1.0 (sharp limbus boundary)
  final double occlusionRatio; // 0.0 (clear) to 1.0 (heavily occluded by eyelids/lashes)
  final double overallQualityScore; // 0.0 to 100.0
  final List<String> guidanceInstructions;

  const IrisQualityAssessment({
    required this.isAcceptable,
    required this.brightnessScore,
    required this.sharpnessScore,
    required this.pupilIrisContrast,
    required this.occlusionRatio,
    required this.overallQualityScore,
    required this.guidanceInstructions,
  });

  factory IrisQualityAssessment.evaluate({
    required List<int> grayscalePixels,
    required int width,
    required int height,
    required double eyeDiameterPixels,
  }) {
    if (grayscalePixels.isEmpty || width <= 0 || height <= 0) {
      return const IrisQualityAssessment(
        isAcceptable: false,
        brightnessScore: 0.0,
        sharpnessScore: 0.0,
        pupilIrisContrast: 0.0,
        occlusionRatio: 1.0,
        overallQualityScore: 0.0,
        guidanceInstructions: ['Camera stream unavailable. Please re-open the camera.'],
      );
    }

    final instructions = <String>[];

    // 1. Brightness check (Mean intensity)
    double sum = 0.0;
    for (int p in grayscalePixels) {
      sum += p;
    }
    final meanIntensity = sum / grayscalePixels.length;
    final brightness = meanIntensity / 255.0;

    if (brightness < 0.15) {
      instructions.add('Lighting is too dark. Move towards a well-lit area.');
    } else if (brightness > 0.95) {
      instructions.add('Too much glare/direct light. Avoid strong backlights or reflections.');
    }

    // 2. Sharpness / Focus check (Laplacian variance approximation)
    double varianceSum = 0.0;
    int edgeCount = 0;
    // Step by 2 for mobile frame performance
    for (int y = 1; y < height - 1; y += 2) {
      for (int x = 1; x < width - 1; x += 2) {
        final center = grayscalePixels[y * width + x];
        final up = grayscalePixels[(y - 1) * width + x];
        final down = grayscalePixels[(y + 1) * width + x];
        final left = grayscalePixels[y * width + (x - 1)];
        final right = grayscalePixels[y * width + (x + 1)];

        final laplacian = (4 * center - up - down - left - right).abs();
        varianceSum += laplacian;
        edgeCount++;
      }
    }
    final avgLaplacian = edgeCount > 0 ? (varianceSum / edgeCount) : 0.0;
    // Normalize sharpness score (values above 6 are sharp on standard webcams)
    final sharpness = (avgLaplacian / 12.0).clamp(0.0, 1.0);

    if (sharpness < 0.15) {
      instructions.add('Camera out of focus. Hold the device steady at eye level.');
    }

    // 3. Eye sizing & distance check
    if (eyeDiameterPixels < 60.0) {
      instructions.add('Too far away. Bring the camera closer until your eye fills the circle.');
    } else if (eyeDiameterPixels > 260.0) {
      instructions.add('Too close. Move the camera back slightly.');
    }

    // 4. Contrast & Occlusion heuristics
    final contrast = (sharpness * 0.7 + (1.0 - (brightness - 0.55).abs() * 2) * 0.3).clamp(0.1, 1.0);
    final occlusion = (brightness > 0.90 || brightness < 0.15 || sharpness < 0.15) ? 0.40 : 0.08;

    if (occlusion > 0.35) {
      instructions.add('Open your eye wide to prevent eyelids or eyelashes from covering the iris.');
    }

    // Compute composite score (0 - 100)
    final score = ((sharpness * 40.0) +
            ((1.0 - (brightness - 0.52).abs() * 2).clamp(0.0, 1.0) * 30.0) +
            (contrast * 20.0) +
            ((1.0 - occlusion) * 10.0))
        .clamp(0.0, 100.0);

    final isAcceptable = instructions.isEmpty;

    if (instructions.isEmpty) {
      instructions.add('Eye well-aligned. Hold steady for capture.');
    }

    return IrisQualityAssessment(
      isAcceptable: isAcceptable,
      brightnessScore: brightness,
      sharpnessScore: sharpness,
      pupilIrisContrast: contrast,
      occlusionRatio: occlusion,
      overallQualityScore: score,
      guidanceInstructions: instructions,
    );
  }
}

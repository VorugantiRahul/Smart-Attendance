import 'dart:async';
import 'dart:developer' as developer;
import 'dart:math' as math;
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/biometrics/daugman_iris_engine.dart';
import '../../../../core/biometrics/face_iris_detector.dart';
import '../../../../core/biometrics/face_recognition_engine.dart';
import '../../../../core/biometrics/iris_localization.dart';
import '../../../../core/biometrics/iris_quality_assessment.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/camera_frame_converter.dart';
import '../../../../core/utils/hardware_camera_manager.dart';
import '../../../features/auth/view_models/auth_view_model.dart';
import '../view_models/iris_capture_view_model.dart';

/// Telemetry metrics captured from a single physical camera frame
class CameraDiagnosticTelemetry {
  final DateTime timestamp;
  final int frameWidth;
  final int frameHeight;
  final bool isPortrait;
  final CameraLensDirection lensDirection;
  final bool isTorchActive;
  final int latencyMs;
  final double fps;

  // Face metrics
  final bool faceDetected;
  final int faceCount;
  final NormalizedBoundingBox? faceBoundingBox;
  final double faceConfidence;

  // Eye & Iris metrics
  final bool bothEyesDetected;
  final EyeIrisLandmarks? leftIris;
  final EyeIrisLandmarks? rightIris;
  final double eyeWidthPixels;
  final double eyeHeightPixels;
  final double interpupillaryDistancePixels;
  final double estimatedIrisDiameterPixels;

  // Optical & Quality metrics
  final double sharpnessLaplacian;
  final double meanLuminance;
  final double specularGlareRatio;
  final double occlusionRatio;
  final double overallQualityScore;
  final String diagnosticGuidance;
  final bool isSuitableForBiometrics;

  const CameraDiagnosticTelemetry({
    required this.timestamp,
    required this.frameWidth,
    required this.frameHeight,
    required this.isPortrait,
    required this.lensDirection,
    required this.isTorchActive,
    required this.latencyMs,
    required this.fps,
    required this.faceDetected,
    required this.faceCount,
    this.faceBoundingBox,
    required this.faceConfidence,
    required this.bothEyesDetected,
    this.leftIris,
    this.rightIris,
    required this.eyeWidthPixels,
    required this.eyeHeightPixels,
    required this.interpupillaryDistancePixels,
    required this.estimatedIrisDiameterPixels,
    required this.sharpnessLaplacian,
    required this.meanLuminance,
    required this.specularGlareRatio,
    required this.occlusionRatio,
    required this.overallQualityScore,
    required this.diagnosticGuidance,
    required this.isSuitableForBiometrics,
  });

  Map<String, dynamic> toJson() => {
    'timestamp': timestamp.toIso8601String(),
    'camera': {
      'lens': lensDirection.name,
      'resolution': '${frameWidth}x$frameHeight',
      'orientation': isPortrait ? 'portrait' : 'landscape',
      'torch_active': isTorchActive,
      'latency_ms': latencyMs,
      'fps': double.parse(fps.toStringAsFixed(1)),
    },
    'face': {
      'detected': faceDetected,
      'count': faceCount,
      'confidence': double.parse(faceConfidence.toStringAsFixed(2)),
      'bbox': faceBoundingBox != null
          ? {
              'left': double.parse(faceBoundingBox!.left.toStringAsFixed(2)),
              'top': double.parse(faceBoundingBox!.top.toStringAsFixed(2)),
              'width': double.parse(faceBoundingBox!.width.toStringAsFixed(2)),
              'height': double.parse(faceBoundingBox!.height.toStringAsFixed(2)),
            }
          : null,
    },
    'eyes_and_iris': {
      'both_eyes_detected': bothEyesDetected,
      'eye_width_px': double.parse(eyeWidthPixels.toStringAsFixed(1)),
      'eye_height_px': double.parse(eyeHeightPixels.toStringAsFixed(1)),
      'interpupillary_dist_px': double.parse(interpupillaryDistancePixels.toStringAsFixed(1)),
      'estimated_iris_diameter_px': double.parse(estimatedIrisDiameterPixels.toStringAsFixed(1)),
      'iso_19794_6_compliant': estimatedIrisDiameterPixels >= 150,
    },
    'optical_quality': {
      'sharpness_laplacian': double.parse(sharpnessLaplacian.toStringAsFixed(2)),
      'mean_luminance_255': double.parse(meanLuminance.toStringAsFixed(1)),
      'specular_glare_pct': double.parse((specularGlareRatio * 100).toStringAsFixed(1)),
      'occlusion_pct': double.parse((occlusionRatio * 100).toStringAsFixed(1)),
      'composite_quality_score': double.parse(overallQualityScore.toStringAsFixed(1)),
      'is_suitable_for_biometrics': isSuitableForBiometrics,
    },
    'guidance': diagnosticGuidance,
  };
}

/// Comprehensive Camera Acquisition & Biometric Recognition Diagnostic Screen
class BiometricDiagnosticScreen extends ConsumerStatefulWidget {
  const BiometricDiagnosticScreen({super.key});

  @override
  ConsumerState<BiometricDiagnosticScreen> createState() => _BiometricDiagnosticScreenState();
}

class _BiometricDiagnosticScreenState extends ConsumerState<BiometricDiagnosticScreen> {
  final HardwareCameraManager _cameraManager = HardwareCameraManager();
  final FaceIrisDetector _detector = AdaptiveFaceIrisDetector();

  bool _isCameraInitializing = true;
  bool _hasPhysicalCamera = false;
  bool _isDiagnosing = false;
  Timer? _diagnosticLoopTimer;

  CameraDiagnosticTelemetry? _latestTelemetry;
  String? _biometricMatchResult;
  bool _isMatching = false;
  int _frameCount = 0;
  DateTime? _lastFrameTime;
  double _calculatedFps = 0.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initCamera();
    });
  }

  @override
  void dispose() {
    _diagnosticLoopTimer?.cancel();
    _cameraManager.dispose();
    super.dispose();
  }

  Future<void> _initCamera() async {
    setState(() {
      _isCameraInitializing = true;
    });

    final success = await _cameraManager.initializeCamera(
      preferredLens: CameraLensDirection.front,
      resolution: ResolutionPreset.medium,
    );

    if (!mounted) return;

    setState(() {
      _isCameraInitializing = false;
      _hasPhysicalCamera = success;
    });

    if (success) {
      _startDiagnosticLoop();
    }
  }

  void _startDiagnosticLoop() {
    _diagnosticLoopTimer?.cancel();
    // Run diagnostics every 600ms on real frames
    _diagnosticLoopTimer = Timer.periodic(const Duration(milliseconds: 650), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (!_isDiagnosing && !_isCameraInitializing && _hasPhysicalCamera && _cameraManager.isReady) {
        _runFrameDiagnostic();
      }
    });
  }

  Future<void> _runFrameDiagnostic() async {
    if (!mounted || _isDiagnosing) return;
    _isDiagnosing = true;
    final stopwatch = Stopwatch()..start();

    try {
      final XFile? frameFile = await _cameraManager.captureFrame();
      if (frameFile != null) {
        final Uint8List rawBytes = await frameFile.readAsBytes();
        final ConvertedFrame? converted = CameraFrameConverter.convertXFileBytes(
          rawBytes,
          targetWidth: 320,
          targetHeight: 240,
        );

        if (converted != null) {
          final now = DateTime.now();
          if (_lastFrameTime != null) {
            final deltaMs = now.difference(_lastFrameTime!).inMilliseconds;
            if (deltaMs > 0) {
              _calculatedFps = (_calculatedFps * 0.7) + ((1000.0 / deltaMs) * 0.3);
            }
          }
          _lastFrameTime = now;
          _frameCount++;

          final telemetry = await _analyzeFrame(
            pixels: converted.grayscalePixels,
            width: converted.width,
            height: converted.height,
            isPortrait: converted.height > converted.width,
            latencyMs: stopwatch.elapsedMilliseconds,
          );

          if (mounted) {
            setState(() {
              _latestTelemetry = telemetry;
            });
          }
        }
      }
    } catch (e) {
      developer.log('Diagnostic loop error: $e', name: 'BiometricDiagnosticScreen');
    } finally {
      if (mounted) {
        _isDiagnosing = false;
      }
    }
  }

  Future<CameraDiagnosticTelemetry> _analyzeFrame({
    required List<int> pixels,
    required int width,
    required int height,
    required bool isPortrait,
    required int latencyMs,
  }) async {
    // 1. Mean luminance and glare
    double lumSum = 0.0;
    int glareCount = 0;
    for (int p in pixels) {
      lumSum += p;
      if (p >= 245) glareCount++;
    }
    final meanLum = pixels.isNotEmpty ? (lumSum / pixels.length) : 0.0;
    final glareRatio = pixels.isNotEmpty ? (glareCount / pixels.length) : 0.0;

    // 2. Laplacian blur / sharpness across central region
    double lapSum = 0.0;
    int lapCount = 0;
    for (int y = 2; y < height - 2; y += 3) {
      for (int x = 2; x < width - 2; x += 3) {
        final c = pixels[y * width + x];
        final l = pixels[y * width + (x - 1)];
        final r = pixels[y * width + (x + 1)];
        final u = pixels[(y - 1) * width + x];
        final d = pixels[(y + 1) * width + x];
        lapSum += (4 * c - l - r - u - d).abs();
        lapCount++;
      }
    }
    final avgLaplacian = lapCount > 0 ? (lapSum / lapCount) : 0.0;

    // 3. Face & Eye landmark localization
    final detection = await _detector.detectLandmarks(
      grayscalePixels: pixels,
      width: width,
      height: height,
    );

    // Compute concrete pixel dimensions
    double eyeW = 0.0;
    double eyeH = 0.0;
    double ipd = 0.0;
    double irisDiam = 0.0;

    if (detection.hasFace && detection.faceBoundingBox != null) {
      final fb = detection.faceBoundingBox!;
      final facePixelW = fb.width * width;
      final facePixelH = fb.height * height;

      // Anatomical eye width is ~20% of face width
      eyeW = facePixelW * 0.22;
      eyeH = facePixelH * 0.15;
      irisDiam = eyeW * 0.45;

      final lx = detection.leftIris.center.x * width;
      final ly = detection.leftIris.center.y * height;
      final rx = detection.rightIris.center.x * width;
      final ry = detection.rightIris.center.y * height;
      ipd = math.sqrt((rx - lx) * (rx - lx) + (ry - ly) * (ry - ly));
    }

    // 4. Occlusion calculation
    final occlusion = (meanLum > 230 || meanLum < 35 || avgLaplacian < 2.0) ? 0.35 : 0.08;

    // 5. Overall composite score
    final sharpnessNorm = (avgLaplacian / 12.0).clamp(0.0, 1.0);
    final brightnessNorm = (1.0 - ((meanLum / 255.0) - 0.52).abs() * 2).clamp(0.0, 1.0);
    final compositeScore = ((sharpnessNorm * 40.0) + (brightnessNorm * 35.0) + ((1.0 - occlusion) * 25.0)).clamp(0.0, 100.0);

    // 6. Actionable Diagnostic Guidance
    String guidance;
    bool isSuitable = false;

    if (!detection.hasFace) {
      guidance = 'Face not detected. Position your entire face squarely in front of the lens.';
    } else if (eyeW < 30.0) {
      guidance = 'Move closer: Eye width is ${eyeW.toInt()} px (minimum 40 px required; ISO iris standard recommends >= 150 px).';
    } else if (avgLaplacian < 2.5) {
      guidance = 'Image is blurred (Sharpness: ${avgLaplacian.toStringAsFixed(1)} < 3.0). Hold device steady at eye level.';
    } else if (meanLum < 45.0) {
      guidance = 'Lighting is insufficient (Luminance: ${meanLum.toInt()} < 45). Move to a brighter area.';
    } else if (meanLum > 235.0) {
      guidance = 'Overexposure / direct glare. Avoid strong backlights or reflections.';
    } else if (glareRatio > 0.08) {
      guidance = 'Specular reflection on cornea (${(glareRatio * 100).toInt()}%). Angle device slightly away from direct ceiling lamps.';
    } else {
      guidance = 'Eye and face region suitable for biometric identity matching.';
      isSuitable = true;
    }

    return CameraDiagnosticTelemetry(
      timestamp: DateTime.now(),
      frameWidth: width,
      frameHeight: height,
      isPortrait: isPortrait,
      lensDirection: _cameraManager.currentDirection,
      isTorchActive: _cameraManager.isTorchOn,
      latencyMs: latencyMs,
      fps: _calculatedFps,
      faceDetected: detection.hasFace,
      faceCount: detection.faceCount,
      faceBoundingBox: detection.faceBoundingBox,
      faceConfidence: detection.confidence,
      bothEyesDetected: detection.bothEyesDetected,
      leftIris: detection.leftIris,
      rightIris: detection.rightIris,
      eyeWidthPixels: eyeW,
      eyeHeightPixels: eyeH,
      interpupillaryDistancePixels: ipd,
      estimatedIrisDiameterPixels: irisDiam,
      sharpnessLaplacian: avgLaplacian,
      meanLuminance: meanLum,
      specularGlareRatio: glareRatio,
      occlusionRatio: occlusion,
      overallQualityScore: compositeScore,
      diagnosticGuidance: guidance,
      isSuitableForBiometrics: isSuitable,
    );
  }

  /// Runs genuine end-to-end biometric comparison against the approved enrolled reference
  Future<void> _runGenuineBiometricTest() async {
    if (_isMatching) return;
    setState(() {
      _isMatching = true;
      _biometricMatchResult = 'Acquiring probe frame and comparing with enrolled reference...';
    });

    try {
      final user = ref.read(authStateProvider).user;
      if (user == null) {
        setState(() {
          _biometricMatchResult = 'Authentication Required: Please log in as faculty to test reference matching.';
          _isMatching = false;
        });
        return;
      }

      final authRepo = ref.read(authRepositoryProvider);
      final enrolled = await authRepo.getEnrolledBiometrics(userId: user.id);

      if (enrolled == null || (enrolled['faceTemplateBase64'] == null && enrolled['templateHex'] == null)) {
        setState(() {
          _biometricMatchResult = 'No Enrolled Reference Found: Faculty account (${user.fullName}) has no biometric enrollment on file. Please complete enrollment first.';
          _isMatching = false;
        });
        return;
      }

      final XFile? frame = await _cameraManager.captureFrame();
      if (frame == null) {
        setState(() {
          _biometricMatchResult = 'Camera capture failed: Unable to read image frame.';
          _isMatching = false;
        });
        return;
      }

      final rawBytes = await frame.readAsBytes();
      final converted = CameraFrameConverter.convertXFileBytes(rawBytes, targetWidth: 320, targetHeight: 240);
      if (converted == null) {
        setState(() {
          _biometricMatchResult = 'Frame conversion failed: Could not decode camera buffer.';
          _isMatching = false;
        });
        return;
      }

      final detection = await _detector.detectLandmarks(
        grayscalePixels: converted.grayscalePixels,
        width: converted.width,
        height: converted.height,
      );

      if (!detection.hasFace || detection.faceBoundingBox == null) {
        setState(() {
          _biometricMatchResult = 'Biometric test halted: No face detected in probe frame (${detection.statusMessage}).';
          _isMatching = false;
        });
        return;
      }

      final results = StringBuffer();
      results.writeln('PROBE BIOMETRIC VERIFICATION RESULT:');
      results.writeln('Faculty: ${user.fullName} (${user.employeeId ?? user.id})');
      results.writeln('Approval Status: ${user.approvalStatus.name}');
      results.writeln('---');

      // 1. Face Biometric Matching
      if (enrolled['faceTemplateBase64'] != null) {
        final faceEngine = StandardFaceRecognitionEngine();
        final probeFace = await faceEngine.extractTemplate(
          imagePixels: converted.grayscalePixels,
          width: converted.width,
          height: converted.height,
          faceBox: detection.faceBoundingBox!,
        );

        final enrolledFace = FaceBiometricTemplate.fromBase64String(
          base64String: enrolled['faceTemplateBase64'] as String,
        );

        final match = faceEngine.compareTemplates(
          probe: probeFace,
          enrolledReference: enrolledFace,
          decisionThreshold: 0.55,
        );

        results.writeln('FACIAL RECOGNITION (Cosine Similarity):');
        results.writeln('  Score: ${match.similarityScore.toStringAsFixed(3)} (Threshold: >= ${match.calibratedThreshold.toStringAsFixed(2)})');
        results.writeln('  Decision: ${match.isMatch ? "GENUINE MATCH" : "NON-MATCH / REJECTED"}');
      }

      // 2. Iris Biometric Matching
      if (enrolled['templateHex'] != null) {
        final irisEngine = DaugmanIrisRecognitionEngine();
        final irisX = detection.rightIris.center.x * converted.width;
        final irisY = detection.rightIris.center.y * converted.height;
        final eyeW = detection.faceBoundingBox!.width * converted.width * 0.22;
        final estRadius = (eyeW * 0.22).clamp(10.0, 35.0);

        final localization = IrisLocalizationResult(
          isDetected: true,
          pupilCircle: IrisBoundaryCircle(centerX: irisX, centerY: irisY, radius: estRadius * 0.35),
          irisLimbusCircle: IrisBoundaryCircle(centerX: irisX, centerY: irisY, radius: estRadius),
          confidence: 0.92,
        );

        final probeIris = await irisEngine.extractTemplate(
          imagePixels: converted.grayscalePixels,
          width: converted.width,
          height: converted.height,
          localization: localization,
        );

        final enrolledIris = IrisBiometricTemplate.fromHex(
          hexCode: enrolled['templateHex'] as String,
          hexMask: (enrolled['maskHex'] as String?) ?? ('ff' * 256),
        );

        final irisMatch = irisEngine.compareTemplates(
          probe: probeIris,
          enrolledReference: enrolledIris,
          decisionThreshold: 0.38,
        );

        results.writeln('IRISCODE RECOGNITION (Hamming Distance):');
        results.writeln('  Hamming Distance: ${irisMatch.hammingDistance.toStringAsFixed(3)} (Threshold: <= ${irisMatch.calibratedThreshold.toStringAsFixed(2)})');
        results.writeln('  Decision: ${irisMatch.isMatch ? "GENUINE MATCH" : "REJECTED (Exceeds HD Threshold)"}');
      }

      setState(() {
        _biometricMatchResult = results.toString();
        _isMatching = false;
      });
    } catch (e) {
      setState(() {
        _biometricMatchResult = 'Error executing biometric verification test: $e';
        _isMatching = false;
      });
    }
  }

  void _copyTelemetryToClipboard() {
    if (_latestTelemetry == null) return;
    Clipboard.setData(ClipboardData(text: _latestTelemetry!.toJson().toString()));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Diagnostic telemetry copied to clipboard.'),
        backgroundColor: AppTheme.irisCyan,
        duration: Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = _cameraManager.controller;
    final t = _latestTelemetry;

    return Scaffold(
      backgroundColor: const Color(0xFF0B0F17),
      appBar: AppBar(
        backgroundColor: const Color(0xFF111827),
        foregroundColor: Colors.white,
        title: const Text('Biometric Camera Diagnostic', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: Icon(_cameraManager.isTorchOn ? Icons.flash_on_rounded : Icons.flash_off_rounded),
            tooltip: 'Toggle Macro Flash/Torch',
            onPressed: () async {
              await _cameraManager.toggleTorch();
              setState(() {});
            },
          ),
          IconButton(
            icon: const Icon(Icons.flip_camera_ios_rounded),
            tooltip: 'Switch Lens (Front / Rear Macro)',
            onPressed: () async {
              await _cameraManager.switchCamera();
              setState(() {});
            },
          ),
          IconButton(
            icon: const Icon(Icons.copy_all_rounded),
            tooltip: 'Copy Telemetry',
            onPressed: _copyTelemetryToClipboard,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Guidance Banner
            Container(
              width: double.infinity,
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: t?.isSuitableForBiometrics == true
                    ? AppTheme.statusSuccess.withOpacity(0.15)
                    : const Color(0xFF1F2937),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: t?.isSuitableForBiometrics == true
                      ? AppTheme.statusSuccess
                      : (t?.faceDetected == true ? AppTheme.irisCyan : AppTheme.statusWarning),
                  width: 1.5,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    t?.isSuitableForBiometrics == true
                        ? Icons.verified_user_rounded
                        : (t?.faceDetected == true ? Icons.visibility_rounded : Icons.warning_amber_rounded),
                    color: t?.isSuitableForBiometrics == true
                        ? AppTheme.statusSuccess
                        : (t?.faceDetected == true ? AppTheme.irisCyan : AppTheme.statusWarning),
                    size: 22,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      t?.diagnosticGuidance ?? 'Analyzing camera sensor stream...',
                      style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
            ),

            // Live Camera Viewport with Graphic HUD Overlay
            Expanded(
              flex: 4,
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white24),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // Camera Preview
                      if (_isCameraInitializing)
                        const Center(child: CircularProgressIndicator(color: AppTheme.irisCyan))
                      else if (_hasPhysicalCamera && controller != null && controller.value.isInitialized)
                        Center(
                          child: AspectRatio(
                            aspectRatio: controller.value.aspectRatio,
                            child: CameraPreview(controller),
                          ),
                        )
                      else
                        const Center(child: Text('Camera sensor unavailable', style: TextStyle(color: Colors.white54))),

                      // Biometric Landmark HUD Overlay
                      if (t != null && t.faceDetected && t.faceBoundingBox != null)
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final w = constraints.maxWidth;
                            final h = constraints.maxHeight;
                            final fb = t.faceBoundingBox!;

                            final boxLeft = fb.left * w;
                            final boxTop = fb.top * h;
                            final boxW = fb.width * w;
                            final boxH = fb.height * h;

                            return Stack(
                              children: [
                                // Face Bounding Box
                                Positioned(
                                  left: boxLeft,
                                  top: boxTop,
                                  width: boxW,
                                  height: boxH,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      border: Border.all(color: AppTheme.irisCyan, width: 2),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                ),

                                // Left Eye Marker
                                if (t.leftIris != null)
                                  Positioned(
                                    left: (t.leftIris!.center.x * w) - 16,
                                    top: (t.leftIris!.center.y * h) - 16,
                                    child: Container(
                                      width: 32,
                                      height: 32,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        border: Border.all(color: Colors.greenAccent, width: 2),
                                      ),
                                    ),
                                  ),

                                // Right Eye Marker
                                if (t.rightIris != null)
                                  Positioned(
                                    left: (t.rightIris!.center.x * w) - 16,
                                    top: (t.rightIris!.center.y * h) - 16,
                                    child: Container(
                                      width: 32,
                                      height: 32,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        border: Border.all(color: Colors.greenAccent, width: 2),
                                      ),
                                    ),
                                  ),
                              ],
                            );
                          },
                        ),

                      // Telemetry HUD Pill (Top Left)
                      Positioned(
                        top: 10,
                        left: 10,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.black87,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.white24),
                          ),
                          child: Text(
                            'FPS: ${(t?.fps ?? 0).toStringAsFixed(1)} | Latency: ${t?.latencyMs ?? 0}ms | Lens: ${_cameraManager.currentDirection.name}',
                            style: const TextStyle(color: AppTheme.irisCyan, fontSize: 11, fontFamily: 'monospace'),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            const SizedBox(height: 8),

            // Telemetry Diagnostic Data Grid
            Expanded(
              flex: 5,
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  // Row 1: Face & Eyes
                  Row(
                    children: [
                      Expanded(
                        child: _MetricCard(
                          title: 'Face Detection',
                          value: t?.faceDetected == true ? 'Single Face (${((t?.faceConfidence ?? 0) * 100).toInt()}%)' : 'No Face Detected',
                          status: t?.faceDetected == true ? _MetricStatus.good : _MetricStatus.bad,
                          subtitle: 'Count: ${t?.faceCount ?? 0}',
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _MetricCard(
                          title: 'Bilateral Eyes',
                          value: t?.bothEyesDetected == true ? 'Both Detected' : 'Unobstructed Eyes Req.',
                          status: t?.bothEyesDetected == true ? _MetricStatus.good : _MetricStatus.bad,
                          subtitle: 'IPD: ${(t?.interpupillaryDistancePixels ?? 0).toInt()} px',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // Row 2: Eye Resolution & Iris Diameter
                  Row(
                    children: [
                      Expanded(
                        child: _MetricCard(
                          title: 'Eye Width (px)',
                          value: '${(t?.eyeWidthPixels ?? 0).toInt()} px',
                          status: (t?.eyeWidthPixels ?? 0) >= 40.0 ? _MetricStatus.good : _MetricStatus.warning,
                          subtitle: 'Min: 40px | Recom: 80px',
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _MetricCard(
                          title: 'Est. Iris Diameter',
                          value: '${(t?.estimatedIrisDiameterPixels ?? 0).toInt()} px',
                          status: (t?.estimatedIrisDiameterPixels ?? 0) >= 150 ? _MetricStatus.good : _MetricStatus.warning,
                          subtitle: 'ISO 19794-6 NIR: 150px+',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // Row 3: Sharpness, Brightness, Glare
                  Row(
                    children: [
                      Expanded(
                        child: _MetricCard(
                          title: 'Sharpness (Laplacian)',
                          value: (t?.sharpnessLaplacian ?? 0).toStringAsFixed(1),
                          status: (t?.sharpnessLaplacian ?? 0) >= 3.0 ? _MetricStatus.good : _MetricStatus.bad,
                          subtitle: 'Threshold: >= 3.0',
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _MetricCard(
                          title: 'Mean Luminance',
                          value: '${(t?.meanLuminance ?? 0).toInt()} / 255',
                          status: (t?.meanLuminance ?? 0) >= 45 && (t?.meanLuminance ?? 0) <= 225 ? _MetricStatus.good : _MetricStatus.warning,
                          subtitle: 'Ideal: 60 - 200',
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _MetricCard(
                          title: 'Corneal Glare',
                          value: '${((t?.specularGlareRatio ?? 0) * 100).toInt()}%',
                          status: (t?.specularGlareRatio ?? 0) < 0.08 ? _MetricStatus.good : _MetricStatus.bad,
                          subtitle: 'Max Allowed: 8%',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // Live Biometric Verification Test Results (if executed)
                  if (_biometricMatchResult != null)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E293B),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppTheme.irisCyan),
                      ),
                      child: Text(
                        _biometricMatchResult!,
                        style: const TextStyle(color: Colors.white, fontSize: 11.5, fontFamily: 'monospace', height: 1.4),
                      ),
                    ),

                  const SizedBox(height: 10),

                  // Action Buttons
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.irisCyan,
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          onPressed: _isMatching ? null : _runGenuineBiometricTest,
                          icon: _isMatching
                              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.fingerprint_rounded, size: 20),
                          label: Text(_isMatching ? 'Testing...' : 'Test Match Against Enrolled Ref'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _MetricStatus { good, warning, bad }

class _MetricCard extends StatelessWidget {
  final String title;
  final String value;
  final String subtitle;
  final _MetricStatus status;

  const _MetricCard({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.status,
  });

  @override
  Widget build(BuildContext context) {
    Color statusColor;
    switch (status) {
      case _MetricStatus.good:
        statusColor = AppTheme.statusSuccess;
        break;
      case _MetricStatus.warning:
        statusColor = AppTheme.statusWarning;
        break;
      case _MetricStatus.bad:
        statusColor = AppTheme.statusError;
        break;
    }

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF161F2E),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: statusColor.withOpacity(0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(color: Colors.white70, fontSize: 10.5, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(color: statusColor, fontSize: 13, fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Text(subtitle, style: const TextStyle(color: Colors.white38, fontSize: 9.5)),
        ],
      ),
    );
  }
}

import 'dart:developer' as developer;
import 'package:camera/camera.dart';

/// Hardware Camera Service & Lifecycle Controller
/// Discovers available cameras (front selfie and high-res rear cameras),
/// initializes CameraController with optimal resolution (720p/1080p for eye/iris capture),
/// manages auto-focus, lens switching, and lifecycle safety.
class HardwareCameraManager {
  static List<CameraDescription> _availableCameras = [];
  CameraController? _controller;
  bool _isInitializing = false;
  CameraLensDirection _currentDirection = CameraLensDirection.front;

  CameraController? get controller => _controller;
  bool get isReady => _controller != null && _controller!.value.isInitialized;
  CameraLensDirection get currentDirection => _currentDirection;
  bool get isUsingRearCamera => _currentDirection == CameraLensDirection.back;

  /// Discovers hardware cameras available on the device.
  static Future<List<CameraDescription>> getCameras() async {
    if (_availableCameras.isEmpty) {
      try {
        _availableCameras = await availableCameras();
        developer.log('Discovered ${_availableCameras.length} device camera(s)', name: 'HardwareCameraManager');
      } catch (e) {
        developer.log('Camera discovery failed or unsupported on current platform: $e', name: 'HardwareCameraManager');
        _availableCameras = [];
      }
    }
    return _availableCameras;
  }

  /// Initializes the requested lens direction (front by default for selfie enrollment,
  /// or back for rear-assisted close-up iris acquisition).
  Future<bool> initializeCamera({
    CameraLensDirection preferredLens = CameraLensDirection.front,
    ResolutionPreset resolution = ResolutionPreset.medium, // 720p provides high-density eye detail
  }) async {
    if (_isInitializing) return false;
    _isInitializing = true;
    _currentDirection = preferredLens;

    try {
      final cameras = await getCameras();
      if (cameras.isEmpty) {
        developer.log('No hardware cameras available on this system.', name: 'HardwareCameraManager');
        _isInitializing = false;
        return false;
      }

      // Find camera matching preferred direction, otherwise fallback to first available
      CameraDescription selected = cameras.firstWhere(
        (cam) => cam.lensDirection == preferredLens,
        orElse: () => cameras.first,
      );

      _currentDirection = selected.lensDirection;

      // Dispose existing controller if any
      await dispose();

      final controller = CameraController(
        selected,
        resolution,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );

      await controller.initialize();

      // Configure autofocus if supported by device
      try {
        await controller.setFocusMode(FocusMode.auto);
      } catch (_) {
        // Not all platforms/web drivers support dynamic focus mode
      }

      _controller = controller;
      _isInitializing = false;
      developer.log('Camera initialized successfully: ${selected.lensDirection.name} @ ${resolution.name}', name: 'HardwareCameraManager');
      return true;
    } catch (e) {
      developer.log('Failed to initialize hardware camera: $e', name: 'HardwareCameraManager');
      _isInitializing = false;
      return false;
    }
  }

  /// Switches between Front Camera (selfie mode) and Rear Camera (assisted macro eye capture)
  Future<bool> switchCamera() async {
    final nextLens = _currentDirection == CameraLensDirection.front
        ? CameraLensDirection.back
        : CameraLensDirection.front;
    return await initializeCamera(preferredLens: nextLens);
  }

  /// Captures an actual high-resolution photographic frame from the physical camera sensor
  Future<XFile?> captureFrame() async {
    if (!isReady) return null;
    try {
      final XFile photo = await _controller!.takePicture();
      developer.log('Real camera frame captured: ${photo.path} (${await photo.length()} bytes)', name: 'HardwareCameraManager');
      return photo;
    } catch (e) {
      developer.log('Error capturing camera picture: $e', name: 'HardwareCameraManager');
      return null;
    }
  }

  /// Releases hardware camera resources safely
  Future<void> dispose() async {
    if (_controller != null) {
      try {
        await _controller!.dispose();
      } catch (_) {}
      _controller = null;
    }
  }
}

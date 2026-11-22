import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'audio_service.dart';

/// ML Service for motion detection and noise detection inference.
///
/// Uses TFLite models from assets/models/:
/// - motion_detection.tflite  – 1D CNN, input [1, 128, 6], output [1, 1] sigmoid
/// - noise_detection.tflite   – MobileNetV2, input [1, 256, 256, 3], output [1, 1] sigmoid
///
/// The noise model runs on mel-spectrogram images extracted from microphone audio
/// by AudioService (256×256 grayscale replicated to 3 RGB channels).
class MLService {
  static final MLService _instance = MLService._internal();
  factory MLService() => _instance;
  MLService._internal();

  bool _isInitialized = false;
  bool _isMonitoring = false;

  /// Whether TFLite loaded successfully (false = stub/heuristic mode)
  bool _tfliteReady = false;

  // TFLite interpreters
  Interpreter? _motionInterpreter;
  Interpreter? _noiseInterpreter;

  // Motion detection parameters
  static const int motionWindowSize = 128;
  static const int motionFeatures = 6; // ax, ay, az, gx, gy, gz
  final List<List<double>> _sensorBuffer = [];

  // Detection callbacks
  Function(bool isAnomaly, double confidence)? onMotionDetection;
  Function(bool isDistress, double confidence)? onNoiseDetection;

  // Sensor subscriptions
  StreamSubscription<AccelerometerEvent>? _accelerometerSubscription;
  StreamSubscription<GyroscopeEvent>? _gyroscopeSubscription;

  // Current sensor values
  double _ax = 0, _ay = 0, _az = 0;
  double _gx = 0, _gy = 0, _gz = 0;

  Timer? _inferenceTimer;

  // Audio service for noise detection
  final AudioService _audioService = AudioService();

  // Cooldown to prevent rapid-fire noise alerts
  DateTime? _lastNoiseAlertTime;
  static const Duration _noiseAlertCooldown = Duration(seconds: 10);

  // =========================================================================
  // INITIALIZATION
  // =========================================================================

  /// Initialize the ML models.
  /// Tries to load TFLite models; falls back to heuristic mode on failure.
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      _motionInterpreter = await Interpreter.fromAsset(
        'models/motion_detection.tflite',
      );
      if (kDebugMode) print('✅ Motion detection model loaded');

      try {
        _noiseInterpreter = await Interpreter.fromAsset(
          'models/noise_detection.tflite',
        );
        if (kDebugMode) print('✅ Noise detection model loaded');
      } catch (e) {
        if (kDebugMode) print('⚠️  Noise model load failed (non-critical): $e');
      }

      _tfliteReady = true;
      if (kDebugMode) print('ML Service initialized (TFLite mode)');
    } catch (e) {
      if (kDebugMode) {
        print('⚠️  TFLite load failed, using heuristic fallback: $e');
      }
      _tfliteReady = false;
    }

    // Initialize audio service for noise detection
    try {
      await _audioService.initialize();
    } catch (e) {
      if (kDebugMode) print('⚠️  AudioService init failed (non-critical): $e');
    }

    _isInitialized = true;
  }

  /// Check if service is initialized
  bool get isInitialized => _isInitialized;

  /// Check if TFLite models are active (vs heuristic fallback)
  bool get isTfliteReady => _tfliteReady;

  /// Check if monitoring is active
  bool get isMonitoring => _isMonitoring;

  // =========================================================================
  // MONITORING
  // =========================================================================

  /// Start monitoring sensors and running inference
  void startMonitoring({
    Function(bool isAnomaly, double confidence)? onMotion,
    Function(bool isDistress, double confidence)? onNoise,
    Duration inferenceInterval = const Duration(milliseconds: 500),
    bool noiseEnabled = true,
  }) {
    if (!_isInitialized) {
      throw StateError('MLService not initialized. Call initialize() first.');
    }

    if (_isMonitoring) return;

    onMotionDetection = onMotion;
    onNoiseDetection = onNoise;
    _isMonitoring = true;

    // Subscribe to accelerometer
    _accelerometerSubscription = accelerometerEventStream().listen((event) {
      _ax = event.x;
      _ay = event.y;
      _az = event.z;
      _addSensorReading();
    });

    // Subscribe to gyroscope
    _gyroscopeSubscription = gyroscopeEventStream().listen((event) {
      _gx = event.x;
      _gy = event.y;
      _gz = event.z;
    });

    // Start periodic inference
    _inferenceTimer = Timer.periodic(inferenceInterval, (_) {
      _runInference();
    });

    // Start audio listening for noise detection
    // ALWAYS start audio when noiseEnabled — even if TFLite model not loaded.
    // The dB amplitude fallback fires via AudioService.onDistressByAmplitude.
    if (noiseEnabled && _audioService.isInitialized) {
      // Wire TFLite callback (only fires if model is loaded)
      _audioService.startListening(
        onFeatures: (spectrogramImage) {
          if (_noiseInterpreter != null) {
            _runTFLiteNoiseDetection(spectrogramImage, onNoise);
          }
        },
      );
      // Wire amplitude fallback (always active, even without TFLite)
      _audioService.onDistressByAmplitude = (rms) {
        if (!_isMonitoring) return;
        // Cooldown check
        final now = DateTime.now();
        if (_lastNoiseAlertTime != null &&
            now.difference(_lastNoiseAlertTime!) < _noiseAlertCooldown) {
          return;
        }
        _lastNoiseAlertTime = now;
        final confidence = ((rms + 1.0) / 1.0).clamp(0.0, 1.0);
        onNoise?.call(true, confidence);
      };
    }

    if (kDebugMode) {
      print(
          'ML monitoring started (${_tfliteReady ? "TFLite" : "heuristic"} mode)');
    }
  }

  /// Stop monitoring
  void stopMonitoring() {
    _isMonitoring = false;

    _accelerometerSubscription?.cancel();
    _accelerometerSubscription = null;

    _gyroscopeSubscription?.cancel();
    _gyroscopeSubscription = null;

    _inferenceTimer?.cancel();
    _inferenceTimer = null;

    _sensorBuffer.clear();

    // Stop audio listening
    _audioService.stopListening();

    if (kDebugMode) print('ML monitoring stopped');
  }

  // =========================================================================
  // SENSOR BUFFERING
  // =========================================================================

  /// Add current sensor reading to buffer
  void _addSensorReading() {
    _sensorBuffer.add([_ax, _ay, _az, _gx, _gy, _gz]);

    // Amortized trim: only trim when buffer exceeds 2x window size
    // This avoids O(n) removeAt(0) on every single sensor reading
    if (_sensorBuffer.length > motionWindowSize * 2) {
      _sensorBuffer.removeRange(0, _sensorBuffer.length - motionWindowSize);
    }
  }

  /// Inject accelerometer data from external source (e.g. BLE wearable).
  /// Gyroscope values default to 0 since most wearables only send accelerometer.
  void injectExternalAccelerometer(double x, double y, double z) {
    _ax = x;
    _ay = y;
    _az = z;
    _addSensorReading();
  }

  // =========================================================================
  // INFERENCE
  // =========================================================================

  /// Run inference on buffered data
  void _runInference() {
    if (!_isMonitoring || !_isInitialized) return;

    if (_sensorBuffer.length >= motionWindowSize) {
      if (_tfliteReady && _motionInterpreter != null) {
        _runTFLiteMotionDetection();
      } else {
        _runPlaceholderMotionDetection();
      }
    }
  }

  /// Run real TFLite motion detection inference
  void _runTFLiteMotionDetection() {
    try {
      // Take the most recent window from the buffer
      final start = _sensorBuffer.length - motionWindowSize;
      final input = List.generate(
        1,
        (_) => List.generate(
          motionWindowSize,
          (t) => List.generate(
            motionFeatures,
            (f) => _sensorBuffer[start + t][f],
          ),
        ),
      );

      // Output tensor: shape [1, 1] (sigmoid)
      final output = List.generate(1, (_) => List.filled(1, 0.0));

      // Run inference
      _motionInterpreter!.run(input, output);

      final score = output[0][0];
      final isAnomaly = score > 0.85;

      onMotionDetection?.call(isAnomaly, score);
    } catch (e) {
      if (kDebugMode) print('TFLite motion inference error: $e');
      _runPlaceholderMotionDetection();
    }
  }

  /// Run TFLite noise detection on mel-spectrogram image from AudioService.
  /// Input shape: [1, 256, 256, 3] (MobileNetV2 expects RGB).
  void _runTFLiteNoiseDetection(
    List<List<List<double>>> spectrogramImage,
    Function(bool isDistress, double confidence)? onNoise,
  ) {
    if (!_isMonitoring || _noiseInterpreter == null) return;

    try {
      // spectrogramImage is already [256, 256, 3], wrap in batch → [1, 256, 256, 3]
      final input = [spectrogramImage];

      final output = List.generate(1, (_) => List.filled(1, 0.0));
      _noiseInterpreter!.run(input, output);

      final score = output[0][0];
      // Higher threshold to reduce false positives
      final isDistress = score > 0.90;

      if (isDistress) {
        // Cooldown check
        final now = DateTime.now();
        if (_lastNoiseAlertTime != null &&
            now.difference(_lastNoiseAlertTime!) < _noiseAlertCooldown) {
          return;
        }
        _lastNoiseAlertTime = now;
      }

      onNoise?.call(isDistress, score);
    } catch (e) {
      if (kDebugMode) print('TFLite noise inference error: $e');
    }
  }

  /// Placeholder motion detection using simple threshold-based heuristic
  /// Used as fallback when TFLite fails to load
  void _runPlaceholderMotionDetection() {
    final magnitude = _calculateAccelerationMagnitude();

    // Simple fall detection heuristic:
    // - Normal activity: magnitude ~9.8 m/s² (gravity)
    // - Potential fall: sudden increase >25 m/s² (severe impact) or <3 m/s² (freefall)
    final isAnomaly = magnitude > 25.0 || magnitude < 3.0;
    final confidence = isAnomaly ? 0.7 : 0.3;

    onMotionDetection?.call(isAnomaly, confidence);
  }

  // =========================================================================
  // UTILITIES
  // =========================================================================

  /// Calculate current acceleration magnitude
  double _calculateAccelerationMagnitude() {
    return sqrt(_ax * _ax + _ay * _ay + _az * _az);
  }

  /// Get current sensor buffer for debugging
  List<List<double>> get sensorBuffer => List.unmodifiable(_sensorBuffer);

  /// Get buffer fill percentage
  double get bufferFillPercentage => _sensorBuffer.length / motionWindowSize;

  /// Current acceleration magnitude
  double get currentMagnitude => _calculateAccelerationMagnitude();

  /// Dispose of resources
  void dispose() {
    stopMonitoring();
    _audioService.dispose();
    _motionInterpreter?.close();
    _noiseInterpreter?.close();
    _motionInterpreter = null;
    _noiseInterpreter = null;
    _tfliteReady = false;
    _isInitialized = false;
  }
}

/// Detection result model
class DetectionResult {
  final DateTime timestamp;
  final DetectionType type;
  final bool isAnomaly;
  final double confidence;
  final Map<String, dynamic>? metadata;

  DetectionResult({
    required this.timestamp,
    required this.type,
    required this.isAnomaly,
    required this.confidence,
    this.metadata,
  });

  @override
  String toString() {
    return 'DetectionResult(type: $type, isAnomaly: $isAnomaly, confidence: ${confidence.toStringAsFixed(2)})';
  }
}

/// Type of detection
enum DetectionType {
  motion,
  noise,
}

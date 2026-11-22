import 'dart:async';
import 'dart:math';
// dart:typed_data types (Uint8List, Float64List, ByteData) are provided by flutter/foundation.dart

import 'package:flutter/foundation.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:fftea/fftea.dart';
import 'package:permission_handler/permission_handler.dart';

/// Service to capture microphone audio and extract mel-spectrogram images
/// compatible with the MobileNetV2-based noise_detection.tflite model.
///
/// Produces spectrogram images of shape [256, 256, 3] by:
/// 1. Computing STFT with nFft=1024, hopLength=125
/// 2. Applying a 256-bin mel filterbank
/// 3. Converting to log-dB scale and normalizing to [0, 1]
/// 4. Resizing to 256×256 and replicating across 3 RGB channels
///
/// Also broadcasts raw RMS amplitude (dB) via [amplitudeStream] for waveform UI
/// and fires [onDistressByAmplitude] as a fallback when TFLite is unavailable.
class AudioService {
  static final AudioService _instance = AudioService._internal();
  factory AudioService() => _instance;
  AudioService._internal();

  // Audio parameters — spectrogram generation for MobileNetV2 model
  static const int sampleRate = 16000;
  static const int duration = 2; // seconds
  static const int targetLength = sampleRate * duration; // 32000 samples
  static const int nFft = 1024; // FFT window size
  static const int hopLength = 125; // Hop between frames (~248 frames per 2s)
  static const int nMels = 256; // Mel frequency bins
  static const int spectrogramSize = 256; // Output image dimension (256×256×3)

  FlutterSoundRecorder? _recorder;
  StreamSubscription? _recorderSubscription;
  StreamController<Uint8List>? _streamController;

  // Audio sample buffer (accumulates PCM16 samples)
  final List<double> _audioBuffer = [];

  bool _isListening = false;
  bool _isInitialized = false;

  // Sustained-loudness counter for amplitude fallback
  int _consecutiveLoudChunks = 0;
  static const int _requiredLoudChunks = 6; // ~0.75s of sustained loud audio

  // Cooldown to prevent rapid-fire alerts
  DateTime? _lastDistressTime;
  static const Duration _distressCooldown = Duration(seconds: 10);

  // Precomputed Hamming window (nFft-length)
  late final Float64List _hammingWindow;

  // FFT instance
  late final FFT _fft;

  // Precomputed mel filterbank matrix [nMels × nBins]
  late final List<List<double>> _melFilterbank;

  // Callback for when spectrogram image is ready (TFLite path)
  Function(List<List<List<double>>> spectrogramImage)? _onFeaturesReady;

  // ── Amplitude / Waveform stream ──────────────────────────────────────────
  /// Broadcasts RMS amplitude in dB [-60, 0] range per audio chunk.
  /// Used for the live waveform visualizer in the ML test screen.
  final StreamController<double> _amplitudeController =
      StreamController<double>.broadcast();

  Stream<double> get amplitudeStream => _amplitudeController.stream;

  // Amplitude threshold for distress detection fallback.
  // Scale: -1.0 = silence, 0.0 = max loudness.
  // -0.15 requires genuinely loud sound (screams, crashes) closer to max.
  static const double distressDbThreshold = -0.15;

  /// Fallback callback — fired when amplitude exceeds [distressDbThreshold]
  /// regardless of whether the TFLite noise model is loaded.
  Function(double normalizedRms)? onDistressByAmplitude;

  // =========================================================================
  // INITIALIZATION
  // =========================================================================

  /// Initialize recorder, precompute Hamming window, FFT, and mel filterbank.
  Future<void> initialize() async {
    if (_isInitialized) return;

    final hasPermission = await requestPermission();
    if (!hasPermission) {
      if (kDebugMode) print('⚠️ Microphone permission denied during init');
      return;
    }

    // Precompute Hamming window for nFft
    _hammingWindow = Float64List(nFft);
    for (int i = 0; i < nFft; i++) {
      _hammingWindow[i] = 0.54 - 0.46 * cos(2 * pi * i / (nFft - 1));
    }

    // Initialize FFT for nFft=1024
    _fft = FFT(nFft);

    // Build mel filterbank
    _buildMelFilterbank();

    _recorder = FlutterSoundRecorder();
    await _recorder!.openRecorder();
    _isInitialized = true;

    if (kDebugMode) {
      print(
          '✅ AudioService initialized (spectrogram mode: ${spectrogramSize}x${spectrogramSize}x3)');
    }
  }

  bool get isListening => _isListening;
  bool get isInitialized => _isInitialized;

  // =========================================================================
  // MEL FILTERBANK
  // =========================================================================

  /// Convert Hz to Mel scale: m = 2595 * log10(1 + f/700)
  static double _hzToMel(double hz) => 2595.0 * log(1.0 + hz / 700.0) / ln10;

  /// Convert Mel scale to Hz: f = 700 * (10^(m/2595) - 1)
  static double _melToHz(double mel) =>
      700.0 * (pow(10.0, mel / 2595.0) - 1.0);

  /// Build triangular mel filterbank matrix [nMels × nBins].
  /// Each row is one triangular filter spanning the appropriate frequency range.
  void _buildMelFilterbank() {
    const nBins = nFft ~/ 2 + 1; // 513 for nFft=1024
    const double fMin = 0.0;
    const double fMax = sampleRate / 2.0; // 8000 Hz (Nyquist)

    final melMin = _hzToMel(fMin);
    final melMax = _hzToMel(fMax);

    // nMels + 2 equally spaced points on the mel scale
    final melPoints = List.generate(
        nMels + 2, (i) => melMin + i * (melMax - melMin) / (nMels + 1));

    // Convert mel points → Hz → FFT bin indices
    final bins = melPoints
        .map((m) => _melToHz(m))
        .map((hz) => ((nFft + 1) * hz / sampleRate).floor())
        .toList();

    // Build triangular filters
    _melFilterbank = List.generate(nMels, (m) {
      final filter = List<double>.filled(nBins, 0.0);
      final low = bins[m];
      final center = bins[m + 1];
      final high = bins[m + 2];

      // Rising slope: low → center
      if (center > low) {
        for (int k = low; k < center && k < nBins; k++) {
          if (k >= 0) filter[k] = (k - low) / (center - low);
        }
      }
      // Falling slope: center → high
      if (high > center) {
        for (int k = center; k < high && k < nBins; k++) {
          if (k >= 0) filter[k] = (high - k) / (high - center);
        }
      }

      return filter;
    });

    if (kDebugMode) {
      print('   Mel filterbank: $nMels filters × $nBins bins');
    }
  }

  // =========================================================================
  // PERMISSION
  // =========================================================================

  /// Request microphone permission
  Future<bool> requestPermission() async {
    final status = await Permission.microphone.request();
    return status.isGranted;
  }

  // =========================================================================
  // LISTENING
  // =========================================================================

  /// Start listening and call [onFeatures] with extracted spectrogram images
  /// of shape [256, 256, 3].
  Future<void> startListening({
    required Function(List<List<List<double>>> spectrogramImage) onFeatures,
  }) async {
    if (!_isInitialized) {
      // Attempt to initialize if not done yet
      await initialize();
      if (!_isInitialized) {
        throw StateError(
            'AudioService failed to initialize. Check permissions.');
      }
    }
    if (_isListening) return;

    _onFeaturesReady = onFeatures;
    _audioBuffer.clear();
    _consecutiveLoudChunks = 0;
    _isListening = true;

    // Create stream for PCM data
    _streamController = StreamController<Uint8List>();

    _recorderSubscription = _streamController!.stream.listen((data) {
      _processPCMChunk(data);
    }, onError: (e) {
      if (kDebugMode) print('AudioService stream error: $e');
    });

    // Start recording PCM16 to stream
    await _recorder!.startRecorder(
      toStream: _streamController!.sink,
      codec: Codec.pcm16,
      sampleRate: sampleRate,
      numChannels: 1,
    );

    if (kDebugMode) {
      print('🎙 Audio listening started (spectrogram mode)');
    }
  }

  // =========================================================================
  // PCM PROCESSING
  // =========================================================================

  /// Process incoming PCM16 byte chunks
  void _processPCMChunk(Uint8List data) {
    // Convert PCM16 bytes (little-endian) to normalized doubles
    final byteData =
        ByteData.view(data.buffer, data.offsetInBytes, data.lengthInBytes);
    final List<double> chunk = [];
    for (int i = 0; i < byteData.lengthInBytes - 1; i += 2) {
      final sample = byteData.getInt16(i, Endian.little);
      final normalized = sample / 32768.0;
      chunk.add(normalized);
      _audioBuffer.add(normalized);
    }

    // Compute RMS amplitude for waveform + fallback detection
    if (chunk.isNotEmpty) {
      final rms = _computeRms(chunk);
      if (!_amplitudeController.isClosed) {
        _amplitudeController.add(rms);
      }
      // Fallback distress detection: require SUSTAINED loud sound
      if (rms > distressDbThreshold) {
        _consecutiveLoudChunks++;
        if (_consecutiveLoudChunks >= _requiredLoudChunks) {
          _consecutiveLoudChunks = 0;
          // Check cooldown — don't fire again within 10 seconds
          final now = DateTime.now();
          if (_lastDistressTime == null ||
              now.difference(_lastDistressTime!) > _distressCooldown) {
            _lastDistressTime = now;
            onDistressByAmplitude?.call(rms);
          }
        }
      } else {
        // Reset counter if sound drops below threshold
        _consecutiveLoudChunks = 0;
      }
    }

    // Once we have enough samples for 2 seconds, extract spectrogram
    if (_audioBuffer.length >= targetLength) {
      final audioChunk = _audioBuffer.sublist(0, targetLength);
      _audioBuffer.removeRange(
          0, targetLength ~/ 2); // 50% overlap for continuity

      final image = _extractSpectrogramImage(audioChunk);
      if (image != null) {
        _onFeaturesReady?.call(image);
      }
    }
  }

  /// Compute normalized RMS (range roughly -1..0 in log scale; 0 = loudest)
  double _computeRms(List<double> samples) {
    if (samples.isEmpty) return -1.0;
    double sum = 0;
    for (final s in samples) {
      sum += s * s;
    }
    final rms = sqrt(sum / samples.length);
    // Convert to log scale: 0 = loudest, -1 = silence
    if (rms < 1e-9) return -1.0;
    // Normalize: clamp to [-1, 0] where 0 = full scale
    return (20 * log(rms) / ln10).clamp(-60.0, 0.0) / 60.0;
  }

  // =========================================================================
  // SPECTROGRAM EXTRACTION
  // =========================================================================

  /// Extract mel-spectrogram image of shape [spectrogramSize, spectrogramSize, 3].
  ///
  /// Pipeline:
  /// Audio → STFT (Hamming, nFft=1024, hop=125)
  ///       → Power spectrum |X(k)|²
  ///       → Mel filterbank (256 bins)
  ///       → Log-dB scale
  ///       → Normalize [0, 1]
  ///       → Nearest-neighbor resize to 256×256
  ///       → Replicate to 3 channels (grayscale → RGB)
  List<List<List<double>>>? _extractSpectrogramImage(List<double> audio) {
    try {
      const nBins = nFft ~/ 2 + 1; // 513
      final List<List<double>> melFrames = [];

      // ── Step 1: Compute STFT and apply mel filterbank per frame ──────────
      for (int i = 0; i <= audio.length - nFft; i += hopLength) {
        // Apply Hamming window
        final windowed = Float64List(nFft);
        for (int j = 0; j < nFft; j++) {
          windowed[j] = audio[i + j] * _hammingWindow[j];
        }

        // FFT → complex spectrum
        final spectrum = _fft.realFft(windowed);

        // Power spectrum |X(k)|²
        final power = List<double>.filled(nBins, 0.0);
        for (int k = 0; k < nBins && k < spectrum.length; k++) {
          final re = spectrum[k].x;
          final im = spectrum[k].y;
          power[k] = re * re + im * im;
        }

        // Apply mel filterbank → nMels energies per frame
        final melEnergies = List<double>.filled(nMels, 0.0);
        for (int m = 0; m < nMels; m++) {
          double s = 0.0;
          for (int k = 0; k < nBins; k++) {
            s += _melFilterbank[m][k] * power[k];
          }
          melEnergies[m] = s;
        }

        melFrames.add(melEnergies);
      }

      if (melFrames.isEmpty) return null;

      final nFrames = melFrames.length;

      // ── Step 2: Convert to log-dB scale (like librosa.power_to_db) ───────
      // spectrogram[mel_bin][time_step]
      final spectrogram = List.generate(
        nMels,
        (m) => List.generate(nFrames, (t) {
          final val = melFrames[t][m];
          return val > 1e-10 ? 10.0 * log(val) / ln10 : -100.0;
        }),
      );

      // ── Step 3: Find global min/max for normalization ────────────────────
      double minVal = double.infinity;
      double maxVal = double.negativeInfinity;
      for (int m = 0; m < nMels; m++) {
        for (int t = 0; t < nFrames; t++) {
          final v = spectrogram[m][t];
          if (v < minVal) minVal = v;
          if (v > maxVal) maxVal = v;
        }
      }
      final range = maxVal - minVal;

      // ── Step 4: Resize to spectrogramSize×spectrogramSize, create RGB ────
      // Rows = mel bins (low freq at bottom → flip vertically)
      // Cols = time frames
      // Replicate grayscale value to 3 channels for MobileNetV2 RGB input
      final image = List.generate(spectrogramSize, (row) {
        // Flip vertically: row 0 = highest mel bin
        final srcRow = ((spectrogramSize - 1 - row) * nMels / spectrogramSize)
            .floor()
            .clamp(0, nMels - 1);
        return List.generate(spectrogramSize, (col) {
          final srcCol =
              (col * nFrames / spectrogramSize).floor().clamp(0, nFrames - 1);
          final val = range > 0
              ? ((spectrogram[srcRow][srcCol] - minVal) / range).clamp(0.0, 1.0)
              : 0.0;
          return [val, val, val]; // grayscale → RGB
        });
      });

      return image;
    } catch (e) {
      if (kDebugMode) {
        print('Spectrogram extraction error: $e');
      }
      return null;
    }
  }

  // =========================================================================
  // STOP / DISPOSE
  // =========================================================================

  /// Stop listening
  Future<void> stopListening() async {
    if (!_isListening) return;

    _isListening = false;
    _onFeaturesReady = null;
    onDistressByAmplitude = null;

    try {
      await _recorder?.stopRecorder();
    } catch (e) {
      if (kDebugMode) {
        print('Error stopping recorder: $e');
      }
    }

    _recorderSubscription?.cancel();
    _recorderSubscription = null;
    _streamController?.close();
    _streamController = null;
    _audioBuffer.clear();

    if (kDebugMode) {
      print('🎙 Audio listening stopped');
    }
  }

  /// Dispose of all resources
  Future<void> dispose() async {
    await stopListening();
    await _recorder?.closeRecorder();
    _recorder = null;
    _isInitialized = false;
    await _amplitudeController.close();
  }
}

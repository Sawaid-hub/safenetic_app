import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:safenetic_app/services/audio_service.dart';
import 'package:safenetic_app/services/ml_service.dart';
import 'package:share_plus/share_plus.dart';

/// ML Test Screen for real-time sensor data visualization and training data collection.
///
/// Features:
/// - Live accelerometer and gyroscope readings
/// - Detection status and confidence levels
/// - Data recording with labels (Normal/Fall) for model training
/// - CSV export for training data
class MLTestScreen extends StatefulWidget {
  const MLTestScreen({super.key});

  @override
  State<MLTestScreen> createState() => _MLTestScreenState();
}

class _MLTestScreenState extends State<MLTestScreen> {
  final MLService _mlService = MLService();

  // Sensor data display
  double _ax = 0, _ay = 0, _az = 0;
  double _gx = 0, _gy = 0, _gz = 0;
  double _magnitude = 0;

  // Motion detection state
  bool _isAnomaly = false;
  double _confidence = 0;
  int _detectionCount = 0;

  // Noise detection state
  bool _isDistress = false;
  double _noiseConfidence = 0;
  int _noiseCount = 0;
  final List<double> _waveformHistory = List.filled(80, 0.0);
  StreamSubscription<double>? _amplitudeSub;
  final AudioService _audioService = AudioService();

  // UI state
  bool _isInitialized = false;
  bool _isMonitoring = false;
  String _statusMessage = 'Press Start to begin monitoring';

  // Recording state
  bool _isRecording = false;
  String _currentLabel = 'normal'; // 'normal' or 'fall'
  final List<RecordedSample> _recordedSamples = [];
  int _recordingSessionId = 0;
  // ignore: unused_field
  DateTime? _recordingStartTime;

  Timer? _uiUpdateTimer;
  Timer? _recordingTimer;
  final List<DetectionEvent> _recentEvents = [];

  @override
  void initState() {
    super.initState();
    _initializeML();
  }

  Future<void> _initializeML() async {
    try {
      await _mlService.initialize();
      setState(() {
        _isInitialized = true;
        _statusMessage = 'Ready to start monitoring';
      });
    } catch (e) {
      setState(() {
        _statusMessage = 'Error initializing ML: $e';
      });
    }
  }

  void _startMonitoring() {
    if (!_isInitialized) return;

    _mlService.startMonitoring(
      onMotion: (isAnomaly, confidence) {
        setState(() {
          _isAnomaly = isAnomaly;
          _confidence = confidence;

          if (isAnomaly) {
            _detectionCount++;
            _recentEvents.insert(
              0,
              DetectionEvent(
                timestamp: DateTime.now(),
                type: 'Motion Anomaly',
                confidence: confidence,
              ),
            );
            if (_recentEvents.length > 10) _recentEvents.removeLast();
          }
        });
      },
      onNoise: (isDistress, confidence) {
        setState(() {
          _isDistress = isDistress;
          _noiseConfidence = confidence;
          if (isDistress) {
            _noiseCount++;
            _recentEvents.insert(
              0,
              DetectionEvent(
                timestamp: DateTime.now(),
                type: 'Noise Distress',
                confidence: confidence,
              ),
            );
            if (_recentEvents.length > 10) _recentEvents.removeLast();
          }
        });
      },
    );

    // Subscribe to amplitude stream for waveform visualization
    _amplitudeSub?.cancel();
    _amplitudeSub = _audioService.amplitudeStream.listen((amp) {
      if (!mounted) return;
      setState(() {
        _waveformHistory.removeAt(0);
        _waveformHistory.add(amp);
      });
    });

    // Start UI update timer
    _uiUpdateTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!mounted) return;

      final buffer = _mlService.sensorBuffer;
      if (buffer.isNotEmpty) {
        final latest = buffer.last;
        setState(() {
          _ax = latest[0];
          _ay = latest[1];
          _az = latest[2];
          _gx = latest[3];
          _gy = latest[4];
          _gz = latest[5];
          _magnitude = _mlService.currentMagnitude;
        });
      }
    });

    setState(() {
      _isMonitoring = true;
      _statusMessage = 'Monitoring active...';
    });
  }

  void _stopMonitoring() {
    _mlService.stopMonitoring();
    _uiUpdateTimer?.cancel();
    _uiUpdateTimer = null;
    _amplitudeSub?.cancel();
    _amplitudeSub = null;
    _stopRecording();

    setState(() {
      _isMonitoring = false;
      _statusMessage = 'Monitoring stopped';
      _isDistress = false;
      _noiseConfidence = 0;
    });
  }

  // Recording functions
  void _startRecording(String label) {
    if (!_isMonitoring) return;

    setState(() {
      _isRecording = true;
      _currentLabel = label;
      _recordingSessionId++;
      _recordingStartTime = DateTime.now();
    });

    // Record samples at 50Hz (20ms interval)
    _recordingTimer = Timer.periodic(const Duration(milliseconds: 20), (_) {
      if (!_isRecording || !mounted) return;

      _recordedSamples.add(RecordedSample(
        timestamp: DateTime.now(),
        sessionId: _recordingSessionId,
        label: _currentLabel,
        ax: _ax,
        ay: _ay,
        az: _az,
        gx: _gx,
        gy: _gy,
        gz: _gz,
        magnitude: _magnitude,
      ));

      // Update UI periodically
      if (_recordedSamples.length % 50 == 0) {
        setState(() {});
      }
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Recording ${label.toUpperCase()} activity...'),
        backgroundColor:
            label == 'fall' ? Colors.redAccent : Colors.greenAccent,
        duration: const Duration(seconds: 1),
      ),
    );
  }

  void _stopRecording() {
    _recordingTimer?.cancel();
    _recordingTimer = null;

    if (_isRecording) {
      setState(() {
        _isRecording = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Stopped recording. Total samples: ${_recordedSamples.length}'),
          backgroundColor: Colors.grey[800],
        ),
      );
    }
  }

  Future<void> _exportToCsv() async {
    if (_recordedSamples.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('No data to export. Record some samples first.')),
      );
      return;
    }

    try {
      // Create CSV content
      final buffer = StringBuffer();
      buffer.writeln('timestamp,session_id,label,ax,ay,az,gx,gy,gz,magnitude');

      for (final sample in _recordedSamples) {
        buffer.writeln(
          '${sample.timestamp.toIso8601String()},'
          '${sample.sessionId},'
          '${sample.label},'
          '${sample.ax.toStringAsFixed(6)},'
          '${sample.ay.toStringAsFixed(6)},'
          '${sample.az.toStringAsFixed(6)},'
          '${sample.gx.toStringAsFixed(6)},'
          '${sample.gy.toStringAsFixed(6)},'
          '${sample.gz.toStringAsFixed(6)},'
          '${sample.magnitude.toStringAsFixed(6)}',
        );
      }

      // Save to file
      final directory = await getApplicationDocumentsDirectory();
      final timestamp =
          DateTime.now().toIso8601String().replaceAll(':', '-').split('.')[0];
      final file = File('${directory.path}/sensor_data_$timestamp.csv');
      await file.writeAsString(buffer.toString());

      // Share the file
      await Share.shareXFiles(
        [XFile(file.path)],
        text: 'Sensor training data (${_recordedSamples.length} samples)',
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Exported ${_recordedSamples.length} samples to CSV'),
          backgroundColor: Colors.greenAccent,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Export failed: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  void _clearRecordedData() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2C2C2C),
        title: const Text('Clear All Data?',
            style: TextStyle(color: Colors.white)),
        content: Text(
          'This will delete ${_recordedSamples.length} recorded samples.',
          style: const TextStyle(color: Colors.grey),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () {
              setState(() {
                _recordedSamples.clear();
                _recordingSessionId = 0;
              });
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('All recorded data cleared')),
              );
            },
            child:
                const Text('Clear', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _uiUpdateTimer?.cancel();
    _recordingTimer?.cancel();
    _amplitudeSub?.cancel();
    _mlService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1E1E1E),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'ML Sensor Test',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (_recordedSamples.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.share, color: Colors.white),
              onPressed: _exportToCsv,
              tooltip: 'Export CSV',
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Status Card
            _buildStatusCard(),
            const SizedBox(height: 20),

            // Recording Controls
            _buildRecordingSection(),
            const SizedBox(height: 20),

            // Motion Detection Indicator
            _buildDetectionIndicator(),
            const SizedBox(height: 20),

            // Audio Waveform
            _buildWaveformPanel(),
            const SizedBox(height: 20),

            // Noise Detection Panel
            _buildNoisePanel(),
            const SizedBox(height: 20),

            // Sensor Data Cards
            _buildSensorDataSection(),
            const SizedBox(height: 20),

            // Buffer Progress
            _buildBufferProgress(),
            const SizedBox(height: 20),

            // Control Buttons
            _buildControlButtons(),
            const SizedBox(height: 20),

            // Recent Events
            _buildRecentEvents(),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF2C2C2C),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _isRecording
              ? Colors.orangeAccent.withValues(alpha: 0.5)
              : _isMonitoring
                  ? Colors.greenAccent.withValues(alpha: 0.3)
                  : Colors.grey.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _isRecording
                  ? Colors.orangeAccent
                  : _isMonitoring
                      ? Colors.greenAccent
                      : Colors.grey,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _isRecording
                      ? 'Recording: ${_currentLabel.toUpperCase()}'
                      : _statusMessage,
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                ),
                Text(
                  _isRecording
                      ? '${_recordedSamples.length} samples collected'
                      : _isInitialized
                          ? 'ML Service Ready'
                          : 'Initializing...',
                  style: TextStyle(color: Colors.grey[400], fontSize: 12),
                ),
              ],
            ),
          ),
          if (_isRecording)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.redAccent,
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.fiber_manual_record,
                      color: Colors.white, size: 12),
                  SizedBox(width: 4),
                  Text('REC',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildRecordingSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF2C2C2C),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.orangeAccent.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.save_alt, color: Colors.orangeAccent, size: 20),
              const SizedBox(width: 8),
              const Text(
                'Data Recording',
                style: TextStyle(
                    color: Colors.orangeAccent,
                    fontSize: 16,
                    fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              Text(
                '${_recordedSamples.length} samples',
                style: TextStyle(color: Colors.grey[400], fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'Record labeled data for training. Hold button while performing the activity.',
            style: TextStyle(color: Colors.grey, fontSize: 12),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTapDown: (_) => _isMonitoring && !_isRecording
                      ? _startRecording('normal')
                      : null,
                  onTapUp: (_) => _stopRecording(),
                  onTapCancel: () => _stopRecording(),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    decoration: BoxDecoration(
                      color: _isRecording && _currentLabel == 'normal'
                          ? Colors.greenAccent
                          : Colors.greenAccent.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.greenAccent),
                    ),
                    child: Column(
                      children: [
                        Icon(
                          Icons.directions_walk,
                          color: _isRecording && _currentLabel == 'normal'
                              ? Colors.black
                              : Colors.greenAccent,
                          size: 28,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'NORMAL',
                          style: TextStyle(
                            color: _isRecording && _currentLabel == 'normal'
                                ? Colors.black
                                : Colors.greenAccent,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'Hold to record',
                          style: TextStyle(
                            color: _isRecording && _currentLabel == 'normal'
                                ? Colors.black54
                                : Colors.grey,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: GestureDetector(
                  onTapDown: (_) => _isMonitoring && !_isRecording
                      ? _startRecording('fall')
                      : null,
                  onTapUp: (_) => _stopRecording(),
                  onTapCancel: () => _stopRecording(),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    decoration: BoxDecoration(
                      color: _isRecording && _currentLabel == 'fall'
                          ? Colors.redAccent
                          : Colors.redAccent.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.redAccent),
                    ),
                    child: Column(
                      children: [
                        Icon(
                          Icons.warning_rounded,
                          color: _isRecording && _currentLabel == 'fall'
                              ? Colors.white
                              : Colors.redAccent,
                          size: 28,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'FALL',
                          style: TextStyle(
                            color: _isRecording && _currentLabel == 'fall'
                                ? Colors.white
                                : Colors.redAccent,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'Hold to record',
                          style: TextStyle(
                            color: _isRecording && _currentLabel == 'fall'
                                ? Colors.white70
                                : Colors.grey,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (_recordedSamples.isNotEmpty) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _exportToCsv,
                    icon: const Icon(Icons.download, size: 18),
                    label: const Text('Export CSV'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.orangeAccent,
                      side: const BorderSide(color: Colors.orangeAccent),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: _clearRecordedData,
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('Clear'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.grey,
                    side: const BorderSide(color: Colors.grey),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _buildRecordingStats(),
          ],
        ],
      ),
    );
  }

  Widget _buildRecordingStats() {
    final normalCount =
        _recordedSamples.where((s) => s.label == 'normal').length;
    final fallCount = _recordedSamples.where((s) => s.label == 'fall').length;

    return Row(
      children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.greenAccent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              children: [
                Text('$normalCount',
                    style: const TextStyle(
                        color: Colors.greenAccent,
                        fontWeight: FontWeight.bold,
                        fontSize: 18)),
                const Text('Normal',
                    style: TextStyle(color: Colors.grey, fontSize: 10)),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.redAccent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              children: [
                Text('$fallCount',
                    style: const TextStyle(
                        color: Colors.redAccent,
                        fontWeight: FontWeight.bold,
                        fontSize: 18)),
                const Text('Fall',
                    style: TextStyle(color: Colors.grey, fontSize: 10)),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.grey.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              children: [
                Text('$_recordingSessionId',
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 18)),
                const Text('Sessions',
                    style: TextStyle(color: Colors.grey, fontSize: 10)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDetectionIndicator() {
    final indicatorColor = _isAnomaly ? Colors.redAccent : Colors.greenAccent;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF2C2C2C),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: indicatorColor.withValues(alpha: 0.5),
          width: 2,
        ),
      ),
      child: Column(
        children: [
          Icon(
            _isAnomaly ? Icons.warning_rounded : Icons.check_circle,
            size: 64,
            color: indicatorColor,
          ),
          const SizedBox(height: 12),
          Text(
            _isAnomaly ? 'ANOMALY DETECTED!' : 'NORMAL',
            style: TextStyle(
              color: indicatorColor,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Confidence: ${(_confidence * 100).toStringAsFixed(1)}%',
            style: const TextStyle(color: Colors.white, fontSize: 16),
          ),
          const SizedBox(height: 4),
          Text(
            'Detections: $_detectionCount',
            style: TextStyle(color: Colors.grey[400], fontSize: 14),
          ),
        ],
      ),
    );
  }

  // ── Waveform Panel ──────────────────────────────────────────────────────

  Widget _buildWaveformPanel() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF2C2C2C),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.cyanAccent.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.graphic_eq_rounded,
                  color: Colors.cyanAccent, size: 20),
              const SizedBox(width: 8),
              const Text(
                'Live Microphone',
                style: TextStyle(
                    color: Colors.cyanAccent,
                    fontSize: 16,
                    fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _isMonitoring
                      ? Colors.cyanAccent.withValues(alpha: 0.15)
                      : Colors.grey.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _isMonitoring ? 'LIVE' : 'IDLE',
                  style: TextStyle(
                    color: _isMonitoring ? Colors.cyanAccent : Colors.grey,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 80,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: CustomPaint(
                painter: _WaveformPainter(
                  samples: _waveformHistory,
                  color: _isMonitoring ? Colors.cyanAccent : Colors.grey,
                ),
                child: const SizedBox.expand(),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _isMonitoring
                ? 'Capturing audio at 16 kHz · FFT [40×87]'
                : 'Start monitoring to see audio waveform',
            style:
                TextStyle(color: Colors.grey[500], fontSize: 11),
          ),
        ],
      ),
    );
  }

  // ── Noise Detection Panel ────────────────────────────────────────────────

  Widget _buildNoisePanel() {
    final noiseColor = _isDistress ? Colors.redAccent : Colors.greenAccent;
    final noiseLabel = _isDistress ? 'DISTRESS DETECTED' : 'AMBIENT / NORMAL';
    final pct = (_noiseConfidence * 100).clamp(0.0, 100.0);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF2C2C2C),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: noiseColor.withValues(alpha: 0.4), width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                _isDistress
                    ? Icons.warning_amber_rounded
                    : Icons.hearing_rounded,
                color: noiseColor,
                size: 20,
              ),
              const SizedBox(width: 8),
              const Text(
                'Noise Detection',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              Text(
                '$_noiseCount detections',
                style: TextStyle(color: Colors.grey[400], fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              // Status badge
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: noiseColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                  border:
                      Border.all(color: noiseColor.withValues(alpha: 0.5)),
                ),
                child: Text(
                  noiseLabel,
                  style: TextStyle(
                    color: noiseColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
              const Spacer(),
              // Confidence value
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${pct.toStringAsFixed(1)}%',
                    style: TextStyle(
                      color: noiseColor,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    'confidence',
                    style:
                        TextStyle(color: Colors.grey[500], fontSize: 11),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Confidence bar
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: _noiseConfidence.clamp(0.0, 1.0),
              backgroundColor: Colors.grey[800],
              valueColor: AlwaysStoppedAnimation<Color>(noiseColor),
              minHeight: 8,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _mlService.isTfliteReady
                ? '🧠 TFLite noise_detection.tflite active'
                : '📊 dB amplitude fallback active (model not loaded)',
            style: TextStyle(color: Colors.grey[500], fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _buildSensorDataSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Sensor Data',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),

        // Accelerometer
        _buildSensorCard(
          'Accelerometer (m/s²)',
          Icons.speed,
          Colors.blueAccent,
          [
            _SensorValue('X', _ax),
            _SensorValue('Y', _ay),
            _SensorValue('Z', _az),
            _SensorValue('Mag', _magnitude),
          ],
        ),
        const SizedBox(height: 12),

        // Gyroscope
        _buildSensorCard(
          'Gyroscope (rad/s)',
          Icons.rotate_right,
          Colors.purpleAccent,
          [
            _SensorValue('X', _gx),
            _SensorValue('Y', _gy),
            _SensorValue('Z', _gz),
          ],
        ),
      ],
    );
  }

  Widget _buildSensorCard(
      String title, IconData icon, Color color, List<_SensorValue> values) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF2C2C2C),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Text(title, style: TextStyle(color: color, fontSize: 14)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: values
                .map((v) => Expanded(
                      child: Column(
                        children: [
                          Text(v.label,
                              style: TextStyle(
                                  color: Colors.grey[400], fontSize: 12)),
                          const SizedBox(height: 4),
                          Text(
                            v.value.toStringAsFixed(2),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ],
                      ),
                    ))
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildBufferProgress() {
    final fillPercent = _mlService.bufferFillPercentage;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF2C2C2C),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Data Buffer',
                style: TextStyle(color: Colors.white, fontSize: 14),
              ),
              Text(
                '${(fillPercent * 100).toStringAsFixed(0)}%',
                style: const TextStyle(color: Colors.greenAccent, fontSize: 14),
              ),
            ],
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: fillPercent,
            backgroundColor: Colors.grey[800],
            valueColor: AlwaysStoppedAnimation<Color>(
              fillPercent >= 1.0 ? Colors.greenAccent : Colors.orangeAccent,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${_mlService.sensorBuffer.length} / ${MLService.motionWindowSize} samples',
            style: TextStyle(color: Colors.grey[400], fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildControlButtons() {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed:
                (_isInitialized && !_isMonitoring) ? _startMonitoring : null,
            icon: const Icon(Icons.play_arrow),
            label: const Text('Start'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.greenAccent,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ElevatedButton.icon(
            onPressed: _isMonitoring ? _stopMonitoring : null,
            icon: const Icon(Icons.stop),
            label: const Text('Stop'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF5252),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRecentEvents() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Recent Detections',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (_recentEvents.isNotEmpty)
              TextButton(
                onPressed: () {
                  setState(() {
                    _recentEvents.clear();
                    _detectionCount = 0;
                  });
                },
                child:
                    const Text('Clear', style: TextStyle(color: Colors.grey)),
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (_recentEvents.isEmpty)
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFF2C2C2C),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Text(
                'No detections yet.\nStart monitoring and shake your device to trigger detection.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey[400]),
              ),
            ),
          )
        else
          ..._recentEvents.take(5).map((event) => Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF2C2C2C),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: Colors.redAccent.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning,
                        color: Colors.redAccent, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            event.type,
                            style: const TextStyle(
                                color: Colors.white, fontSize: 14),
                          ),
                          Text(
                            '${event.timestamp.hour.toString().padLeft(2, '0')}:${event.timestamp.minute.toString().padLeft(2, '0')}:${event.timestamp.second.toString().padLeft(2, '0')}',
                            style: TextStyle(
                                color: Colors.grey[400], fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      '${(event.confidence * 100).toStringAsFixed(0)}%',
                      style: const TextStyle(
                          color: Colors.redAccent, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              )),
      ],
    );
  }
}

/// CustomPainter that draws a scrolling bar-chart waveform from RMS amplitude history.
/// [samples] is a list of normalized values in [-1, 0] where 0 = loudest.
class _WaveformPainter extends CustomPainter {
  final List<double> samples;
  final Color color;

  _WaveformPainter({required this.samples, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: 0.8)
      ..strokeCap = StrokeCap.round;

    // Background
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = const Color(0xFF1A1A1A),
    );

    // Center line
    canvas.drawLine(
      Offset(0, size.height / 2),
      Offset(size.width, size.height / 2),
      Paint()
        ..color = color.withValues(alpha: 0.15)
        ..strokeWidth = 1,
    );

    if (samples.isEmpty) return;

    final barWidth = (size.width / samples.length) - 1;
    for (int i = 0; i < samples.length; i++) {
      // samples[i] in [-1, 0] → 0 = loud, -1 = silent
      // Convert to [0, 1] height fraction
      final fraction = (samples[i] + 1.0).clamp(0.0, 1.0);
      final barHeight = max(2.0, fraction * size.height * 0.9);
      final x = i * (barWidth + 1);
      final top = (size.height - barHeight) / 2;

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, top, barWidth, barHeight),
          const Radius.circular(2),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_WaveformPainter oldDelegate) =>
      oldDelegate.samples != samples || oldDelegate.color != color;
}

class _SensorValue {
  final String label;
  final double value;

  _SensorValue(this.label, this.value);
}

class DetectionEvent {
  final DateTime timestamp;
  final String type;
  final double confidence;

  DetectionEvent({
    required this.timestamp,
    required this.type,
    required this.confidence,
  });
}

class RecordedSample {
  final DateTime timestamp;
  final int sessionId;
  final String label;
  final double ax, ay, az;
  final double gx, gy, gz;
  final double magnitude;

  RecordedSample({
    required this.timestamp,
    required this.sessionId,
    required this.label,
    required this.ax,
    required this.ay,
    required this.az,
    required this.gx,
    required this.gy,
    required this.gz,
    required this.magnitude,
  });
}

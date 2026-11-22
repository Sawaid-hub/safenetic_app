import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:location/location.dart';
import 'package:safenetic_app/services/location_helper.dart';
import 'package:safenetic_app/services/notification_service.dart';
import 'package:safenetic_app/models/guardian_model.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../constants/app_colors.dart';
import '../constants/app_constants.dart';
import '../constants/app_text_styles.dart';

class AlertSentScreen extends StatefulWidget {
  final LatLng? currentLocation;
  final LocationData? locationData;
  final double sosDelaySeconds;
  final String alertType; // 'manual' or 'fall'
  final String userName;

  // List of guardians passed from HomeScreen
  final List<Map<String, dynamic>> guardians;

  const AlertSentScreen({
    super.key,
    this.currentLocation,
    this.locationData,
    this.sosDelaySeconds = 10.0,
    this.guardians = const [],
    this.alertType = 'manual',
    this.userName = 'User',
  });

  @override
  State<AlertSentScreen> createState() => _AlertSentScreenState();
}

class _AlertSentScreenState extends State<AlertSentScreen> {
  String _locationStatus = "Initializing GPS...";
  LocationData? _currentPosition;
  bool _isLoading = true;

  // Timer State
  late int _secondsRemaining;
  Timer? _timer;
  bool _isAlertSent = false;

  // Notification tracking
  final Map<String, String> _guardianStatuses = {}; // name → status
  bool _isSendingNotifications = false;
  String _deliverySummary = 'Preparing emergency channels...';

  @override
  void initState() {
    super.initState();
    // Initialize countdown with value passed from Home
    _secondsRemaining = widget.sosDelaySeconds.toInt();
    if (_secondsRemaining < 0) _secondsRemaining = 0;

    // Start the countdown immediately
    _startCountdown();
  }

  void _startCountdown() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          if (_secondsRemaining > 0) {
            _secondsRemaining--;
          } else {
            _timer?.cancel();
            _triggerAlert(); // Timer finished, send alert
          }
        });
      }
    });
  }

  void _triggerAlert() {
    setState(() {
      _isAlertSent = true;
      _isSendingNotifications = true;
      _deliverySummary = 'Contacting guardians...';
      // Mark all guardians as "Sending..."
      for (final g in widget.guardians) {
        _guardianStatuses[g['name'] ?? 'Unknown'] = 'Sending...';
      }
    });

    // Fetch location first, then send notifications
    if (widget.locationData != null && mounted) {
      setState(() {
        _currentPosition = widget.locationData;
        _locationStatus =
            "Location Shared: ${widget.locationData!.latitude?.toStringAsFixed(4) ?? 'N/A'}, ${widget.locationData!.longitude?.toStringAsFixed(4) ?? 'N/A'}";
        _isLoading = false;
      });
      _sendNotifications();
    } else {
      _fetchLocation().then((_) => _sendNotifications());
    }
  }

  Future<void> _sendNotifications() async {
    // Convert guardian maps back to models for the service
    final guardianModels =
        widget.guardians.map((g) => GuardianModel.fromMap(g)).toList();

    try {
      final result = await NotificationService.instance.sendEmergencyAlerts(
        guardians: guardianModels,
        locationData: _currentPosition,
        userName: widget.userName,
        alertType: widget.alertType,
      );

      if (!mounted) return;
      setState(() {
        _isSendingNotifications = false;
        _deliverySummary = result.deliverySummary;
        result.smsStatuses.forEach((name, status) {
          switch (status) {
            case 'sent':
              _guardianStatuses[name] = 'SMS Sent ✓';
              break;
            case 'no_phone':
              _guardianStatuses[name] = 'No phone number';
              break;
            case 'no_permission':
              _guardianStatuses[name] = 'SMS permission denied';
              break;
            case 'intent_fallback':
              _guardianStatuses[name] = 'SMS app opened — send manually';
              break;
            default:
              _guardianStatuses[name] = 'Failed to send';
          }
        });
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSendingNotifications = false;
        _deliverySummary =
            'Delivery result could not be confirmed. Check your alert history.';
        for (final name in _guardianStatuses.keys.toList()) {
          if (_guardianStatuses[name] == 'Sending...') {
            _guardianStatuses[name] = 'Delivery not confirmed';
          }
        }
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _fetchLocation() async {
    try {
      LocationData locationData = await LocationHelper.determinePosition();

      if (mounted) {
        setState(() {
          _currentPosition = locationData;
          _locationStatus =
              "Location Shared: ${locationData.latitude?.toStringAsFixed(4) ?? 'N/A'}, ${locationData.longitude?.toStringAsFixed(4) ?? 'N/A'}";
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _locationStatus = "Error: ${e.toString()}";
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          // 1. Map Background (Only visible AFTER alert is sent)
          Positioned.fill(
            child: _isAlertSent && _currentPosition != null
                ? GoogleMap(
                    initialCameraPosition: CameraPosition(
                      target: LatLng(_currentPosition!.latitude!,
                          _currentPosition!.longitude!),
                      zoom: 16.0,
                    ),
                    markers: {
                      Marker(
                        markerId: const MarkerId('emergency_location'),
                        position: LatLng(_currentPosition!.latitude!,
                            _currentPosition!.longitude!),
                        icon: BitmapDescriptor.defaultMarkerWithHue(
                            BitmapDescriptor.hueRed),
                        infoWindow:
                            const InfoWindow(title: 'Emergency Location'),
                      ),
                    },
                    myLocationEnabled: true,
                    myLocationButtonEnabled: false,
                    compassEnabled: false,
                    mapToolbarEnabled: false,
                    zoomControlsEnabled: false,
                    tiltGesturesEnabled: false,
                    zoomGesturesEnabled: false,
                    style: '''
                      [
                        {
                          "elementType": "geometry",
                          "stylers": [
                            {
                              "color": "#1e1e1e"
                            }
                          ]
                        },
                        {
                          "elementType": "labels.icon",
                          "stylers": [
                            {
                              "visibility": "off"
                            }
                          ]
                        },
                        {
                          "elementType": "labels.text.fill",
                          "stylers": [
                            {
                              "color": "#757575"
                            }
                          ]
                        },
                        {
                          "elementType": "labels.text.stroke",
                          "stylers": [
                            {
                              "color": "#1e1e1e"
                            }
                          ]
                        },
                        {
                          "featureType": "administrative",
                          "elementType": "geometry",
                          "stylers": [
                            {
                              "color": "#757575"
                            }
                          ]
                        },
                        {
                          "featureType": "administrative.country",
                          "elementType": "labels.text.fill",
                          "stylers": [
                            {
                              "color": "#9e9e9e"
                            }
                          ]
                        },
                        {
                          "featureType": "administrative.land_parcel",
                          "stylers": [
                            {
                              "visibility": "off"
                            }
                          ]
                        },
                        {
                          "featureType": "administrative.locality",
                          "elementType": "labels.text.fill",
                          "stylers": [
                            {
                              "color": "#bdbdbd"
                            }
                          ]
                        },
                        {
                          "featureType": "poi",
                          "elementType": "labels.text.fill",
                          "stylers": [
                            {
                              "color": "#757575"
                            }
                          ]
                        },
                        {
                          "featureType": "poi.park",
                          "elementType": "geometry",
                          "stylers": [
                            {
                              "color": "#181818"
                            }
                          ]
                        },
                        {
                          "featureType": "poi.park",
                          "elementType": "labels.text.fill",
                          "stylers": [
                            {
                              "color": "#616161"
                            }
                          ]
                        },
                        {
                          "featureType": "poi.park",
                          "elementType": "labels.text.stroke",
                          "stylers": [
                            {
                              "color": "#1b1b1b"
                            }
                          ]
                        },
                        {
                          "featureType": "road",
                          "elementType": "geometry.fill",
                          "stylers": [
                            {
                              "color": "#2c2c2c"
                            }
                          ]
                        },
                        {
                          "featureType": "road",
                          "elementType": "labels.text.fill",
                          "stylers": [
                            {
                              "color": "#8a8a8a"
                            }
                          ]
                        },
                        {
                          "featureType": "road.arterial",
                          "elementType": "geometry",
                          "stylers": [
                            {
                              "color": "#373737"
                            }
                          ]
                        },
                        {
                          "featureType": "road.highway",
                          "elementType": "geometry",
                          "stylers": [
                            {
                              "color": "#3c3c3c"
                            }
                          ]
                        },
                        {
                          "featureType": "road.highway.controlled_access",
                          "elementType": "geometry",
                          "stylers": [
                            {
                              "color": "#4e4e4e"
                            }
                          ]
                        },
                        {
                          "featureType": "road.local",
                          "elementType": "labels.text.fill",
                          "stylers": [
                            {
                              "color": "#616161"
                            }
                          ]
                        },
                        {
                          "featureType": "transit",
                          "elementType": "labels.text.fill",
                          "stylers": [
                            {
                              "color": "#757575"
                            }
                          ]
                        },
                        {
                          "featureType": "water",
                          "elementType": "geometry",
                          "stylers": [
                            {
                              "color": "#000000"
                            }
                          ]
                        },
                        {
                          "featureType": "water",
                          "elementType": "labels.text.fill",
                          "stylers": [
                            {
                              "color": "#3d3d3d"
                            }
                          ]
                        }
                      ]
                    ''',
                  )
                : Container(
                    color: AppColors.surfaceLight,
                    child: Stack(
                      children: [
                        // Grid lines for sci-fi effect
                        ...List.generate(
                            10,
                            (index) => Positioned(
                                  top: index * 80.0,
                                  left: 0,
                                  right: 0,
                                  child: Container(
                                      height: 1,
                                      // ignore: deprecated_member_use
                                      color: Colors.white.withOpacity(0.05)),
                                )),
                        ...List.generate(
                            6,
                            (index) => Positioned(
                                  left: index * 80.0,
                                  top: 0,
                                  bottom: 0,
                                  child: Container(
                                      width: 1,
                                      // ignore: deprecated_member_use
                                      color: Colors.white.withOpacity(0.05)),
                                )),

                        // Center Pulse (Orange during countdown, Red after)
                        Center(
                            child: _buildPulsingLocationMarker(
                          color: _isAlertSent
                              ? AppColors.primary
                              : AppColors.warning,
                        )),
                      ],
                    ),
                  ),
          ),

          // 2. Top Status Bar (Only visible AFTER alert is sent)
          if (_isAlertSent)
            SafeArea(
              child: Align(
                alignment: Alignment.topCenter,
                child: Container(
                  margin: const EdgeInsets.all(AppConstants.spacing20),
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppConstants.spacing20,
                      vertical: AppConstants.spacing16),
                  decoration: BoxDecoration(
                    color: _isLoading ? AppColors.warning : AppColors.primary,
                    borderRadius:
                        BorderRadius.circular(AppConstants.radiusXLarge),
                    boxShadow: [
                      BoxShadow(
                        // ignore: deprecated_member_use
                        color: Colors.black.withOpacity(0.2),
                        blurRadius: 10,
                        spreadRadius: 2,
                      )
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_isLoading)
                        const SizedBox(
                            width: 15,
                            height: 15,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                      else
                        const Icon(Icons.my_location,
                            color: Colors.white, size: 20),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Text(
                          _currentPosition != null
                              ? "GPS: ${_currentPosition!.latitude?.toStringAsFixed(4) ?? 'N/A'}, ${_currentPosition!.longitude?.toStringAsFixed(4) ?? 'N/A'}"
                              : _locationStatus,
                          style: AppTextStyles.labelLarge
                              .copyWith(color: AppColors.textOnPrimary),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // 3. Bottom Control Panel
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppConstants.spacing24),
              decoration: const BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.vertical(
                    top: Radius.circular(AppConstants.radiusXLarge)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black45,
                    blurRadius: 20,
                    offset: Offset(0, -5),
                  )
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // --- COUNTDOWN UI (Shown when _isAlertSent is false) ---
                  if (!_isAlertSent) ...[
                    Center(
                      child: Column(
                        children: [
                          Text(
                            "SENDING SOS IN",
                            style: AppTextStyles.labelLarge.copyWith(
                                letterSpacing: 2, color: AppColors.textHint),
                          ),
                          const SizedBox(height: AppConstants.spacing12),
                          Text(
                            "$_secondsRemaining",
                            style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 64, // Big text for countdown
                                fontWeight: FontWeight.w900),
                          ),
                          const SizedBox(height: AppConstants.spacing12),
                          // Visual progress bar for urgency
                          LinearProgressIndicator(
                            value: (widget.sosDelaySeconds > 0)
                                ? _secondsRemaining / widget.sosDelaySeconds
                                : 0,
                            color: AppColors.warning,
                            backgroundColor: AppColors.surfaceLight,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 40),
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton(
                        onPressed: () {
                          // CANCEL LOGIC
                          _timer?.cancel();
                          context.pop(); // Go back without sending
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          side: const BorderSide(color: AppColors.border),
                          shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(AppConstants.radiusLarge),
                          ),
                        ),
                        child: Text(
                          "CANCEL ALERT",
                          style: AppTextStyles.button
                              .copyWith(color: AppColors.textPrimary),
                        ),
                      ),
                    ),
                  ]

                  // --- ALERT SENT UI (Shown when timer finishes) ---
                  else ...[
                    const Text(
                      "Emergency Active",
                      style: AppTextStyles.h2,
                    ),
                    const SizedBox(height: AppConstants.spacing8),
                    Text(
                      _isSendingNotifications
                          ? 'Contacting emergency channels...'
                          : _deliverySummary,
                      style: AppTextStyles.bodyMedium
                          .copyWith(color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 25),

                    // Display the dynamic guardians passed from Home
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 200),
                      child: SingleChildScrollView(
                        child: Column(
                          children: widget.guardians.isNotEmpty
                              ? widget.guardians.map((g) {
                                  final name = g['name'] ?? 'Unknown';
                                  final status =
                                      _guardianStatuses[name] ?? 'Pending';
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 15),
                                    child: _buildGuardianItem(name, status),
                                  );
                                }).toList()
                              : [
                                  // Fallback if no guardians
                                  const Padding(
                                    padding: EdgeInsets.all(8.0),
                                    child: Text("No guardians configured.",
                                        style: TextStyle(color: Colors.grey)),
                                  )
                                ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 15),

                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.of(context)
                              .popUntil((route) => route.isFirst);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.success,
                          shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(AppConstants.radiusLarge),
                          ),
                        ),
                        child: Text(
                          "I AM SAFE",
                          style: AppTextStyles.button
                              .copyWith(color: AppColors.textOnPrimary),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPulsingLocationMarker({required Color color}) {
    return Container(
      width: 100,
      height: 100,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        // ignore: deprecated_member_use
        color: color.withOpacity(0.2),
      ),
      child: Center(
        child: Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            // ignore: deprecated_member_use
            color: color.withOpacity(0.4),
            border: Border.all(color: Colors.white, width: 2),
          ),
          child: const Center(
            child: Icon(Icons.navigation, color: Colors.white, size: 30),
          ),
        ),
      ),
    );
  }

  Widget _buildGuardianItem(String name, String status) {
    final isPending = status.contains('Sending') || status == 'Pending';
    final isSuccessful = status.contains('SMS Sent');
    final isManual = status.contains('opened');
    final statusColor = isPending
        ? AppColors.primary
        : isSuccessful
            ? AppColors.success
            : isManual
                ? AppColors.warning
                : Colors.redAccent;
    final statusIcon = isPending
        ? Icons.hourglass_top_rounded
        : isSuccessful
            ? Icons.check_circle_rounded
            : isManual
                ? Icons.open_in_new_rounded
                : Icons.error_rounded;

    return Row(
      children: [
        CircleAvatar(
          backgroundColor: AppColors.surfaceLight,
          child: Text(name.isNotEmpty ? name[0] : '?',
              style: AppTextStyles.buttonSmall
                  .copyWith(color: AppColors.textPrimary)),
        ),
        const SizedBox(width: AppConstants.spacing16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                style: AppTextStyles.h3,
              ),
              Text(
                status,
                style: AppTextStyles.labelMedium.copyWith(
                  color: statusColor,
                ),
              ),
            ],
          ),
        ),
        Icon(statusIcon, color: statusColor, size: 20),
      ],
    );
  }
}

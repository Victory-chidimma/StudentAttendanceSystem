import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:geolocator/geolocator.dart';
import '../services/api_service.dart';

class MarkAttendanceScreen extends StatefulWidget {
  final String sessionId;
  final String courseName;
  final String courseCode;

  const MarkAttendanceScreen({
    super.key,
    required this.sessionId,
    required this.courseName,
    required this.courseCode,
  });

  @override
  State<MarkAttendanceScreen> createState() => _MarkAttendanceScreenState();
}

class _MarkAttendanceScreenState extends State<MarkAttendanceScreen> {
  bool _faceScanned = false;
  bool _locationVerified = false;
  bool _isSubmitting = false;
  String _status = 'idle';
  String? _faceImageBase64;
  String? _faceImageTurnedBase64;
  int _captureStage = 0;
  double? _latitude;
  double? _longitude;
  CameraController? _cameraController;
  bool _showCamera = false;

  Future<void> _openCamera() async {
    final cameras = await availableCameras();
    if (cameras.isEmpty) return;

    final camera = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.front,
      orElse: () => cameras.first,
    );

    _cameraController = CameraController(camera, ResolutionPreset.medium);
    await _cameraController!.initialize();
    setState(() {
      _showCamera = true;
      _captureStage = 0;
      _faceImageBase64 = null;
      _faceImageTurnedBase64 = null;
      _faceScanned = false;
    });
  }

  Future<void> _captureAndClose() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized)
      return;

    final image = await _cameraController!.takePicture();
    final bytes = await image.readAsBytes();
    final base64Image = base64Encode(bytes);

    if (_captureStage == 0) {
      setState(() {
        _faceImageBase64 = base64Image;
        _captureStage = 1;
      });
    } else {
      await _cameraController!.dispose();
      _cameraController = null;

      setState(() {
        _faceImageTurnedBase64 = base64Image;
        _faceScanned = true;
        _captureStage = 2;
        _showCamera = false;
      });
    }
  }

  Future<void> _getLocation() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      _showSnackbar('Please enable location services', isError: true);
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        _showSnackbar('Location permission denied', isError: true);
        return;
      }
    }
    if (permission == LocationPermission.deniedForever) {
      _showSnackbar(
        'Location permissions are permanently denied in settings',
        isError: true,
      );
      return;
    }

    try {
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      if (position.isMocked) {
        _showSnackbar(
          'Fake or mock location detected. Please disable location spoofing to mark attendance.',
          isError: true,
        );
        return;
      }

      setState(() {
        _latitude = position.latitude;
        _longitude = position.longitude;
        _locationVerified = true;
      });
    } catch (e) {
      _showSnackbar('Failed to get location: $e', isError: true);
    }
  }

  Future<void> _submitAttendance() async {
    if (_faceImageBase64 == null ||
        _faceImageTurnedBase64 == null ||
        _latitude == null ||
        _longitude == null)
      return;

    setState(() {
      _isSubmitting = true;
      _status = 'idle';
    });

    try {
      final result = await ApiService.markAttendance(
        widget.sessionId,
        _faceImageBase64!,
        _faceImageTurnedBase64!,
        _latitude!,
        _longitude!,
      );

      if (result.containsKey('id')) {
        setState(() => _status = 'success');
        _showSnackbar('Attendance marked successfully!');
        await Future.delayed(const Duration(seconds: 2));
        if (!mounted) return;
        Navigator.pop(context, true);
      } else {
        setState(() => _status = 'failed');
        _showSnackbar(result['detail'] ?? 'Verification failed', isError: true);
      }
    } catch (e) {
      setState(() => _status = 'failed');
      _showSnackbar('Connection error', isError: true);
    }

    setState(() => _isSubmitting = false);
  }

  void _showSnackbar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
      ),
    );
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_showCamera &&
        _cameraController != null &&
        _cameraController!.value.isInitialized) {
      return Scaffold(
        body: Stack(
          children: [
            CameraPreview(_cameraController!),
            Positioned(
              top: 60,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.6),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _captureStage == 0
                        ? 'Look straight at the camera'
                        : 'Now turn your head slightly to the side',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: 40,
              left: 0,
              right: 0,
              child: Center(
                child: ElevatedButton.icon(
                  onPressed: _captureAndClose,
                  icon: const Icon(Icons.camera),
                  label: Text(_captureStage == 0 ? 'Capture' : 'Capture Again'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0D47A1),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: 14,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Mark Attendance'), centerTitle: true),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF0D47A1), Color(0xFF1976D2)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.courseName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.courseCode,
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: const [
                      Icon(Icons.access_time, size: 14, color: Colors.white70),
                      SizedBox(width: 4),
                      Text(
                        'Session active',
                        style: TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),

            const Text(
              'Step 1: Face Verification',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            GestureDetector(
              onTap: _faceScanned ? null : _openCamera,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 32),
                decoration: BoxDecoration(
                  color: _faceScanned
                      ? const Color(0xFFE8F5E9)
                      : Theme.of(context).cardTheme.color,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _faceScanned
                        ? const Color(0xFF1B5E20)
                        : const Color(0xFF90CAF9),
                    width: 1.5,
                  ),
                ),
                child: Column(
                  children: [
                    Icon(
                      _faceScanned
                          ? Icons.check_circle
                          : Icons.camera_alt_outlined,
                      size: 48,
                      color: _faceScanned
                          ? const Color(0xFF1B5E20)
                          : const Color(0xFF1565C0),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _faceScanned
                          ? 'Face verified ✓'
                          : 'Tap to scan your face',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: _faceScanned ? const Color(0xFF1B5E20) : null,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _faceScanned
                          ? 'Identity confirmed'
                          : 'Camera will open for face recognition',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            const Text(
              'Step 2: Location Verification',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            GestureDetector(
              onTap: _locationVerified ? null : _getLocation,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 32),
                decoration: BoxDecoration(
                  color: _locationVerified
                      ? const Color(0xFFE8F5E9)
                      : Theme.of(context).cardTheme.color,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _locationVerified
                        ? const Color(0xFF1B5E20)
                        : const Color(0xFF90CAF9),
                    width: 1.5,
                  ),
                ),
                child: Column(
                  children: [
                    Icon(
                      _locationVerified
                          ? Icons.check_circle
                          : Icons.location_on_outlined,
                      size: 48,
                      color: _locationVerified
                          ? const Color(0xFF1B5E20)
                          : const Color(0xFF1565C0),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _locationVerified
                          ? 'Location verified ✓'
                          : 'Tap to verify location',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: _locationVerified
                            ? const Color(0xFF1B5E20)
                            : null,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _locationVerified
                          ? 'You are within range'
                          : 'GPS will check your proximity to classroom',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 32),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: (_faceScanned && _locationVerified && !_isSubmitting)
                    ? _submitAttendance
                    : null,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: _isSubmitting
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Text(
                        'Submit Attendance',
                        style: TextStyle(fontSize: 16),
                      ),
              ),
            ),

            if (_status == 'success') ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F5E9),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.check_circle, color: Color(0xFF1B5E20)),
                    SizedBox(width: 8),
                    Text(
                      'Attendance marked successfully!',
                      style: TextStyle(
                        color: Color(0xFF1B5E20),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],

            if (_status == 'failed') ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFEBEE),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.error_outline, color: Color(0xFFB71C1C)),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Verification failed. You may be out of range or face not recognized.',
                        style: TextStyle(
                          color: Color(0xFFB71C1C),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

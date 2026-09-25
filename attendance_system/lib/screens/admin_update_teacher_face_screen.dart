import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import '../services/api_service.dart';

class AdminUpdateTeacherFaceScreen extends StatefulWidget {
  final String teacherId;
  final String teacherName;

  const AdminUpdateTeacherFaceScreen({
    super.key,
    required this.teacherId,
    required this.teacherName,
  });

  @override
  State<AdminUpdateTeacherFaceScreen> createState() =>
      _AdminUpdateTeacherFaceScreenState();
}

class _AdminUpdateTeacherFaceScreenState
    extends State<AdminUpdateTeacherFaceScreen> {
  bool _isLoading = false;
  bool _faceScanned = false;
  String? _faceImageBase64;
  String? _faceImageTurnedBase64;
  int _captureStage = 0;
  CameraController? _cameraController;
  bool _showCamera = false;

  @override
  void dispose() {
    _cameraController?.dispose();
    super.dispose();
  }

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
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }

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

  Future<void> _submitUpdate() async {
    if (_faceImageBase64 == null || _faceImageTurnedBase64 == null) {
      _showSnackbar('Please complete the face scan (both steps)', isError: true);
      return;
    }

    setState(() => _isLoading = true);

    try {
      final result = await ApiService.adminUpdateTeacherFace(
        widget.teacherId,
        _faceImageBase64!,
        _faceImageTurnedBase64!,
      );

      if (result['status'] == 'accepted') {
        _showSnackbar(result['message'] ?? 'Face updated successfully');
        if (!mounted) return;
        await Future.delayed(const Duration(seconds: 1));
        Navigator.pop(context);
      } else {
        _showSnackbar(result['detail'] ?? 'Face update failed', isError: true);
      }
    } catch (e) {
      _showSnackbar('Connection error. Check your network.', isError: true);
    }

    if (mounted) setState(() => _isLoading = false);
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
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
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
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text('Update Face — ${widget.teacherName}')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Capture a new face scan for ${widget.teacherName}. This will replace their currently registered face.',
                style: const TextStyle(fontSize: 13, color: Colors.grey),
              ),
              const SizedBox(height: 20),
              GestureDetector(
                onTap: _openCamera,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _faceScanned ? const Color(0xFF1B5E20) : const Color(0xFF90CAF9),
                      width: 1.5,
                    ),
                  ),
                  child: Column(
                    children: [
                      Icon(
                        _faceScanned ? Icons.check_circle_outline : Icons.camera_alt_outlined,
                        size: 32,
                        color: _faceScanned ? const Color(0xFF1B5E20) : const Color(0xFF1565C0),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _faceScanned ? 'New face captured ✓' : 'Tap to scan new face',
                        style: TextStyle(
                          fontWeight: FontWeight.w500,
                          fontSize: 13,
                          color: _faceScanned ? const Color(0xFF1B5E20) : null,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _submitUpdate,
                  child: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                        )
                      : const Text('Update Face', style: TextStyle(fontSize: 16)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
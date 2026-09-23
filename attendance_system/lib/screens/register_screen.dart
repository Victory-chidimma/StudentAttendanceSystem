import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:provider/provider.dart';
import '../utils/theme_provider.dart';
import '../services/api_service.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _fullNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _matriculeController = TextEditingController();
  final _levelController = TextEditingController();
  String _selectedRole = 'student';
  String? _selectedDepartmentId;
  List<dynamic> _departments = [];
  bool _obscurePassword = true;
  bool _isLoading = false;
  bool _faceScanned = false;
  String? _faceImageBase64;
  String? _faceImageTurnedBase64;
  int _captureStage =
      0; // 0 = not started, 1 = first frame captured, 2 = both captured
  CameraController? _cameraController;
  bool _showCamera = false;

  @override
  void initState() {
    super.initState();
    _loadDepartments();
  }

  Future<void> _loadDepartments() async {
    try {
      final deps = await ApiService.getDepartmentsPublic();
      setState(() => _departments = deps);
    } catch (e) {
      print('Error loading departments: $e');
    }
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _matriculeController.dispose();
    _levelController.dispose();
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

  Future<void> _register() async {
    if (_fullNameController.text.isEmpty ||
        _emailController.text.isEmpty ||
        _passwordController.text.isEmpty) {
      _showSnackbar('Please fill in all fields', isError: true);
      return;
    }
    if (_selectedRole == 'student' && _matriculeController.text.isEmpty) {
      _showSnackbar('Please enter your matricule', isError: true);
      return;
    }
    if (_selectedRole == 'student' && _selectedDepartmentId == null) {
      _showSnackbar('Please select your department', isError: true);
      return;
    }
    if (_selectedRole == 'student' && _levelController.text.isEmpty) {
      _showSnackbar('Please enter your level', isError: true);
      return;
    }
    if (_faceImageBase64 == null || _faceImageTurnedBase64 == null) {
      _showSnackbar(
        'Please complete the face scan (both steps)',
        isError: true,
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final result = await ApiService.register(
        _fullNameController.text.trim(),
        _emailController.text.trim(),
        _passwordController.text,
        _selectedRole,
        _faceImageBase64!,
        _faceImageTurnedBase64!,
        _selectedRole == 'student' ? _matriculeController.text.trim() : null,
        _selectedRole == 'student' ? _selectedDepartmentId : null,
        _selectedRole == 'student'
            ? int.tryParse(_levelController.text.trim())
            : null,
      );

      if (result.containsKey('access_token')) {
        _showSnackbar('Account created successfully!');
        if (!mounted) return;
        await Future.delayed(const Duration(seconds: 1));
        Navigator.pop(context);
      } else {
        _showSnackbar(result['detail'] ?? 'Registration failed', isError: true);
      }
    } catch (e) {
      _showSnackbar('Connection error. Check your network.', isError: true);
    }

    setState(() => _isLoading = false);
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
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDark = themeProvider.isDarkMode;

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
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              Container(
                width: double.infinity,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF0D47A1), Color(0xFF1976D2)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                padding: const EdgeInsets.symmetric(
                  vertical: 36,
                  horizontal: 24,
                ),
                child: Column(
                  children: [
                    Align(
                      alignment: Alignment.topLeft,
                      child: IconButton(
                        icon: const Icon(Icons.arrow_back, color: Colors.white),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ),
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.4),
                          width: 1.5,
                        ),
                      ),
                      child: const Icon(
                        Icons.person_add_outlined,
                        color: Colors.white,
                        size: 30,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Create account',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'HIMS Buea Attendance System',
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Full name',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _fullNameController,
                      decoration: const InputDecoration(
                        hintText: 'John Doe',
                        prefixIcon: Icon(
                          Icons.person_outline,
                          color: Color(0xFF1565C0),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Email address',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        hintText: 'student@hims.edu',
                        prefixIcon: Icon(
                          Icons.mail_outline,
                          color: Color(0xFF1565C0),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Password',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      decoration: InputDecoration(
                        hintText: '••••••••',
                        prefixIcon: const Icon(
                          Icons.lock_outline,
                          color: Color(0xFF1565C0),
                        ),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_off
                                : Icons.visibility,
                          ),
                          onPressed: () => setState(
                            () => _obscurePassword = !_obscurePassword,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Role',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1A2332) : Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFE0E0E0)),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _selectedRole,
                          isExpanded: true,
                          items: const [
                            DropdownMenuItem(
                              value: 'student',
                              child: Text('Student'),
                            ),
                          ],
                          onChanged: (val) =>
                              setState(() => _selectedRole = val!),
                        ),
                      ),
                    ),
                    if (_selectedRole == 'student') ...[
                      const SizedBox(height: 16),
                      const Text(
                        'Matricule',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _matriculeController,
                        decoration: const InputDecoration(
                          hintText: 'e.g. HIMS/25E/0324',
                          prefixIcon: Icon(
                            Icons.badge_outlined,
                            color: Color(0xFF1565C0),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Department',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: isDark
                              ? const Color(0xFF1A2332)
                              : Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFE0E0E0)),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _selectedDepartmentId,
                            isExpanded: true,
                            hint: const Text('Select department'),
                            items: _departments
                                .map<DropdownMenuItem<String>>(
                                  (d) => DropdownMenuItem<String>(
                                    value: d['id'],
                                    child: Text(d['name']),
                                  ),
                                )
                                .toList(),
                            onChanged: (val) =>
                                setState(() => _selectedDepartmentId = val),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Level',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _levelController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          hintText: 'e.g. 400',
                          prefixIcon: Icon(
                            Icons.stairs_outlined,
                            color: Color(0xFF1565C0),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    GestureDetector(
                      onTap: _openCamera,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 20),
                        decoration: BoxDecoration(
                          color: isDark
                              ? const Color(0xFF1A2332)
                              : Colors.white,
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
                                  ? Icons.check_circle_outline
                                  : Icons.camera_alt_outlined,
                              size: 32,
                              color: _faceScanned
                                  ? const Color(0xFF1B5E20)
                                  : const Color(0xFF1565C0),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _faceScanned
                                  ? 'Face captured ✓'
                                  : 'Tap to scan your face',
                              style: TextStyle(
                                fontWeight: FontWeight.w500,
                                fontSize: 13,
                                color: _faceScanned
                                    ? const Color(0xFF1B5E20)
                                    : null,
                              ),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'Required for attendance verification',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey,
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
                        onPressed: _isLoading ? null : _register,
                        child: _isLoading
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text(
                                'Create account',
                                style: TextStyle(fontSize: 16),
                              ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Center(
                      child: GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: RichText(
                          text: TextSpan(
                            style: TextStyle(
                              color: isDark ? Colors.white70 : Colors.black54,
                              fontSize: 13,
                            ),
                            children: const [
                              TextSpan(text: 'Already have an account? '),
                              TextSpan(
                                text: 'Login',
                                style: TextStyle(
                                  color: Color(0xFF0D47A1),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

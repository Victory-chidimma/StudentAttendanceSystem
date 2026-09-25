import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:provider/provider.dart';
import '../utils/theme_provider.dart';
import '../services/api_service.dart';
import 'register_screen.dart';
import 'student_dashboard.dart';
import 'teacher_dashboard.dart';
import 'admin_dashboard.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _isLoading = false;
  bool _faceScanned = false;
  bool _isAdminLogin = false;
  String? _faceImageBase64;
  String? _faceImageTurnedBase64;
  int _captureStage =
      0; // 0 = not started, 1 = first frame captured, 2 = both captured
  CameraController? _cameraController;
  bool _showCamera = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
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

  void _resetFaceCapture() {
    setState(() {
      _faceImageBase64 = null;
      _faceImageTurnedBase64 = null;
      _faceScanned = false;
      _captureStage = 0;
    });
  }

  Future<void> _captureAndClose() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized)
      return;

    final image = await _cameraController!.takePicture();
    final bytes = await image.readAsBytes();
    final base64Image = base64Encode(bytes);

    if (_captureStage == 0) {
      // First frame captured — keep camera open, ask for head turn
      setState(() {
        _faceImageBase64 = base64Image;
        _captureStage = 1;
      });
    } else {
      // Second frame captured — now close camera
      await _cameraController!.dispose();
      _cameraController = null;

      setState(() {
        _faceImageTurnedBase64 = base64Image;
        _faceScanned = true;
        _captureStage = 2;
        _showCamera = false;
      });

      // Retry login now that we have both face frames (this path is for teachers)
      setState(() => _isLoading = true);
      try {
        final result = await ApiService.login(
          _emailController.text.trim(),
          _passwordController.text,
          _faceImageBase64,
          _faceImageTurnedBase64,
        );

        if (result.containsKey('access_token')) {
          await _completeLogin(result);
        } else {
          _showSnackbar(result['detail'] ?? 'Login failed', isError: true);
          _resetFaceCapture();
          if (mounted)
            await _openCamera(); // give them a fresh attempt right away
        }
      } catch (e) {
        _showSnackbar('Connection error. Check your network.', isError: true);
        _resetFaceCapture();
      }
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _login() async {
    if (_emailController.text.isEmpty || _passwordController.text.isEmpty) {
      _showSnackbar('Please enter your details', isError: true);
      return;
    }

    setState(() => _isLoading = true);

    try {
      final result = await ApiService.login(
        _emailController.text.trim(),
        _passwordController.text,
        _faceImageBase64,
        _faceImageTurnedBase64,
      );

      if (result.containsKey('access_token')) {
        await _completeLogin(result);
        return;
      }

      if (result['detail'] ==
          'Face images are required for this account type') {
        setState(() => _isLoading = false);
        await _openCamera();
        return;
      }

      if (result['detail'] == 'User not found') {
        _showRegisterPrompt();
      } else {
        _showSnackbar(result['detail'] ?? 'Login failed', isError: true);
        _resetFaceCapture();
      }
    } catch (e) {
      _showSnackbar('Connection error. Check your network.', isError: true);
    }

    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _completeLogin(Map<String, dynamic> result) async {
    await ApiService.saveToken(
      result['access_token'],
      result['role'],
      result['user_id'],
      result['full_name'],
    );

    if (!mounted) return;

    final role = result['role'];
    if (role == 'student') {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const StudentDashboard()),
      );
    } else if (role == 'teacher') {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const TeacherDashboard()),
      );
    } else if (role == 'admin') {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const AdminDashboard()),
      );
    }
  }

  Future<void> _adminLogin() async {
    if (_emailController.text.isEmpty || _passwordController.text.isEmpty) {
      _showSnackbar('Please enter email and password', isError: true);
      return;
    }

    setState(() => _isLoading = true);

    try {
      final result = await ApiService.adminLogin(
        _emailController.text.trim(),
        _passwordController.text,
      );

      if (result.containsKey('access_token')) {
        await ApiService.saveToken(
          result['access_token'],
          result['role'],
          result['user_id'],
          result['full_name'],
        );

        if (!mounted) return;

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const AdminDashboard()),
        );
      } else {
        _showSnackbar(result['detail'] ?? 'Login failed', isError: true);
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

  void _showRegisterPrompt() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Account not found'),
        content: const Text(
          'No account found with these details. If you are a student, you can register below.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const RegisterScreen()),
              );
            },
            child: const Text('Register now'),
          ),
        ],
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
                  vertical: 48,
                  horizontal: 24,
                ),
                child: Column(
                  children: [
                    Align(
                      alignment: Alignment.topRight,
                      child: IconButton(
                        icon: Icon(
                          isDark ? Icons.light_mode : Icons.dark_mode,
                          color: Colors.white,
                        ),
                        onPressed: () => themeProvider.toggleTheme(),
                      ),
                    ),
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.4),
                          width: 1.5,
                        ),
                      ),
                      child: const Icon(
                        Icons.fingerprint,
                        color: Colors.white,
                        size: 36,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Welcome back',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'HIMS Buea Attendance System',
                      style: TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 8),
                    Text(
                      _isAdminLogin ? 'Admin email' : 'Email or Matricule',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _emailController,
                      decoration: InputDecoration(
                        hintText: _isAdminLogin
                            ? 'admin@hims.edu'
                            : 'Email or Matricule',
                        prefixIcon: const Icon(
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
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isLoading
                            ? null
                            : (_isAdminLogin ? _adminLogin : _login),
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
                                'Login',
                                style: TextStyle(fontSize: 16),
                              ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Center(
                      child: TextButton(
                        onPressed: () =>
                            setState(() => _isAdminLogin = !_isAdminLogin),
                        child: Text(
                          _isAdminLogin
                              ? 'Login as Student/Teacher instead'
                              : 'Login as Admin instead',
                          style: const TextStyle(
                            color: Color(0xFF0D47A1),
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Center(
                      child: GestureDetector(
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const RegisterScreen(),
                          ),
                        ),
                        child: RichText(
                          text: TextSpan(
                            style: TextStyle(
                              color: isDark ? Colors.white70 : Colors.black54,
                              fontSize: 13,
                            ),
                            children: const [
                              TextSpan(text: "Don't have an account? "),
                              TextSpan(
                                text: 'Register',
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

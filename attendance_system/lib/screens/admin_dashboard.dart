import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../utils/theme_provider.dart';
import '../services/api_service.dart';
import 'login_screen.dart';
import 'user_detail_screen.dart';
import 'dart:convert';
import 'package:camera/camera.dart';
import 'session_logs_screen.dart';
import 'student_search_screen.dart';
import 'admin_update_teacher_face_screen.dart';

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  int _currentIndex = 0;
  bool _isLoading = true;
  List<dynamic> _departments = [];
  List<dynamic> _courses = [];
  List<dynamic> _users = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final departments = await ApiService.getDepartments();
      final courses = await ApiService.getCourses();
      final users = await ApiService.getAllUsers();
      setState(() {
        _departments = departments;
        _courses = courses;
        _users = users;
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading admin data: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _logout() async {
    await ApiService.clearToken();
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDark = themeProvider.isDarkMode;

    return Scaffold(
      body: SafeArea(
        child: _currentIndex == 0
            ? _buildHome(isDark)
            : _currentIndex == 1
            ? _buildCourses(isDark)
            : _currentIndex == 2
            ? _buildUsers(isDark)
            : _buildProfile(isDark, themeProvider),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (i) => setState(() => _currentIndex = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Dashboard',
          ),
          NavigationDestination(
            icon: Icon(Icons.book_outlined),
            selectedIcon: Icon(Icons.book),
            label: 'Courses',
          ),
          NavigationDestination(
            icon: Icon(Icons.people_outline),
            selectedIcon: Icon(Icons.people),
            label: 'Users',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
      floatingActionButton: _currentIndex == 1
          ? FloatingActionButton.extended(
              onPressed: () => _showAddCourseDialog(context, isDark),
              backgroundColor: const Color(0xFF0D47A1),
              icon: const Icon(Icons.add, color: Colors.white),
              label: const Text(
                'Add Course',
                style: TextStyle(color: Colors.white),
              ),
            )
          : null,
    );
  }

  Widget _buildHome(bool isDark) {
    return RefreshIndicator(
      onRefresh: _loadData,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
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
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Admin Panel',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'HIMS Buea',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                      CircleAvatar(
                        radius: 22,
                        backgroundColor: Colors.white.withOpacity(0.2),
                        child: const Icon(
                          Icons.admin_panel_settings,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      _statCard(_departments.length.toString(), 'Departments'),
                      const SizedBox(width: 8),
                      _statCard(_courses.length.toString(), 'Courses'),
                      const SizedBox(width: 8),
                      _statCard(_users.length.toString(), 'Users'),
                    ],
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Quick Actions',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _quickAction(
                          Icons.add_business,
                          'Add Department',
                          const Color(0xFFE3F2FD),
                          const Color(0xFF0D47A1),
                          () => _showAddDepartmentDialog(context, isDark),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _quickAction(
                          Icons.library_add,
                          'Add Course',
                          const Color(0xFFE8F5E9),
                          const Color(0xFF1B5E20),
                          () => _showAddCourseDialog(context, isDark),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _quickAction(
                          Icons.person_add,
                          'View Users',
                          const Color(0xFFFFF3E0),
                          const Color(0xFFE65100),
                          () => setState(() => _currentIndex = 2),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _quickAction(
                          Icons.assignment_ind,
                          'Add Teacher',
                          const Color(0xFFEDE7F6),
                          const Color(0xFF4527A0),
                          () => _showAddTeacherDialog(context, isDark),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _quickAction(
                          Icons.history,
                          'Session Logs',
                          const Color(0xFFE0F2F1),
                          const Color(0xFF00695C),
                          () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const SessionLogsScreen(),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _quickAction(
                          Icons.manage_search,
                          'Search Students',
                          const Color(0xFFFCE4EC),
                          const Color(0xFFAD1457),
                          () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const StudentSearchScreen(),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCourses(bool isDark) {
    return RefreshIndicator(
      onRefresh: _loadData,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Courses',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _courses.isEmpty
                  ? const Center(child: Text('No courses yet'))
                  : ListView(
                      children: _courses
                          .map(
                            (c) => Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: _courseItem(
                                isDark,
                                c['id'] ?? '',
                                c['name'] ?? '',
                                c['code'] ?? '',
                                c['department_id'] ?? '',
                                c['teacher_id'] ?? 'Unassigned',
                              ),
                            ),
                          )
                          .toList(),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _courseItem(
    bool isDark,
    String courseId,
    String name,
    String code,
    String dept,
    String teacher,
  ) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A2332) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border(
          left: BorderSide(color: const Color(0xFF1565C0), width: 3),
        ),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  code,
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
                const SizedBox(height: 3),
                Text(
                  'Teacher: $teacher',
                  style: TextStyle(
                    fontSize: 11,
                    color: teacher == 'Unassigned'
                        ? Colors.orange
                        : Colors.grey,
                  ),
                ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.grey),
            onSelected: (value) {
              if (value == 'assign') {
                _showAssignTeacherDialog(context, courseId, name);
              } else if (value == 'delete') {
                _confirmDeleteCourse(context, courseId, name);
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'assign',
                child: Text('Assign Teacher'),
              ),
              const PopupMenuItem(
                value: 'delete',
                child: Text(
                  'Delete Course',
                  style: TextStyle(color: Colors.red),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  int _usersSubTab = 0; // 0 = students, 1 = teachers

Widget _buildUsers(bool isDark) {
  final teachers = _users.where((u) => u['role'] == 'teacher').toList();

  return Column(
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Row(
          children: [
            Expanded(child: _subTabButton('Students', 0)),
            const SizedBox(width: 8),
            Expanded(child: _subTabButton('Teachers', 1)),
          ],
        ),
      ),
      Expanded(
        child: _usersSubTab == 0
            ? const StudentSearchScreen(embedded: true)
            : RefreshIndicator(
                onRefresh: _loadData,
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : teachers.isEmpty
                    ? ListView(
                        children: const [
                          Padding(
                            padding: EdgeInsets.symmetric(vertical: 32),
                            child: Center(child: Text('No teachers yet')),
                          ),
                        ],
                      )
                    : ListView(
                        padding: const EdgeInsets.all(16),
                        children: teachers
                            .map(
                              (u) => Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: _userItem(
                                  isDark,
                                  u['full_name'] ?? '',
                                  u['email'] ?? '',
                                  u['role'] ?? '',
                                  u['id'] ?? '',
                                ),
                              ),
                            )
                            .toList(),
                      ),
              ),
      ),
    ],
  );
}

Widget _subTabButton(String label, int index) {
  final isSelected = _usersSubTab == index;
  return GestureDetector(
    onTap: () => setState(() => _usersSubTab = index),
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: isSelected ? const Color(0xFF0D47A1) : Colors.grey.shade200,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: isSelected ? Colors.white : Colors.black87,
          fontWeight: FontWeight.w600,
          fontSize: 13,
        ),
      ),
    ),
  );
}

  Widget _userItem(
    bool isDark,
    String name,
    String email,
    String role,
    String userId,
  ) {
    final isTeacher = role == 'teacher';
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => UserDetailScreen(
              userId: userId,
              userName: name,
              userRole: role,
            ),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1A2332) : Colors.white,
          borderRadius: BorderRadius.circular(10),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6),
          ],
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: isTeacher
                  ? const Color(0xFFE3F2FD)
                  : const Color(0xFFE8F5E9),
              child: Icon(
                isTeacher ? Icons.school : Icons.person,
                color: isTeacher
                    ? const Color(0xFF0D47A1)
                    : const Color(0xFF1B5E20),
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      fontWeight: FontWeight.w500,
                      fontSize: 13,
                    ),
                  ),
                  Text(
                    email,
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ],
              ),
            ),
            if (isTeacher)
              IconButton(
                icon: const Icon(
                  Icons.face_retouching_natural_outlined,
                  color: Color(0xFF4527A0),
                  size: 20,
                ),
                tooltip: 'Update Face',
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => AdminUpdateTeacherFaceScreen(
                        teacherId: userId,
                        teacherName: name,
                      ),
                    ),
                  );
                },
              ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: isTeacher
                    ? const Color(0xFFE3F2FD)
                    : const Color(0xFFE8F5E9),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                role,
                style: TextStyle(
                  fontSize: 10,
                  color: isTeacher
                      ? const Color(0xFF0D47A1)
                      : const Color(0xFF1B5E20),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfile(bool isDark, ThemeProvider themeProvider) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const SizedBox(height: 20),
          CircleAvatar(
            radius: 40,
            backgroundColor: const Color(0xFF0D47A1),
            child: const Icon(
              Icons.admin_panel_settings,
              color: Colors.white,
              size: 36,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Administrator',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const Text('admin@hims.edu', style: TextStyle(color: Colors.grey)),
          const SizedBox(height: 32),
          ListTile(
            leading: const Icon(Icons.dark_mode_outlined),
            title: const Text('Dark mode'),
            trailing: Switch(
              value: isDark,
              onChanged: (_) => themeProvider.toggleTheme(),
              activeColor: const Color(0xFF0D47A1),
            ),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.red),
            title: const Text('Logout', style: TextStyle(color: Colors.red)),
            onTap: _logout,
          ),
        ],
      ),
    );
  }

  void _showAddDepartmentDialog(BuildContext context, bool isDark) {
    final nameController = TextEditingController();
    final codeController = TextEditingController();
    bool isLoading = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Add Department'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Department Name',
                  hintText: 'e.g. Computer Engineering',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: codeController,
                decoration: const InputDecoration(
                  labelText: 'Code',
                  hintText: 'e.g. CENG',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: isLoading
                  ? null
                  : () async {
                      if (nameController.text.isEmpty ||
                          codeController.text.isEmpty)
                        return;
                      setDialogState(() => isLoading = true);
                      try {
                        await ApiService.createDepartment(
                          nameController.text.trim(),
                          codeController.text.trim(),
                        );
                        if (!context.mounted) return;
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Department created!'),
                            backgroundColor: Colors.green,
                          ),
                        );
                        _loadData();
                      } catch (e) {
                        setDialogState(() => isLoading = false);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Failed to create department'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    },
              child: isLoading
                  ? const SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Add'),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddCourseDialog(BuildContext context, bool isDark) {
    final nameController = TextEditingController();
    final codeController = TextEditingController();
    final levelController = TextEditingController();
    String selectedSemester = 'first';
    String? selectedDepartmentId;
    List<dynamic> departments = [];
    bool isLoading = false;
    TimeOfDay? startTime;
    TimeOfDay? endTime;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          if (departments.isEmpty) {
            ApiService.getDepartments().then((deps) {
              setDialogState(() => departments = deps);
            });
          }

          return AlertDialog(
            title: const Text('Add Course'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'Course Name',
                      hintText: 'e.g. Computer Control System',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: codeController,
                    decoration: const InputDecoration(
                      labelText: 'Course Code',
                      hintText: 'e.g. SEC410',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: levelController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Level',
                      hintText: 'e.g. 400',
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: selectedSemester,
                    decoration: const InputDecoration(labelText: 'Semester'),
                    items: const [
                      DropdownMenuItem(
                        value: 'first',
                        child: Text('First Semester'),
                      ),
                      DropdownMenuItem(
                        value: 'second',
                        child: Text('Second Semester'),
                      ),
                    ],
                    onChanged: (val) =>
                        setDialogState(() => selectedSemester = val!),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: selectedDepartmentId,
                    decoration: const InputDecoration(labelText: 'Department'),
                    items: departments
                        .map(
                          (d) => DropdownMenuItem<String>(
                            value: d['id'],
                            child: Text(d['name']),
                          ),
                        )
                        .toList(),
                    onChanged: (val) =>
                        setDialogState(() => selectedDepartmentId = val),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () async {
                            final picked = await showTimePicker(
                              context: context,
                              initialTime:
                                  startTime ??
                                  const TimeOfDay(hour: 9, minute: 0),
                            );
                            if (picked != null) {
                              setDialogState(() => startTime = picked);
                            }
                          },
                          child: Text(
                            startTime == null
                                ? 'Start time'
                                : startTime!.format(context),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () async {
                            final picked = await showTimePicker(
                              context: context,
                              initialTime:
                                  endTime ??
                                  const TimeOfDay(hour: 11, minute: 0),
                            );
                            if (picked != null) {
                              setDialogState(() => endTime = picked);
                            }
                          },
                          child: Text(
                            endTime == null
                                ? 'End time'
                                : endTime!.format(context),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: isLoading
                    ? null
                    : () async {
                        if (nameController.text.isEmpty ||
                            codeController.text.isEmpty ||
                            selectedDepartmentId == null)
                          return;
                        setDialogState(() => isLoading = true);
                        try {
                          await ApiService.createCourse({
                            'name': nameController.text.trim(),
                            'code': codeController.text.trim(),
                            'level': int.tryParse(levelController.text) ?? 100,
                            'semester': selectedSemester,
                            'department_id': selectedDepartmentId,
                            'start_time': startTime != null
                                ? '${startTime!.hour.toString().padLeft(2, '0')}:${startTime!.minute.toString().padLeft(2, '0')}:00'
                                : null,
                            'end_time': endTime != null
                                ? '${endTime!.hour.toString().padLeft(2, '0')}:${endTime!.minute.toString().padLeft(2, '0')}:00'
                                : null,
                          });
                          if (!context.mounted) return;
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Course created!'),
                              backgroundColor: Colors.green,
                            ),
                          );
                          _loadData();
                        } catch (e) {
                          setDialogState(() => isLoading = false);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Failed to create course'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      },
                child: isLoading
                    ? const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Add'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showAddTeacherDialog(BuildContext context, bool isDark) {
    final nameController = TextEditingController();
    final emailController = TextEditingController();
    final passwordController = TextEditingController();
    String? faceImageBase64;
    bool faceScanned = false;
    bool isLoading = false;
    CameraController? cameraController;
    bool showCamera = false;

    Future<void> openCamera(StateSetter setDialogState) async {
      final cameras = await availableCameras();
      if (cameras.isEmpty) return;
      final camera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      cameraController = CameraController(camera, ResolutionPreset.medium);
      await cameraController!.initialize();
      setDialogState(() => showCamera = true);
    }

    Future<void> captureAndClose(StateSetter setDialogState) async {
      if (cameraController == null || !cameraController!.value.isInitialized)
        return;
      final image = await cameraController!.takePicture();
      final bytes = await image.readAsBytes();
      final base64Image = base64Encode(bytes);
      await cameraController!.dispose();
      cameraController = null;
      setDialogState(() {
        faceImageBase64 = base64Image;
        faceScanned = true;
        showCamera = false;
      });
    }

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          if (showCamera &&
              cameraController != null &&
              cameraController!.value.isInitialized) {
            return Dialog(
              child: SizedBox(
                height: 400,
                child: Stack(
                  children: [
                    CameraPreview(cameraController!),
                    Positioned(
                      bottom: 16,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: ElevatedButton.icon(
                          onPressed: () => captureAndClose(setDialogState),
                          icon: const Icon(Icons.camera),
                          label: const Text('Capture'),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          return AlertDialog(
            title: const Text('Add Teacher'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'Full Name',
                      hintText: 'e.g. Dr. Smith',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: emailController,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      hintText: 'e.g. teacher@hims.edu',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: passwordController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Password',
                      hintText: 'Set a password',
                    ),
                  ),
                  const SizedBox(height: 12),
                  GestureDetector(
                    onTap: () => openCamera(setDialogState),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: faceScanned
                              ? const Color(0xFF1B5E20)
                              : const Color(0xFF90CAF9),
                          width: 1.5,
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        children: [
                          Icon(
                            faceScanned
                                ? Icons.check_circle_outline
                                : Icons.camera_alt_outlined,
                            color: faceScanned
                                ? const Color(0xFF1B5E20)
                                : const Color(0xFF1565C0),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            faceScanned
                                ? 'Face captured ✓'
                                : 'Tap to scan face',
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: isLoading
                    ? null
                    : () async {
                        if (nameController.text.isEmpty ||
                            emailController.text.isEmpty ||
                            passwordController.text.isEmpty ||
                            faceImageBase64 == null) {
                          return;
                        }
                        setDialogState(() => isLoading = true);
                        try {
                          await ApiService.createTeacher(
                            nameController.text.trim(),
                            emailController.text.trim(),
                            passwordController.text,
                            faceImageBase64!,
                          );
                          if (!context.mounted) return;
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Teacher created!'),
                              backgroundColor: Colors.green,
                            ),
                          );
                          _loadData();
                        } catch (e) {
                          setDialogState(() => isLoading = false);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Failed to create teacher'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      },
                child: isLoading
                    ? const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Add'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showAssignTeacherDialog(
    BuildContext context,
    String courseId,
    String courseName,
  ) {
    String? selectedTeacherId;
    List<dynamic> teachers = _users
        .where((u) => u['role'] == 'teacher')
        .toList();
    bool isLoading = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Assign Teacher to $courseName'),
          content: teachers.isEmpty
              ? const Text('No teachers available. Add a teacher first.')
              : DropdownButtonFormField<String>(
                  value: selectedTeacherId,
                  decoration: const InputDecoration(labelText: 'Teacher'),
                  items: teachers
                      .map(
                        (t) => DropdownMenuItem<String>(
                          value: t['id'],
                          child: Text(t['full_name']),
                        ),
                      )
                      .toList(),
                  onChanged: (val) =>
                      setDialogState(() => selectedTeacherId = val),
                ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            if (teachers.isNotEmpty)
              ElevatedButton(
                onPressed: isLoading
                    ? null
                    : () async {
                        if (selectedTeacherId == null) return;
                        setDialogState(() => isLoading = true);
                        try {
                          await ApiService.assignTeacher(
                            courseId,
                            selectedTeacherId!,
                          );
                          if (!context.mounted) return;
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Teacher assigned!'),
                              backgroundColor: Colors.green,
                            ),
                          );
                          _loadData();
                        } catch (e) {
                          setDialogState(() => isLoading = false);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Failed to assign teacher'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      },
                child: isLoading
                    ? const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Assign'),
              ),
          ],
        ),
      ),
    );
  }

  void _confirmDeleteCourse(
    BuildContext context,
    String courseId,
    String courseName,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Course'),
        content: Text(
          'Are you sure you want to delete "$courseName"? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              try {
                await ApiService.deleteCourse(courseId);
                if (context.mounted) Navigator.pop(context);
                await _loadData();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Course deleted'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Failed to delete course'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _statCard(String value, String label) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.15),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(fontSize: 10, color: Colors.white70),
            ),
          ],
        ),
      ),
    );
  }

  Widget _quickAction(
    IconData icon,
    String label,
    Color bgColor,
    Color iconColor,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, color: iconColor, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: iconColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

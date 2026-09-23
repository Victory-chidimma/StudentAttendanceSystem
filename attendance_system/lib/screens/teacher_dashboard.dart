import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:geolocator/geolocator.dart';
import '../utils/theme_provider.dart';
import '../services/api_service.dart';
import 'login_screen.dart';
import 'session_records_screen.dart';

class TeacherDashboard extends StatefulWidget {
  const TeacherDashboard({super.key});

  @override
  State<TeacherDashboard> createState() => _TeacherDashboardState();
}

class _TeacherDashboardState extends State<TeacherDashboard> {
  int _currentIndex = 0;
  List<dynamic> _courses = [];
  bool _isLoading = true;
  String _fullName = '';
  int _activeSessionCount = 0;

  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _loadData();
    _pollTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) _loadData();
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final name = await ApiService.getFullName();
      final courses = await ApiService.getCourses();
      final activeSessions = await ApiService.getActiveSessions();
      setState(() {
        _fullName = name ?? 'Teacher';
        _courses = courses;
        _activeSessionCount = activeSessions.length;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _openSession(String courseId) async {
    int duration = 60;
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Open Attendance Session'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Duration (minutes):'),
            const SizedBox(height: 8),
            TextField(
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(hintText: '60'),
              onChanged: (v) => duration = int.tryParse(v) ?? 60,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);

              bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
              if (!serviceEnabled) {
                _showSnackbar('Please enable location services', isError: true);
                return;
              }
              LocationPermission permission =
                  await Geolocator.checkPermission();
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
                await _attemptOpenSession(
                  courseId,
                  duration,
                  false,
                  position.latitude,
                  position.longitude,
                );
              } catch (e) {
                _showSnackbar('Failed to get location: $e', isError: true);
              }
            },
            child: const Text('Open'),
          ),
        ],
      ),
    );
  }

  Future<void> _attemptOpenSession(
    String courseId,
    int duration,
    bool confirmDuplicate,
    double latitude,
    double longitude, {
    bool confirmOutsideSchedule = false,
  }) async {
    try {
      final result = await ApiService.openSession(
        courseId,
        latitude,
        longitude,
        duration,
        100,
        confirmDuplicate: confirmDuplicate,
        confirmOutsideSchedule: confirmOutsideSchedule,
      );

      if (result['detail'] == 'DUPLICATE_SESSION_TODAY') {
        if (!mounted) return;
        final shouldRetry = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Session already opened today'),
            content: const Text(
              'A session for this course was already opened today. '
              'This can happen if network issues prevented students from marking attendance earlier. '
              'Do you want to open another session anyway?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Open anyway'),
              ),
            ],
          ),
        );
        if (shouldRetry == true) {
          await _attemptOpenSession(
            courseId,
            duration,
            true,
            latitude,
            longitude,
            confirmOutsideSchedule: confirmOutsideSchedule,
          );
        }
        return;
      }

      if (result['detail'] == 'OUTSIDE_SCHEDULED_TIME') {
        if (!mounted) return;
        final shouldRetry = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Outside scheduled time'),
            content: const Text(
              'This is outside the course\'s scheduled time. '
              'This can happen if you\'re running a makeup session or covering for another teacher. '
              'Do you want to continue anyway?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Continue anyway'),
              ),
            ],
          ),
        );
        if (shouldRetry == true) {
          await _attemptOpenSession(
            courseId,
            duration,
            confirmDuplicate,
            latitude,
            longitude,
            confirmOutsideSchedule: true,
          );
        }
        return;
      }

      if (result.containsKey('id')) {
        _showSnackbar('Session opened successfully!');
        _loadData();
      } else {
        _showSnackbar(
          result['detail'] ?? 'Failed to open session',
          isError: true,
        );
      }
    } catch (e) {
      _showSnackbar('Failed to open session', isError: true);
    }
  }

  Future<void> _closeSession(String sessionId) async {
    try {
      await ApiService.closeSession(sessionId);
      _showSnackbar('Session closed successfully!');
      _loadData();
    } catch (e) {
      _showSnackbar('Failed to close session', isError: true);
    }
  }

  void _showSnackbar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
      ),
    );
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
            ? _buildStudents(isDark)
            : _buildProfile(isDark, themeProvider),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (i) => setState(() => _currentIndex = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.groups_outlined),
            selectedIcon: Icon(Icons.groups),
            label: 'Students',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
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
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _fullName,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Teacher',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                      CircleAvatar(
                        radius: 22,
                        backgroundColor: Colors.white.withValues(alpha: 0.2),
                        child: Text(
                          _fullName.isNotEmpty
                              ? _fullName[0].toUpperCase()
                              : 'T',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      _statCard(_courses.length.toString(), 'Courses'),
                      const SizedBox(width: 8),
                      _statCard(_activeSessionCount.toString(), 'Active'),
                      const SizedBox(width: 8),
                      _statCard('0', 'Students'),
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
                    'My Courses',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 12),
                  if (_isLoading)
                    const Center(child: CircularProgressIndicator())
                  else if (_courses.isEmpty)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          children: const [
                            Icon(
                              Icons.book_outlined,
                              size: 48,
                              color: Colors.grey,
                            ),
                            SizedBox(height: 12),
                            Text(
                              'No courses assigned yet',
                              style: TextStyle(color: Colors.grey),
                            ),
                            Text(
                              'Contact admin to assign courses',
                              style: TextStyle(
                                color: Colors.grey,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    ..._courses.map(
                      (course) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _courseCard(isDark, course),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _courseCard(bool isDark, Map<String, dynamic> course) {
    final isActive = course['is_active'] == true;
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => SessionRecordsScreen(
            sessionId: course['active_session_id'] ?? course['id'],
            courseName: course['name'] ?? '',
            courseCode: course['code'] ?? '',
          ),
        ),
      ),
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1A2332) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: const Border(
            left: BorderSide(color: Color(0xFF1565C0), width: 3),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        course['name'] ?? '',
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${course['code'] ?? ''} · Level ${course['level'] ?? ''}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${course['semester'] ?? ''} semester',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: isActive
                        ? const Color(0xFFE8F5E9)
                        : const Color(0xFFFFEBEE),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    isActive ? 'Active' : 'Closed',
                    style: TextStyle(
                      fontSize: 11,
                      color: isActive
                          ? const Color(0xFF1B5E20)
                          : const Color(0xFFB71C1C),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (isActive)
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () =>
                      _closeSession(course['active_session_id'] ?? ''),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                    side: const BorderSide(color: Colors.red),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                  child: const Text(
                    'Close session',
                    style: TextStyle(fontSize: 13),
                  ),
                ),
              )
            else
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _openSession(course['id']),
                  icon: const Icon(Icons.play_arrow_outlined, size: 16),
                  label: const Text(
                    'Open session',
                    style: TextStyle(fontSize: 13),
                  ),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _statCard(String value, String label) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.15),
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

  Widget _buildStudents(bool isDark) {
    return const Center(child: Text('Students list - Coming soon'));
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
            child: Text(
              _fullName.isNotEmpty ? _fullName[0].toUpperCase() : 'T',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            _fullName,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const Text('Teacher', style: TextStyle(color: Colors.grey)),
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
}

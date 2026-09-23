import 'package:flutter/material.dart';
import '../services/api_service.dart';

class UserDetailScreen extends StatefulWidget {
  final String userId;
  final String userName;
  final String userRole;

  const UserDetailScreen({
    super.key,
    required this.userId,
    required this.userName,
    required this.userRole,
  });

  @override
  State<UserDetailScreen> createState() => _UserDetailScreenState();
}

class _UserDetailScreenState extends State<UserDetailScreen> {
  bool _isLoading = true;
  Map<String, dynamic>? _data;
  String _selectedCourse = 'All Courses';
  String _selectedSemester = 'All';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final result = await ApiService.getUserAttendance(widget.userId);
      setState(() {
        _data = result;
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading user attendance: $e');
      setState(() => _isLoading = false);
    }
  }

  List<String> _getCourseOptions(List<dynamic> items) {
    final names = items
        .map((item) => (item['course_name'] ?? 'Unknown').toString())
        .toSet()
        .toList();
    names.sort();
    return ['All Courses', ...names];
  }

  List<dynamic> _applyFilters(List<dynamic> items) {
    return items.where((item) {
      final matchesCourse =
          _selectedCourse == 'All Courses' ||
          item['course_name'] == _selectedCourse;
      final matchesSemester =
          _selectedSemester == 'All' ||
          (item['semester']?.toString().toLowerCase() ==
              _selectedSemester.toLowerCase());
      return matchesCourse && matchesSemester;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final isStudent = widget.userRole == 'student';

    return Scaffold(
      appBar: AppBar(title: Text(widget.userName)),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _data == null
          ? const Center(child: Text('Failed to load data'))
          : RefreshIndicator(
              onRefresh: _loadData,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _data!['email'] ?? '',
                      style: const TextStyle(color: Colors.grey, fontSize: 13),
                    ),
                    const SizedBox(height: 16),
                    if (isStudent)
                      ..._buildStudentView()
                    else
                      ..._buildTeacherView(),
                  ],
                ),
              ),
            ),
    );
  }

  List<Widget> _buildStudentView() {
    final allRecords = _data!['records'] as List<dynamic>? ?? [];
    final courseOptions = _getCourseOptions(allRecords);
    final filteredRecords = _applyFilters(allRecords);

    final presentCount = filteredRecords
        .where((r) => r['status'] == 'present')
        .length;
    final absentCount = filteredRecords
        .where((r) => r['status'] == 'absent')
        .length;

    return [
      Row(
        children: [
          _statBox(
            presentCount.toString(),
            'Present',
            const Color(0xFFE8F5E9),
            const Color(0xFF1B5E20),
          ),
          const SizedBox(width: 8),
          _statBox(
            absentCount.toString(),
            'Absent',
            const Color(0xFFFFEBEE),
            const Color(0xFFC62828),
          ),
          const SizedBox(width: 8),
          _statBox(
            filteredRecords.length.toString(),
            'Total',
            const Color(0xFFE3F2FD),
            const Color(0xFF0D47A1),
          ),
        ],
      ),
      const SizedBox(height: 16),
      SizedBox(
        height: 48,
        child: Row(
          children: [
            Expanded(child: _courseFilterDropdown(courseOptions)),
            const SizedBox(width: 8),
            Expanded(child: _semesterFilterDropdown()),
          ],
        ),
      ),
      const SizedBox(height: 20),
      const Text(
        'Attendance Records',
        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 12),
      if (filteredRecords.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 32),
          child: Center(
            child: Text('No attendance records match these filters'),
          ),
        )
      else
        ...filteredRecords.map(
          (r) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _recordCard(r),
          ),
        ),
    ];
  }

  Widget _courseFilterDropdown(List<String> options) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFE0E0E0)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _selectedCourse,
          isExpanded: true,
          items: options
              .map(
                (c) => DropdownMenuItem(
                  value: c,
                  child: Text(c, overflow: TextOverflow.ellipsis),
                ),
              )
              .toList(),
          onChanged: (val) => setState(() => _selectedCourse = val!),
        ),
      ),
    );
  }

  Widget _semesterFilterDropdown() {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFE0E0E0)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _selectedSemester,
          isExpanded: true,
          items: const [
            DropdownMenuItem(value: 'All', child: Text('All Semesters')),
            DropdownMenuItem(value: 'first', child: Text('First Semester')),
            DropdownMenuItem(value: 'second', child: Text('Second Semester')),
          ],
          onChanged: (val) => setState(() => _selectedSemester = val!),
        ),
      ),
    );
  }

  Widget _recordCard(Map<String, dynamic> r) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(12),
        border: Border(
          left: BorderSide(
            color: r['status'] == 'present'
                ? const Color(0xFF1B5E20)
                : const Color(0xFFC62828),
            width: 3,
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  r['course_name'] ?? 'Unknown',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  r['course_code'] ?? '',
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
                const SizedBox(height: 3),
                Text(
                  r['marked_at'] ?? '',
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: r['status'] == 'present'
                  ? const Color(0xFFE8F5E9)
                  : const Color(0xFFFFEBEE),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              r['status'] ?? '',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: r['status'] == 'present'
                    ? const Color(0xFF1B5E20)
                    : const Color(0xFFC62828),
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildTeacherView() {
    final allSessions = _data!['sessions'] as List<dynamic>? ?? [];
    final courseOptions = _getCourseOptions(allSessions);
    final filteredSessions = _applyFilters(allSessions);

    return [
      Row(
        children: [
          _statBox(
            filteredSessions.length.toString(),
            'Sessions Opened',
            const Color(0xFFE3F2FD),
            const Color(0xFF0D47A1),
          ),
        ],
      ),
      const SizedBox(height: 16),
      SizedBox(
        height: 48,
        child: Row(
          children: [
            Expanded(child: _courseFilterDropdown(courseOptions)),
            const SizedBox(width: 8),
            Expanded(child: _semesterFilterDropdown()),
          ],
        ),
      ),
      const SizedBox(height: 20),
      const Text(
        'Sessions',
        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 12),
      if (filteredSessions.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 32),
          child: Center(child: Text('No sessions match these filters')),
        )
      else
        ...filteredSessions.map(
          (s) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _sessionCard(s),
          ),
        ),
    ];
  }

  Widget _sessionCard(Map<String, dynamic> s) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(12),
        border: Border(
          left: BorderSide(
            color: s['is_active'] == true
                ? const Color(0xFF1B5E20)
                : Colors.grey,
            width: 3,
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s['course_name'] ?? 'Unknown',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                if (s['opened_outside_schedule'] == true) ...[
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF3E0),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      'Outside scheduled time',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFFE65100),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 3),
                Text(
                  s['course_code'] ?? '',
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
                const SizedBox(height: 3),
                Text(
                  'Opened: ${s['opened_at'] ?? ''}',
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${s['attendance_count'] ?? 0} marked',
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: s['is_active'] == true
                      ? const Color(0xFFE8F5E9)
                      : const Color(0xFFF5F5F5),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  s['is_active'] == true ? 'Active' : 'Closed',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: s['is_active'] == true
                        ? const Color(0xFF1B5E20)
                        : Colors.grey,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statBox(String value, String label, Color bg, Color fg) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: fg,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(fontSize: 10, color: fg),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'user_detail_screen.dart';

class StudentSearchScreen extends StatefulWidget {
  const StudentSearchScreen({super.key});

  @override
  State<StudentSearchScreen> createState() => _StudentSearchScreenState();
}

class _StudentSearchScreenState extends State<StudentSearchScreen> {
  final _searchController = TextEditingController();
  List<dynamic> _departments = [];
  String? _selectedDepartmentId;
  int? _selectedLevel;
  List<dynamic> _results = [];
  bool _isLoading = false;
  bool _hasSearched = false;

  final List<int> _levels = [100, 200, 300, 400, 500];

  @override
  void initState() {
    super.initState();
    _loadDepartments();
  }

  Future<void> _loadDepartments() async {
    try {
      final deps = await ApiService.getDepartments();
      setState(() => _departments = deps);
    } catch (e) {
      print('Error loading departments: $e');
    }
  }

  Future<void> _search() async {
    setState(() {
      _isLoading = true;
      _hasSearched = true;
    });
    try {
      final results = await ApiService.searchStudents(
        departmentId: _selectedDepartmentId,
        level: _selectedLevel,
        query: _searchController.text.trim(),
      );
      setState(() {
        _results = results;
        _isLoading = false;
      });
    } catch (e) {
      print('Error searching students: $e');
      setState(() => _isLoading = false);
    }
  }

  void _clearFilters() {
    setState(() {
      _selectedDepartmentId = null;
      _selectedLevel = null;
      _searchController.clear();
      _results = [];
      _hasSearched = false;
    });
  }

  String _departmentName(String? id) {
    if (id == null) return '';
    final dept = _departments.firstWhere(
      (d) => d['id'] == id,
      orElse: () => null,
    );
    return dept != null ? dept['name'] : '';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Search Students'),
        actions: [
          IconButton(
            icon: const Icon(Icons.clear_all),
            onPressed: _clearFilters,
            tooltip: 'Clear filters',
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search by name, email, or matricule',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onSubmitted: (_) => _search(),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          border: Border.all(color: const Color(0xFFE0E0E0)),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _selectedDepartmentId,
                            isExpanded: true,
                            hint: const Text('Department'),
                            items: _departments
                                .map<DropdownMenuItem<String>>(
                                  (d) => DropdownMenuItem<String>(
                                    value: d['id'],
                                    child: Text(
                                      d['name'],
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: (val) =>
                                setState(() => _selectedDepartmentId = val),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          border: Border.all(color: const Color(0xFFE0E0E0)),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<int>(
                            value: _selectedLevel,
                            isExpanded: true,
                            hint: const Text('Level'),
                            items: _levels
                                .map<DropdownMenuItem<int>>(
                                  (l) => DropdownMenuItem<int>(
                                    value: l,
                                    child: Text('Level $l'),
                                  ),
                                )
                                .toList(),
                            onChanged: (val) =>
                                setState(() => _selectedLevel = val),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _search,
                    icon: const Icon(Icons.search),
                    label: const Text('Search'),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : !_hasSearched
                ? const Center(
                    child: Text(
                      'Use the filters above to search for students',
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                : _results.isEmpty
                ? const Center(
                    child: Text(
                      'No students found',
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _results.length,
                    itemBuilder: (context, index) {
                      final s = _results[index];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _studentCard(s),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _studentCard(Map<String, dynamic> s) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => UserDetailScreen(
              userId: s['id'],
              userName: s['full_name'] ?? '',
              userRole: 'student',
            ),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Theme.of(context).cardTheme.color,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6),
          ],
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: const Color(0xFFE8F5E9),
              child: const Icon(Icons.person, color: Color(0xFF1B5E20)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s['full_name'] ?? '',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    s['email'] ?? '',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  if (s['matricule'] != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      s['matricule'],
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                  if (s['level'] != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      '${_departmentName(s['department_id'])} · Level ${s['level']}',
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                  ],
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.grey),
          ],
        ),
      ),
    );
  }
}

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ApiService {
  static const String baseUrl = 'http://127.0.0.1:8001';

  // ---- Token Management ----
  static Future<void> saveToken(
    String token,
    String role,
    String userId,
    String fullName,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('token', token);
    await prefs.setString('role', role);
    await prefs.setString('userId', userId);
    await prefs.setString('fullName', fullName);
  }

  static Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('token');
  }

  static Future<String?> getRole() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('role');
  }

  static Future<String?> getFullName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('fullName');
  }

  static Future<void> clearToken() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }

  static Future<Map<String, String>> getAuthHeaders() async {
    final token = await getToken();
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  static Future<Map<String, dynamic>> login(
    String email,
    String password,
    String faceImage,
    String faceImageTurned,
  ) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'email': email,
        'password': password,
        'face_image': faceImage,
        'face_image_turned': faceImageTurned,
      }),
    );
    return jsonDecode(response.body);
  }

  static Future<Map<String, dynamic>> adminLogin(
    String email,
    String password,
  ) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/auth/admin-login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email, 'password': password}),
    );
    return jsonDecode(response.body);
  }

  static Future<Map<String, dynamic>> register(
    String fullName,
    String email,
    String password,
    String role,
    String faceImage,
    String faceImageTurned,
    String? matricule,
    String? departmentId,
    int? level,
  ) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/auth/register'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'full_name': fullName,
        'email': email,
        'password': password,
        'role': role,
        'face_image': faceImage,
        'face_image_turned': faceImageTurned,
        'matricule': matricule,
        'department_id': departmentId,
        'level': level,
      }),
    );
    return jsonDecode(response.body);
  }

  // ---- Courses ----
  static Future<List<dynamic>> getCourses() async {
    final headers = await getAuthHeaders();
    final response = await http.get(
      Uri.parse('$baseUrl/api/courses'),
      headers: headers,
    );
    return jsonDecode(response.body);
  }

  static Future<Map<String, dynamic>> createCourse(
    Map<String, dynamic> data,
  ) async {
    final headers = await getAuthHeaders();
    final response = await http.post(
      Uri.parse('$baseUrl/api/courses'),
      headers: headers,
      body: jsonEncode(data),
    );
    return jsonDecode(response.body);
  }

  static Future<Map<String, dynamic>> deleteCourse(String courseId) async {
    final headers = await getAuthHeaders();
    final response = await http.delete(
      Uri.parse('$baseUrl/api/courses/$courseId'),
      headers: headers,
    );
    return jsonDecode(response.body);
  }

  // ---- Departments ----
  static Future<List<dynamic>> getDepartments() async {
    final headers = await getAuthHeaders();
    final response = await http.get(
      Uri.parse('$baseUrl/api/departments'),
      headers: headers,
    );
    return jsonDecode(response.body);
  }

  static Future<List<dynamic>> getDepartmentsPublic() async {
    final response = await http.get(Uri.parse('$baseUrl/api/departments'));
    return jsonDecode(response.body);
  }

  static Future<Map<String, dynamic>> createDepartment(
    String name,
    String code,
  ) async {
    final headers = await getAuthHeaders();
    final response = await http.post(
      Uri.parse('$baseUrl/api/departments'),
      headers: headers,
      body: jsonEncode({'name': name, 'code': code}),
    );
    return jsonDecode(response.body);
  }

  // ---- Attendance Sessions ----
  static Future<Map<String, dynamic>> openSession(
    String courseId,
    double latitude,
    double longitude,
    int durationMinutes,
    double radiusMeters, {
    bool confirmDuplicate = false,
    bool confirmOutsideSchedule = false,
  }) async {
    final headers = await getAuthHeaders();
    final response = await http.post(
      Uri.parse('$baseUrl/api/attendance/sessions/open'),
      headers: headers,
      body: jsonEncode({
        'course_id': courseId,
        'latitude': latitude,
        'longitude': longitude,
        'duration_minutes': durationMinutes,
        'radius_meters': radiusMeters,
        'confirm_duplicate': confirmDuplicate,
        'confirm_outside_schedule': confirmOutsideSchedule,
      }),
    );
    return jsonDecode(response.body);
  }

  static Future<Map<String, dynamic>> closeSession(String sessionId) async {
    final headers = await getAuthHeaders();
    final response = await http.post(
      Uri.parse('$baseUrl/api/attendance/sessions/$sessionId/close'),
      headers: headers,
    );
    return jsonDecode(response.body);
  }

  static Future<List<dynamic>> getActiveSessions() async {
    final headers = await getAuthHeaders();
    final response = await http.get(
      Uri.parse('$baseUrl/api/attendance/sessions/active'),
      headers: headers,
    );
    return jsonDecode(response.body);
  }

  // ---- Mark Attendance ----
  static Future<Map<String, dynamic>> markAttendance(
    String sessionId,
    String faceImage,
    String faceImageTurned,
    double latitude,
    double longitude,
  ) async {
    final headers = await getAuthHeaders();
    final response = await http.post(
      Uri.parse('$baseUrl/api/attendance/mark'),
      headers: headers,
      body: jsonEncode({
        'session_id': sessionId,
        'face_image': faceImage,
        'face_image_turned': faceImageTurned,
        'latitude': latitude,
        'longitude': longitude,
      }),
    );
    return jsonDecode(response.body);
  }

  // ---- Admin ----
  static Future<List<dynamic>> getAllUsers() async {
    final headers = await getAuthHeaders();
    final response = await http.get(
      Uri.parse('$baseUrl/api/admin/users'),
      headers: headers,
    );
    return jsonDecode(response.body);
  }

  static Future<List<dynamic>> searchStudents({
    String? departmentId,
    int? level,
    String? query,
  }) async {
    final headers = await getAuthHeaders();
    final params = <String, String>{};
    if (departmentId != null) params['department_id'] = departmentId;
    if (level != null) params['level'] = level.toString();
    if (query != null && query.isNotEmpty) params['query'] = query;

    final uri = Uri.parse(
      '$baseUrl/api/admin/students/search',
    ).replace(queryParameters: params.isEmpty ? null : params);

    final response = await http.get(uri, headers: headers);
    return jsonDecode(response.body);
  }

  static Future<Map<String, dynamic>> getSessionLogs() async {
    final headers = await getAuthHeaders();
    final response = await http.get(
      Uri.parse('$baseUrl/api/admin/session-logs'),
      headers: headers,
    );
    return jsonDecode(response.body);
  }

  static Future<Map<String, dynamic>> getUserAttendance(String userId) async {
    final headers = await getAuthHeaders();
    final response = await http.get(
      Uri.parse('$baseUrl/api/admin/users/$userId/attendance'),
      headers: headers,
    );
    return jsonDecode(response.body);
  }

  static Future<Map<String, dynamic>> createAdmin(
    String fullName,
    String email,
    String password,
    String faceImage,
  ) async {
    final headers = await getAuthHeaders();
    final response = await http.post(
      Uri.parse('$baseUrl/api/admin/create-admin'),
      headers: headers,
      body: jsonEncode({
        'full_name': fullName,
        'email': email,
        'password': password,
        'role': 'admin',
        'face_image': faceImage,
      }),
    );
    return jsonDecode(response.body);
  }

  static Future<Map<String, dynamic>> createTeacher(
    String fullName,
    String email,
    String password,
    String faceImage,
  ) async {
    final headers = await getAuthHeaders();
    final response = await http.post(
      Uri.parse('$baseUrl/api/admin/create-teacher'),
      headers: headers,
      body: jsonEncode({
        'full_name': fullName,
        'email': email,
        'password': password,
        'face_image': faceImage,
      }),
    );
    return jsonDecode(response.body);
  }

  static Future<Map<String, dynamic>> assignTeacher(
    String courseId,
    String teacherId,
  ) async {
    final headers = await getAuthHeaders();
    final response = await http.post(
      Uri.parse('$baseUrl/api/courses/$courseId/assign-teacher'),
      headers: headers,
      body: jsonEncode({'teacher_id': teacherId}),
    );
    return jsonDecode(response.body);
  }

  static Future<Map<String, dynamic>> getMyRecords() async {
    final headers = await getAuthHeaders();
    final response = await http.get(
      Uri.parse('$baseUrl/api/attendance/my-records'),
      headers: headers,
    );
    return jsonDecode(response.body);
  }

  static Future<Map<String, dynamic>> getSessionRecords(
    String sessionId,
  ) async {
    final headers = await getAuthHeaders();
    final response = await http.get(
      Uri.parse('$baseUrl/api/attendance/sessions/$sessionId/records'),
      headers: headers,
    );
    return jsonDecode(response.body);
  }
}

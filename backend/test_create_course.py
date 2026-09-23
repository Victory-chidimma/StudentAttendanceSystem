import requests

# Step 1: Login as admin
login_response = requests.post(
    "http://127.0.0.1:8001/api/auth/admin-login",
    json={"email": "admin@hims.edu", "password": "Admin123"}
)
print("Login status:", login_response.status_code)
token = login_response.json()["access_token"]
headers = {"Authorization": f"Bearer {token}"}

# Step 2: Get departments to find the department_id
dept_response = requests.get("http://127.0.0.1:8001/api/departments", headers=headers)
print("Departments:", dept_response.json())
# Step 3: Create a course
course_data = {
    "name": "Test Course",
    "code": "TEST101",
    "department_id": "d479bb9c-136e-4039-91b7-4514414980d0",
    "semester": "first",
    "level": "100"
}

create_response = requests.post(
    "http://127.0.0.1:8001/api/courses",
    json=course_data,
    headers=headers
)
print("Create course status:", create_response.status_code)
print("Response:", create_response.json())
# Test viewing a student's attendance as admin
users_response = requests.get("http://127.0.0.1:8001/api/admin/users", headers=headers)
users = users_response.json()
print("Users:", users)

# pick the first student
student = next((u for u in users if u["role"] == "student"), None)
if student:
    detail_response = requests.get(
        f"http://127.0.0.1:8001/api/admin/users/{student['id']}/attendance",
        headers=headers
    )
    print("Student attendance:", detail_response.json())
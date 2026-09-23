import requests

# Step 1: Login as admin
login_response = requests.post(
    "http://127.0.0.1:8001/api/auth/admin-login",
    json={"email": "admin@hims.edu", "password": "Admin123"}
)
print("Login status:", login_response.status_code)
token = login_response.json()["access_token"]
headers = {"Authorization": f"Bearer {token}"}

# Step 2: Get all users
users_response = requests.get("http://127.0.0.1:8001/api/admin/users", headers=headers)
users = users_response.json()
print("Users:", users)

# Step 3: Pick the first student and check their attendance
student = next((u for u in users if u["email"] == "student1@test.com"), None)
if student:
    print("Checking attendance for:", student["email"])
    detail_response = requests.get(
        f"http://127.0.0.1:8001/api/admin/users/{student['id']}/attendance",
        headers=headers
    )
    print("Status:", detail_response.status_code)
    print("Student attendance:", detail_response.json())
else:
    print("No student found")
from app.database import SessionLocal
from app.models import User
from app.utils.security import verify_password

db = SessionLocal()

# Exact same query as admin_login route
user = db.query(User).filter(User.email == "admin@hims.edu", User.role == "admin").first()

if not user:
    print("QUERY WITH ROLE FILTER: NO USER FOUND")
else:
    print("QUERY WITH ROLE FILTER: FOUND -", user.email, user.role)

# Also check what role value is actually stored
user2 = db.query(User).filter(User.email == "admin@hims.edu").first()
if user2:
    print("Raw role value:", repr(user2.role))
    print("Role type:", type(user2.role))

db.close()
from app.database import engine, Base
from app.models import User, Department, Course, AttendanceSession, Attendance

Base.metadata.create_all(bind=engine)
print("Tables created successfully!")
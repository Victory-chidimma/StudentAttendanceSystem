
from sqlalchemy import Column, String, Integer, Boolean, DateTime, ForeignKey, Float, Enum, Time
from sqlalchemy.orm import relationship
from app.database import Base
from datetime import datetime
import enum

# Enums
class UserRole(str, enum.Enum):
    student = "student"
    teacher = "teacher"
    admin = "admin"

class SemesterType(str, enum.Enum):
    first = "first"
    second = "second"

class AttendanceStatus(str, enum.Enum):
    present = "present"
    absent = "absent"

# Models
class User(Base):
    __tablename__ = "users"
    id = Column(String, primary_key=True)
    full_name = Column(String, nullable=False)
    email = Column(String, unique=True, nullable=False)
    password = Column(String, nullable=False)
    role = Column(Enum(UserRole), nullable=False)
    face_image = Column(String, nullable=True)
    matricule = Column(String, nullable=True)
    department_id = Column(String, nullable=True)
    level = Column(Integer, nullable=True)
    is_active = Column(Boolean, default=True)
    created_at = Column(DateTime, default=datetime.utcnow)

class Department(Base):
    __tablename__ = "departments"
    id = Column(String, primary_key=True)
    name = Column(String, nullable=False)
    code = Column(String, unique=True, nullable=False)

class Course(Base):
    __tablename__ = "courses"
    id = Column(String, primary_key=True)
    name = Column(String, nullable=False)
    code = Column(String, unique=True, nullable=False)
    department_id = Column(String, ForeignKey("departments.id"))
    teacher_id = Column(String, ForeignKey("users.id"))
    semester = Column(Enum(SemesterType), nullable=False)
    level = Column(Integer, nullable=False)
    start_time = Column(Time, nullable=True)
    end_time = Column(Time, nullable=True)

class AttendanceSession(Base):
    __tablename__ = "attendance_sessions"
    id = Column(String, primary_key=True)
    course_id = Column(String, ForeignKey("courses.id"))
    teacher_id = Column(String, ForeignKey("users.id"))
    opened_at = Column(DateTime, default=datetime.utcnow)
    closes_at = Column(DateTime, nullable=False)
    is_active = Column(Boolean, default=True)
    latitude = Column(Float, nullable=True)
    longitude = Column(Float, nullable=True)
    radius_meters = Column(Float, default=100.0)
    opened_outside_schedule = Column(Boolean, default=False)

class Attendance(Base):
    __tablename__ = "attendance"
    id = Column(String, primary_key=True)
    session_id = Column(String, ForeignKey("attendance_sessions.id"))
    student_id = Column(String, ForeignKey("users.id"))
    status = Column(Enum(AttendanceStatus), nullable=False)
    marked_at = Column(DateTime, default=datetime.utcnow)
    face_verified = Column(Boolean, default=False)
    location_verified = Column(Boolean, default=False)

from pydantic import BaseModel, EmailStr
from typing import Optional
from enum import Enum
from datetime import datetime

class UserRole(str, Enum):
    student = "student"
    teacher = "teacher"
    admin = "admin"

# ---------- AUTH SCHEMAS ----------
class RegisterRequest(BaseModel):
    full_name: str
    email: EmailStr
    password: str
    role: UserRole
    face_image: str  # base64 encoded image
    face_image_turned: str  # second frame, head turned, for liveness check
    matricule: str | None = None
    department_id: str | None = None
    level: int | None = None

class LoginRequest(BaseModel):
    email: str
    password: str
    face_image: Optional[str] = None
    face_image_turned: Optional[str] = None
    
class AdminLoginRequest(BaseModel):
    email: EmailStr
    password: str

class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    user_id: str
    full_name: str
    role: UserRole

class UserResponse(BaseModel):
    id: str
    full_name: str
    email: str
    role: UserRole
    is_active: bool

class Config:
        from_attributes = True

class SessionCreateRequest(BaseModel):
    course_id: str
    latitude: float
    longitude: float
    duration_minutes: int
    radius_meters: float = 100.0
    confirm_duplicate: bool = False
    confirm_outside_schedule: bool = False

class SessionResponse(BaseModel):
    id: str
    course_id: str
    teacher_id: str
    opened_at: datetime
    closes_at: datetime
    is_active: bool
    latitude: float
    longitude: float
    radius_meters: float

class AttendanceMarkRequest(BaseModel):
    session_id: str
    face_image: str
    face_image_turned: str
    latitude: float
    longitude: float

class AttendanceResponse(BaseModel):
    id: str
    session_id: str
    student_id: str
    status: str
    marked_at: datetime
    face_verified: bool
    location_verified: bool

class UpdateFaceRequest(BaseModel):
    password: str
    face_image: str
    face_image_turned: str

class UpdateFaceResponse(BaseModel):
    message: str
    status: str  # "accepted" or "accepted_flagged"
    distance: float

class AdminUpdateTeacherFaceRequest(BaseModel):
    face_image: str
    face_image_turned: str
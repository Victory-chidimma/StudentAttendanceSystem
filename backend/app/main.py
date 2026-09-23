from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from dotenv import load_dotenv
import os
from datetime import datetime
from apscheduler.schedulers.background import BackgroundScheduler

load_dotenv()

from app.routes import auth, students, teachers, admin, attendance, courses
from app.database import SessionLocal
from app.models import AttendanceSession

# Load environment variables
load_dotenv()

from app.routes import auth, students, teachers, admin, attendance, courses 

app = FastAPI(
    title="Attendance System API",
    description="Facial Recognition Attendance System",
    version="1.0.0"
)

# ---------- BACKGROUND JOB: Auto-close expired sessions ----------
def close_expired_sessions():
    db = SessionLocal()
    try:
        now = datetime.utcnow()
        expired = (
            db.query(AttendanceSession)
            .filter(AttendanceSession.is_active == True, AttendanceSession.closes_at < now)
            .all()
        )
        for s in expired:
            s.is_active = False
        if expired:
            db.commit()
            print(f"[Scheduler] Auto-closed {len(expired)} expired session(s)")
    finally:
        db.close()

scheduler = BackgroundScheduler()
scheduler.add_job(close_expired_sessions, 'interval', minutes=1)
scheduler.start()

# CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Routes
app.include_router(auth.router, prefix="/api/auth", tags=["Authentication"])
app.include_router(students.router, prefix="/api/students", tags=["Students"])
app.include_router(teachers.router, prefix="/api/teachers", tags=["Teachers"])
app.include_router(admin.router, prefix="/api/admin", tags=["Admin"])
app.include_router(attendance.router, prefix="/api/attendance", tags=["Attendance"])
app.include_router(courses.router, prefix="/api", tags=["Courses"])

@app.get("/")
def root():
    return {
        "message": "Attendance System API is running!",
        "database": os.getenv("SUPABASE_URL")
    }
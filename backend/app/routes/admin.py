from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from uuid import uuid4
import bcrypt

from app.database import get_db
from app.models import User
from app.utils.security import get_current_user
from app.services.face_service import (
    decode_base64_image,
    get_face_encoding,
)

router = APIRouter()


@router.get("/test")
def admin_root():
    return {"message": "Admin route working"}


@router.get("/users")
def get_all_users(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    if current_user.role != "admin":
        raise HTTPException(status_code=403, detail="Only admins can view all users")
    users = db.query(User).all()
    return [
        {
            "id": u.id,
            "full_name": u.full_name,
            "email": u.email,
            "role": u.role,
            "created_at": u.created_at,
        }
        for u in users
    ]
@router.get("/students/search")
def search_students(
    department_id: str = None,
    level: int = None,
    query: str = None,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    if current_user.role != "admin":
        raise HTTPException(status_code=403, detail="Only admins can search students")

    students_query = db.query(User).filter(User.role == "student")

    if department_id:
        students_query = students_query.filter(User.department_id == department_id)

    if level:
        students_query = students_query.filter(User.level == level)

    if query:
        search = f"%{query}%"
        students_query = students_query.filter(
            (User.full_name.ilike(search))
            | (User.email.ilike(search))
            | (User.matricule.ilike(search))
        )

    students = students_query.all()

    return [
        {
            "id": s.id,
            "full_name": s.full_name,
            "email": s.email,
            "matricule": s.matricule,
            "department_id": s.department_id,
            "level": s.level,
        }
        for s in students
    ]
@router.get("/users/{user_id}/attendance")
def get_user_attendance(
    user_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    if current_user.role != "admin":
        raise HTTPException(status_code=403, detail="Only admins can view user attendance")

    target_user = db.query(User).filter(User.id == user_id).first()
    if not target_user:
        raise HTTPException(status_code=404, detail="User not found")

    from app.models import Attendance, AttendanceSession, Course

    if target_user.role == "student":
        records = (
            db.query(Attendance)
            .filter(Attendance.student_id == user_id)
            .order_by(Attendance.marked_at.desc())
            .all()
        )
        present_count = sum(1 for r in records if r.status == "present")
        absent_count = sum(1 for r in records if r.status == "absent")

        result = []
        for r in records:
            session = db.query(AttendanceSession).filter(AttendanceSession.id == r.session_id).first()
            course = db.query(Course).filter(Course.id == session.course_id).first() if session else None
            result.append({
                "id": r.id,
                "session_id": r.session_id,
                "course_name": course.name if course else "Unknown",
                "course_code": course.code if course else "",
                "semester": course.semester if course else None,
                "status": r.status,
                "marked_at": str(r.marked_at),
                "face_verified": r.face_verified,
                "location_verified": r.location_verified,
            })

        return {
            "user_id": user_id,
            "full_name": target_user.full_name,
            "email": target_user.email,
            "role": target_user.role,
            "present_count": present_count,
            "absent_count": absent_count,
            "total": len(records),
            "records": result,
        }

    elif target_user.role == "teacher":
        sessions = (
            db.query(AttendanceSession)
            .filter(AttendanceSession.teacher_id == user_id)
            .order_by(AttendanceSession.opened_at.desc())
            .all()
        )

        result = []
        for s in sessions:
            course = db.query(Course).filter(Course.id == s.course_id).first()
            attendance_count = db.query(Attendance).filter(Attendance.session_id == s.id).count()
            result.append({
                "session_id": s.id,
                "course_name": course.name if course else "Unknown",
                "course_code": course.code if course else "",
                "semester": course.semester if course else None,
                "opened_at": str(s.opened_at),
                "closes_at": str(s.closes_at),
                "is_active": s.is_active,
                "attendance_count": attendance_count,
                "opened_outside_schedule": s.opened_outside_schedule,
            })

        return {
            "user_id": user_id,
            "full_name": target_user.full_name,
            "email": target_user.email,
            "role": target_user.role,
            "total_sessions": len(sessions),
            "sessions": result,
        }

    else:
        return {
            "user_id": user_id,
            "full_name": target_user.full_name,
            "email": target_user.email,
            "role": target_user.role,
            "message": "No attendance data for this role",
        }


@router.post("/create-admin")
def create_admin(
    data: dict,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    if current_user.role != "admin":
        raise HTTPException(status_code=403, detail="Only admins can create admin accounts")

    existing = db.query(User).filter(User.email == data["email"]).first()
    if existing:
        raise HTTPException(status_code=400, detail="Email already registered")

    image_array = decode_base64_image(data["face_image"])
    encoding, error = get_face_encoding(image_array)
    if error:
        raise HTTPException(status_code=400, detail=error)

    hashed = bcrypt.hashpw(data["password"].encode(), bcrypt.gensalt()).decode()

    user = User(
        id=str(uuid4()),
        full_name=data["full_name"],
        email=data["email"],
        password=hashed,
        role="admin",
        face_image=str(encoding.tolist()),
    )
    db.add(user)
    db.commit()
    db.refresh(user)

    return {"message": "Admin created successfully", "user_id": user.id, "email": user.email}
@router.post("/create-teacher")
def create_teacher(
    data: dict,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    if current_user.role != "admin":
        raise HTTPException(status_code=403, detail="Only admins can create teacher accounts")

    existing = db.query(User).filter(User.email == data["email"]).first()
    if existing:
        raise HTTPException(status_code=400, detail="Email already registered")

    image_array = decode_base64_image(data["face_image"])
    encoding, error = get_face_encoding(image_array)
    if error:
        raise HTTPException(status_code=400, detail=error)

    hashed = bcrypt.hashpw(data["password"].encode(), bcrypt.gensalt()).decode()

    user = User(
        id=str(uuid4()),
        full_name=data["full_name"],
        email=data["email"],
        password=hashed,
        role="teacher",
        face_image=str(encoding.tolist()),
    )
    db.add(user)
    db.commit()
    db.refresh(user)

    return {"message": "Teacher created successfully", "user_id": user.id, "email": user.email}

@router.get("/session-logs")
def get_session_logs(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    if current_user.role != "admin":
        raise HTTPException(status_code=403, detail="Only admins can view session logs")

    from app.models import AttendanceSession, Attendance, Course

    sessions = (
        db.query(AttendanceSession)
        .order_by(AttendanceSession.opened_at.desc())
        .all()
    )

    result = []
    for s in sessions:
        course = db.query(Course).filter(Course.id == s.course_id).first()
        teacher = db.query(User).filter(User.id == s.teacher_id).first()
        attendance_count = db.query(Attendance).filter(Attendance.session_id == s.id).count()
        result.append({
            "session_id": s.id,
            "course_name": course.name if course else "Unknown",
            "course_code": course.code if course else "",
            "teacher_name": teacher.full_name if teacher else "Unknown",
            "opened_at": str(s.opened_at),
            "closes_at": str(s.closes_at),
            "is_active": s.is_active,
            "attendance_count": attendance_count,
            "opened_outside_schedule": s.opened_outside_schedule,
        })

    return {
        "total_sessions": len(result),
        "sessions": result,
    }
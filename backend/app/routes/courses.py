from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from uuid import uuid4
from app.models import Course, Department, User, AttendanceSession
from app.database import get_db
from app.models import Course, Department, User
from app.utils.security import get_current_user

router = APIRouter()


# ---------- DEPARTMENTS ----------
@router.post("/departments")
def create_department(
    data: dict,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    if current_user.role != "admin":
        raise HTTPException(status_code=403, detail="Only admins can create departments")

    dept = Department(
        id=str(uuid4()),
        name=data["name"],
        code=data["code"],
    )
    db.add(dept)
    db.commit()
    db.refresh(dept)
    return dept


@router.get("/departments")
def get_departments(
    db: Session = Depends(get_db),
):
    return db.query(Department).all()


# ---------- COURSES ----------
@router.post("/courses")
def create_course(
    data: dict,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    if current_user.role != "admin":
        raise HTTPException(status_code=403, detail="Only admins can create courses")

    # Check department exists
    dept = db.query(Department).filter(Department.id == data["department_id"]).first()
    if not dept:
        raise HTTPException(status_code=404, detail="Department not found")

    # Check teacher exists if provided
    if data.get("teacher_id"):
        teacher = db.query(User).filter(User.id == data["teacher_id"], User.role == "teacher").first()
        if not teacher:
            raise HTTPException(status_code=404, detail="Teacher not found")

    course = Course(
        id=str(uuid4()),
        name=data["name"],
        code=data["code"],
        department_id=data["department_id"],
        teacher_id=data.get("teacher_id"),
        semester=data["semester"],
        level=data["level"],
        start_time=data.get("start_time"),
        end_time=data.get("end_time"),
    )
    db.add(course)
    db.commit()
    db.refresh(course)
    return course

@router.delete("/courses/{course_id}")
def delete_course(
    course_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    if current_user.role != "admin":
        raise HTTPException(status_code=403, detail="Only admins can delete courses")

    course = db.query(Course).filter(Course.id == course_id).first()
    if not course:
        raise HTTPException(status_code=404, detail="Course not found")

    db.delete(course)
    db.commit()

    return {"message": "Course deleted successfully"}


@router.get("/courses")
def get_courses(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    from datetime import datetime

    # Auto-close any expired sessions before returning course data
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

    if current_user.role == "teacher":
        courses = db.query(Course).filter(Course.teacher_id == current_user.id).all()
    else:
        courses = db.query(Course).all()
    
    result = []
    for c in courses:
        # Get active session for this course
        active_session = db.query(AttendanceSession).filter(
            AttendanceSession.course_id == c.id,
            AttendanceSession.is_active == True
        ).first()

        result.append({
            "id": c.id,
            "name": c.name,
            "code": c.code,
            "department_id": c.department_id,
            "teacher_id": c.teacher_id,
            "semester": c.semester,
            "level": c.level,
            "start_time": str(c.start_time) if c.start_time else None,
            "end_time": str(c.end_time) if c.end_time else None,
            "active_session_id": active_session.id if active_session else None,
            "is_active": active_session is not None,
        })
    
    return result
@router.post("/courses/{course_id}/assign-teacher")
def assign_teacher(
    course_id: str,
    data: dict,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    if current_user.role != "admin":
        raise HTTPException(status_code=403, detail="Only admins can assign teachers")

    course = db.query(Course).filter(Course.id == course_id).first()
    if not course:
        raise HTTPException(status_code=404, detail="Course not found")

    teacher = db.query(User).filter(User.id == data["teacher_id"], User.role == "teacher").first()
    if not teacher:
        raise HTTPException(status_code=404, detail="Teacher not found")

    course.teacher_id = data["teacher_id"]
    db.commit()
    db.refresh(course)
    return course
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import func
from sqlalchemy.orm import Session
from uuid import uuid4
from app.models import Course, Department, User, AttendanceSession, TimetableEntry, CourseDepartment
from app.database import get_db
from app.utils.security import get_current_user
from app.utils.timetable_rules import check_teacher_change

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

    dept = db.query(Department).filter(Department.id == data["department_id"]).first()
    if not dept:
        raise HTTPException(status_code=404, detail="Department not found")

    if data.get("teacher_id"):
        teacher = db.query(User).filter(User.id == data["teacher_id"], User.role == "teacher").first()
        if not teacher:
            raise HTTPException(status_code=404, detail="Teacher not found")

    code = data["code"].strip().upper()
    if db.query(Course).filter(func.upper(Course.code) == code).first():
        raise HTTPException(status_code=400, detail=f"A course with code {code} already exists")

    # Extra departments for a joint course (the home department is not repeated)
    joint_ids = []
    for d in data.get("joint_department_ids") or []:
        if d == data["department_id"] or d in joint_ids:
            continue
        if not db.query(Department).filter(Department.id == d).first():
            raise HTTPException(status_code=404, detail="A joint department was not found")
        joint_ids.append(d)

    course = Course(
        id=str(uuid4()),
        name=data["name"].strip(),
        code=code,
        department_id=data["department_id"],
        teacher_id=data.get("teacher_id"),
        semester=data["semester"],
        level=data["level"],
        start_time=data.get("start_time"),
        end_time=data.get("end_time"),
    )
    db.add(course)
    db.flush()
    for d in joint_ids:
        db.add(CourseDepartment(course_id=course.id, department_id=d))
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
    
    if db.query(AttendanceSession).filter(AttendanceSession.course_id == course_id).first():
        raise HTTPException(
            status_code=400,
            detail="This course has attendance records and cannot be deleted.",
        )
    
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

@router.put("/courses/{course_id}")
def update_course(
    course_id: str,
    data: dict,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    if current_user.role != "admin":
        raise HTTPException(status_code=403, detail="Only admins can edit courses")

    course = db.query(Course).filter(Course.id == course_id).first()
    if not course:
        raise HTTPException(status_code=404, detail="Course not found")

    on_timetable = (
        db.query(TimetableEntry).filter(TimetableEntry.course_id == course.id).first() is not None
    )
    current_sem = getattr(course.semester, "value", course.semester)
    new_dept = data.get("department_id", course.department_id)
    new_level = int(data.get("level", course.level))
    new_sem = data.get("semester", current_sem)

    if on_timetable and (
        new_dept != course.department_id or new_level != course.level or new_sem != current_sem
    ):
        raise HTTPException(
            status_code=400,
            detail="This course is on the timetable. Remove its timetable entries before "
                   "changing its department, level or semester.",
        )

    if new_dept != course.department_id:
        if not db.query(Department).filter(Department.id == new_dept).first():
            raise HTTPException(status_code=404, detail="Department not found")

    if "code" in data:
        code = data["code"].strip().upper()
        clash = db.query(Course).filter(func.upper(Course.code) == code, Course.id != course.id).first()
        if clash:
            raise HTTPException(status_code=400, detail=f"A course with code {code} already exists")
        course.code = code

    if data.get("teacher_id") and data["teacher_id"] != course.teacher_id:
        teacher = db.query(User).filter(User.id == data["teacher_id"], User.role == "teacher").first()
        if not teacher:
            raise HTTPException(status_code=404, detail="Teacher not found")
        check_teacher_change(db, course, teacher)
        course.teacher_id = teacher.id

    if "name" in data:
        course.name = data["name"].strip()
    course.department_id = new_dept
    course.level = new_level
    course.semester = new_sem

    db.commit()
    db.refresh(course)
    return course
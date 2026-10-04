import ast
from datetime import datetime, timedelta
from uuid import uuid4

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from sqlalchemy import or_

from app.database import get_db
from app.models import AttendanceSession, Attendance, Course, User, TimetableEntry, CourseDepartment
from app.models.schemas import (
    SessionCreateRequest,
    SessionResponse,
    AttendanceMarkRequest,
    AttendanceResponse,
)
from app.services.face_service import (
    decode_base64_image,
    get_face_encoding,
    compare_faces,
    list_to_encoding,
    detect_head_turn,
)
from app.utils.geo import is_within_radius
from app.utils.security import get_current_user
from app.utils.schedule_rules import (
    to_local,
    academic_year_for,
    block_window,
    locate,
    week_bounds_utc,
    day_bounds_utc,
    used_entry_ids,
)

router = APIRouter()


@router.get("/")
def attendance_root():
    return {"message": "Attendance route working"}


# ---------- TEACHER: OPEN SESSION ----------
@router.post("/sessions/open", response_model=SessionResponse)
def open_session(
    data: SessionCreateRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    if current_user.role != "teacher":
        raise HTTPException(status_code=403, detail="Only teachers can open sessions")

    course = db.query(Course).filter(Course.id == data.course_id).first()
    if not course:
        raise HTTPException(status_code=404, detail="Course not found")

    if course.teacher_id != current_user.id:
        raise HTTPException(status_code=403, detail="You are not assigned to this course")

    now = datetime.utcnow()
    local_now = to_local(now)
    year = academic_year_for(local_now)

    entries = (
        db.query(TimetableEntry)
        .filter(TimetableEntry.course_id == course.id, TimetableEntry.academic_year == year)
        .all()
    )
    if not entries:
        raise HTTPException(
            status_code=400,
            detail=f"This course is not on the {year} timetable. Ask the admin to schedule it first.",
        )

    today_entries = [e for e in entries if e.day_of_week == local_now.weekday()]
    if not today_entries:
        raise HTTPException(
            status_code=400,
            detail="This course has no class scheduled today.",
        )

    week_start, week_end = week_bounds_utc(local_now)
    week_sessions = (
        db.query(AttendanceSession)
        .filter(
            AttendanceSession.course_id == course.id,
            AttendanceSession.opened_at >= week_start,
            AttendanceSession.opened_at < week_end,
        )
        .all()
    )
    used = used_entry_ids(week_sessions, entries)

    # Which of today's classes is this session for?
    target, inside = locate(today_entries, local_now)
    if not inside:
        unused_today = [e for e in today_entries if e.id not in used]
        if not unused_today:
            raise HTTPException(
                status_code=400,
                detail="All of today's classes for this course already had their attendance "
                       "session, and none is running now.",
            )
        target, _ = locate(unused_today, local_now)

    # Reopening a class that already had a session is allowed only while its time is running
    if target.id in used and not data.confirm_duplicate:
        raise HTTPException(status_code=409, detail="DUPLICATE_SESSION_TODAY")

    # Opening outside every class time (a swap, or running late) needs confirmation
    is_outside_schedule = not inside
    if is_outside_schedule and not data.confirm_outside_schedule:
        raise HTTPException(status_code=409, detail="OUTSIDE_SCHEDULED_TIME")

    # Close any existing active session for this course
    existing = (
        db.query(AttendanceSession)
        .filter(AttendanceSession.course_id == data.course_id, AttendanceSession.is_active == True)
        .first()
    )
    if existing:
        existing.is_active = False

    session = AttendanceSession(
        id=str(uuid4()),
        course_id=data.course_id,
        teacher_id=current_user.id,
        opened_at=now,
        closes_at=now + timedelta(minutes=data.duration_minutes),
        is_active=True,
        latitude=data.latitude,
        longitude=data.longitude,
        radius_meters=data.radius_meters,
        opened_outside_schedule=is_outside_schedule,
    )
    db.add(session)
    db.commit()
    db.refresh(session)

    return session

# ---------- TEACHER: CLOSE SESSION ----------
@router.post("/sessions/{session_id}/close", response_model=SessionResponse)
def close_session(
    session_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    session = db.query(AttendanceSession).filter(AttendanceSession.id == session_id).first()
    if not session:
        raise HTTPException(status_code=404, detail="Session not found")

    if session.teacher_id != current_user.id:
        raise HTTPException(status_code=403, detail="You did not open this session")

    session.is_active = False
    db.commit()
    db.refresh(session)

    return session


# ---------- VIEW ACTIVE SESSIONS (auto-closes expired ones) ----------
@router.get("/sessions/active")
def get_active_sessions(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
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

    sessions = db.query(AttendanceSession).filter(AttendanceSession.is_active == True).all()
    
    result = []
    for s in sessions:
        course = db.query(Course).filter(Course.id == s.course_id).first()
        session_dict = {
            "id": s.id,
            "course_id": s.course_id,
            "course_name": course.name if course else "Unknown",
            "course_code": course.code if course else "",
            "teacher_id": s.teacher_id,
            "opened_at": str(s.opened_at),
            "closes_at": str(s.closes_at),
            "is_active": s.is_active,
            "latitude": s.latitude,
            "longitude": s.longitude,
            "radius_meters": s.radius_meters,
        }
        result.append(session_dict)
    
    return result

# ---------- TEACHER: GET ALL MY SESSIONS (active + closed) ----------
@router.get("/sessions/my-sessions")
def get_my_sessions(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    if current_user.role != "teacher":
        raise HTTPException(status_code=403, detail="Only teachers can view their sessions")

    sessions = (
        db.query(AttendanceSession)
        .filter(AttendanceSession.teacher_id == current_user.id)
        .order_by(AttendanceSession.opened_at.desc())
        .all()
    )

    result = []
    for s in sessions:
        course = db.query(Course).filter(Course.id == s.course_id).first()
        attendance_count = (
            db.query(Attendance)
            .filter(Attendance.session_id == s.id)
            .count()
        )
        result.append({
            "id": s.id,
            "course_id": s.course_id,
            "course_name": course.name if course else "Unknown",
            "course_code": course.code if course else "",
            "opened_at": str(s.opened_at),
            "closes_at": str(s.closes_at),
            "is_active": s.is_active,
            "opened_outside_schedule": s.opened_outside_schedule,
            "attendance_count": attendance_count,
        })

    return {"sessions": result}


# ---------- STUDENT: MARK ATTENDANCE (Face + GPS) ----------
@router.post("/mark", response_model=AttendanceResponse)
def mark_attendance(
    data: AttendanceMarkRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    if current_user.role != "student":
        raise HTTPException(status_code=403, detail="Only students can mark attendance")

    session = db.query(AttendanceSession).filter(AttendanceSession.id == data.session_id).first()
    if not session:
        raise HTTPException(status_code=404, detail="Session not found")

    if not session.is_active or session.closes_at < datetime.utcnow():
        raise HTTPException(status_code=400, detail="This session is closed")

    already_marked = (
        db.query(Attendance)
        .filter(Attendance.session_id == data.session_id, Attendance.student_id == current_user.id)
        .first()
    )
    if already_marked:
        raise HTTPException(status_code=400, detail="Attendance already marked for this session")

        # --- Liveness check ---
    frame1_array = decode_base64_image(data.face_image)
    frame2_array = decode_base64_image(data.face_image_turned)
    is_live, liveness_error = detect_head_turn(frame1_array, frame2_array)
    if not is_live:
        raise HTTPException(status_code=400, detail=f"Liveness check failed: {liveness_error}")

    # --- Face verification ---
    image_array = decode_base64_image(data.face_image)
    incoming_encoding, error = get_face_encoding(image_array)
    if error:
        raise HTTPException(status_code=400, detail=error)


    stored_encoding = list_to_encoding(ast.literal_eval(current_user.face_image))
    face_verified, distance = compare_faces(stored_encoding, incoming_encoding)

    # --- GPS verification ---
    location_verified = is_within_radius(
        data.latitude, data.longitude, session.latitude, session.longitude, session.radius_meters
    )

    if not face_verified or not location_verified:
        raise HTTPException(
            status_code=400,
            detail=f"Verification failed. Face match: {face_verified}, Location within range: {location_verified}",
        )

    attendance = Attendance(
        id=str(uuid4()),
        session_id=data.session_id,
        student_id=current_user.id,
        status="present",
        marked_at=datetime.utcnow(),
        face_verified=face_verified,
        location_verified=location_verified,
    )
    db.add(attendance)
    db.commit()
    db.refresh(attendance)

    return attendance

# ---------- STUDENT: GET OWN ATTENDANCE RECORDS ----------
@router.get("/my-records")
def get_my_records(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    if current_user.role != "student":
        raise HTTPException(status_code=403, detail="Only students can view their records")

    records = (
        db.query(Attendance)
        .filter(Attendance.student_id == current_user.id)
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
            "status": r.status,
            "marked_at": str(r.marked_at),
            "face_verified": r.face_verified,
            "location_verified": r.location_verified,
        })

    return {
        "present_count": present_count,
        "absent_count": absent_count,
        "total": len(records),
        "records": result,
    }
# ---------- TEACHER: GET SESSION ATTENDANCE RECORDS ----------
@router.get("/sessions/{session_id}/records")
def get_session_records(
    session_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    if current_user.role != "teacher" and current_user.role != "admin":
        raise HTTPException(status_code=403, detail="Only teachers and admins can view session records")

    session = db.query(AttendanceSession).filter(AttendanceSession.id == session_id).first()
    if not session:
        raise HTTPException(status_code=404, detail="Session not found")

    records = db.query(Attendance).filter(Attendance.session_id == session_id).all()

    result = []
    for r in records:
        student = db.query(User).filter(User.id == r.student_id).first()
        result.append({
            "id": r.id,
            "student_id": r.student_id,
            "student_name": student.full_name if student else "Unknown",
            "student_email": student.email if student else "",
            "status": r.status,
            "marked_at": str(r.marked_at),
            "face_verified": r.face_verified,
            "location_verified": r.location_verified,
        })

    return {
        "session_id": session_id,
        "total": len(result),
        "records": result,
    }
# ---------- STUDENT: ATTENDANCE PERCENTAGE PER COURSE ----------
@router.get("/my-percentages")
def get_my_percentages(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    if current_user.role != "student":
        raise HTTPException(status_code=403, detail="Only students can view their percentages")

    if not current_user.department_id or not current_user.level:
        return {"courses": [], "overall": None}

    dept_id = str(current_user.department_id)

    year = academic_year_for(to_local(datetime.utcnow()))
    start_year = int(year[:4])
    year_start = datetime(start_year, 10, 1)
    year_end = datetime(start_year + 1, 10, 1)
    if current_user.created_at and current_user.created_at > year_start:
        year_start = current_user.created_at

    shared = db.query(CourseDepartment.course_id).filter(
        CourseDepartment.department_id == dept_id
    )
    courses = (
        db.query(Course)
        .filter(
            Course.level == current_user.level,
            or_(Course.department_id == dept_id, Course.id.in_(shared)),
        )
        .order_by(Course.name)
        .all()
    )

    result = []
    total_held = 0
    total_attended = 0
    for c in courses:
        session_ids = [
            s.id
            for s in db.query(AttendanceSession.id).filter(
                AttendanceSession.course_id == c.id,
                AttendanceSession.opened_at >= year_start,
                AttendanceSession.opened_at < year_end,
            )
        ]
        held = len(session_ids)
        attended = 0
        if session_ids:
            attended = (
                db.query(Attendance)
                .filter(
                    Attendance.student_id == current_user.id,
                    Attendance.status == "present",
                    Attendance.session_id.in_(session_ids),
                )
                .count()
            )
        percentage = round(attended / held * 100, 1) if held else None
        total_held += held
        total_attended += attended
        result.append({
            "course_id": c.id,
            "course_name": c.name,
            "course_code": c.code,
            "sessions_held": held,
            "attended": attended,
            "percentage": percentage,
        })

    overall = round(total_attended / total_held * 100, 1) if total_held else None
    return {"academic_year": year, "courses": result, "overall": overall}
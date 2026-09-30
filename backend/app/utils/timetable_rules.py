import re
from fastapi import HTTPException
from app.models import TimetableEntry, Course, User, CourseDepartment, Department

DAY_NAMES = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
PERIOD_STARTS = {1: "7:30", 2: "9:30", 3: "12:30", 4: "2:30"}
PERIOD_ENDS = {1: "9:30", 2: "11:30", 3: "2:30", 4: "4:30"}


def block_periods(start_period, span):
    return set(range(start_period, start_period + span))


def block_label(day, start_period, span):
    return f"{DAY_NAMES[day]} {PERIOD_STARTS[start_period]}-{PERIOD_ENDS[start_period + span - 1]}"


def check_shape(day_of_week, start_period, span, hall, academic_year):
    try:
        day = int(day_of_week)
        start = int(start_period)
        span = int(span)
    except (TypeError, ValueError):
        raise HTTPException(status_code=400, detail="Day, period and span must be numbers")
    if day < 0 or day > 5:
        raise HTTPException(status_code=400, detail="Day must be 0 (Monday) to 5 (Saturday)")
    if start < 1 or start > 4:
        raise HTTPException(status_code=400, detail="Period must be 1 to 4")
    if span not in (1, 2):
        raise HTTPException(status_code=400, detail="Span must be 1 (single) or 2 (double period)")
    if span == 2 and start not in (1, 3):
        raise HTTPException(
            status_code=400,
            detail="A double period must be periods 1-2 or periods 3-4 (it cannot cross the break)",
        )
    hall = (hall or "").strip().upper()
    if not hall:
        raise HTTPException(status_code=400, detail="Hall is required")
    year = (academic_year or "").strip()
    m = re.fullmatch(r"(\d{4})/(\d{4})", year)
    if not m or int(m.group(2)) != int(m.group(1)) + 1:
        raise HTTPException(status_code=400, detail="Academic year must look like 2025/2026")
    return day, start, span, hall, year


def check_weekly_blocks(db, course, year, span, exclude_entry_id=None):
    existing = (
        db.query(TimetableEntry)
        .filter(TimetableEntry.course_id == course.id, TimetableEntry.academic_year == year)
        .all()
    )
    others = [e for e in existing if e.id != exclude_entry_id]
    if others and (span == 2 or any(e.span == 2 for e in others)):
        raise HTTPException(
            status_code=400,
            detail="A double period is the only session of that course for the week.",
        )
    if len(others) >= 2:
        raise HTTPException(status_code=400, detail="This course already has 2 sessions a week.")


def course_department_ids(db, course):
    ids = {course.department_id}
    for row in db.query(CourseDepartment).filter(CourseDepartment.course_id == course.id).all():
        ids.add(row.department_id)
    return ids


def check_clashes(db, course, teacher_id, day, start, span, hall, year, exclude_entry_id=None):
    periods = block_periods(start, span)
    my_depts = course_department_ids(db, course)
    rows = (
        db.query(TimetableEntry, Course)
        .join(Course, TimetableEntry.course_id == Course.id)
        .filter(
            TimetableEntry.academic_year == year,
            TimetableEntry.day_of_week == day,
            Course.semester == course.semester,
        )
        .all()
    )
    for entry, other in rows:
        if entry.id == exclude_entry_id:
            continue
        if not periods & block_periods(entry.start_period, entry.span):
            continue
        when = block_label(entry.day_of_week, entry.start_period, entry.span)
        if teacher_id and other.teacher_id == teacher_id:
            teacher = db.query(User).filter(User.id == teacher_id).first()
            name = teacher.full_name if teacher else "This teacher"
            raise HTTPException(
                status_code=409,
                detail=f"{name} is already teaching {other.code} in {entry.hall} on {when}.",
            )
        if entry.hall.strip().upper() == hall:
            raise HTTPException(
                status_code=409,
                detail=f"{entry.hall} is already used by {other.code} on {when}.",
            )
        if other.level == course.level:
            shared = my_depts & course_department_ids(db, other)
            if shared:
                names = [
                    d.name
                    for d in db.query(Department).filter(Department.id.in_(list(shared))).all()
                ]
                raise HTTPException(
                    status_code=409,
                    detail=f"{other.code} is already scheduled for {', '.join(names)} on {when}.",
                )
            

def check_teacher_change(db, course, teacher):
    """Used when a course gets a new teacher: the teacher must be free at every
    slot this course already occupies."""
    entries = db.query(TimetableEntry).filter(TimetableEntry.course_id == course.id).all()
    for e in entries:
        periods = block_periods(e.start_period, e.span)
        rows = (
            db.query(TimetableEntry, Course)
            .join(Course, TimetableEntry.course_id == Course.id)
            .filter(
                TimetableEntry.academic_year == e.academic_year,
                TimetableEntry.day_of_week == e.day_of_week,
                Course.teacher_id == teacher.id,
                Course.id != course.id,
                Course.semester == course.semester,
            )
            .all()
        )
        for other_entry, other_course in rows:
            if periods & block_periods(other_entry.start_period, other_entry.span):
                when = block_label(other_entry.day_of_week, other_entry.start_period, other_entry.span)
                raise HTTPException(
                    status_code=409,
                    detail=f"{teacher.full_name} is already teaching {other_course.code} on {when}. "
                           f"Move one of the classes first.",
                )
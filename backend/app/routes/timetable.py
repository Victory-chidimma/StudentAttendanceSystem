from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from uuid import uuid4

from app.database import get_db
from sqlalchemy import or_
from app.models import Course, User, TimetableEntry, CourseDepartment
from app.utils.security import get_current_user
from app.utils.timetable_rules import (
    check_shape,
    check_weekly_blocks,
    check_clashes,
    check_teacher_change,
)

router = APIRouter()


def _require_admin(user):
    if user.role != "admin":
        raise HTTPException(status_code=403, detail="Only admins can change the timetable")


def _entry_dict(entry, course, teacher, is_joint=False):
    return {
        "id": entry.id,
        "course_id": course.id,
        "course_code": course.code,
        "course_name": course.name,
        "teacher_id": course.teacher_id,
        "teacher_name": teacher.full_name if teacher else None,
        "day_of_week": entry.day_of_week,
        "start_period": entry.start_period,
        "span": entry.span,
        "hall": entry.hall,
        "academic_year": entry.academic_year,
        "is_joint": is_joint,
    }


@router.get("")
def get_timetable(
    department_id: str,
    level: int,
    semester: str,
    academic_year: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    # Courses whose home department is this one, plus joint courses shared with it
    joint_course_ids = [
        r.course_id
        for r in db.query(CourseDepartment).filter(CourseDepartment.department_id == department_id).all()
    ]
    condition = Course.department_id == department_id
    if joint_course_ids:
        condition = or_(condition, Course.id.in_(joint_course_ids))

    courses = (
        db.query(Course)
        .filter(condition, Course.level == level, Course.semester == semester)
        .all()
    )
    course_map = {c.id: c for c in courses}

    teacher_ids = {c.teacher_id for c in courses if c.teacher_id}
    teachers = {}
    if teacher_ids:
        teachers = {u.id: u for u in db.query(User).filter(User.id.in_(teacher_ids)).all()}

    joint_set = set()
    entries = []
    if course_map:
        joint_set = {
            r.course_id
            for r in db.query(CourseDepartment)
            .filter(CourseDepartment.course_id.in_(list(course_map.keys())))
            .all()
        }
        entries = (
            db.query(TimetableEntry)
            .filter(
                TimetableEntry.course_id.in_(list(course_map.keys())),
                TimetableEntry.academic_year == academic_year,
            )
            .all()
        )

    blocks = {}
    for e in entries:
        blocks[e.course_id] = blocks.get(e.course_id, 0) + 1

    return {
        "entries": [
            _entry_dict(
                e,
                course_map[e.course_id],
                teachers.get(course_map[e.course_id].teacher_id),
                e.course_id in joint_set,
            )
            for e in entries
        ],
        "courses": [
            {
                "id": c.id,
                "code": c.code,
                "name": c.name,
                "teacher_id": c.teacher_id,
                "teacher_name": teachers[c.teacher_id].full_name if c.teacher_id in teachers else None,
                "blocks": blocks.get(c.id, 0),
                "is_joint": c.id in joint_set,
            }
            for c in courses
        ],
    }

@router.post("")
def create_entry(
    data: dict,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    _require_admin(current_user)

    course = db.query(Course).filter(Course.id == data.get("course_id")).first()
    if not course:
        raise HTTPException(status_code=404, detail="Course not found")

    day, start, span, hall, year = check_shape(
        data.get("day_of_week"),
        data.get("start_period"),
        data.get("span", 1),
        data.get("hall"),
        data.get("academic_year"),
    )

    teacher_id = data.get("teacher_id") or course.teacher_id
    if not teacher_id:
        raise HTTPException(status_code=400, detail="Choose a teacher for this course first.")
    teacher = db.query(User).filter(User.id == teacher_id, User.role == "teacher").first()
    if not teacher:
        raise HTTPException(status_code=404, detail="Teacher not found")

    teacher_changed = teacher_id != course.teacher_id
    if teacher_changed:
        check_teacher_change(db, course, teacher)

    check_weekly_blocks(db, course, year, span)
    check_clashes(db, course, teacher_id, day, start, span, hall, year)

    entry = TimetableEntry(
        id=str(uuid4()),
        course_id=course.id,
        day_of_week=day,
        start_period=start,
        span=span,
        hall=hall,
        academic_year=year,
    )
    if teacher_changed:
        course.teacher_id = teacher_id
    db.add(entry)
    db.commit()
    db.refresh(entry)
    return _entry_dict(entry, course, teacher)

@router.put("/{entry_id}")
def update_entry(
    entry_id: str,
    data: dict,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    _require_admin(current_user)

    entry = db.query(TimetableEntry).filter(TimetableEntry.id == entry_id).first()
    if not entry:
        raise HTTPException(status_code=404, detail="Timetable entry not found")
    old_course = db.query(Course).filter(Course.id == entry.course_id).first()

    # The course may be swapped for another one of the same level and semester
    course = old_course
    new_course_id = data.get("course_id")
    if new_course_id and new_course_id != entry.course_id:
        course = db.query(Course).filter(Course.id == new_course_id).first()
        if not course:
            raise HTTPException(status_code=404, detail="Course not found")
        if course.level != old_course.level or course.semester != old_course.semester:
            raise HTTPException(
                status_code=400,
                detail="Choose a course of the same level and semester.",
            )

    day, start, span, hall, year = check_shape(
        data.get("day_of_week", entry.day_of_week),
        data.get("start_period", entry.start_period),
        data.get("span", entry.span),
        data.get("hall", entry.hall),
        entry.academic_year,
    )

    teacher_id = data.get("teacher_id") or course.teacher_id
    if not teacher_id:
        raise HTTPException(status_code=400, detail="Choose a teacher for this course first.")
    teacher = db.query(User).filter(User.id == teacher_id, User.role == "teacher").first()
    if not teacher:
        raise HTTPException(status_code=404, detail="Teacher not found")

    teacher_changed = teacher_id != course.teacher_id
    if teacher_changed:
        check_teacher_change(db, course, teacher)

    check_weekly_blocks(db, course, year, span, exclude_entry_id=entry.id)
    check_clashes(db, course, teacher_id, day, start, span, hall, year, exclude_entry_id=entry.id)

    entry.course_id = course.id
    entry.day_of_week = day
    entry.start_period = start
    entry.span = span
    entry.hall = hall
    if teacher_changed:
        course.teacher_id = teacher_id
    db.commit()
    db.refresh(entry)
    return _entry_dict(entry, course, teacher)

@router.delete("/{entry_id}")
def delete_entry(
    entry_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    _require_admin(current_user)
    entry = db.query(TimetableEntry).filter(TimetableEntry.id == entry_id).first()
    if not entry:
        raise HTTPException(status_code=404, detail="Timetable entry not found")
    db.delete(entry)
    db.commit()
    return {"message": "Timetable entry deleted"}
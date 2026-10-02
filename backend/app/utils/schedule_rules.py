from datetime import timedelta, time

# Cameroon (WAT) is one hour ahead of the server's UTC clock
WAT_OFFSET = timedelta(hours=1)

PERIOD_START = {1: time(7, 30), 2: time(9, 30), 3: time(12, 30), 4: time(14, 30)}
PERIOD_END = {1: time(9, 30), 2: time(11, 30), 3: time(14, 30), 4: time(16, 30)}


def to_local(utc_dt):
    return utc_dt + WAT_OFFSET


def academic_year_for(local_dt):
    """September to August counts as one academic year."""
    y = local_dt.year
    return f"{y}/{y + 1}" if local_dt.month >= 10 else f"{y - 1}/{y}"


def block_window(entry):
    start = PERIOD_START[entry.start_period]
    end = PERIOD_END[entry.start_period + entry.span - 1]
    return start, end


def _minutes(t):
    return t.hour * 60 + t.minute


def locate(entries_on_day, local_dt):
    """Return (entry, inside). The entry is the class this moment belongs to:
    the class whose time contains it, otherwise the nearest class that day."""
    now_min = _minutes(local_dt.time())
    best = None
    best_gap = None
    for e in entries_on_day:
        start, end = block_window(e)
        s, en = _minutes(start), _minutes(end)
        if s <= now_min <= en:
            return e, True
        gap = s - now_min if now_min < s else now_min - en
        if best is None or gap < best_gap:
            best, best_gap = e, gap
    return best, False


def week_bounds_utc(local_dt):
    """Monday 00:00 to next Monday 00:00 (local time), expressed in UTC."""
    monday = (local_dt - timedelta(days=local_dt.weekday())).replace(
        hour=0, minute=0, second=0, microsecond=0
    )
    start_utc = monday - WAT_OFFSET
    return start_utc, start_utc + timedelta(days=7)


def day_bounds_utc(local_dt):
    midnight = local_dt.replace(hour=0, minute=0, second=0, microsecond=0)
    start_utc = midnight - WAT_OFFSET
    return start_utc, start_utc + timedelta(days=1)


def used_entry_ids(sessions, entries):
    """Which timetable classes already had a session this week."""
    by_day = {}
    for e in entries:
        by_day.setdefault(e.day_of_week, []).append(e)
    used = set()
    for s in sessions:
        local = to_local(s.opened_at)
        day_entries = by_day.get(local.weekday())
        if not day_entries:
            continue
        entry, _ = locate(day_entries, local)
        used.add(entry.id)
    return used
import re
from datetime import datetime

from fastapi import HTTPException

from app.utils.schedule_rules import academic_year_for, to_local

BTECH_PATTERN = re.compile(r"^UBA/HIMS/(\d{2})([A-Z])/(\d{1,5})$")
HND_PATTERN = re.compile(r"^HIMS/(\d{2})([A-Z])/(\d{1,5})$")


def normalize_matricule(raw):
    """Remove spaces and use capitals."""
    return re.sub(r"\s+", "", raw or "").upper()


def check_matricule(raw, level):
    """Return the cleaned matricule, or raise a clear error."""
    matricule = normalize_matricule(raw)

    if level == 400:
        match = BTECH_PATTERN.match(matricule)
        if not match:
            raise HTTPException(
                status_code=400,
                detail="Level 400 matricules look like UBA/HIMS/25E/0324. Please check your matricule.",
            )
    else:
        if matricule.startswith("UBA/"):
            raise HTTPException(
                status_code=400,
                detail="This matricule format (UBA) is for Level 400 students only. Please check your level or matricule.",
            )
        match = HND_PATTERN.match(matricule)
        if not match:
            raise HTTPException(
                status_code=400,
                detail="Level 200 and 300 matricules look like HIMS/25E/065. Please check your matricule.",
            )

    year = 2000 + int(match.group(1))
    current = int(academic_year_for(to_local(datetime.utcnow()))[:4])
    if year > current:
        raise HTTPException(
            status_code=400,
            detail=f"The year in this matricule ({year}) has not started yet. Please check your matricule.",
        )
    if year < 2010:
        raise HTTPException(
            status_code=400,
            detail=f"The year in this matricule ({year}) is not valid. Please check your matricule.",
        )
    if level == 300 and year > current - 1:
        raise HTTPException(
            status_code=400,
            detail="A Level 300 student entered school the year before. Please check your level or matricule.",
        )
    return matricule
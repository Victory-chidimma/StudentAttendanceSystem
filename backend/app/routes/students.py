from fastapi import APIRouter
router = APIRouter()

@router.get("/test")
def students_root():
    return {"message": "Students route working"}
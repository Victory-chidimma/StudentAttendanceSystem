from fastapi import APIRouter
router = APIRouter()

@router.get("/test")
def teachers_root():
    return {"message": "Teachers route working"}
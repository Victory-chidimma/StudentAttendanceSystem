from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from sqlalchemy.exc import IntegrityError
import uuid
from sqlalchemy import or_

from app.database import get_db
from app.models import User
from app.models.schemas import RegisterRequest, LoginRequest, AdminLoginRequest, TokenResponse
from app.utils.security import hash_password, verify_password, create_access_token
from app.services.face_service import decode_base64_image, get_face_encoding, compare_faces, encoding_to_list, list_to_encoding, detect_head_turn
router = APIRouter()

@router.get("/")
def auth_root():
    return {"message": "Auth route working"}

# ---------- REGISTER ----------
@router.post("/register", response_model=TokenResponse)
def register(data: RegisterRequest, db: Session = Depends(get_db)):
    # Check if email already exists
    existing_user = db.query(User).filter(User.email == data.email).first()
    if existing_user:
        raise HTTPException(status_code=400, detail="Email already registered")
    if data.role != "student":
        raise HTTPException(status_code=403, detail="Self-registration is only permitted for students. Teacher and admin accounts must be created by an administrator.")

     # Liveness check: verify a genuine head turn between two frames
    frame1_array = decode_base64_image(data.face_image)
    frame2_array = decode_base64_image(data.face_image_turned)
    is_live, liveness_error = detect_head_turn(frame1_array, frame2_array)
    if not is_live:
        raise HTTPException(status_code=400, detail=f"Liveness check failed: {liveness_error}")

    # Process face image
    image_array = decode_base64_image(data.face_image)
    encoding, error = get_face_encoding(image_array)
    if error:
        raise HTTPException(status_code=400, detail=error)

    # Create new user
    new_user = User(
        id=str(uuid.uuid4()),
        full_name=data.full_name,
        email=data.email,
        password=hash_password(data.password),
        role=data.role,
        face_image=str(encoding_to_list(encoding)), # store encoding as string
        matricule=data.matricule,
        department_id=data.department_id,
        level=data.level,
    )
    

    db.add(new_user)
    db.commit()
    db.refresh(new_user)

    token = create_access_token({"sub": new_user.id, "role": new_user.role})

    return TokenResponse(
        access_token=token,
        user_id=new_user.id,
        full_name=new_user.full_name,
        role=new_user.role
    )

# ---------- FACIAL LOGIN (Students & Teachers) ----------
@router.post("/login", response_model=TokenResponse)
def login(data: LoginRequest, db: Session = Depends(get_db)):
    user = db.query(User).filter(
    (User.email == data.email) | (User.matricule == data.email)
).first()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    
    if not verify_password(data.password, user.password):
        raise HTTPException(status_code=401, detail="Incorrect password")

    if not user.face_image:
        raise HTTPException(status_code=400, detail="No face registered for this user")

    # Liveness check: verify a genuine head turn between two frames
    frame1_array = decode_base64_image(data.face_image)
    frame2_array = decode_base64_image(data.face_image_turned)
    is_live, liveness_error = detect_head_turn(frame1_array, frame2_array)
    if not is_live:
        raise HTTPException(status_code=400, detail=f"Liveness check failed: {liveness_error}")
    
    # Process incoming face image
    image_array = decode_base64_image(data.face_image)
    encoding, error = get_face_encoding(image_array)
    if error:
        raise HTTPException(status_code=400, detail=error)

    # Compare with stored encoding
    import ast
    stored_encoding = list_to_encoding(ast.literal_eval(user.face_image))
    match, distance = compare_faces(stored_encoding, encoding)

    if not match:
        raise HTTPException(status_code=401, detail="Face does not match. Login failed")

    token = create_access_token({"sub": user.id, "role": user.role})

    return TokenResponse(
        access_token=token,
        user_id=user.id,
        full_name=user.full_name,
        role=user.role
    )

# ---------- ADMIN LOGIN (Email + Password) ----------
@router.post("/admin-login", response_model=TokenResponse)
def admin_login(data: AdminLoginRequest, db: Session = Depends(get_db)):
    user = db.query(User).filter(User.email == data.email, User.role == "admin").first()
    if not user or not verify_password(data.password, user.password):
        raise HTTPException(status_code=401, detail="Invalid email or password")

    token = create_access_token({"sub": user.id, "role": user.role})

    return TokenResponse(
        access_token=token,
        user_id=user.id,
        full_name=user.full_name,
        role=user.role
    )
from datetime import datetime, timedelta
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from sqlalchemy.exc import IntegrityError
import uuid
from sqlalchemy import or_

from app.database import get_db
from app.models import User
from app.models.schemas import (
    RegisterRequest, LoginRequest, AdminLoginRequest, TokenResponse,
    UpdateFaceRequest, UpdateFaceResponse, AdminUpdateTeacherFaceRequest,
)
from app.utils.security import hash_password, verify_password, create_access_token, get_current_user
from app.services.face_service import (
    decode_base64_image, get_face_encoding, compare_faces,
    encoding_to_list, list_to_encoding, detect_head_turn, evaluate_face_update,
)

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

    if data.matricule and data.level:
        matricule_upper = data.matricule.strip().upper()
        is_btec_format = "UBA" in matricule_upper

        if is_btec_format and data.level != 400:
            raise HTTPException(
                status_code=400,
                detail="This matricule format (UBA) is for Level 400 students only. Please check your level or matricule."
            )
        if not is_btec_format and data.level == 400:
            raise HTTPException(
                status_code=400,
                detail="Level 400 matricules must start with UBA. Please check your matricule."
            )

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
        face_last_updated=datetime.utcnow(),
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

# ---------- STUDENT SELF-SERVICE FACE UPDATE ----------
@router.put("/update-face", response_model=UpdateFaceResponse)
def update_face(
    data: UpdateFaceRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    # Confirm identity with password
    if not verify_password(data.password, current_user.password):
        raise HTTPException(status_code=401, detail="Incorrect password")

    if not current_user.face_image:
        raise HTTPException(status_code=400, detail="No existing face registered for this account")

    # Cooldown check: only allow face updates once every 6 months
    if current_user.face_last_updated:
        days_since_update = (datetime.utcnow() - current_user.face_last_updated).days
        if days_since_update < 180:
            days_remaining = 180 - days_since_update
            raise HTTPException(
                status_code=400,
                detail=f"You can only update your face once every 6 months. Please try again in {days_remaining} day(s)."
            )

    # Liveness check on the new capture
    frame1_array = decode_base64_image(data.face_image)
    frame2_array = decode_base64_image(data.face_image_turned)
    is_live, liveness_error = detect_head_turn(frame1_array, frame2_array)
    if not is_live:
        raise HTTPException(status_code=400, detail=f"Liveness check failed: {liveness_error}")

    # Encode the new face
    image_array = decode_base64_image(data.face_image)
    new_encoding, error = get_face_encoding(image_array)
    if error:
        raise HTTPException(status_code=400, detail=error)

    # Compare against stored encoding using dual thresholds
    import ast
    stored_encoding = list_to_encoding(ast.literal_eval(current_user.face_image))
    decision, distance = evaluate_face_update(stored_encoding, new_encoding)

    if decision == "reject":
        raise HTTPException(
            status_code=400,
            detail="New face does not sufficiently match your registered identity. Please contact an administrator."
        )

    # Accept (either "accept" or "accept_flagged") — update stored encoding
    current_user.face_image = str(encoding_to_list(new_encoding))
    current_user.face_last_updated = datetime.utcnow()
    db.commit()

    status = "accepted" if decision == "accept" else "accepted_flagged"
    message = (
        "Face updated successfully."
        if decision == "accept"
        else "Face updated successfully. Moderate change detected from previous registration."
    )

    return UpdateFaceResponse(message=message, status=status, distance=distance)

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

    # Students: password-only login, no face check
    if user.role == "student":
        token = create_access_token({"sub": user.id, "role": user.role})
        return TokenResponse(
            access_token=token,
            user_id=user.id,
            full_name=user.full_name,
            role=user.role
        )

    # Teachers (and any other non-student role): face + liveness still required
    if not data.face_image or not data.face_image_turned:
        raise HTTPException(status_code=400, detail="Face images are required for this account type")

    if not user.face_image:
        raise HTTPException(status_code=400, detail="No face registered for this user")

    frame1_array = decode_base64_image(data.face_image)
    frame2_array = decode_base64_image(data.face_image_turned)
    is_live, liveness_error = detect_head_turn(frame1_array, frame2_array)
    if not is_live:
        raise HTTPException(status_code=400, detail=f"Liveness check failed: {liveness_error}")

    image_array = decode_base64_image(data.face_image)
    encoding, error = get_face_encoding(image_array)
    if error:
        raise HTTPException(status_code=400, detail=error)

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

# ---------- ADMIN: UPDATE TEACHER FACE ----------
@router.put("/admin/teachers/{teacher_id}/face", response_model=UpdateFaceResponse)
def admin_update_teacher_face(
    teacher_id: str,
    data: AdminUpdateTeacherFaceRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    if current_user.role != "admin":
        raise HTTPException(status_code=403, detail="Only admins can perform this action")

    teacher = db.query(User).filter(User.id == teacher_id, User.role == "teacher").first()
    if not teacher:
        raise HTTPException(status_code=404, detail="Teacher not found")

    frame1_array = decode_base64_image(data.face_image)
    frame2_array = decode_base64_image(data.face_image_turned)
    is_live, liveness_error = detect_head_turn(frame1_array, frame2_array)
    if not is_live:
        raise HTTPException(status_code=400, detail=f"Liveness check failed: {liveness_error}")

    image_array = decode_base64_image(data.face_image)
    new_encoding, error = get_face_encoding(image_array)
    if error:
        raise HTTPException(status_code=400, detail=error)

    teacher.face_image = str(encoding_to_list(new_encoding))
    teacher.face_last_updated = datetime.utcnow()
    db.commit()

    return UpdateFaceResponse(
        message=f"Face updated successfully for {teacher.full_name}.",
        status="accepted",
        distance=0.0
    )
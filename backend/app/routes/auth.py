from datetime import datetime, timedelta
import os
import re
from html import escape
from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException
from fastapi.responses import HTMLResponse
from sqlalchemy.orm import Session
from sqlalchemy.exc import IntegrityError
import uuid
from sqlalchemy import or_, func

from app.database import get_db
from app.models import User
from app.models.schemas import (
    RegisterRequest, LoginRequest, AdminLoginRequest, TokenResponse,
    UpdateFaceRequest, UpdateFaceResponse, AdminUpdateTeacherFaceRequest,
)
from app.utils.security import hash_password, verify_password, create_access_token, get_current_user
from app.utils.matricule_rules import check_matricule
from app.utils.mailer import send_email
from app.utils.reset_tokens import make_reset_token, read_reset_token
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

    matricule = None
    if data.matricule:
        if not data.level:
            raise HTTPException(status_code=400, detail="Level is required with a matricule")
        matricule = check_matricule(data.matricule, data.level)
        duplicate = db.query(User).filter(func.upper(User.matricule) == matricule).first()
        if duplicate:
            raise HTTPException(status_code=400, detail="This matricule is already registered.")

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
        matricule=matricule,
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
    identifier = data.email.strip().lower()
    user = db.query(User).filter(
        (func.lower(User.email) == identifier)
        | (func.lower(User.matricule) == identifier)
    ).first()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    if not verify_password(data.password, user.password):
        raise HTTPException(status_code=401, detail="Incorrect password")

    # The account type must match the login tab, checked before any face scan is asked for
    role_name = getattr(user.role, "value", user.role)

    if role_name == "admin":
        # An admin account gets the same reply as a wrong password on this login
        raise HTTPException(status_code=401, detail="Incorrect password")
    if data.role and data.role != role_name:
        raise HTTPException(
            status_code=403,
            detail=f"This is a {role_name} account. Please use the {role_name.capitalize()} login.",
        )

    # Students: password-only login, no face check
    if role_name == "student":
        token = create_access_token({"sub": user.id, "role": user.role})
        return TokenResponse(
            access_token=token,
            user_id=user.id,
            full_name=user.full_name,
            role=user.role
        )

    # Teachers: face + liveness still required
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

# ---------- FORGOT PASSWORD ----------
PUBLIC_BASE_URL = os.getenv(
    "PUBLIC_BASE_URL", "https://studentattendancesystem-production-fc88.up.railway.app"
)

RESET_PAGE = """<!DOCTYPE html>
<html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Reset password</title>
<style>
body{font-family:Arial,sans-serif;background:#f4f6fb;margin:0;padding:24px;}
.card{max-width:380px;margin:40px auto;background:#fff;padding:24px;border-radius:12px;box-shadow:0 2px 10px rgba(0,0,0,.08);}
h2{margin-top:0;color:#0D47A1;}
input{width:100%;box-sizing:border-box;padding:12px;margin:6px 0 14px;border:1px solid #ccc;border-radius:8px;font-size:15px;}
button{width:100%;padding:13px;background:#0D47A1;color:#fff;border:0;border-radius:8px;font-size:16px;}
#msg{margin-top:14px;font-size:14px;}
</style></head><body><div class="card">
<h2>Choose a new password</h2>
<label>New password</label><input id="p1" type="password" autocomplete="new-password">
<label>Confirm password</label><input id="p2" type="password" autocomplete="new-password">
<label style="display:block;margin-bottom:14px;font-size:14px;"><input type="checkbox" style="width:auto;margin:0 8px 0 0;" onchange="document.getElementById('p1').type=this.checked?'text':'password';document.getElementById('p2').type=this.checked?'text':'password';"> Show password</label>
<button id="go">Save new password</button>
<div id="msg"></div></div>
<script>
const token = "__TOKEN__";
document.getElementById("go").onclick = async () => {
  const msg = document.getElementById("msg");
  const p1 = document.getElementById("p1").value;
  const p2 = document.getElementById("p2").value;
  if (p1.length < 6) { msg.style.color = "#b00020"; msg.textContent = "Use at least 6 characters."; return; }
  if (p1 !== p2) { msg.style.color = "#b00020"; msg.textContent = "The two passwords do not match."; return; }
  msg.style.color = "#333"; msg.textContent = "Saving...";
  try {
    const res = await fetch("/api/auth/reset-password", {
      method: "POST",
      headers: {"Content-Type": "application/json"},
      body: JSON.stringify({token: token, password: p1})
    });
    const body = await res.json();
    if (res.ok) {
      msg.style.color = "#1B5E20";
      msg.textContent = "Password changed. You can now return to the app and log in.";
      document.getElementById("go").disabled = true;
    } else {
      msg.style.color = "#b00020";
      msg.textContent = body.detail || "Could not change the password.";
    }
  } catch (e) {
    msg.style.color = "#b00020";
    msg.textContent = "Connection problem. Please try again.";
  }
};
</script></body></html>"""


def _send_reset_email(user_email, full_name, link):
    body = (
        f"<p>Hello {escape(full_name or '')},</p>"
        "<p>We received a request to reset your HIMS Attendance password. "
        "Tap the button below to choose a new one. The link works once and "
        "expires in 30 minutes.</p>"
        f'<p><a href="{link}" style="background:#0D47A1;color:#ffffff;padding:12px 20px;'
        'border-radius:6px;text-decoration:none;">Reset my password</a></p>'
        "<p>If you did not ask for this, you can ignore this email. "
        "Your password will not change.</p>"
    )
    send_email(user_email, "Reset your HIMS Attendance password", body)


@router.post("/forgot-password")
def forgot_password(
    data: dict,
    background_tasks: BackgroundTasks,
    db: Session = Depends(get_db),
):
    email = (data.get("email") or "").strip().lower()
    if not email:
        raise HTTPException(status_code=400, detail="Please enter your email address")

    user = db.query(User).filter(func.lower(User.email) == email).first()
    if not user:
        print("[mail] forgot-password: no account with that email")
    else:
        token = make_reset_token(user)
        if not token:
            print("[mail] forgot-password: no secret set (BREVO_API_KEY is missing)")
        else:
            link = f"{PUBLIC_BASE_URL}/api/auth/reset-password?token={token}"
            background_tasks.add_task(_send_reset_email, user.email, user.full_name, link)
            print("[mail] forgot-password: reset email queued")

    # The same answer whether or not the email exists
    return {"message": "If this email is registered, a reset link has been sent to it."}


@router.get("/reset-password", response_class=HTMLResponse)
def reset_password_page(token: str = "", db: Session = Depends(get_db)):
    if not re.fullmatch(r"[A-Za-z0-9_.\-]+", token) or not read_reset_token(token, db, User):
        return HTMLResponse(
            "<html><body style='font-family:Arial;padding:24px'>"
            "<h3>This link is no longer valid.</h3>"
            "<p>It may have expired or already been used. "
            "Please request a new one from the app.</p></body></html>",
            status_code=400,
        )
    return HTMLResponse(RESET_PAGE.replace("__TOKEN__", token))


@router.post("/reset-password")
def reset_password(data: dict, db: Session = Depends(get_db)):
    token = data.get("token") or ""
    password = data.get("password") or ""
    if len(password) < 6:
        raise HTTPException(status_code=400, detail="Use at least 6 characters.")
    user = read_reset_token(token, db, User)
    if not user:
        raise HTTPException(
            status_code=400,
            detail="This link is no longer valid. Please request a new one.",
        )
    user.password = hash_password(password)
    db.commit()
    return {"message": "Password changed"}
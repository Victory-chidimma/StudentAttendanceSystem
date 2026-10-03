import base64
import hashlib
import hmac
import os
import time

TOKEN_LIFETIME_SECONDS = 30 * 60


def _secret():
    return (os.getenv("RESET_SECRET") or os.getenv("BREVO_API_KEY") or "").encode()


def _fingerprint(password_hash):
    # Changes as soon as the password changes, so a link works only once
    return hashlib.sha256((password_hash or "").encode()).hexdigest()[:12]


def make_reset_token(user):
    secret = _secret()
    if not secret:
        return None
    expires = int(time.time()) + TOKEN_LIFETIME_SECONDS
    payload = f"{user.id}.{expires}.{_fingerprint(user.password)}"
    body = base64.urlsafe_b64encode(payload.encode()).decode().rstrip("=")
    signature = hmac.new(secret, body.encode(), hashlib.sha256).hexdigest()
    return f"{body}.{signature}"


def read_reset_token(token, db, User):
    """Return the user if the link is valid and not expired or used, otherwise None."""
    secret = _secret()
    if not secret or not token or "." not in token:
        return None
    body, signature = token.rsplit(".", 1)
    expected = hmac.new(secret, body.encode(), hashlib.sha256).hexdigest()
    if not hmac.compare_digest(signature, expected):
        return None
    try:
        padded = body + "=" * (-len(body) % 4)
        user_id, expires, fingerprint = (
            base64.urlsafe_b64decode(padded.encode()).decode().split(".")
        )
        if int(expires) < time.time():
            return None
    except Exception:
        return None
    user = db.query(User).filter(User.id == user_id).first()
    if not user or _fingerprint(user.password) != fingerprint:
        return None
    return user
import json
import os
import urllib.error
import urllib.request


def send_email(to_email, subject, html_content):
    """Send one email through Brevo's web API. Returns True if it was accepted."""
    api_key = os.getenv("BREVO_API_KEY")
    sender_email = os.getenv("MAIL_SENDER_EMAIL")
    if not api_key or not sender_email:
        print("[mail] BREVO_API_KEY or MAIL_SENDER_EMAIL is not set, so no email was sent")
        return False

    payload = {
        "sender": {
            "name": os.getenv("MAIL_SENDER_NAME", "HIMS Attendance"),
            "email": sender_email,
        },
        "to": [{"email": to_email}],
        "subject": subject,
        "htmlContent": html_content,
    }
    request = urllib.request.Request(
        "https://api.brevo.com/v3/smtp/email",
        data=json.dumps(payload).encode("utf-8"),
        headers={
            "api-key": api_key,
            "content-type": "application/json",
            "accept": "application/json",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=15) as response:
            return 200 <= response.status < 300
    except urllib.error.HTTPError as err:
        print("[mail] Brevo refused the email:", err.code, err.read().decode("utf-8", "ignore"))
        return False
    except Exception as err:
        print("[mail] could not send the email:", err)
        return False
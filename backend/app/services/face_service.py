import face_recognition
import numpy as np
import base64
import dlib
import face_recognition_models
from io import BytesIO
from PIL import Image

_face_detector = dlib.get_frontal_face_detector()
_landmark_predictor = dlib.shape_predictor(face_recognition_models.pose_predictor_model_location())

def decode_base64_image(base64_string: str):
    """Convert base64 image string to numpy array"""
    if "," in base64_string:
        base64_string = base64_string.split(",")[1]
    image_data = base64.b64decode(base64_string)
    image = Image.open(BytesIO(image_data)).convert("RGB")
    return np.array(image)

def get_face_encoding(image_array):
    """Extract face encoding (128-d vector) from an image"""
    face_locations = face_recognition.face_locations(image_array)
    if len(face_locations) == 0:
        return None, "No face detected. Please make sure your face is well-lit, centered, and close enough to the camera, then try again"
    if len(face_locations) > 1:
        return None, "Multiple faces detected. Please make sure only your face is visible in the frame"
    
    encodings = face_recognition.face_encodings(image_array, face_locations)
    return encodings[0], None

def compare_faces(known_encoding, unknown_encoding, tolerance=0.6):
    """Compare two face encodings, returns (match: bool, distance: float)"""
    known_encoding = np.array(known_encoding)
    unknown_encoding = np.array(unknown_encoding)
    distance = face_recognition.face_distance([known_encoding], unknown_encoding)[0]
    match = distance <= tolerance
    return bool(match), float(distance)

def encoding_to_list(encoding):
    """Convert numpy array encoding to a list for JSON/DB storage"""
    return encoding.tolist()

def list_to_encoding(encoding_list):
    """Convert list back to numpy array"""
    return np.array(encoding_list)

def get_nose_offset(image_array):
    face_locations = face_recognition.face_locations(image_array)
    if len(face_locations) == 0:
        return None, "No face detected. Please make sure your face is well-lit, centered, and close enough to the camera, then try again"
    top, right, bottom, left = face_locations[0]
    face_rect = dlib.rectangle(left, top, right, bottom)
    landmarks = _landmark_predictor(image_array, face_rect)
    left_eye_x = landmarks.part(36).x
    right_eye_x = landmarks.part(45).x
    nose_x = landmarks.part(30).x
    eye_midpoint = (left_eye_x + right_eye_x) / 2
    face_width = right_eye_x - left_eye_x
    offset_ratio = (nose_x - eye_midpoint) / face_width
    return offset_ratio, None

def detect_head_turn(frame1_array, frame2_array, min_shift=0.15):
    offset1, error1 = get_nose_offset(frame1_array)
    if error1:
        return False, f"First frame: {error1}"
    offset2, error2 = get_nose_offset(frame2_array)
    if error2:
        return False, f"Second frame: {error2}"
    shift = abs(offset2 - offset1)
    if shift < min_shift:
        return False, "No significant head movement detected between frames"
    return True, None

def evaluate_face_update(known_encoding, new_encoding, accept_tolerance=0.6, reject_tolerance=0.75):
    """
    Compare a new face against the stored encoding for a face-update request.
    Returns (decision, distance) where decision is one of:
      "accept"          - clearly the same person (distance <= accept_tolerance)
      "accept_flagged"  - same person, moderate change detected (accept_tolerance < distance <= reject_tolerance)
      "reject"          - does not sufficiently match (distance > reject_tolerance)
    """
    known_encoding = np.array(known_encoding)
    new_encoding = np.array(new_encoding)
    distance = float(face_recognition.face_distance([known_encoding], new_encoding)[0])

    if distance <= accept_tolerance:
        return "accept", distance
    elif distance <= reject_tolerance:
        return "accept_flagged", distance
    else:
        return "reject", distance
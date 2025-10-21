from __future__ import annotations

from http import HTTPStatus
from typing import Any, Dict, Optional

from flask import (
    Blueprint,
    Response,
    abort,
    current_app,
    jsonify,
    request,
)

from .firebase_auth import FirebaseAuthError, FirebaseAuthService
from .jwt_auth import JWTAuthError, JWTAuthService
from .repository import (
    check_storage_available,
    decrement_storage_usage,
    delete_file_by_id,
    get_file_by_id,
    get_or_create_user_storage,
    increment_storage_usage,
    list_files_for_user,
    record_completed_upload,
    record_or_update_session,
)
from .storage import build_blob_pathname, delete_from_blob, upload_to_blob

api_bp = Blueprint("api", __name__)


def _resolve_user_id() -> str:
    token = _extract_bearer_token()
    if not token:
        abort(HTTPStatus.UNAUTHORIZED, description="Session token invalid or missing.")

    try:
        session = _jwt_service().verify_token(token)
        return session.user_id
    except JWTAuthError as exc:
        abort(HTTPStatus.UNAUTHORIZED, description=str(exc))


def _extract_bearer_token() -> Optional[str]:
    auth_header = request.headers.get("Authorization", "")
    if auth_header.lower().startswith("bearer "):
        return auth_header.split(" ", 1)[1].strip() or None

    return None


def _firebase_service() -> FirebaseAuthService:
    service_account_base64 = current_app.config.get("FIREBASE_SERVICE_ACCOUNT_BASE64")
    return FirebaseAuthService(service_account_base64)


def _jwt_service() -> JWTAuthService:
    secret_key = current_app.config.get("JWT_SECRET_KEY")
    ttl_seconds = int(current_app.config.get("JWT_TTL_SECONDS", 0) or 0)
    return JWTAuthService(secret_key=secret_key, ttl_seconds=ttl_seconds)


@api_bp.get("/")
def healthcheck() -> Dict[str, Any]:
    return {"status": "ok"}


# Frontend is now served separately via web app
# API endpoints below handle backend logic


@api_bp.post("/auth/firebase/session")
def firebase_finalize_session() -> Response:
    request_token = _extract_bearer_token()

    if not request_token:
        payload = request.get_json(silent=True) or {}
        request_token = (payload.get("token") or "").strip()

    if not request_token:
        abort(HTTPStatus.BAD_REQUEST, description="Missing Firebase authentication token.")

    try:
        firebase_user = _firebase_service().verify_token(request_token)
    except FirebaseAuthError as exc:
        abort(HTTPStatus.UNAUTHORIZED, description=str(exc))

    session_token = _jwt_service().create_token(
        user_id=firebase_user.user_id,
        email=firebase_user.email,
        display_name=firebase_user.display_name,
    )

    session_doc = record_or_update_session(
        current_app.mongo_db,
        user_id=firebase_user.user_id,
        session_token=session_token,
        email=firebase_user.email,
    )

    token_ttl = current_app.config.get("JWT_TTL_SECONDS") or None

    return jsonify(
        {
            "session_token": session_token,
            "user_id": firebase_user.user_id,
            "email": firebase_user.email,
            "display_name": firebase_user.display_name,
            "session_id": session_doc.get("id"),
            "expires_in": token_ttl,
        }
    )


@api_bp.get("/list/")
def list_files() -> Response:
    user_id = _resolve_user_id()
    files = list_files_for_user(current_app.mongo_db, user_id=user_id)

    # Get user storage information
    user_storage = get_or_create_user_storage(current_app.mongo_db, user_id=user_id)

    return jsonify({
        "files": files,
        "storage": {
            "used": user_storage.get("storage_used", 0),
            "cap": user_storage.get("storage_cap", 100 * 1024 * 1024)
        }
    })


@api_bp.post("/upload/")
def request_upload() -> Response:
    user_id = _resolve_user_id()

    # Only support multipart file upload
    if 'file' not in request.files:
        abort(HTTPStatus.BAD_REQUEST, description="file is required")

    file = request.files['file']
    if not file or not file.filename:
        abort(HTTPStatus.BAD_REQUEST, description="file is required")

    filename = file.filename
    content_type = file.content_type

    # Read file into memory to check size before uploading
    file_data = file.read()
    file_size = len(file_data)

    # Check storage limit before starting upload
    has_space, user_storage = check_storage_available(
        current_app.mongo_db,
        user_id=user_id,
        additional_bytes=file_size
    )

    if not has_space:
        storage_used = user_storage.get("storage_used", 0)
        storage_cap = user_storage.get("storage_cap", 0)
        abort(
            HTTPStatus.INSUFFICIENT_STORAGE,
            description=(
                f"Storage limit exceeded. "
                f"Used: {storage_used} bytes, "
                f"Cap: {storage_cap} bytes, "
                f"File size: {file_size} bytes"
            )
        )

    # Generate blob pathname and upload
    blob_pathname = build_blob_pathname(user_id, filename)

    # Create a file-like object from bytes for upload
    from io import BytesIO
    file_stream = BytesIO(file_data)

    blob_response = upload_to_blob(
        pathname=blob_pathname,
        file_data=file_stream,
        content_type=content_type,
    )

    # Get the actual size from uploaded blob
    size = blob_response.get("size")

    # Record completed upload
    file_doc = record_completed_upload(
        current_app.mongo_db,
        user_id=user_id,
        filename=filename,
        blob_pathname=blob_pathname,
        blob_url=blob_response.get("url"),
        size=size,
        content_type=content_type,
    )

    # Increment storage usage after successful upload
    increment_storage_usage(
        current_app.mongo_db,
        user_id=user_id,
        bytes_added=size
    )

    return jsonify({"file": file_doc}), HTTPStatus.CREATED


@api_bp.get("/download/<file_id>")
def download_file(file_id: str) -> Response:
    user_id = _resolve_user_id()
    file_doc = get_file_by_id(current_app.mongo_db, file_id=file_id, user_id=user_id)
    if not file_doc:
        abort(HTTPStatus.NOT_FOUND, description="File not found")

    if not file_doc.get("blob_url"):
        abort(HTTPStatus.NOT_FOUND, description="File upload not completed")

    # Vercel Blob URLs are directly accessible, no need for presigning
    return jsonify({"download_url": file_doc["blob_url"], "file": file_doc})


@api_bp.delete("/files/<file_id>")
def delete_file(file_id: str) -> Response:
    user_id = _resolve_user_id()

    # Get the file document first to retrieve blob_url and size
    file_doc = get_file_by_id(current_app.mongo_db, file_id=file_id, user_id=user_id)
    if not file_doc:
        abort(HTTPStatus.NOT_FOUND, description="File not found")

    blob_url = file_doc.get("blob_url")
    file_size = file_doc.get("size", 0)

    # Delete from Vercel Blob storage if blob_url exists
    if blob_url:
        try:
            delete_from_blob(blob_url)
        except Exception as e:
            # Log error but continue with database deletion
            current_app.logger.error(f"Failed to delete blob {blob_url}: {e}")

    # Delete from database
    deleted_file = delete_file_by_id(current_app.mongo_db, file_id=file_id, user_id=user_id)
    if not deleted_file:
        abort(HTTPStatus.NOT_FOUND, description="File not found")

    # Decrement storage usage if file had a size
    if file_size > 0:
        decrement_storage_usage(
            current_app.mongo_db,
            user_id=user_id,
            bytes_removed=file_size
        )

    return jsonify({"message": "File deleted successfully", "file": deleted_file})

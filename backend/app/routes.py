from __future__ import annotations

from http import HTTPStatus
from typing import Any, Dict, Optional

from flask import (
    Blueprint,
    Response,
    abort,
    current_app,
    jsonify,
    render_template,
    request,
    session,
    url_for,
)

from .auth import ClerkAuthError, ClerkAuthService
from .repository import (
    get_file_by_id,
    list_files_for_user,
    mark_upload_completed,
    record_upload_init,
)
from .storage import build_blob_pathname, upload_to_blob

api_bp = Blueprint("api", __name__)


def _resolve_user_id() -> str:
    user_id = session.get("user_id")
    if user_id:
        return user_id

    token = _extract_clerk_token()
    if token:
        try:
            clerk_user = _clerk_service().verify_token(token)
        except ClerkAuthError as exc:
            abort(HTTPStatus.UNAUTHORIZED, description=str(exc))

        session["user_id"] = clerk_user.user_id
        session["email"] = clerk_user.email
        return clerk_user.user_id

    header_user_id = request.headers.get("X-User-Id")
    if header_user_id:
        return header_user_id

    abort(HTTPStatus.UNAUTHORIZED, description="User identity is required")


def _extract_clerk_token() -> Optional[str]:
    auth_header = request.headers.get("Authorization", "")
    if auth_header.lower().startswith("bearer "):
        return auth_header.split(" ", 1)[1].strip() or None

    header_token = request.headers.get("Clerk-Session")
    if header_token:
        return header_token.strip() or None

    return None


def _clerk_service() -> ClerkAuthService:
    secret_key = current_app.config["CLERK_SECRET_KEY"]
    return ClerkAuthService(secret_key)


@api_bp.get("/healthz")
def healthcheck() -> Dict[str, Any]:
    return {"status": "ok"}


@api_bp.get("/login/")
def login_portal() -> Response:
    return render_template(
        "login.html",
        clerk_publishable_key=current_app.config["CLERK_PUBLISHABLE_KEY"],
        finalize_url=url_for("api.clerk_finalize_session"),
        app_redirect_uri=current_app.config["APP_REDIRECT_URI"],
        clerk_jwt_template=current_app.config.get("CLERK_JWT_TEMPLATE"),
    )


@api_bp.post("/auth/clerk/session")
def clerk_finalize_session() -> Response:
    request_token = _extract_clerk_token()
    if not request_token:
        payload = request.get_json(silent=True) or {}
        request_token = (payload.get("token") or "").strip()

    if not request_token:
        abort(HTTPStatus.BAD_REQUEST, description="Missing Clerk authentication token.")

    try:
        clerk_user = _clerk_service().verify_token(request_token)
    except ClerkAuthError as exc:
        abort(HTTPStatus.UNAUTHORIZED, description=str(exc))

    session["user_id"] = clerk_user.user_id
    session["email"] = clerk_user.email
    return jsonify({"user_id": clerk_user.user_id, "email": clerk_user.email})


@api_bp.get("/list/")
def list_files() -> Response:
    user_id = _resolve_user_id()
    files = list_files_for_user(current_app.mongo_db, user_id=user_id)
    return jsonify({"files": files})


@api_bp.post("/upload/")
def request_upload() -> Response:
    user_id = _resolve_user_id()

    # Check if this is a multipart file upload
    if 'file' in request.files:
        file = request.files['file']
        if not file or not file.filename:
            abort(HTTPStatus.BAD_REQUEST, description="file is required")

        filename = file.filename
        content_type = file.content_type

        # Generate blob pathname and upload
        blob_pathname = build_blob_pathname(user_id, filename)
        blob_response = upload_to_blob(
            pathname=blob_pathname,
            file_data=file.stream,
            content_type=content_type,
        )

        # Get the actual size from uploaded blob
        size = blob_response.get("size")

        # Record as completed upload
        file_doc = record_upload_init(
            current_app.mongo_db,
            user_id=user_id,
            filename=filename,
            blob_pathname=blob_pathname,
            size=size,
            content_type=content_type,
        )

        # Mark as completed immediately with blob URL
        file_doc = mark_upload_completed(
            current_app.mongo_db,
            file_id=file_doc["_id"],
            user_id=user_id,
            blob_url=blob_response.get("url"),
            size=size,
        )

        return jsonify({"file": file_doc}), HTTPStatus.CREATED

    # Legacy JSON-based flow for backward compatibility
    payload = request.get_json(force=True) or {}
    filename = payload.get("filename")
    if not filename:
        abort(HTTPStatus.BAD_REQUEST, description="filename or file is required")

    content_type = payload.get("content_type")
    size = payload.get("size")
    if size is not None:
        try:
            size = int(size)
        except (TypeError, ValueError):
            abort(HTTPStatus.BAD_REQUEST, description="size must be an integer")
        if size <= 0:
            abort(HTTPStatus.BAD_REQUEST, description="size must be positive")

    blob_pathname = build_blob_pathname(user_id, filename)

    file_doc = record_upload_init(
        current_app.mongo_db,
        user_id=user_id,
        filename=filename,
        blob_pathname=blob_pathname,
        size=size,
        content_type=content_type,
    )

    return jsonify({
        "upload": {
            "pathname": blob_pathname,
        },
        "file": file_doc
    }), HTTPStatus.CREATED


@api_bp.post("/upload/<file_id>/complete")
def confirm_upload(file_id: str) -> Response:
    user_id = _resolve_user_id()
    payload = request.get_json(force=True) or {}

    blob_url = payload.get("blob_url")
    if not blob_url:
        abort(HTTPStatus.BAD_REQUEST, description="blob_url is required")

    size = payload.get("size")
    if size is not None:
        try:
            size = int(size)
        except (TypeError, ValueError):
            abort(HTTPStatus.BAD_REQUEST, description="size must be an integer")
        if size <= 0:
            abort(HTTPStatus.BAD_REQUEST, description="size must be positive")

    updated = mark_upload_completed(
        current_app.mongo_db,
        file_id=file_id,
        user_id=user_id,
        blob_url=blob_url,
        size=size,
    )
    if not updated:
        abort(HTTPStatus.NOT_FOUND, description="File not found")
    return jsonify({"file": updated})


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

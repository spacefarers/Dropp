from __future__ import annotations

from http import HTTPStatus
from typing import Any, Dict

from flask import (
    Blueprint,
    Response,
    abort,
    current_app,
    jsonify,
    redirect,
    render_template,
    request,
    session,
    url_for,
)

from .auth import GoogleOAuthConfig, GoogleOAuthService
from .repository import (
    get_file_by_id,
    list_files_for_user,
    mark_upload_completed,
    record_upload_init,
)
from .storage import build_blob_pathname, generate_client_upload_token

api_bp = Blueprint("api", __name__)


def _resolve_user_id() -> str:
    user_id = session.get("user_id") or request.headers.get("X-User-Id")
    if not user_id:
        abort(HTTPStatus.UNAUTHORIZED, description="User identity is required")
    return user_id


def _google_service() -> GoogleOAuthService:
    cfg = GoogleOAuthConfig(
        client_id=current_app.config["GOOGLE_CLIENT_ID"],
        client_secret=current_app.config["GOOGLE_CLIENT_SECRET"],
        redirect_uri=current_app.config["GOOGLE_REDIRECT_URI"],
    )
    return GoogleOAuthService(cfg)


@api_bp.get("/healthz")
def healthcheck() -> Dict[str, Any]:
    return {"status": "ok"}


@api_bp.get("/login/")
def login_portal() -> Response:
    return render_template(
        "login.html",
        google_client_id=current_app.config["GOOGLE_CLIENT_ID"],
        google_redirect_url=url_for("api.google_login"),
    )


@api_bp.get("/auth/google")
def google_login() -> Response:
    service = _google_service()
    redirect_uri, state = service.authorization_url()
    session["oauth_state"] = state
    return redirect(redirect_uri)


@api_bp.get("/auth/google/callback")
def google_callback() -> Response:
    service = _google_service()
    state = session.get("oauth_state")
    credentials = service.exchange_code(request.url, state)
    profile = service.user_profile(credentials)
    session["user_id"] = profile["sub"]
    session["email"] = profile.get("email")
    app_redirect = current_app.config["APP_REDIRECT_URI"]
    return redirect(f"{app_redirect}?user_id={profile['sub']}&email={profile.get('email', '')}")


@api_bp.get("/list/")
def list_files() -> Response:
    user_id = _resolve_user_id()
    files = list_files_for_user(current_app.mongo_db, user_id=user_id)
    return jsonify({"files": files})


@api_bp.post("/upload/")
def request_upload() -> Response:
    user_id = _resolve_user_id()
    payload = request.get_json(force=True) or {}
    filename = payload.get("filename")
    if not filename:
        abort(HTTPStatus.BAD_REQUEST, description="filename is required")

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
    client_token = generate_client_upload_token(
        pathname=blob_pathname,
        expires_in=current_app.config["UPLOAD_POST_TTL_SECONDS"],
    )

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
            "client_token": client_token,
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

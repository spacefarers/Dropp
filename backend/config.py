import os
from dataclasses import dataclass
from typing import Optional

from dotenv import load_dotenv

# Load environment variables from a .env file when present.
load_dotenv()


def _get_env(name: str, default: Optional[str] = None, required: bool = True) -> Optional[str]:
    """
    Retrieve an environment variable, returning a default when provided.
    """
    value = os.environ.get(name, default)
    if value is None and required:
        raise RuntimeError(f"Missing required environment variable: {name}")
    return value


def _get_env_list(name: str) -> Optional[tuple[str, ...]]:
    """
    Retrieve a comma-separated list environment variable as a tuple of strings.
    """
    value = os.environ.get(name)
    if not value:
        return None

    entries = tuple(item.strip() for item in value.split(",") if item.strip())
    return entries or None


@dataclass(frozen=True)
class Config:
    secret_key: str = _get_env("SECRET_KEY", "replace-me")
    mongo_uri: str = _get_env("MONGODB_URI")
    mongo_db: str = _get_env("MONGO_DB", "dropp")
    # Vercel automatically injects BLOB_READ_WRITE_TOKEN when Vercel Blob is enabled
    blob_read_write_token: Optional[str] = os.environ.get("BLOB_READ_WRITE_TOKEN")
    presign_ttl_seconds: int = int(os.environ.get("PRESIGN_TTL_SECONDS", "900"))
    upload_post_ttl_seconds: int = int(os.environ.get("UPLOAD_POST_TTL_SECONDS", "3600"))
    firebase_service_account_base64: Optional[str] = os.environ.get("FIREBASE_SERVICE_ACCOUNT_BASE64")
    app_redirect_uri: str = _get_env("APP_REDIRECT_URI", "dropp://auth/callback")
    cors_allowed_origins: Optional[tuple[str, ...]] = _get_env_list("CORS_ALLOWED_ORIGINS")
    jwt_secret_key: Optional[str] = os.environ.get("JWT_SECRET_KEY")

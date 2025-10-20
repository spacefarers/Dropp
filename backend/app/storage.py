from __future__ import annotations

from datetime import datetime, timezone
from pathlib import Path
from typing import Dict, Optional
from uuid import uuid4

from vercel_blob import generate_client_token


def build_blob_pathname(user_id: str, original_filename: str) -> str:
    """
    Create a unique blob pathname per user.
    """
    suffix = Path(original_filename).suffix
    timestamp = datetime.now(tz=timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    return f"{user_id}/{timestamp}-{uuid4().hex}{suffix}"


def generate_client_upload_token(
    *,
    pathname: str,
    expires_in: int,
) -> str:
    """
    Generate a client upload token for direct uploads to Vercel Blob.
    The client can use this token to upload directly without going through the server.
    """
    return generate_client_token(
        pathname=pathname,
        token_payload={
            "allowedContentTypes": [],  # Allow any content type
            "maximumSizeInBytes": 100 * 1024 * 1024,  # 100MB max
            "validUntil": int((datetime.now(tz=timezone.utc).timestamp() + expires_in) * 1000),
        }
    )

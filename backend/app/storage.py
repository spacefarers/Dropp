from __future__ import annotations

from datetime import datetime, timezone
from pathlib import Path
from typing import BinaryIO
from uuid import uuid4

import vercel_blob


def build_blob_pathname(user_id: str, original_filename: str) -> str:
    """
    Create a unique blob pathname per user.
    """
    suffix = Path(original_filename).suffix
    timestamp = datetime.now(tz=timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    return f"{user_id}/{timestamp}-{uuid4().hex}{suffix}"


def upload_to_blob(
    *,
    pathname: str,
    file_data: BinaryIO,
    content_type: str | None = None,
) -> dict:
    """
    Upload a file to Vercel Blob storage.
    Returns the blob response containing url, pathname, etc.
    """
    options = {}
    if content_type:
        options["content_type"] = content_type

    response = vercel_blob.put(pathname, file_data, options=options)
    return response


def delete_from_blob(blob_url: str) -> None:
    """
    Delete a file from Vercel Blob storage by its URL.
    """
    vercel_blob.delete(blob_url)

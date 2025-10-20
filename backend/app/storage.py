from __future__ import annotations

from datetime import datetime, timezone
from pathlib import Path
from typing import Dict, Optional
from uuid import uuid4


def build_object_key(user_id: str, original_filename: str) -> str:
    """
    Create a unique S3 object key per user.
    """
    suffix = Path(original_filename).suffix
    timestamp = datetime.now(tz=timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    return f"{user_id}/{timestamp}-{uuid4().hex}{suffix}"


def generate_upload_post(
    *,
    s3_client,
    bucket: str,
    key: str,
    content_type: Optional[str],
    expires_in: int,
    max_content_length: Optional[int] = None,
) -> Dict[str, object]:
    """
    Create a pre-signed POST policy so the client can upload directly to S3.
    """
    fields = {"key": key}
    conditions = [["eq", "$key", key]]

    if content_type:
        fields["Content-Type"] = content_type
        conditions.append(["eq", "$Content-Type", content_type])

    if max_content_length:
        conditions.append(["content-length-range", 1, max_content_length])

    return s3_client.generate_presigned_post(
        bucket,
        key,
        Fields=fields,
        Conditions=conditions,
        ExpiresIn=expires_in,
    )


def generate_download_url(
    *,
    s3_client,
    bucket: str,
    key: str,
    expires_in: int,
) -> str:
    """
    Produce a presigned GET URL for downloading an object.
    """
    return s3_client.generate_presigned_url(
        "get_object",
        Params={"Bucket": bucket, "Key": key},
        ExpiresIn=expires_in,
    )

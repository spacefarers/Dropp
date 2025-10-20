from __future__ import annotations

from datetime import datetime, timezone
from typing import Any, Dict, List, Optional

from bson import ObjectId
from bson.errors import InvalidId
from pymongo import ReturnDocument
from pymongo.database import Database


def _utcnow() -> datetime:
    return datetime.now(tz=timezone.utc)


def serialize_file(doc: Dict[str, Any]) -> Dict[str, Any]:
    """
    Convert a Mongo document into a JSON-serialisable payload.
    """
    return {
        "id": str(doc["_id"]),
        "user_id": doc["user_id"],
        "filename": doc["filename"],
        "size": doc.get("size"),
        "content_type": doc.get("content_type"),
        "blob_pathname": doc.get("blob_pathname"),
        "blob_url": doc.get("blob_url"),
        "status": doc.get("status", "pending"),
        "created_at": doc["created_at"].isoformat(),
        "updated_at": doc["updated_at"].isoformat(),
        "uploaded_at": doc.get("uploaded_at").isoformat()
        if doc.get("uploaded_at")
        else None,
    }


def record_upload_init(
    db: Database,
    *,
    user_id: str,
    filename: str,
    blob_pathname: str,
    size: Optional[int],
    content_type: Optional[str],
) -> Dict[str, Any]:
    """
    Store upload metadata before the client pushes the bytes to Vercel Blob.
    """
    now = _utcnow()
    document = {
        "user_id": user_id,
        "filename": filename,
        "size": size,
        "content_type": content_type,
        "blob_pathname": blob_pathname,
        "blob_url": None,
        "status": "pending",
        "created_at": now,
        "updated_at": now,
        "uploaded_at": None,
    }
    result = db.files.insert_one(document)
    document["_id"] = result.inserted_id
    return serialize_file(document)


def mark_upload_completed(
    db: Database,
    *,
    file_id: str,
    user_id: str,
    blob_url: str,
    size: Optional[int] = None,
) -> Optional[Dict[str, Any]]:
    """
    Mark an upload as completed, storing the blob URL and final size.
    """
    update_fields: Dict[str, Any] = {
        "status": "complete",
        "blob_url": blob_url,
        "uploaded_at": _utcnow(),
        "updated_at": _utcnow()
    }
    if size is not None:
        update_fields["size"] = size

    try:
        object_id = ObjectId(file_id)
    except (InvalidId, TypeError):
        return None

    result = db.files.find_one_and_update(
        {"_id": object_id, "user_id": user_id},
        {"$set": update_fields},
        return_document=ReturnDocument.AFTER,
    )
    if not result:
        return None
    return serialize_file(result)


def list_files_for_user(db: Database, *, user_id: str) -> List[Dict[str, Any]]:
    """
    Fetch all files for a user ordered by creation date.
    """
    cursor = db.files.find({"user_id": user_id}).sort("created_at", -1)
    return [serialize_file(doc) for doc in cursor]


def get_file_by_id(db: Database, *, file_id: str, user_id: str) -> Optional[Dict[str, Any]]:
    """
    Retrieve a file document, ensuring it belongs to the requesting user.
    """
    try:
        object_id = ObjectId(file_id)
    except (InvalidId, TypeError):
        return None
    doc = db.files.find_one({"_id": object_id, "user_id": user_id})
    if not doc:
        return None
    return serialize_file(doc)

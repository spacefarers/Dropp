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
        "created_at": doc["created_at"].isoformat(),
        "updated_at": doc["updated_at"].isoformat(),
        "uploaded_at": doc.get("uploaded_at").isoformat()
        if doc.get("uploaded_at")
        else None,
    }


def record_completed_upload(
    db: Database,
    *,
    user_id: str,
    filename: str,
    blob_pathname: str,
    blob_url: str,
    size: int,
    content_type: Optional[str],
) -> Dict[str, Any]:
    """
    Store a completed file upload with all metadata.
    """
    now = _utcnow()
    document = {
        "user_id": user_id,
        "filename": filename,
        "size": size,
        "content_type": content_type,
        "blob_pathname": blob_pathname,
        "blob_url": blob_url,
        "created_at": now,
        "updated_at": now,
        "uploaded_at": now,
    }
    result = db.files.insert_one(document)
    document["_id"] = result.inserted_id
    return serialize_file(document)


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


def delete_file_by_id(db: Database, *, file_id: str, user_id: str) -> Optional[Dict[str, Any]]:
    """
    Delete a file document from the database, ensuring it belongs to the requesting user.
    Returns the deleted document if successful.
    """
    try:
        object_id = ObjectId(file_id)
    except (InvalidId, TypeError):
        return None
    doc = db.files.find_one_and_delete({"_id": object_id, "user_id": user_id})
    if not doc:
        return None
    return serialize_file(doc)


def get_or_create_user_storage(db: Database, *, user_id: str) -> Dict[str, Any]:
    """
    Get or create a user storage document.
    Default storage cap is 100MB (100 * 1024 * 1024 bytes).
    """
    DEFAULT_STORAGE_CAP = 100 * 1024 * 1024  # 100MB in bytes

    now = _utcnow()
    result = db.users.find_one_and_update(
        {"user_id": user_id},
        {
            "$setOnInsert": {
                "user_id": user_id,
                "storage_used": 0,
                "storage_cap": DEFAULT_STORAGE_CAP,
                "created_at": now,
            },
            "$set": {
                "updated_at": now,
            },
        },
        upsert=True,
        return_document=ReturnDocument.AFTER,
    )
    return result


def check_storage_available(
    db: Database, *, user_id: str, additional_bytes: int
) -> tuple[bool, Dict[str, Any]]:
    """
    Check if user has enough storage available for the additional bytes.
    Returns (has_space, user_storage_doc).
    """
    user_storage = get_or_create_user_storage(db, user_id=user_id)
    storage_used = user_storage.get("storage_used", 0)
    storage_cap = user_storage.get("storage_cap", 100 * 1024 * 1024)

    has_space = (storage_used + additional_bytes) <= storage_cap
    return has_space, user_storage


def increment_storage_usage(
    db: Database, *, user_id: str, bytes_added: int
) -> Optional[Dict[str, Any]]:
    """
    Increment the user's storage usage by the specified number of bytes.
    """
    result = db.users.find_one_and_update(
        {"user_id": user_id},
        {
            "$inc": {"storage_used": bytes_added},
            "$set": {"updated_at": _utcnow()},
        },
        return_document=ReturnDocument.AFTER,
    )
    return result


def decrement_storage_usage(
    db: Database, *, user_id: str, bytes_removed: int
) -> Optional[Dict[str, Any]]:
    """
    Decrement the user's storage usage by the specified number of bytes.
    Ensures storage_used doesn't go below 0.
    """
    result = db.users.find_one_and_update(
        {"user_id": user_id},
        {
            "$inc": {"storage_used": -bytes_removed},
            "$set": {"updated_at": _utcnow()},
        },
        return_document=ReturnDocument.AFTER,
    )

    # Ensure storage_used doesn't go negative
    if result and result.get("storage_used", 0) < 0:
        result = db.users.find_one_and_update(
            {"user_id": user_id},
            {
                "$set": {
                    "storage_used": 0,
                    "updated_at": _utcnow()
                }
            },
            return_document=ReturnDocument.AFTER,
        )

    return result


def serialize_session(doc: Dict[str, Any]) -> Dict[str, Any]:
    return {
        "id": str(doc["_id"]),
        "user_id": doc["user_id"],
        "session_token": doc.get("session_token"),
        "email": doc.get("email"),
        "created_at": doc.get("created_at").isoformat()
        if doc.get("created_at")
        else None,
        "updated_at": doc.get("updated_at").isoformat()
        if doc.get("updated_at")
        else None,
    }


def record_or_update_session(
    db: Database,
    *,
    user_id: str,
    session_token: str,
    email: Optional[str],
) -> Dict[str, Any]:
    """Persist the mapping between a Dropp session token and a user."""

    now = _utcnow()
    update = {
        "$set": {
            "user_id": user_id,
            "session_token": session_token,
            "email": email,
            "updated_at": now,
        },
        "$setOnInsert": {
            "created_at": now,
        },
    }

    result = db.sessions.find_one_and_update(
        {"session_token": session_token},
        update,
        upsert=True,
        return_document=ReturnDocument.AFTER,
    )

    return serialize_session(result)

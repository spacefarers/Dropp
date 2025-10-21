from __future__ import annotations

import base64
import json
import os
from dataclasses import dataclass
from typing import Any, Dict, Optional

import firebase_admin
from firebase_admin import auth, credentials


class FirebaseAuthError(RuntimeError):
    """Raised when Firebase authentication or API calls fail."""


@dataclass(frozen=True)
class FirebaseUser:
    user_id: str
    email: Optional[str] = None
    display_name: Optional[str] = None


class FirebaseAuthService:
    """
    Minimal helper around Firebase Admin SDK for token verification.
    Supports multiple credential loading methods for flexible deployment.
    """

    _initialized = False

    def __init__(self, service_account_base64: Optional[str] = None):
        """
        Initialize Firebase Auth Service.

        Uses FIREBASE_SERVICE_ACCOUNT_BASE64 environment variable.

        Args:
            service_account_base64: Base64-encoded Firebase service account JSON string.
                                   If None, reads from FIREBASE_SERVICE_ACCOUNT_BASE64 env var.
        """
        if not FirebaseAuthService._initialized:
            try:
                cred = self._load_credentials(service_account_base64)
                firebase_admin.initialize_app(cred)
                FirebaseAuthService._initialized = True
            except ValueError:
                # App already initialized
                pass

    def _load_credentials(self, service_account_base64: Optional[str] = None) -> credentials.Certificate:
        """
        Load Firebase credentials from base64-encoded environment variable.
        """
        base64_string = service_account_base64 or os.environ.get("FIREBASE_SERVICE_ACCOUNT_BASE64")

        if not base64_string:
            raise FirebaseAuthError(
                "Missing Firebase credentials. Set FIREBASE_SERVICE_ACCOUNT_BASE64 environment variable."
            )

        try:
            decoded = base64.b64decode(base64_string)
            service_account_info = json.loads(decoded)
            return credentials.Certificate(service_account_info)
        except (base64.binascii.Error, json.JSONDecodeError, ValueError) as exc:
            raise FirebaseAuthError(
                f"Failed to load Firebase credentials from base64: {exc}"
            ) from exc

    def verify_token(self, token: str) -> FirebaseUser:
        """
        Verify a Firebase ID token and return user information.

        Args:
            token: Firebase ID token from the client

        Returns:
            FirebaseUser object with user_id, email, and display_name

        Raises:
            FirebaseAuthError: If token verification fails
        """
        token_value = (token or "").strip()
        if not token_value:
            raise FirebaseAuthError("Missing Firebase token.")

        try:
            decoded_token = auth.verify_id_token(token_value)
            user_id = decoded_token.get("uid")

            if not user_id:
                raise FirebaseAuthError("Firebase token is missing a user ID.")

            email = decoded_token.get("email")
            display_name = decoded_token.get("name")

            return FirebaseUser(
                user_id=user_id,
                email=email,
                display_name=display_name
            )
        except auth.InvalidIdTokenError as exc:
            raise FirebaseAuthError(f"Invalid Firebase token: {exc}") from exc
        except auth.ExpiredIdTokenError as exc:
            raise FirebaseAuthError(f"Expired Firebase token: {exc}") from exc
        except auth.RevokedIdTokenError as exc:
            raise FirebaseAuthError(f"Revoked Firebase token: {exc}") from exc
        except auth.CertificateFetchError as exc:
            raise FirebaseAuthError(f"Certificate fetch error: {exc}") from exc
        except Exception as exc:
            raise FirebaseAuthError(f"Firebase token verification failed: {exc}") from exc

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Optional

import jwt


class JWTAuthError(RuntimeError):
    """Raised when Dropp session token handling fails."""


@dataclass(frozen=True)
class JWTSession:
    user_id: str
    email: Optional[str] = None
    display_name: Optional[str] = None


class JWTAuthService:
    """
    Issue and validate Dropp session tokens (JWT) signed with a shared secret.
    """

    _algorithm = "HS256"

    def __init__(self, *, secret_key: str):
        if not secret_key:
            raise JWTAuthError("Missing JWT secret key.")
        self._secret_key = secret_key

    def create_token(
        self,
        *,
        user_id: str,
        email: Optional[str],
        display_name: Optional[str],
    ) -> str:
        """
        Build a signed JWT for the authenticated user.
        """
        now = datetime.now(timezone.utc)
        payload = {
            "sub": user_id,
            "email": email,
            "display_name": display_name,
            "iat": int(now.timestamp()),
        }

        return jwt.encode(payload, self._secret_key, algorithm=self._algorithm)

    def verify_token(self, token: str) -> JWTSession:
        """
        Decode and validate a Dropp session token.
        """
        token_value = (token or "").strip()
        if not token_value:
            raise JWTAuthError("Missing session token.")

        try:
            payload = jwt.decode(token_value, self._secret_key, algorithms=[self._algorithm])
        except jwt.ExpiredSignatureError as exc:
            raise JWTAuthError("Session token expired.") from exc
        except jwt.InvalidTokenError as exc:
            raise JWTAuthError("Session token invalid.") from exc

        user_id = payload.get("sub")
        if not user_id:
            raise JWTAuthError("Session token missing required claims.")

        return JWTSession(
            user_id=user_id,
            email=payload.get("email"),
            display_name=payload.get("display_name"),
        )

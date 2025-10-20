from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Dict, Optional

from clerk_backend_api import Clerk
from clerk_backend_api.models import ClerkBaseError
from clerk_backend_api.security import verify_token as clerk_verify_token
from clerk_backend_api.security.types import TokenVerificationError, VerifyTokenOptions


class ClerkAuthError(RuntimeError):
    """Raised when Clerk authentication or API calls fail."""


@dataclass(frozen=True)
class ClerkUser:
    user_id: str
    email: Optional[str] = None


class ClerkAuthService:
    """
    Minimal helper around Clerk's backend SDK so route handlers stay lean.
    """

    def __init__(self, secret_key: str):
        self._secret_key = secret_key
        self._verify_options = VerifyTokenOptions(secret_key=secret_key)

    def verify_token(self, token: str) -> ClerkUser:
        claims = self._verify_token_claims(token)
        user_id = claims.get("sub") or claims.get("user_id")
        if not user_id:
            raise ClerkAuthError("Clerk token is missing a subject identifier.")

        email = self._extract_email_from_claims(claims)
        if email:
            return ClerkUser(user_id=user_id, email=email)

        return ClerkUser(user_id=user_id, email=self._fetch_primary_email(user_id))

    def _verify_token_claims(self, token: str) -> Dict[str, Any]:
        token_value = (token or "").strip()
        if not token_value:
            raise ClerkAuthError("Missing Clerk token.")

        try:
            return clerk_verify_token(token_value, self._verify_options)
        except TokenVerificationError as exc:
            raise ClerkAuthError(f"Clerk token verification failed: {exc}") from exc

    @staticmethod
    def _extract_email_from_claims(claims: Dict[str, Any]) -> Optional[str]:
        email = claims.get("email")
        if email:
            return email

        # The template might embed addresses inside email_addresses for compatibility.
        email_addresses = claims.get("email_addresses")
        if isinstance(email_addresses, list):
            for address in email_addresses:
                if isinstance(address, dict):
                    candidate = address.get("email") or address.get("email_address")
                    if candidate:
                        return candidate

        primary_email = claims.get("primary_email_address")
        if isinstance(primary_email, dict):
            candidate = primary_email.get("email_address") or primary_email.get("email")
            if candidate:
                return candidate

        return None

    def _fetch_primary_email(self, user_id: str) -> Optional[str]:
        try:
            with Clerk(bearer_auth=self._secret_key) as client:
                user = client.users.get(user_id=user_id)
        except ClerkBaseError:
            return None

        if not user:
            return None

        addresses = list(user.email_addresses or [])
        primary_id = user.primary_email_address_id
        if primary_id:
            for entry in addresses:
                if getattr(entry, "id", None) == primary_id:
                    candidate = getattr(entry, "email_address", None)
                    if candidate:
                        return candidate

        for entry in addresses:
            candidate = getattr(entry, "email_address", None)
            if candidate:
                return candidate

        return None

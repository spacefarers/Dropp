from __future__ import annotations

from dataclasses import dataclass
from http import HTTPStatus
from typing import Any, Dict, Optional

import requests


class ClerkAuthError(RuntimeError):
    """Raised when Clerk authentication or API calls fail."""


@dataclass(frozen=True)
class ClerkUser:
    user_id: str
    email: Optional[str] = None


class ClerkAuthService:
    """
    Minimal helper around Clerk's Verify Token API so route handlers stay lean.
    """

    _VERIFY_URL = "https://api.clerk.com/v1/tokens/verify"
    _USER_URL_TEMPLATE = "https://api.clerk.com/v1/users/{user_id}"

    def __init__(self, secret_key: str):
        self._secret_key = secret_key

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
        if not token or not token.strip():
            raise ClerkAuthError("Missing Clerk token.")

        try:
            response = requests.post(
                self._VERIFY_URL,
                headers={
                    "Authorization": f"Bearer {self._secret_key}",
                    "Content-Type": "application/json",
                },
                json={"token": token},
                timeout=10,
            )
        except requests.RequestException as exc:
            raise ClerkAuthError("Unable to reach Clerk token verification endpoint.") from exc

        if response.status_code != HTTPStatus.OK:
            error_detail: Any
            try:
                error_detail = response.json()
            except ValueError:
                error_detail = response.text
            raise ClerkAuthError(f"Clerk token verification failed: {error_detail}")

        payload = response.json()
        return payload.get("claims", {})

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
            response = requests.get(
                self._USER_URL_TEMPLATE.format(user_id=user_id),
                headers={"Authorization": f"Bearer {self._secret_key}"},
                timeout=10,
            )
        except requests.RequestException:
            return None

        if response.status_code != HTTPStatus.OK:
            return None

        data = response.json()
        primary_id = data.get("primary_email_address_id")
        addresses = data.get("email_addresses") or []
        if primary_id:
            for entry in addresses:
                if isinstance(entry, dict) and entry.get("id") == primary_id:
                    return entry.get("email_address")

        for entry in addresses:
            if isinstance(entry, dict):
                candidate = entry.get("email_address")
                if candidate:
                    return candidate

        return None

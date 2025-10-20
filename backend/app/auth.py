from __future__ import annotations

from dataclasses import dataclass
from typing import Dict, Tuple

import google.auth.transport.requests
from google.oauth2 import id_token
from google_auth_oauthlib.flow import Flow


GOOGLE_SCOPES = (
    "openid",
    "https://www.googleapis.com/auth/userinfo.email",
    "https://www.googleapis.com/auth/userinfo.profile",
)


@dataclass
class GoogleOAuthConfig:
    client_id: str
    client_secret: str
    redirect_uri: str


class GoogleOAuthService:
    """
    Minimal helper around google-auth so we keep route handlers lean.
    """

    def __init__(self, config: GoogleOAuthConfig):
        self._config = config

    def _build_flow(self, state: str | None = None) -> Flow:
        return Flow.from_client_config(
            {
                "web": {
                    "client_id": self._config.client_id,
                    "client_secret": self._config.client_secret,
                    "redirect_uris": [self._config.redirect_uri],
                    "auth_uri": "https://accounts.google.com/o/oauth2/auth",
                    "token_uri": "https://oauth2.googleapis.com/token",
                }
            },
            scopes=list(GOOGLE_SCOPES),
            state=state,
            redirect_uri=self._config.redirect_uri,
        )

    def authorization_url(self, state: str | None = None) -> Tuple[str, str]:
        flow = self._build_flow(state)
        url, new_state = flow.authorization_url(
            access_type="offline",
            include_granted_scopes="true",
            prompt="consent",
        )
        return url, new_state

    def exchange_code(self, authorization_response: str, state: str | None = None):
        flow = self._build_flow(state)
        flow.fetch_token(authorization_response=authorization_response)
        return flow.credentials

    def user_profile(self, credentials) -> Dict[str, str]:
        request = google.auth.transport.requests.Request()
        claims = id_token.verify_oauth2_token(
            id_token=credentials._id_token,  # pylint: disable=protected-access
            request=request,
            audience=self._config.client_id,
        )
        return {
            "sub": claims["sub"],
            "email": claims.get("email"),
            "name": claims.get("name"),
            "picture": claims.get("picture"),
        }

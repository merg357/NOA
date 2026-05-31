"""Bearer-token authentication dependency for FastAPI routes."""

from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from vps.config import Settings, get_settings

_bearer = HTTPBearer(auto_error=False)


def require_auth(
    creds: HTTPAuthorizationCredentials | None = Depends(_bearer),
    settings: Settings = Depends(get_settings),
) -> None:
    """Raise 401 if the bearer token is wrong.

    In dev mode (VPS_BEARER_TOKEN not set) all requests are allowed through
    with a logged warning.  Never deploy without a token in production.
    """
    if not settings.bearer_token:
        # Dev mode — no token configured, pass through.
        return

    if creds is None or creds.credentials != settings.bearer_token:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or missing bearer token",
            headers={"WWW-Authenticate": "Bearer"},
        )

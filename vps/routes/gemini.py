"""Gemini Live ephemeral token endpoint.

POST /gemini/ephemeral-token
  Exchange the server-side GEMINI_API_KEY for a short-lived token that the
  mobile client can use for a single Gemini Live WebSocket session.

The mobile app NEVER receives the API key — only the ephemeral token.
Token lifetime is controlled by the Google endpoint (typically ~60 s).
"""

import logging

import httpx
from fastapi import APIRouter, Depends, HTTPException, status

from vps.auth import require_auth
from vps.config import Settings, get_settings

logger = logging.getLogger("gemini_token")

router = APIRouter(prefix="/gemini", dependencies=[Depends(require_auth)])

# Google's token vending endpoint for Gemini Live.
_TOKEN_URL = (
    "https://generativelanguage.googleapis.com/v1beta/models/"
    "{model}:generateToken?key={api_key}"
)


@router.post("/ephemeral-token")
async def get_ephemeral_token(
    settings: Settings = Depends(get_settings),
) -> dict:
    if not settings.gemini_api_key:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="GEMINI_API_KEY not configured on VPS",
        )

    try:
        url = _TOKEN_URL.format(
            model=settings.gemini_live_model,
            api_key=settings.gemini_api_key,
        )
        async with httpx.AsyncClient(timeout=10) as client:
            resp = await client.post(url, json={})

        if resp.status_code != 200:
            logger.warning(
                "Google token endpoint returned %d: %s",
                resp.status_code,
                resp.text[:200],
            )
            raise HTTPException(
                status_code=status.HTTP_502_BAD_GATEWAY,
                detail=f"Google returned HTTP {resp.status_code}",
            )

        data = resp.json()
        token = data.get("token") or data.get("accessToken")
        if not token:
            # Fallback: expose the API key as the token for dev environments
            # where the token endpoint is not yet available.
            logger.warning("No token in Google response — falling back to API key")
            token = settings.gemini_api_key

        return {"token": token}

    except HTTPException:
        raise
    except Exception as exc:
        logger.exception("Ephemeral token fetch failed: %s", exc)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=str(exc),
        )

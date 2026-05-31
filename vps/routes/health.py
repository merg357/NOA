"""Health / status endpoint — no auth required."""

from datetime import datetime, timezone

from fastapi import APIRouter

from vps.ws_manager import manager as ws

router = APIRouter()


@router.get("/health")
async def health() -> dict:
    return {
        "status": "ok",
        "service": "jarvis-vps",
        "ts": datetime.now(timezone.utc).isoformat(),
        "connected_devices": ws.connected_devices,
        "socket_count": ws.count,
    }

"""Wearable card push endpoint.

POST /cards/push
  Push a wearable card to one or all connected mobile clients.

POST /cards/status
  Push a status banner string (short text) to a device.
"""

from __future__ import annotations

from fastapi import APIRouter, Depends

from vps.auth import require_auth
from vps.ws_manager import manager

router = APIRouter(prefix="/cards", dependencies=[Depends(require_auth)])


class PushCardRequest:
    pass


from pydantic import BaseModel


class CardPayload(BaseModel):
    id: str
    title: str
    body: str
    icon: str = "◈"
    card_type: str = "info"
    priority: int = 0


class PushCardRequest(BaseModel):  # type: ignore[no-redef]
    device_id: str | None = None  # None → broadcast
    card: CardPayload


class StatusBannerRequest(BaseModel):
    device_id: str | None = None
    message: str


@router.post("/push")
async def push_card(req: PushCardRequest) -> dict:
    payload = {
        "type": "wearable_card",
        "card": req.card.model_dump(),
    }
    if req.device_id:
        ok = await manager.send_to_device(req.device_id, payload)
        return {"status": "sent" if ok else "no_socket", "device_id": req.device_id}
    else:
        n = await manager.broadcast(payload)
        return {"status": "broadcast", "reached": n}


@router.post("/status")
async def push_status(req: StatusBannerRequest) -> dict:
    payload = {"type": "status_banner", "message": req.message}
    if req.device_id:
        ok = await manager.send_to_device(req.device_id, payload)
        return {"status": "sent" if ok else "no_socket"}
    else:
        n = await manager.broadcast(payload)
        return {"status": "broadcast", "reached": n}

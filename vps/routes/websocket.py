"""WebSocket endpoint for mobile clients.

Connect:  ws://<host>:<port>/ws?device_id=<uuid>
          Authorization: Bearer <token> (passed as query param `token` for WS
          clients that cannot set headers, OR in the initial JSON handshake).

Protocol (all messages are JSON):
  Client → server:
    {"type": "ping"}
    {"type": "hermes_trigger", "task": "<name>", "params": {...}}
    {"type": "card_ack", "card_id": "<id>"}

  Server → client:
    {"type": "pong", "ts": "..."}
    {"type": "wearable_card", "card": {...}}
    {"type": "hermes_result", "task": "...", "result": {...}}
    {"type": "error", "detail": "..."}
"""

import json
import logging

from fastapi import APIRouter, Query, WebSocket, WebSocketDisconnect

from vps.auth import _bearer  # noqa: F401  (not used directly — see note)
from vps.config import get_settings
from vps.hermes_bridge import trigger_task
from vps.ws_manager import manager

logger = logging.getLogger("ws_endpoint")

router = APIRouter()


@router.websocket("/ws")
async def websocket_endpoint(
    ws: WebSocket,
    device_id: str = Query(default="unknown"),
    token: str = Query(default=""),
) -> None:
    settings = get_settings()

    # Authenticate: check query-param token if bearer token is configured.
    if settings.bearer_token and token != settings.bearer_token:
        await ws.close(code=4001, reason="Unauthorized")
        return

    await manager.connect(device_id, ws)
    try:
        # Send welcome message.
        await ws.send_json(
            {
                "type": "connected",
                "device_id": device_id,
                "message": "Jarvis VPS connected. Ready.",
            }
        )

        while True:
            raw = await ws.receive_text()
            try:
                msg = json.loads(raw)
            except json.JSONDecodeError:
                await ws.send_json({"type": "error", "detail": "invalid JSON"})
                continue

            msg_type = msg.get("type", "")
            logger.debug("WS [%s] → %s", device_id, msg_type)

            if msg_type == "ping":
                from datetime import datetime, timezone

                await ws.send_json(
                    {"type": "pong", "ts": datetime.now(timezone.utc).isoformat()}
                )

            elif msg_type == "hermes_trigger":
                task = msg.get("task", "ping")
                params = msg.get("params", {})
                params["device_id"] = device_id
                result = await trigger_task(task, params)
                await ws.send_json(
                    {"type": "hermes_result", "task": task, "result": result}
                )

            elif msg_type == "card_ack":
                logger.info(
                    "Card ACK from %s: card_id=%s", device_id, msg.get("card_id")
                )

            else:
                await ws.send_json(
                    {"type": "error", "detail": f"unknown message type: {msg_type}"}
                )

    except WebSocketDisconnect:
        pass
    finally:
        manager.disconnect(device_id, ws)

"""WebSocket connection manager for mobile clients.

Each client connects with a device_id query parameter.  The manager:
 - tracks all live connections keyed by device_id
 - lets routes push JSON payloads to a specific device or broadcast to all
 - handles graceful disconnects without crashing the broadcast loop
"""

import asyncio
import json
import logging
from collections import defaultdict

from fastapi import WebSocket

logger = logging.getLogger("ws_manager")


class ConnectionManager:
    def __init__(self) -> None:
        # device_id → list of active WebSocket objects (a device may have
        # multiple tabs open in a debug scenario).
        self._connections: dict[str, list[WebSocket]] = defaultdict(list)

    # ── Lifecycle ─────────────────────────────────────────────────────────────

    async def connect(self, device_id: str, ws: WebSocket) -> None:
        await ws.accept()
        self._connections[device_id].append(ws)
        logger.info("Device connected: %s (total sockets: %d)", device_id, self.count)

    def disconnect(self, device_id: str, ws: WebSocket) -> None:
        sockets = self._connections.get(device_id, [])
        if ws in sockets:
            sockets.remove(ws)
        if not sockets:
            self._connections.pop(device_id, None)
        logger.info(
            "Device disconnected: %s (remaining sockets: %d)", device_id, self.count
        )

    # ── Push helpers ──────────────────────────────────────────────────────────

    async def send_to_device(self, device_id: str, payload: dict) -> bool:
        """Send a JSON payload to all sockets belonging to *device_id*.

        Returns True if at least one socket was reached.
        """
        sockets = list(self._connections.get(device_id, []))
        if not sockets:
            logger.warning("send_to_device: no sockets for %s", device_id)
            return False

        text = json.dumps(payload)
        dead: list[WebSocket] = []
        for ws in sockets:
            try:
                await ws.send_text(text)
            except Exception as exc:
                logger.warning("send failed to %s: %s", device_id, exc)
                dead.append(ws)

        for ws in dead:
            self.disconnect(device_id, ws)

        return bool(sockets) and not dead

    async def broadcast(self, payload: dict) -> int:
        """Broadcast to all connected devices. Returns number reached."""
        text = json.dumps(payload)
        reached = 0
        dead: list[tuple[str, WebSocket]] = []

        for device_id, sockets in list(self._connections.items()):
            for ws in list(sockets):
                try:
                    await ws.send_text(text)
                    reached += 1
                except Exception as exc:
                    logger.warning("broadcast failed for %s: %s", device_id, exc)
                    dead.append((device_id, ws))

        for device_id, ws in dead:
            self.disconnect(device_id, ws)

        return reached

    # ── Info ──────────────────────────────────────────────────────────────────

    @property
    def count(self) -> int:
        return sum(len(v) for v in self._connections.values())

    @property
    def connected_devices(self) -> list[str]:
        return list(self._connections.keys())


# Module-level singleton shared by all routes.
manager = ConnectionManager()

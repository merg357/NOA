"""Tests for the Jarvis VPS backend."""

from __future__ import annotations

import asyncio
import json
import os
import sys

# Ensure the jarvis root is on the path when running from the test directory.
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

import pytest
from fastapi.testclient import TestClient

# Force-set test credentials BEFORE importing the app so that Settings class
# attributes (evaluated at module-definition time) see "test-token" even when
# a real .env or inherited shell environment supplies a different value.
os.environ["VPS_BEARER_TOKEN"] = "test-token"
os.environ["GEMINI_API_KEY"] = ""

from vps.main import app  # noqa: E402
from vps.config import Settings, get_settings  # noqa: E402
from vps.ws_manager import manager  # noqa: E402

# Clear lru_cache and patch the Settings class attribute so that any
# previously-cached Settings instance with the real token is invalidated.
get_settings.cache_clear()
Settings.bearer_token = "test-token"
Settings.gemini_api_key = ""

client = TestClient(app)


# ── Health ────────────────────────────────────────────────────────────────────


def test_health_ok():
    resp = client.get("/health")
    assert resp.status_code == 200
    body = resp.json()
    assert body["status"] == "ok"
    assert body["service"] == "jarvis-vps"
    assert "ts" in body


# ── Auth ──────────────────────────────────────────────────────────────────────


def test_hermes_ping_no_auth_returns_401():
    resp = client.get("/hermes/ping")
    assert resp.status_code == 401


def test_hermes_ping_wrong_token_returns_401():
    resp = client.get("/hermes/ping", headers={"Authorization": "Bearer wrong"})
    assert resp.status_code == 401


def test_hermes_ping_valid_token():
    resp = client.get(
        "/hermes/ping", headers={"Authorization": "Bearer test-token"}
    )
    assert resp.status_code == 200
    body = resp.json()
    assert body["type"] == "hermes_ping"
    assert "hermes_available" in body
    assert "state_db_exists" in body


# ── Hermes trigger ────────────────────────────────────────────────────────────


def test_hermes_trigger_ping():
    resp = client.post(
        "/hermes/trigger",
        json={"task": "ping", "params": {}},
        headers={"Authorization": "Bearer test-token"},
    )
    assert resp.status_code == 200
    body = resp.json()
    assert body["status"] == "ok"
    assert body["task"] == "ping"


def test_hermes_trigger_daily_brief():
    resp = client.post(
        "/hermes/trigger",
        json={"task": "daily_brief", "params": {}},
        headers={"Authorization": "Bearer test-token"},
    )
    assert resp.status_code == 200
    body = resp.json()
    assert body["status"] == "ok"
    assert "brief" in body["result"]


def test_hermes_trigger_unknown_task():
    resp = client.post(
        "/hermes/trigger",
        json={"task": "does_not_exist", "params": {}},
        headers={"Authorization": "Bearer test-token"},
    )
    assert resp.status_code == 200
    body = resp.json()
    assert body["result"]["status"] == "unknown_task"


# ── Card push ─────────────────────────────────────────────────────────────────


def test_push_card_broadcast_no_sockets():
    resp = client.post(
        "/cards/push",
        json={
            "device_id": None,
            "card": {
                "id": "test-1",
                "title": "Hello",
                "body": "World",
            },
        },
        headers={"Authorization": "Bearer test-token"},
    )
    assert resp.status_code == 200
    body = resp.json()
    assert body["status"] == "broadcast"
    assert body["reached"] == 0


def test_push_status_no_sockets():
    resp = client.post(
        "/cards/status",
        json={"device_id": None, "message": "Listening…"},
        headers={"Authorization": "Bearer test-token"},
    )
    assert resp.status_code == 200
    assert resp.json()["status"] == "broadcast"


# ── Gemini token ──────────────────────────────────────────────────────────────


def test_gemini_ephemeral_token_no_key_returns_503():
    # GEMINI_API_KEY is empty — should get 503
    resp = client.post(
        "/gemini/ephemeral-token",
        headers={"Authorization": "Bearer test-token"},
    )
    assert resp.status_code == 503


# ── Connection manager ────────────────────────────────────────────────────────


@pytest.mark.asyncio
async def test_ws_manager_connect_disconnect():
    from unittest.mock import AsyncMock, MagicMock

    ws = MagicMock()
    ws.accept = AsyncMock()
    ws.send_text = AsyncMock()

    await manager.connect("dev-1", ws)
    assert "dev-1" in manager.connected_devices
    assert manager.count == 1

    manager.disconnect("dev-1", ws)
    assert "dev-1" not in manager.connected_devices
    assert manager.count == 0


@pytest.mark.asyncio
async def test_ws_manager_send_to_device_not_found():
    result = await manager.send_to_device("ghost-device", {"type": "test"})
    assert result is False


@pytest.mark.asyncio
async def test_ws_manager_broadcast_empty():
    reached = await manager.broadcast({"type": "test"})
    assert reached == 0


# ── WebSocket endpoint ────────────────────────────────────────────────────────


def test_ws_rejects_bad_token():
    # Server closes with code 4001 — the TestClient raises WebSocketDisconnect
    # at context-manager entry when the server immediately closes the socket.
    from starlette.websockets import WebSocketDisconnect

    with pytest.raises(WebSocketDisconnect):
        with client.websocket_connect("/ws?device_id=tester&token=bad"):
            pass  # pragma: no cover


def test_ws_accepts_valid_token():
    with client.websocket_connect("/ws?device_id=tester&token=test-token") as ws:
        msg = json.loads(ws.receive_text())
        assert msg["type"] == "connected"
        assert msg["device_id"] == "tester"

        # Ping
        ws.send_text(json.dumps({"type": "ping"}))
        pong = json.loads(ws.receive_text())
        assert pong["type"] == "pong"


def test_ws_hermes_trigger_over_socket():
    with client.websocket_connect("/ws?device_id=tester2&token=test-token") as ws:
        ws.receive_text()  # welcome
        ws.send_text(json.dumps({"type": "hermes_trigger", "task": "ping"}))
        resp = json.loads(ws.receive_text())
        assert resp["type"] == "hermes_result"
        assert resp["task"] == "ping"


def test_hermes_trigger_test_card_http():
    """test_card task returns status ok and a message string."""
    resp = client.post(
        "/hermes/trigger",
        json={"task": "test_card", "params": {}},
        headers={"Authorization": "Bearer test-token"},
    )
    assert resp.status_code == 200
    body = resp.json()
    assert body["status"] == "ok"
    assert body["task"] == "test_card"
    result = body["result"]
    assert result["status"] == "ok"
    assert "test card" in result["message"].lower()


def test_ws_test_card_pushes_wearable_card():
    """test_card via WebSocket delivers a wearable_card message to the same connection."""
    with client.websocket_connect("/ws?device_id=tester3&token=test-token") as ws:
        ws.receive_text()  # welcome
        ws.send_text(json.dumps({"type": "hermes_trigger", "task": "test_card"}))
        # The VPS sends a wearable_card directly to the device socket...
        card_msg = json.loads(ws.receive_text())
        assert card_msg["type"] == "wearable_card"
        assert "card" in card_msg
        assert card_msg["card"]["title"] == "VPS Test Card"
        # ...and also sends back a hermes_result.
        result_msg = json.loads(ws.receive_text())
        assert result_msg["type"] == "hermes_result"
        assert result_msg["task"] == "test_card"
        assert result_msg["result"]["status"] == "ok"

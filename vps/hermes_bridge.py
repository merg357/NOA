"""Hermes integration bridge.

Wraps the installed hermes-agent CLI and SQLite state DB to:
  - ping the agent (connectivity check)
  - trigger scheduled / ad-hoc tasks
  - read back stored results
  - push result cards to mobile via ws_manager
"""

from __future__ import annotations

import asyncio
import json
import logging
import sqlite3
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from vps.config import Settings, get_settings
from vps.ws_manager import manager as ws

logger = logging.getLogger("hermes_bridge")

# ── Helpers ───────────────────────────────────────────────────────────────────


def _now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def _state_db_path(settings: Settings) -> Path:
    return Path(settings.hermes_state_db)


# ── Ping ─────────────────────────────────────────────────────────────────────


async def ping() -> dict[str, Any]:
    """Return a lightweight status dict without touching the DB."""
    hermes_bin = await asyncio.to_thread(_find_hermes_bin)
    version: str | None = None
    if hermes_bin:
        try:
            proc = await asyncio.create_subprocess_exec(
                hermes_bin,
                "--version",
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.DEVNULL,
            )
            stdout, _ = await asyncio.wait_for(proc.communicate(), timeout=5)
            version = stdout.decode().strip().splitlines()[0] if stdout else None
        except Exception as exc:
            logger.warning("hermes ping failed: %s", exc)

    settings = get_settings()
    db_ok = _state_db_path(settings).exists()
    return {
        "type": "hermes_ping",
        "hermes_available": hermes_bin is not None,
        "hermes_version": version,
        "state_db_exists": db_ok,
        "ts": _now_iso(),
    }


def _find_hermes_bin() -> str | None:
    import shutil

    for name in ("hermes", "hermes-agent"):
        path = shutil.which(name)
        if path:
            return path
    return None


# ── Test card ─────────────────────────────────────────────────────────────────


async def send_test_card(device_id: str | None = None) -> dict[str, Any]:
    """Push a sample wearable card to verify the push→receive pipeline."""
    card = {
        "type": "wearable_card",
        "card": {
            "id": f"test-{datetime.now().timestamp():.0f}",
            "title": "VPS Test Card",
            "body": "Card received from VPS ✓",
            "icon": "◈",
            "card_type": "info",
            "priority": 0,
            "ts": _now_iso(),
        },
    }
    if device_id:
        await ws.send_to_device(device_id, card)
    else:
        await ws.broadcast(card)
    return {"status": "ok", "message": "test card sent"}


# ── Daily brief ───────────────────────────────────────────────────────────────


async def generate_daily_brief(device_id: str | None = None) -> dict[str, Any]:
    """Build a daily brief from available context and push it to the device."""
    settings = get_settings()
    items: list[str] = []

    # Read pending reminders from state DB (best-effort).
    reminders = await asyncio.to_thread(_read_reminders, settings)
    if reminders:
        items.append(f"Reminders ({len(reminders)}): " + "; ".join(reminders[:3]))
        if len(reminders) > 3:
            items[-1] += f" +{len(reminders) - 3} more"

    # Read recent tasks from state DB (best-effort).
    tasks = await asyncio.to_thread(_read_tasks, settings)
    if tasks:
        open_tasks = [t for t in tasks if not t.get("done")]
        if open_tasks:
            items.append(
                f"Open tasks ({len(open_tasks)}): "
                + "; ".join(t.get("title", "?") for t in open_tasks[:3])
            )

    if not items:
        items.append("No pending items.")

    brief_text = "Daily Brief — " + _now_iso()[:10] + "\n" + "\n".join(items)

    card = {
        "type": "wearable_card",
        "card": {
            "id": f"brief-{datetime.now().timestamp():.0f}",
            "title": "Daily Brief",
            "body": brief_text[:300],
            "icon": "◈",
            "card_type": "dailyBrief",
            "priority": 0,
            "ts": _now_iso(),
        },
    }

    if device_id:
        await ws.send_to_device(device_id, card)
    else:
        await ws.broadcast(card)

    return {"status": "ok", "brief": brief_text}


def _read_reminders(settings: Settings) -> list[str]:
    db = _state_db_path(settings)
    if not db.exists():
        return []
    try:
        con = sqlite3.connect(str(db))
        cur = con.execute(
            "SELECT value FROM kv WHERE key LIKE 'reminder:%' LIMIT 20"
        )
        rows = [r[0] for r in cur.fetchall()]
        con.close()
        return rows
    except Exception as exc:
        logger.debug("_read_reminders: %s", exc)
        return []


def _read_tasks(settings: Settings) -> list[dict]:
    db = _state_db_path(settings)
    if not db.exists():
        return []
    try:
        con = sqlite3.connect(str(db))
        cur = con.execute(
            "SELECT value FROM kv WHERE key LIKE 'task:%' LIMIT 20"
        )
        rows = []
        for (v,) in cur.fetchall():
            try:
                rows.append(json.loads(v))
            except Exception:
                rows.append({"title": str(v)})
        con.close()
        return rows
    except Exception as exc:
        logger.debug("_read_tasks: %s", exc)
        return []


# ── Generic task trigger ──────────────────────────────────────────────────────


async def trigger_task(task_name: str, params: dict[str, Any]) -> dict[str, Any]:
    """Run a named Hermes skill / task asynchronously and return its output.

    Currently supported tasks:
      - ``daily_brief`` — generate and push a daily brief card
      - ``reminder_sync`` — alias for daily_brief
      - ``ping`` — connectivity check
    """
    task_name = task_name.lower().strip()
    device_id: str | None = params.get("device_id")

    if task_name in ("daily_brief", "reminder_sync", "inbox_summary"):
        return await generate_daily_brief(device_id=device_id)

    if task_name == "ping":
        return await ping()

    if task_name == "test_card":
        return await send_test_card(device_id=device_id)

    return {"status": "unknown_task", "task": task_name}


# ── Store result in state DB ──────────────────────────────────────────────────


async def store_result(key: str, value: Any) -> None:
    """Persist an arbitrary result to the Hermes state DB."""
    settings = get_settings()
    await asyncio.to_thread(_write_kv, settings, key, value)


def _write_kv(settings: Settings, key: str, value: Any) -> None:
    db = _state_db_path(settings)
    if not db.exists():
        logger.debug("store_result: state DB not found at %s", db)
        return
    try:
        text = json.dumps(value) if not isinstance(value, str) else value
        con = sqlite3.connect(str(db))
        con.execute(
            "CREATE TABLE IF NOT EXISTS kv (key TEXT PRIMARY KEY, value TEXT)"
        )
        con.execute("INSERT OR REPLACE INTO kv (key, value) VALUES (?, ?)", (key, text))
        con.commit()
        con.close()
    except Exception as exc:
        logger.warning("store_result failed: %s", exc)

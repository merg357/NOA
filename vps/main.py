"""Jarvis VPS — FastAPI application entry point.

Start with:
    uvicorn vps.main:app --host 0.0.0.0 --port 8765 --reload

Or via the systemd service (see deploy/jarvis-vps.service).
"""

import logging
import sys

from contextlib import asynccontextmanager

import uvicorn
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from vps.config import get_settings
from vps.routes import cards, gemini, health, hermes, websocket

# ── Logging ───────────────────────────────────────────────────────────────────

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
    stream=sys.stdout,
)
logger = logging.getLogger("main")

# ── App ───────────────────────────────────────────────────────────────────────

@asynccontextmanager
async def _lifespan(application: FastAPI):
    settings = get_settings()
    for warning in settings.validate():
        logger.warning("CONFIG: %s", warning)
    logger.info("Jarvis VPS started on %s:%d", settings.host, settings.port)
    yield
    logger.info("Jarvis VPS shutting down")


app = FastAPI(
    title="Jarvis VPS",
    description="Always-on VPS brain for the Jarvis assistant system.",
    version="1.0.0",
    lifespan=_lifespan,
)

# Allow cross-origin requests from the Flutter web debug build and any LAN tool.
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

# ── Routes ────────────────────────────────────────────────────────────────────

app.include_router(health.router)
app.include_router(websocket.router)
app.include_router(cards.router)
app.include_router(hermes.router)
app.include_router(gemini.router)

# ── Dev runner ────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    settings = get_settings()
    uvicorn.run(
        "vps.main:app",
        host=settings.host,
        port=settings.port,
        log_level=settings.log_level,
        reload=True,
    )

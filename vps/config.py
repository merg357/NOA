"""VPS configuration — loaded once at startup from .env."""

import os
from functools import lru_cache

from dotenv import load_dotenv

load_dotenv()


class Settings:
    # ── Auth ──────────────────────────────────────────────────────────────────
    bearer_token: str = os.getenv("VPS_BEARER_TOKEN", "")

    # ── Server ────────────────────────────────────────────────────────────────
    host: str = os.getenv("VPS_HOST", "0.0.0.0")
    port: int = int(os.getenv("VPS_PORT", "8765"))
    log_level: str = os.getenv("VPS_LOG_LEVEL", "info")

    # ── Gemini ────────────────────────────────────────────────────────────────
    gemini_api_key: str = os.getenv("GEMINI_API_KEY", "")
    gemini_live_model: str = os.getenv(
        "GEMINI_LIVE_MODEL", "models/gemini-2.0-flash-live-001"
    )

    # ── Hermes ────────────────────────────────────────────────────────────────
    hermes_state_db: str = os.getenv(
        "HERMES_STATE_DB", "/root/.hermes/state.db"
    )
    hermes_skills_dir: str = os.getenv(
        "HERMES_SKILLS_DIR", "/root/.hermes/skills"
    )

    # ── Feature flags ─────────────────────────────────────────────────────────
    enable_hermes: bool = os.getenv("ENABLE_HERMES", "true").lower() == "true"

    def validate(self) -> list[str]:
        """Return list of warnings for missing optional config."""
        warnings: list[str] = []
        if not self.bearer_token:
            warnings.append(
                "VPS_BEARER_TOKEN not set — all requests will be accepted (dev mode)"
            )
        if not self.gemini_api_key:
            warnings.append(
                "GEMINI_API_KEY not set — ephemeral token endpoint will return 503"
            )
        return warnings


@lru_cache
def get_settings() -> Settings:
    return Settings()

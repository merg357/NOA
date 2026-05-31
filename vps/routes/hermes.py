"""Hermes task trigger endpoint.

POST /hermes/trigger
  Trigger a named task and receive the result.

GET /hermes/ping
  Quick connectivity check — no Hermes process required.
"""

from pydantic import BaseModel

from fastapi import APIRouter, Depends

from vps.auth import require_auth
from vps.hermes_bridge import ping, trigger_task

router = APIRouter(prefix="/hermes", dependencies=[Depends(require_auth)])


class TriggerRequest(BaseModel):
    task: str = "ping"
    params: dict = {}


@router.get("/ping")
async def hermes_ping() -> dict:
    return await ping()


@router.post("/trigger")
async def hermes_trigger(req: TriggerRequest) -> dict:
    result = await trigger_task(req.task, req.params)
    return {"status": "ok", "task": req.task, "result": result}

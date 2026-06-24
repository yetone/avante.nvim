"""Avante IPC Service - cross-process instance registry and message broker.

Each Neovim process running Avante registers its root sidebar instances here so
that instances in different nvim processes can discover, inspect, and message each
other.  The service is stateless across restarts: a volatile in-memory registry
backed by heartbeats; dead instances are reaped automatically.
"""  # noqa: INP001

from __future__ import annotations

import asyncio
import os
import time
from contextlib import asynccontextmanager
from typing import TYPE_CHECKING

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field

if TYPE_CHECKING:
    from collections.abc import AsyncGenerator

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

INSTANCE_TTL_SECONDS = float(os.getenv("IPC_INSTANCE_TTL", "30"))
REAPER_INTERVAL_SECONDS = 5.0


# ---------------------------------------------------------------------------
# Data models
# ---------------------------------------------------------------------------


class InstanceInfo(BaseModel):
    name: str = Field(..., description="Adjective-noun instance name e.g. swift-fox")
    instance_id: str = Field(..., description="Stable UUID assigned to this history session")
    nvim_pid: int = Field(..., description="PID of the owning Neovim process")
    project: str = Field("", description="Absolute path of the project this instance is working in")
    description: str = Field("", description="Short summary of what this instance is currently doing")
    registered_at: float = Field(default_factory=time.time)
    last_heartbeat: float = Field(default_factory=time.time)


class RegisterRequest(BaseModel):
    name: str
    instance_id: str
    nvim_pid: int
    project: str = ""
    description: str = ""


class HeartbeatRequest(BaseModel):
    instance_id: str
    description: str | None = None


class UnregisterRequest(BaseModel):
    instance_id: str


class UpdateDescriptionRequest(BaseModel):
    instance_id: str
    description: str


class SendMessageRequest(BaseModel):
    from_name: str = Field(..., description="Sender instance name")
    to_name: str = Field(..., description="Recipient instance name")
    message: str = Field(..., description="Message body")


class PendingMessage(BaseModel):
    from_name: str
    message: str
    sent_at: float = Field(default_factory=time.time)


class InstanceSummary(BaseModel):
    name: str
    instance_id: str
    nvim_pid: int
    project: str
    description: str
    registered_at: float
    last_heartbeat: float


# ---------------------------------------------------------------------------
# In-memory registry
# ---------------------------------------------------------------------------

_registry: dict[str, InstanceInfo] = {}
_message_queues: dict[str, list[PendingMessage]] = {}
_registry_lock = asyncio.Lock()


# ---------------------------------------------------------------------------
# Background reaper
# ---------------------------------------------------------------------------


async def _reaper() -> None:
    while True:
        await asyncio.sleep(REAPER_INTERVAL_SECONDS)
        now = time.time()
        async with _registry_lock:
            stale = [
                iid for iid, info in _registry.items()
                if now - info.last_heartbeat > INSTANCE_TTL_SECONDS
            ]
            for iid in stale:
                name = _registry[iid].name
                del _registry[iid]
                _message_queues.pop(name, None)


@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncGenerator[None, None]:  # noqa: ARG001
    task = asyncio.create_task(_reaper())
    yield
    task.cancel()
    try:
        await task
    except asyncio.CancelledError:
        pass


# ---------------------------------------------------------------------------
# Application
# ---------------------------------------------------------------------------

app = FastAPI(
    title="Avante IPC Service",
    description=(
        "Cross-process instance registry and message broker for Avante.nvim. "
        "Enables root Avante sidebar instances in separate Neovim processes to "
        "discover each other, share responsibility context, and exchange messages."
    ),
    version="0.0.1",
    lifespan=lifespan,
)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _find_by_name(name: str) -> InstanceInfo | None:
    return next((i for i in _registry.values() if i.name == name), None)


# ---------------------------------------------------------------------------
# Endpoints
# ---------------------------------------------------------------------------


@app.get("/api/health")
async def health_check() -> dict[str, str]:
    """Health / readiness probe polled by Lua until the service is up."""
    return {"status": "ok"}


@app.post("/api/v1/register", response_model=dict[str, str])
async def register(req: RegisterRequest) -> dict[str, str]:
    """Register a sidebar instance (idempotent: re-registering refreshes metadata)."""
    async with _registry_lock:
        existing = _registry.get(req.instance_id)
        if existing:
            existing.name = req.name
            existing.nvim_pid = req.nvim_pid
            existing.project = req.project
            if req.description:
                existing.description = req.description
            existing.last_heartbeat = time.time()
        else:
            _registry[req.instance_id] = InstanceInfo(
                name=req.name,
                instance_id=req.instance_id,
                nvim_pid=req.nvim_pid,
                project=req.project,
                description=req.description,
            )
            _message_queues.setdefault(req.name, [])
    return {"status": "ok", "instance_id": req.instance_id}


@app.post("/api/v1/unregister", response_model=dict[str, str])
async def unregister(req: UnregisterRequest) -> dict[str, str]:
    """Unregister an instance (called on sidebar close / nvim exit)."""
    async with _registry_lock:
        info = _registry.pop(req.instance_id, None)
        if info:
            _message_queues.pop(info.name, None)
    return {"status": "ok"}


@app.post("/api/v1/heartbeat", response_model=dict[str, str])
async def heartbeat(req: HeartbeatRequest) -> dict[str, str]:
    """Refresh TTL for an instance; returns 404 if not found (need to re-register)."""
    async with _registry_lock:
        info = _registry.get(req.instance_id)
        if not info:
            raise HTTPException(status_code=404, detail="Instance not found - re-register first")
        info.last_heartbeat = time.time()
        if req.description is not None:
            info.description = req.description[:500]
    return {"status": "ok"}


@app.post("/api/v1/update_description", response_model=dict[str, str])
async def update_description(req: UpdateDescriptionRequest) -> dict[str, str]:
    """Update the responsibility description for an instance."""
    async with _registry_lock:
        info = _registry.get(req.instance_id)
        if not info:
            raise HTTPException(status_code=404, detail="Instance not found")
        info.description = req.description[:500]
        info.last_heartbeat = time.time()
    return {"status": "ok"}


@app.get("/api/v1/instances", response_model=list[InstanceSummary])
async def list_instances(exclude_instance_id: str | None = None) -> list[InstanceSummary]:
    """List all live instances, each with their description so callers know what coworkers are doing."""
    async with _registry_lock:
        result = [
            InstanceSummary(
                name=i.name,
                instance_id=i.instance_id,
                nvim_pid=i.nvim_pid,
                project=i.project,
                description=i.description,
                registered_at=i.registered_at,
                last_heartbeat=i.last_heartbeat,
            )
            for i in _registry.values()
            if i.instance_id != exclude_instance_id
        ]
    return result


@app.post("/api/v1/send_message", response_model=dict[str, str])
async def send_message(req: SendMessageRequest) -> dict[str, str]:
    """Queue a message for a target instance; returns 404 if target is not registered."""
    async with _registry_lock:
        target = _find_by_name(req.to_name)
        if not target:
            available = sorted(i.name for i in _registry.values() if i.name != req.from_name)
            raise HTTPException(
                status_code=404,
                detail=f"Instance {req.to_name!r} not registered. Available: {', '.join(available) or 'none'}",
            )
        _message_queues.setdefault(req.to_name, []).append(
            PendingMessage(from_name=req.from_name, message=req.message)
        )
    return {"status": "ok", "queued_for": req.to_name}


@app.get("/api/v1/poll_messages/{instance_name}", response_model=list[PendingMessage])
async def poll_messages(instance_name: str) -> list[PendingMessage]:
    """Drain and return all pending messages (at-most-once delivery)."""
    async with _registry_lock:
        msgs = _message_queues.get(instance_name, [])
        _message_queues[instance_name] = []
    return list(msgs)

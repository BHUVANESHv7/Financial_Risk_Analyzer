"""
realtime.py
───────────
WebSocket connection manager for live updates.

Event routing:
  • Bank officers (ADMIN) receive every application event.
  • Applicants receive events for their own applications only.

Event shape sent to clients:
  {"type": "application.created" | "application.updated" | "stats.changed" | "presence" | "hello",
   "data": {...}, "ts": "<iso time>"}
"""

import asyncio
import json
from dataclasses import dataclass, field
from datetime import datetime, timezone

from fastapi import WebSocket


@dataclass(eq=False)
class Client:
    ws: WebSocket
    user_id: int
    role: str
    email: str
    lock: asyncio.Lock = field(default_factory=asyncio.Lock)


class ConnectionManager:
    def __init__(self):
        self._clients: set[Client] = set()

    @property
    def count(self) -> int:
        return len(self._clients)

    def presence(self) -> dict:
        officers = {c.user_id for c in self._clients if c.role == "ADMIN"}
        applicants = {c.user_id for c in self._clients if c.role != "ADMIN"}
        return {"officers_online": len(officers), "applicants_online": len(applicants)}

    async def connect(self, client: Client):
        self._clients.add(client)
        await self._send(client, "hello", {"user_id": client.user_id, "role": client.role,
                                           **self.presence()})
        await self.broadcast_admins("presence", self.presence())

    async def disconnect(self, client: Client):
        self._clients.discard(client)
        await self.broadcast_admins("presence", self.presence())

    async def _send(self, client: Client, event: str, data: dict) -> bool:
        message = json.dumps({
            "type": event,
            "data": data,
            "ts": datetime.now(timezone.utc).isoformat(),
        }, default=str)
        try:
            async with client.lock:
                await client.ws.send_text(message)
            return True
        except Exception:  # noqa: BLE001 — dead socket
            self._clients.discard(client)
            return False

    async def _send_many(self, clients, event: str, data: dict):
        if clients:
            await asyncio.gather(*(self._send(c, event, data) for c in clients))

    async def broadcast_admins(self, event: str, data: dict):
        await self._send_many([c for c in self._clients if c.role == "ADMIN"], event, data)

    async def notify_application(self, event: str, application: dict):
        """Send to all officers plus the applicant who owns the application."""
        owner = application.get("user_id")
        targets = [c for c in self._clients if c.role == "ADMIN" or c.user_id == owner]
        await self._send_many(targets, event, application)
        await self._send_many(targets, "stats.changed", {})


manager = ConnectionManager()

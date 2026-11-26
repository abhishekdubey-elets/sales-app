"""In-process WebSocket fan-out.

Single-instance deployments work as-is. For several API replicas, replace `publish` with a Redis
pub/sub publish and run `_deliver` from a subscriber in each instance.
"""

import asyncio
import json
import logging
import uuid
from collections import defaultdict
from collections.abc import Iterable
from typing import Any

from fastapi import WebSocket
from fastapi.encoders import jsonable_encoder

log = logging.getLogger(__name__)


class Hub:
    def __init__(self) -> None:
        self._sockets: dict[uuid.UUID, set[WebSocket]] = defaultdict(set)
        self._lock = asyncio.Lock()

    async def connect(self, user_id: uuid.UUID, ws: WebSocket) -> None:
        async with self._lock:
            self._sockets[user_id].add(ws)

    async def disconnect(self, user_id: uuid.UUID, ws: WebSocket) -> None:
        async with self._lock:
            self._sockets[user_id].discard(ws)
            if not self._sockets[user_id]:
                self._sockets.pop(user_id, None)

    def connected_users(self) -> set[uuid.UUID]:
        return set(self._sockets)

    async def publish(self, user_ids: Iterable[uuid.UUID], event_type: str, data: Any) -> None:
        message = json.dumps({"type": event_type, "data": jsonable_encoder(data)})
        await self._deliver(set(user_ids), message)

    async def _deliver(self, user_ids: set[uuid.UUID], message: str) -> None:
        targets = [(uid, ws) for uid in user_ids for ws in list(self._sockets.get(uid, ()))]
        for uid, ws in targets:
            try:
                await ws.send_text(message)
            except Exception:  # noqa: BLE001 - dead socket
                log.debug("dropping websocket for %s", uid)
                await self.disconnect(uid, ws)


hub = Hub()

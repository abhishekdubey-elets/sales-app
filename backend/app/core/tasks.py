"""Fire-and-forget background tasks that are not garbage-collected mid-flight."""

import asyncio
import logging
from collections.abc import Coroutine
from typing import Any

from app.core.config import settings

log = logging.getLogger(__name__)
_tasks: set[asyncio.Task] = set()


async def spawn(coro: Coroutine[Any, Any, Any]) -> None:
    """Run `coro` in the background. In tests it runs inline so assertions see its effects."""
    if settings.ENVIRONMENT == "test":
        await coro
        return
    task = asyncio.create_task(coro)
    _tasks.add(task)
    task.add_done_callback(_done)


def _done(task: asyncio.Task) -> None:
    _tasks.discard(task)
    if not task.cancelled() and task.exception():
        log.error("background task failed", exc_info=task.exception())

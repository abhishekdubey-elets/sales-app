import asyncio
import contextlib
import logging
from contextlib import asynccontextmanager

import sqlalchemy as sa
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.api.v1 import ai, analytics, auth, calls, campaigns, leads, misc, realtime, users, webhooks
from app.core.config import settings
from app.core.database import SessionLocal
from app.core.errors import install_error_handlers
from app.telephony.registry import telephony_status
from app.voice.registry import voice_status

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s")
log = logging.getLogger("elets")


@asynccontextmanager
async def lifespan(app: FastAPI):
    stop = asyncio.Event()
    worker = None
    if settings.RUN_WORKERS and settings.ENVIRONMENT != "test":
        from app.workers.jobs import run_forever

        worker = asyncio.create_task(run_forever(stop))
        log.info("background workers started")
    t = telephony_status()
    log.info("telephony: %s (configured=%s)", t["provider"] or "none", t["configured"])
    yield
    stop.set()
    if worker:
        with contextlib.suppress(Exception):
            await asyncio.wait_for(worker, timeout=10)


def create_app() -> FastAPI:
    app = FastAPI(
        title="Elets SalesCall AI API",
        version="1.0.0",
        description="Sales calling, lead management and AI voice agents for Elets Technomedia. "
                    "See docs/API.md for the contract.",
        lifespan=lifespan,
    )
    app.add_middleware(
        CORSMiddleware, allow_origins=settings.CORS_ORIGINS, allow_credentials=False,
        allow_methods=["*"], allow_headers=["*"],
    )
    install_error_handlers(app)
    prefix = "/api/v1"
    for r in (auth.router, users.router, leads.router, calls.router, ai.router, campaigns.router, analytics.router,
              misc.router, webhooks.router, realtime.router):
        app.include_router(r, prefix=prefix)

    @app.get("/health", tags=["health"])
    async def health():
        db_ok = True
        try:
            async with SessionLocal() as db:
                await db.execute(sa.text("SELECT 1"))
        except Exception:  # noqa: BLE001
            db_ok = False
        return {"status": "ok" if db_ok else "degraded", "database": db_ok, "telephony": telephony_status(),
                "voice": voice_status()}

    return app


app = create_app()

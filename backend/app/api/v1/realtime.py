"""WebSockets: app event stream (`/ws`) and provider media streams for AI calls (`/media/...`)."""

import asyncio
import json
import logging
import time
import uuid

from fastapi import APIRouter, WebSocket, WebSocketDisconnect

from app.core.database import SessionLocal
from app.core.deps import user_from_access_token
from app.core.security import decode_token, verify_webhook_token
from app.realtime.hub import hub
from app.telephony.registry import get_provider
from app.voice.engine import VoiceCallSession
from app.voice.registry import get_llm, get_stt, get_tts, voice_ready

log = logging.getLogger(__name__)
router = APIRouter(tags=["realtime"])


@router.websocket("/ws")
async def events(ws: WebSocket, token: str = ""):
    async with SessionLocal() as db:
        user = await user_from_access_token(db, token) if token else None
    if user is None:
        await ws.close(code=4401)
        return
    exp = (decode_token(token) or {}).get("exp", 0)
    await ws.accept()
    await hub.connect(user.id, ws)
    try:
        await ws.send_text(json.dumps({"type": "hello", "data": {"user_id": str(user.id)}}))
        while True:
            raw = await ws.receive_text()
            if time.time() > exp:
                await ws.close(code=4401)  # client reconnects with a fresh access token
                break
            try:
                msg = json.loads(raw)
            except ValueError:
                continue
            if msg.get("type") == "ping":
                await ws.send_text(json.dumps({"type": "pong"}))
    except WebSocketDisconnect:
        pass
    finally:
        await hub.disconnect(user.id, ws)


@router.websocket("/media/{provider}/{ai_call_id}")
async def media_stream(ws: WebSocket, provider: str, ai_call_id: uuid.UUID):
    p = get_provider(provider)
    adapter = p.media_adapter() if p else None
    if adapter is None:
        await ws.close(code=1008)
        return
    await ws.accept()
    start = None
    try:
        async with asyncio.timeout(15):
            while start is None:
                ev = adapter.parse(json.loads(await ws.receive_text()))
                if ev.kind == "start":
                    start = ev
    except (TimeoutError, WebSocketDisconnect, ValueError):
        await ws.close(code=1008)
        return
    params = start.params if isinstance(start.params, dict) else {}
    token = ws.query_params.get("wt") or params.get("wt")
    if not verify_webhook_token("ai", str(ai_call_id), token):
        log.warning("rejected media stream for %s: bad token", ai_call_id)
        await ws.close(code=1008)
        return
    ok, why = voice_ready()
    if not ok:
        log.error("AI call %s connected but voice is not ready: %s", ai_call_id, why)
        await ws.close(code=1011)
        return
    session = VoiceCallSession(ws=ws, adapter=adapter, ai_call_id=ai_call_id, provider=p, llm=get_llm(),
                               stt=get_stt(), tts=get_tts())
    await session.run()

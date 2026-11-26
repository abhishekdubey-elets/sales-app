"""Telephony provider callbacks. Every request must carry a valid `wt` token (per call, or per provider for
static URLs configured in a provider console). Twilio requests are additionally signature-checked."""

import logging
import uuid

import sqlalchemy as sa
from fastapi import APIRouter, Depends, Request
from fastapi.responses import JSONResponse, PlainTextResponse, Response
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.core.database import get_db
from app.core.errors import AppError, not_found
from app.core.security import verify_webhook_token, webhook_token
from app.models import AICall, HumanCall, TelephonyEvent
from app.services import ai_calls as ai_svc
from app.services import calls as human_svc
from app.services.org import get_org_settings
from app.telephony.base import build_callbacks
from app.telephony.registry import get_provider

log = logging.getLogger(__name__)
router = APIRouter(prefix="/webhooks/telephony", tags=["webhooks"])


async def _params(request: Request) -> tuple[dict, dict]:
    body: dict = {}
    ctype = request.headers.get("content-type", "")
    if request.method in ("POST", "PUT"):
        if "application/json" in ctype:
            try:
                data = await request.json()
                body = data if isinstance(data, dict) else {}
            except ValueError:
                body = {}
        else:
            form = await request.form()
            body = {k: v for k, v in form.items() if isinstance(v, str)}
    merged = {**body, **dict(request.query_params)}
    return body, merged


def _public_url(request: Request) -> str:
    q = request.url.query
    return f"{settings.API_PUBLIC_BASE_URL}{request.url.path}{'?' + q if q else ''}"


def _ack(provider: str) -> Response:
    if provider in ("twilio", "plivo"):
        return Response('<?xml version="1.0" encoding="UTF-8"?><Response></Response>', media_type="application/xml")
    return PlainTextResponse("OK")


def _authenticate(provider_name: str, request: Request, body: dict, params: dict) -> tuple[str | None, str | None]:
    provider = get_provider(provider_name)
    if provider is None:
        raise not_found("Provider")
    kind, cid, wt = params.get("kind"), params.get("cid"), params.get("wt")
    if cid:
        if kind not in ("human", "ai") or not verify_webhook_token(kind, cid, wt):
            raise AppError(403, "forbidden", "Invalid webhook token")
    elif not verify_webhook_token("provider", provider_name, wt):
        raise AppError(403, "forbidden", "Invalid webhook token")
    if provider_name == "twilio" and provider.is_configured() and settings.ENVIRONMENT != "test":
        if not provider.verify_signature(_public_url(request), body, {k.lower(): v for k, v in request.headers.items()}):
            raise AppError(403, "forbidden", "Invalid Twilio signature")
    return kind, cid


def _uuid(value: str | None) -> uuid.UUID | None:
    try:
        return uuid.UUID(value) if value else None
    except ValueError:
        return None


@router.post("/{provider}/status")
async def status_callback(provider: str, request: Request, db: AsyncSession = Depends(get_db)):
    body, params = await _params(request)
    kind, cid = _authenticate(provider, request, body, params)
    p = get_provider(provider)
    upd = p.parse_status(params)
    call_id = _uuid(cid)
    db.add(TelephonyEvent(provider=provider, kind=kind or "unknown", call_ref_id=call_id,
                          provider_call_id=upd.provider_call_id, event=upd.raw_status or "status",
                          payload={k: v for k, v in params.items() if k != "wt"}))
    if kind == "human" and call_id:
        call = await db.get(HumanCall, call_id)
        if call:
            await human_svc.apply_human_status(db, call, upd)
    elif kind == "ai" and call_id:
        call = await db.get(AICall, call_id)
        if call:
            await ai_svc.apply_ai_status(db, call, upd)
    elif upd.provider_call_id:  # provider-level webhook (e.g. Knowlarity): match by provider call id
        human = (await db.execute(sa.select(HumanCall).where(
            HumanCall.provider == provider, HumanCall.provider_call_id == upd.provider_call_id))).scalar()
        if human:
            await human_svc.apply_human_status(db, human, upd)
        else:
            ai = (await db.execute(sa.select(AICall).where(
                AICall.provider == provider, AICall.provider_call_id == upd.provider_call_id))).scalars().first()
            if ai:
                await ai_svc.apply_ai_status(db, ai, upd)
    await db.commit()
    return _ack(provider)


@router.api_route("/{provider}/answer", methods=["GET", "POST"])
async def answer(provider: str, request: Request, db: AsyncSession = Depends(get_db)):
    body, params = await _params(request)
    kind, cid = _authenticate(provider, request, body, params)
    p = get_provider(provider)
    org = await get_org_settings(db)
    mode = params.get("mode") or ("ai" if kind == "ai" else "bridge")
    call_id = _uuid(cid)
    callbacks = build_callbacks(provider, kind, call_id)
    if kind == "human":
        call = await db.get(HumanCall, call_id)
        if call is None:
            raise not_found("Call")
        return p.answer_response(kind=kind, mode="bridge", customer_number=call.phone_number, callbacks=callbacks,
                                 record=org.recording_enabled, caller_id=settings.TELEPHONY_CALLER_ID,
                                 time_limit_seconds=settings.CALL_TIME_LIMIT_SECONDS)
    call = await db.get(AICall, call_id)
    if call is None:
        raise not_found("Call")
    record = org.recording_enabled and call.agent.recording_enabled
    # mode=transfer (Plivo live hand-off): the engine stored the salesperson's number before transferring.
    return p.answer_response(kind=kind, mode=mode, customer_number=call.phone_number, callbacks=callbacks,
                             record=record, caller_id=settings.TELEPHONY_CALLER_ID,
                             agent_number=call.transfer_to_number,
                             time_limit_seconds=call.agent.max_call_duration_seconds + 60)


@router.post("/{provider}/recording")
async def recording(provider: str, request: Request, db: AsyncSession = Depends(get_db)):
    body, params = await _params(request)
    kind, cid = _authenticate(provider, request, body, params)
    info = get_provider(provider).parse_recording(params)
    call_id = _uuid(cid)
    if info and call_id:
        if kind == "human":
            call = await db.get(HumanCall, call_id)
            if call:
                await human_svc.attach_recording(db, call, info.url, info.recording_id, info.duration_seconds)
        elif kind == "ai":
            call = await db.get(AICall, call_id)
            if call:
                await ai_svc.attach_ai_recording(db, call, info.url, info.recording_id, info.duration_seconds)
        await db.commit()
    return _ack(provider)


@router.api_route("/{provider}/inbound", methods=["GET", "POST"])
async def inbound(provider: str, request: Request, db: AsyncSession = Depends(get_db)):
    body, params = await _params(request)
    _authenticate(provider, request, body, {k: v for k, v in params.items() if k not in ("cid", "kind")})
    db.add(TelephonyEvent(provider=provider, kind="inbound", event="inbound",
                          payload={k: v for k, v in params.items() if k != "wt"}))
    await db.flush()
    return await human_svc.handle_inbound(db, provider, params)


async def _exotel_ai_call(db: AsyncSession, request: Request) -> AICall | None:
    params = dict(request.query_params)
    if not verify_webhook_token("provider", "exotel", params.get("wt")):
        raise AppError(403, "forbidden", "Invalid webhook token")
    sid = params.get("CallSid")
    if not sid:
        return None
    return (await db.execute(sa.select(AICall).where(AICall.provider == "exotel", AICall.provider_call_id == sid))
            ).scalars().first()


@router.get("/exotel/voicebot-url")
async def exotel_voicebot_url(request: Request, db: AsyncSession = Depends(get_db)):
    call = await _exotel_ai_call(db, request)
    if call is None:
        raise not_found("AI call")
    cb = build_callbacks("exotel", "ai", call.id)
    return JSONResponse({"url": f"{cb.media_ws}?wt={cb.token}"})


@router.get("/exotel/transfer-target")
async def exotel_transfer_target(request: Request, db: AsyncSession = Depends(get_db)):
    call = await _exotel_ai_call(db, request)
    return PlainTextResponse((call.transfer_to_number or "") if call else "")


def provider_webhook_urls(provider: str) -> dict[str, str]:
    """Static URLs to paste into a provider console (used by `python -m app.cli webhook-urls`)."""
    wt = webhook_token("provider", provider)
    base = f"{settings.API_PUBLIC_BASE_URL}/api/v1/webhooks/telephony/{provider}"
    urls = {"inbound": f"{base}/inbound?wt={wt}", "status (provider-level)": f"{base}/status?wt={wt}"}
    if provider == "exotel":
        urls["voicebot dynamic URL"] = f"{base}/voicebot-url?wt={wt}"
        urls["connect applet (AI hand-off)"] = f"{base}/transfer-target?wt={wt}"
    return urls


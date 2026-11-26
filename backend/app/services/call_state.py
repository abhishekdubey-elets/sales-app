"""Monotonic call-state transitions driven only by provider webhooks."""

from dataclasses import dataclass
from datetime import datetime

from app.core.database import as_utc
from app.models.enums import TERMINAL_CALL_STATUSES, CallStatus
from app.telephony.base import StatusUpdate

_RANK = {CallStatus.INITIATED: 0, CallStatus.RINGING: 1, CallStatus.CONNECTED: 2}


def rank(status: str) -> int:
    return 3 if status in TERMINAL_CALL_STATUSES else _RANK.get(CallStatus(status), 0)


@dataclass
class Transition:
    changed: bool = False
    became_terminal: bool = False


def apply_update(call, upd: StatusUpdate, now: datetime, *, bridge: bool) -> Transition:
    """Apply a provider status update to a HumanCall or AICall.

    Bridge calls have two legs: the salesperson ("agent") leg rings first; the customer leg decides whether the
    call connected. Single-leg calls (AI calls, Exotel/Knowlarity summaries) use `leg=None`.
    """
    t = Transition()
    has_talk = hasattr(call, "talk_seconds")
    if call.status in TERMINAL_CALL_STATUSES:
        # Late callbacks may still carry durations.
        if upd.duration_seconds and upd.duration_seconds > (call.duration_seconds or 0):
            call.duration_seconds = upd.duration_seconds
            t.changed = True
        if has_talk and upd.talk_seconds and upd.talk_seconds > (call.talk_seconds or 0):
            call.talk_seconds = upd.talk_seconds
            t.changed = True
        return t
    if upd.status is None:
        return t

    agent_leg = bridge and upd.leg == "agent"
    new = upd.status

    if agent_leg:
        if new == CallStatus.RINGING and rank(call.status) < 1:
            call.status, t.changed = CallStatus.RINGING, True
        elif new in TERMINAL_CALL_STATUSES:
            if call.answered_at is not None:
                final = CallStatus.COMPLETED
            elif new == CallStatus.COMPLETED:
                final = CallStatus.NOT_ANSWERED  # salesperson picked up but the lead never connected
            else:
                final = new
                call.failure_reason = call.failure_reason or f"Salesperson's phone: {upd.raw_status}"
            _finish(call, final, upd, now)
            t.changed = t.became_terminal = True
        return t

    if new == CallStatus.RINGING:
        if rank(call.status) < 1:
            call.status, t.changed = CallStatus.RINGING, True
    elif new == CallStatus.CONNECTED:
        if rank(call.status) < 2:
            call.status, t.changed = CallStatus.CONNECTED, True
            call.answered_at = call.answered_at or now
    elif new in TERMINAL_CALL_STATUSES:
        if bridge and upd.leg in ("customer", "dial"):
            # Customer leg finished; the salesperson's leg may still be up for a moment. Finalise now so the
            # app can show the disposition sheet; the agent-leg callback only adds duration.
            final = CallStatus.COMPLETED if (call.answered_at or (upd.talk_seconds or 0) > 0) else (
                new if new != CallStatus.COMPLETED else CallStatus.NOT_ANSWERED)
        else:
            final = new
            if new == CallStatus.COMPLETED and call.answered_at is None and not (upd.talk_seconds or upd.duration_seconds):
                final = CallStatus.NOT_ANSWERED
        if final == CallStatus.COMPLETED and call.answered_at is None:
            call.answered_at = now
        _finish(call, final, upd, now)
        t.changed = t.became_terminal = True
    return t


def _finish(call, status: CallStatus, upd: StatusUpdate, now: datetime) -> None:
    call.status = status
    call.ended_at = now
    started = as_utc(call.started_at)
    computed = int((now - started).total_seconds()) if started else 0
    call.duration_seconds = upd.duration_seconds if upd.duration_seconds is not None else max(computed, 0)
    if hasattr(call, "talk_seconds"):
        if upd.talk_seconds is not None:
            call.talk_seconds = upd.talk_seconds
        elif call.answered_at is not None and status == CallStatus.COMPLETED:
            call.talk_seconds = max(int((now - as_utc(call.answered_at)).total_seconds()), 0)

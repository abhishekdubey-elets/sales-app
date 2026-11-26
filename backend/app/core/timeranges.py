from datetime import date, datetime, time, timedelta, timezone
from typing import Literal
from zoneinfo import ZoneInfo

from app.core.errors import bad_request

RangeName = Literal["today", "yesterday", "this_week", "this_month", "custom"]


def _local_midnight(d: date, tz: ZoneInfo) -> datetime:
    return datetime.combine(d, time.min, tzinfo=tz)


def resolve_range(
    range_name: str | None,
    date_from: date | None,
    date_to: date | None,
    tz_name: str,
    now: datetime | None = None,
) -> tuple[datetime, datetime]:
    """Return [start, end) in UTC for a named range evaluated in the org timezone."""
    tz = ZoneInfo(tz_name)
    now_local = (now or datetime.now(timezone.utc)).astimezone(tz)
    today = now_local.date()
    name = range_name or "today"

    if name == "today":
        start, end = today, today + timedelta(days=1)
    elif name == "yesterday":
        start, end = today - timedelta(days=1), today
    elif name == "this_week":
        start = today - timedelta(days=today.weekday())
        end = today + timedelta(days=1)
    elif name == "this_month":
        start = today.replace(day=1)
        end = today + timedelta(days=1)
    elif name == "custom":
        if not date_from or not date_to:
            raise bad_request("Custom range requires 'from' and 'to' dates", code="validation_error")
        if date_to < date_from:
            raise bad_request("'to' must be on or after 'from'", code="validation_error")
        if (date_to - date_from).days > 366:
            raise bad_request("Custom range cannot exceed 366 days", code="validation_error")
        start, end = date_from, date_to + timedelta(days=1)
    else:
        raise bad_request(f"Unknown range '{name}'", code="validation_error")

    return (
        _local_midnight(start, tz).astimezone(timezone.utc),
        _local_midnight(end, tz).astimezone(timezone.utc),
    )


def within_daily_window(now: datetime, tz_name: str, start_hhmm: str, end_hhmm: str, days: list[int]) -> bool:
    """days use ISO weekday numbers: 1 = Monday … 7 = Sunday."""
    local = now.astimezone(ZoneInfo(tz_name))
    if days and local.isoweekday() not in days:
        return False
    sh, sm = (int(x) for x in start_hhmm.split(":"))
    eh, em = (int(x) for x in end_hhmm.split(":"))
    current = local.hour * 60 + local.minute
    return sh * 60 + sm <= current < eh * 60 + em


def local_date(now: datetime, tz_name: str) -> date:
    return now.astimezone(ZoneInfo(tz_name)).date()

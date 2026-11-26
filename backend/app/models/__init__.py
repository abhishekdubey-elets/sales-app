import sqlalchemy as sa

from app.models.ai import AIAgent, AICall, AICampaign, AICampaignLead, AIHandoff, CampaignLog
from app.models.call import CallNote, CallRecording, CallTranscript, HumanCall, TelephonyEvent
from app.models.lead import FavouriteLead, Lead, LeadActivity, LeadAssignment, LeadCallLock, OptOut
from app.models.misc import AuditLog, Followup, Notification, OrgSettings
from app.models.user import DeviceToken, RoleModel, Team, User, UserSession

# Read-only unified reporting view (created by migration 0002). Human and AI calls stay in their own
# tables; this view only unions them with an explicit `origin` column.
_view_md = sa.MetaData()
unified_calls_view = sa.Table(
    "v_unified_calls",
    _view_md,
    sa.Column("id", sa.Uuid),
    sa.Column("origin", sa.String),
    sa.Column("direction", sa.String),
    sa.Column("lead_id", sa.Uuid),
    sa.Column("lead_name", sa.String),
    sa.Column("salesperson_id", sa.Uuid),
    sa.Column("salesperson_name", sa.String),
    sa.Column("ai_agent_id", sa.Uuid),
    sa.Column("campaign_id", sa.Uuid),
    sa.Column("provider", sa.String),
    sa.Column("status", sa.String),
    sa.Column("started_at", sa.DateTime(timezone=True)),
    sa.Column("answered_at", sa.DateTime(timezone=True)),
    sa.Column("ended_at", sa.DateTime(timezone=True)),
    sa.Column("duration_seconds", sa.Integer),
    sa.Column("outcome", sa.String),
    sa.Column("interest_level", sa.String),
    sa.Column("summary", sa.Text),
)


def unified_calls_view_sql(dialect: str) -> str:
    uuid_null = "CAST(NULL AS UUID)" if dialect == "postgresql" else "NULL"
    return f"""
CREATE VIEW v_unified_calls AS
SELECT h.id, 'human' AS origin, h.direction, h.lead_id, h.lead_name,
       h.salesperson_id, h.salesperson_name, {uuid_null} AS ai_agent_id, {uuid_null} AS campaign_id,
       h.provider, h.status, h.started_at, h.answered_at, h.ended_at, h.duration_seconds,
       h.outcome, NULL AS interest_level, NULL AS summary
FROM human_calls h
UNION ALL
SELECT a.id, 'ai' AS origin, 'outbound' AS direction, a.lead_id, a.lead_name,
       {uuid_null} AS salesperson_id, NULL AS salesperson_name, a.agent_id AS ai_agent_id, a.campaign_id,
       a.provider, a.status, a.started_at, a.answered_at, a.ended_at, a.duration_seconds,
       NULL AS outcome, a.interest_level, a.summary
FROM ai_calls a
"""


__all__ = [
    "AIAgent", "AICall", "AICampaign", "AICampaignLead", "AIHandoff", "AuditLog", "CallNote", "CallRecording",
    "CallTranscript", "CampaignLog", "DeviceToken", "FavouriteLead", "Followup", "HumanCall", "Lead",
    "LeadActivity", "LeadAssignment", "LeadCallLock", "Notification", "OptOut", "OrgSettings", "RoleModel",
    "Team", "TelephonyEvent", "User", "UserSession", "unified_calls_view", "unified_calls_view_sql",
]

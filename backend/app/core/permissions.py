"""Permission catalogue and default grants per role.

Roles live in the `roles` table (seeded from DEFAULT_ROLE_PERMISSIONS) so grants can be tuned
without a deploy. Data scoping (own / team / all) is applied separately in services.
"""

from enum import StrEnum


class Role(StrEnum):
    ADMIN = "admin"
    MANAGER = "manager"
    EXECUTIVE = "executive"


class P(StrEnum):
    USERS_VIEW = "users.view"
    USERS_MANAGE = "users.manage"
    TEAMS_MANAGE = "teams.manage"
    LEADS_VIEW = "leads.view"
    LEADS_CREATE = "leads.create"
    LEADS_EDIT = "leads.edit"
    LEADS_DELETE = "leads.delete"
    LEADS_ASSIGN = "leads.assign"
    LEADS_IMPORT = "leads.import"
    CALLS_MAKE = "calls.make"
    CALLS_VIEW = "calls.view"
    RECORDINGS_VIEW = "recordings.view"
    AI_AGENTS_VIEW = "ai_agents.view"
    AI_AGENTS_MANAGE = "ai_agents.manage"
    AI_CALLS_VIEW = "ai_calls.view"
    AI_CALLS_MAKE = "ai_calls.make"
    CAMPAIGNS_VIEW = "campaigns.view"
    CAMPAIGNS_MANAGE = "campaigns.manage"
    ANALYTICS_VIEW = "analytics.view"
    ANALYTICS_TEAM = "analytics.team"
    ANALYTICS_EXPORT = "analytics.export"
    SETTINGS_MANAGE = "settings.manage"
    AUDIT_VIEW = "audit.view"


DEFAULT_ROLE_PERMISSIONS: dict[Role, set[P]] = {
    Role.ADMIN: set(P),
    Role.MANAGER: {
        P.USERS_VIEW,
        P.LEADS_VIEW, P.LEADS_CREATE, P.LEADS_EDIT, P.LEADS_ASSIGN, P.LEADS_IMPORT,
        P.CALLS_MAKE, P.CALLS_VIEW, P.RECORDINGS_VIEW,
        P.AI_AGENTS_VIEW, P.AI_CALLS_VIEW, P.CAMPAIGNS_VIEW,
        P.ANALYTICS_VIEW, P.ANALYTICS_TEAM, P.ANALYTICS_EXPORT,
    },
    Role.EXECUTIVE: {
        P.LEADS_VIEW, P.LEADS_CREATE, P.LEADS_EDIT,
        P.CALLS_MAKE, P.CALLS_VIEW,
        P.AI_CALLS_VIEW,
        P.ANALYTICS_VIEW,
    },
}

ROLE_DESCRIPTIONS = {
    Role.ADMIN: "Full access: all teams, calls, AI agents, campaigns, settings and audit logs",
    Role.MANAGER: "Team access: team calls and recordings, lead assignment, team analytics",
    Role.EXECUTIVE: "Own assigned leads, own calls and personal analytics",
}

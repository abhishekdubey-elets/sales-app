"""initial schema

Revision ID: 0001
Revises: 
Create Date: 2026-11-26 13:57:05.328192
"""
from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op


revision: str = '0001'
down_revision: str | None = None
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table('org_settings',
    sa.Column('id', sa.Integer(), nullable=False),
    sa.Column('timezone', sa.String(length=64), nullable=False),
    sa.Column('calling_hours_start', sa.String(length=5), nullable=False),
    sa.Column('calling_hours_end', sa.String(length=5), nullable=False),
    sa.Column('calling_days', sa.JSON(), nullable=False),
    sa.Column('recording_enabled', sa.Boolean(), nullable=False),
    sa.Column('recording_disclosure_text', sa.Text(), nullable=False),
    sa.Column('ai_disclosure_text', sa.Text(), nullable=False),
    sa.Column('require_consent_for_ai_calls', sa.Boolean(), nullable=False),
    sa.Column('mask_numbers_for_executives', sa.Boolean(), nullable=False),
    sa.Column('calling_credits_minutes', sa.Integer(), nullable=True),
    sa.Column('credits_used_minutes', sa.Integer(), nullable=False),
    sa.Column('low_credit_threshold_minutes', sa.Integer(), nullable=False),
    sa.Column('daily_summary_time', sa.String(length=5), nullable=False),
    sa.Column('last_daily_summary_date', sa.Date(), nullable=True),
    sa.Column('created_at', sa.DateTime(timezone=True), nullable=False),
    sa.Column('updated_at', sa.DateTime(timezone=True), nullable=False),
    sa.PrimaryKeyConstraint('id', name=op.f('pk_org_settings'))
    )
    op.create_table('roles',
    sa.Column('name', sa.String(length=32), nullable=False),
    sa.Column('description', sa.String(length=255), nullable=True),
    sa.Column('permissions', sa.JSON(), nullable=False),
    sa.Column('created_at', sa.DateTime(timezone=True), nullable=False),
    sa.Column('id', sa.Uuid(), nullable=False),
    sa.PrimaryKeyConstraint('id', name=op.f('pk_roles')),
    sa.UniqueConstraint('name', name=op.f('uq_roles_name'))
    )
    op.create_table('teams',
    sa.Column('name', sa.String(length=120), nullable=False),
    sa.Column('department', sa.String(length=120), nullable=True),
    sa.Column('manager_id', sa.Uuid(), nullable=True),
    sa.Column('id', sa.Uuid(), nullable=False),
    sa.Column('created_at', sa.DateTime(timezone=True), nullable=False),
    sa.Column('updated_at', sa.DateTime(timezone=True), nullable=False),
    sa.PrimaryKeyConstraint('id', name=op.f('pk_teams')),
    sa.UniqueConstraint('name', name=op.f('uq_teams_name'))
    )
    op.create_index(op.f('ix_teams_manager_id'), 'teams', ['manager_id'], unique=False)
    op.create_table('telephony_events',
    sa.Column('provider', sa.String(length=32), nullable=False),
    sa.Column('kind', sa.String(length=16), nullable=False),
    sa.Column('call_ref_id', sa.Uuid(), nullable=True),
    sa.Column('provider_call_id', sa.String(length=128), nullable=True),
    sa.Column('event', sa.String(length=32), nullable=False),
    sa.Column('payload', sa.JSON(), nullable=False),
    sa.Column('created_at', sa.DateTime(timezone=True), nullable=False),
    sa.Column('id', sa.Uuid(), nullable=False),
    sa.PrimaryKeyConstraint('id', name=op.f('pk_telephony_events'))
    )
    op.create_index(op.f('ix_telephony_events_call_ref_id'), 'telephony_events', ['call_ref_id'], unique=False)
    op.create_index(op.f('ix_telephony_events_provider_call_id'), 'telephony_events', ['provider_call_id'], unique=False)
    op.create_table('users',
    sa.Column('full_name', sa.String(length=160), nullable=False),
    sa.Column('email', sa.String(length=254), nullable=False),
    sa.Column('password_hash', sa.String(length=255), nullable=False),
    sa.Column('phone', sa.String(length=20), nullable=True),
    sa.Column('calling_number', sa.String(length=20), nullable=True),
    sa.Column('role_id', sa.Uuid(), nullable=False),
    sa.Column('team_id', sa.Uuid(), nullable=True),
    sa.Column('is_active', sa.Boolean(), nullable=False),
    sa.Column('last_login_at', sa.DateTime(timezone=True), nullable=True),
    sa.Column('id', sa.Uuid(), nullable=False),
    sa.Column('created_at', sa.DateTime(timezone=True), nullable=False),
    sa.Column('updated_at', sa.DateTime(timezone=True), nullable=False),
    sa.ForeignKeyConstraint(['role_id'], ['roles.id'], name=op.f('fk_users_role_id_roles')),
    sa.ForeignKeyConstraint(['team_id'], ['teams.id'], name=op.f('fk_users_team_id_teams'), ondelete='SET NULL'),
    sa.PrimaryKeyConstraint('id', name=op.f('pk_users')),
    sa.UniqueConstraint('email', name=op.f('uq_users_email'))
    )
    op.create_index(op.f('ix_users_role_id'), 'users', ['role_id'], unique=False)
    op.create_index(op.f('ix_users_team_id'), 'users', ['team_id'], unique=False)
    # users ⇄ teams is circular: add the manager FK once both tables exist.
    # (SQLite can't add a constraint to an existing table; the column still works there, just unenforced.)
    if op.get_bind().dialect.name != 'sqlite':
        op.create_foreign_key(op.f('fk_teams_manager_id_users'), 'teams', 'users', ['manager_id'], ['id'],
                              ondelete='SET NULL')
    op.create_table('ai_agents',
    sa.Column('name', sa.String(length=160), nullable=False),
    sa.Column('description', sa.Text(), nullable=True),
    sa.Column('personality', sa.Text(), nullable=True),
    sa.Column('language', sa.String(length=16), nullable=False),
    sa.Column('voice_id', sa.String(length=120), nullable=True),
    sa.Column('speaking_speed', sa.Float(), nullable=False),
    sa.Column('system_prompt', sa.Text(), nullable=False),
    sa.Column('knowledge_base', sa.Text(), nullable=True),
    sa.Column('objectives', sa.JSON(), nullable=False),
    sa.Column('greeting', sa.Text(), nullable=True),
    sa.Column('max_call_duration_seconds', sa.Integer(), nullable=False),
    sa.Column('retry_rules', sa.JSON(), nullable=False),
    sa.Column('handoff_conditions', sa.JSON(), nullable=False),
    sa.Column('recording_enabled', sa.Boolean(), nullable=False),
    sa.Column('is_active', sa.Boolean(), nullable=False),
    sa.Column('created_by_id', sa.Uuid(), nullable=True),
    sa.Column('id', sa.Uuid(), nullable=False),
    sa.Column('created_at', sa.DateTime(timezone=True), nullable=False),
    sa.Column('updated_at', sa.DateTime(timezone=True), nullable=False),
    sa.ForeignKeyConstraint(['created_by_id'], ['users.id'], name=op.f('fk_ai_agents_created_by_id_users'), ondelete='SET NULL'),
    sa.PrimaryKeyConstraint('id', name=op.f('pk_ai_agents'))
    )
    op.create_table('audit_logs',
    sa.Column('actor_id', sa.Uuid(), nullable=True),
    sa.Column('actor_name', sa.String(length=160), nullable=True),
    sa.Column('action', sa.String(length=64), nullable=False),
    sa.Column('entity_type', sa.String(length=64), nullable=True),
    sa.Column('entity_id', sa.String(length=64), nullable=True),
    sa.Column('details', sa.JSON(), nullable=False),
    sa.Column('ip_address', sa.String(length=64), nullable=True),
    sa.Column('created_at', sa.DateTime(timezone=True), nullable=False),
    sa.Column('id', sa.Uuid(), nullable=False),
    sa.ForeignKeyConstraint(['actor_id'], ['users.id'], name=op.f('fk_audit_logs_actor_id_users'), ondelete='SET NULL'),
    sa.PrimaryKeyConstraint('id', name=op.f('pk_audit_logs'))
    )
    op.create_index(op.f('ix_audit_logs_action'), 'audit_logs', ['action'], unique=False)
    op.create_index(op.f('ix_audit_logs_actor_id'), 'audit_logs', ['actor_id'], unique=False)
    op.create_index(op.f('ix_audit_logs_created_at'), 'audit_logs', ['created_at'], unique=False)
    op.create_index(op.f('ix_audit_logs_entity_type'), 'audit_logs', ['entity_type'], unique=False)
    op.create_table('device_tokens',
    sa.Column('user_id', sa.Uuid(), nullable=False),
    sa.Column('token', sa.String(length=512), nullable=False),
    sa.Column('platform', sa.String(length=16), nullable=False),
    sa.Column('created_at', sa.DateTime(timezone=True), nullable=False),
    sa.Column('last_seen_at', sa.DateTime(timezone=True), nullable=False),
    sa.Column('id', sa.Uuid(), nullable=False),
    sa.ForeignKeyConstraint(['user_id'], ['users.id'], name=op.f('fk_device_tokens_user_id_users'), ondelete='CASCADE'),
    sa.PrimaryKeyConstraint('id', name=op.f('pk_device_tokens')),
    sa.UniqueConstraint('token', name=op.f('uq_device_tokens_token'))
    )
    op.create_index(op.f('ix_device_tokens_user_id'), 'device_tokens', ['user_id'], unique=False)
    op.create_table('leads',
    sa.Column('full_name', sa.String(length=160), nullable=False),
    sa.Column('company_name', sa.String(length=200), nullable=True),
    sa.Column('phone', sa.Text(), nullable=False),
    sa.Column('phone_hash', sa.String(length=64), nullable=False),
    sa.Column('alternate_phone', sa.Text(), nullable=True),
    sa.Column('alternate_phone_hash', sa.String(length=64), nullable=True),
    sa.Column('email', sa.Text(), nullable=True),
    sa.Column('email_hash', sa.String(length=64), nullable=True),
    sa.Column('designation', sa.String(length=160), nullable=True),
    sa.Column('industry', sa.String(length=120), nullable=True),
    sa.Column('location', sa.String(length=160), nullable=True),
    sa.Column('source', sa.String(length=120), nullable=True),
    sa.Column('assigned_to_id', sa.Uuid(), nullable=True),
    sa.Column('status', sa.String(length=32), nullable=False),
    sa.Column('priority', sa.String(length=16), nullable=False),
    sa.Column('last_called_at', sa.DateTime(timezone=True), nullable=True),
    sa.Column('next_followup_at', sa.DateTime(timezone=True), nullable=True),
    sa.Column('remarks', sa.Text(), nullable=True),
    sa.Column('consent_status', sa.String(length=16), nullable=False),
    sa.Column('opted_out', sa.Boolean(), nullable=False),
    sa.Column('created_by_id', sa.Uuid(), nullable=True),
    sa.Column('deleted_at', sa.DateTime(timezone=True), nullable=True),
    sa.Column('id', sa.Uuid(), nullable=False),
    sa.Column('created_at', sa.DateTime(timezone=True), nullable=False),
    sa.Column('updated_at', sa.DateTime(timezone=True), nullable=False),
    sa.CheckConstraint("consent_status IN ('unknown', 'granted', 'revoked')", name=op.f('ck_leads_consent_status_valid')),
    sa.CheckConstraint("priority IN ('low', 'medium', 'high')", name=op.f('ck_leads_priority_valid')),
    sa.CheckConstraint("status IN ('new', 'assigned', 'contacted', 'interested', 'follow_up', 'meeting_scheduled', 'converted', 'lost')", name=op.f('ck_leads_status_valid')),
    sa.ForeignKeyConstraint(['assigned_to_id'], ['users.id'], name=op.f('fk_leads_assigned_to_id_users'), ondelete='SET NULL'),
    sa.ForeignKeyConstraint(['created_by_id'], ['users.id'], name=op.f('fk_leads_created_by_id_users'), ondelete='SET NULL'),
    sa.PrimaryKeyConstraint('id', name=op.f('pk_leads'))
    )
    op.create_index(op.f('ix_leads_alternate_phone_hash'), 'leads', ['alternate_phone_hash'], unique=False)
    op.create_index(op.f('ix_leads_assigned_to_id'), 'leads', ['assigned_to_id'], unique=False)
    op.create_index(op.f('ix_leads_company_name'), 'leads', ['company_name'], unique=False)
    op.create_index(op.f('ix_leads_deleted_at'), 'leads', ['deleted_at'], unique=False)
    op.create_index(op.f('ix_leads_full_name'), 'leads', ['full_name'], unique=False)
    op.create_index(op.f('ix_leads_industry'), 'leads', ['industry'], unique=False)
    op.create_index(op.f('ix_leads_next_followup_at'), 'leads', ['next_followup_at'], unique=False)
    op.create_index(op.f('ix_leads_source'), 'leads', ['source'], unique=False)
    op.create_index('ix_leads_status_assigned', 'leads', ['status', 'assigned_to_id'], unique=False)
    op.create_index('uq_leads_email_hash_live', 'leads', ['email_hash'], unique=True, postgresql_where=sa.text('deleted_at IS NULL AND email_hash IS NOT NULL'), sqlite_where=sa.text('deleted_at IS NULL AND email_hash IS NOT NULL'))
    op.create_index('uq_leads_phone_hash_live', 'leads', ['phone_hash'], unique=True, postgresql_where=sa.text('deleted_at IS NULL'), sqlite_where=sa.text('deleted_at IS NULL'))
    op.create_table('notifications',
    sa.Column('user_id', sa.Uuid(), nullable=False),
    sa.Column('type', sa.String(length=32), nullable=False),
    sa.Column('title', sa.String(length=255), nullable=False),
    sa.Column('body', sa.Text(), nullable=False),
    sa.Column('data', sa.JSON(), nullable=False),
    sa.Column('read_at', sa.DateTime(timezone=True), nullable=True),
    sa.Column('pushed_at', sa.DateTime(timezone=True), nullable=True),
    sa.Column('created_at', sa.DateTime(timezone=True), nullable=False),
    sa.Column('id', sa.Uuid(), nullable=False),
    sa.CheckConstraint("type IN ('lead_assigned', 'followup_reminder', 'ai_qualified_lead', 'handoff_request', 'campaign_completed', 'daily_summary', 'incoming_call', 'system')", name=op.f('ck_notifications_type_valid')),
    sa.ForeignKeyConstraint(['user_id'], ['users.id'], name=op.f('fk_notifications_user_id_users'), ondelete='CASCADE'),
    sa.PrimaryKeyConstraint('id', name=op.f('pk_notifications'))
    )
    op.create_index(op.f('ix_notifications_created_at'), 'notifications', ['created_at'], unique=False)
    op.create_index('ix_notifications_user_read', 'notifications', ['user_id', 'read_at'], unique=False)
    op.create_table('user_sessions',
    sa.Column('user_id', sa.Uuid(), nullable=False),
    sa.Column('refresh_token_hash', sa.String(length=64), nullable=False),
    sa.Column('device_name', sa.String(length=120), nullable=True),
    sa.Column('ip_address', sa.String(length=64), nullable=True),
    sa.Column('user_agent', sa.String(length=255), nullable=True),
    sa.Column('created_at', sa.DateTime(timezone=True), nullable=False),
    sa.Column('last_used_at', sa.DateTime(timezone=True), nullable=False),
    sa.Column('expires_at', sa.DateTime(timezone=True), nullable=False),
    sa.Column('revoked_at', sa.DateTime(timezone=True), nullable=True),
    sa.Column('id', sa.Uuid(), nullable=False),
    sa.ForeignKeyConstraint(['user_id'], ['users.id'], name=op.f('fk_user_sessions_user_id_users'), ondelete='CASCADE'),
    sa.PrimaryKeyConstraint('id', name=op.f('pk_user_sessions')),
    sa.UniqueConstraint('refresh_token_hash', name=op.f('uq_user_sessions_refresh_token_hash'))
    )
    op.create_index(op.f('ix_user_sessions_user_id'), 'user_sessions', ['user_id'], unique=False)
    op.create_table('ai_campaigns',
    sa.Column('name', sa.String(length=200), nullable=False),
    sa.Column('description', sa.Text(), nullable=True),
    sa.Column('agent_id', sa.Uuid(), nullable=False),
    sa.Column('status', sa.String(length=16), nullable=False),
    sa.Column('schedule', sa.JSON(), nullable=False),
    sa.Column('max_attempts', sa.Integer(), nullable=False),
    sa.Column('retry_delay_minutes', sa.Integer(), nullable=False),
    sa.Column('max_concurrent_calls', sa.Integer(), nullable=False),
    sa.Column('calls_per_minute', sa.Integer(), nullable=False),
    sa.Column('created_by_id', sa.Uuid(), nullable=True),
    sa.Column('started_at', sa.DateTime(timezone=True), nullable=True),
    sa.Column('completed_at', sa.DateTime(timezone=True), nullable=True),
    sa.Column('id', sa.Uuid(), nullable=False),
    sa.Column('created_at', sa.DateTime(timezone=True), nullable=False),
    sa.Column('updated_at', sa.DateTime(timezone=True), nullable=False),
    sa.CheckConstraint("status IN ('draft', 'running', 'paused', 'completed', 'stopped')", name=op.f('ck_ai_campaigns_status_valid')),
    sa.ForeignKeyConstraint(['agent_id'], ['ai_agents.id'], name=op.f('fk_ai_campaigns_agent_id_ai_agents'), ondelete='RESTRICT'),
    sa.ForeignKeyConstraint(['created_by_id'], ['users.id'], name=op.f('fk_ai_campaigns_created_by_id_users'), ondelete='SET NULL'),
    sa.PrimaryKeyConstraint('id', name=op.f('pk_ai_campaigns'))
    )
    op.create_index(op.f('ix_ai_campaigns_agent_id'), 'ai_campaigns', ['agent_id'], unique=False)
    op.create_index(op.f('ix_ai_campaigns_status'), 'ai_campaigns', ['status'], unique=False)
    op.create_table('favourite_leads',
    sa.Column('user_id', sa.Uuid(), nullable=False),
    sa.Column('lead_id', sa.Uuid(), nullable=False),
    sa.Column('created_at', sa.DateTime(timezone=True), nullable=False),
    sa.ForeignKeyConstraint(['lead_id'], ['leads.id'], name=op.f('fk_favourite_leads_lead_id_leads'), ondelete='CASCADE'),
    sa.ForeignKeyConstraint(['user_id'], ['users.id'], name=op.f('fk_favourite_leads_user_id_users'), ondelete='CASCADE'),
    sa.PrimaryKeyConstraint('user_id', 'lead_id', name=op.f('pk_favourite_leads'))
    )
    op.create_table('human_calls',
    sa.Column('direction', sa.String(length=16), nullable=False),
    sa.Column('lead_id', sa.Uuid(), nullable=True),
    sa.Column('lead_name', sa.String(length=160), nullable=True),
    sa.Column('phone_number', sa.Text(), nullable=False),
    sa.Column('phone_hash', sa.String(length=64), nullable=False),
    sa.Column('salesperson_id', sa.Uuid(), nullable=False),
    sa.Column('salesperson_name', sa.String(length=160), nullable=False),
    sa.Column('team_id', sa.Uuid(), nullable=True),
    sa.Column('provider', sa.String(length=32), nullable=False),
    sa.Column('provider_call_id', sa.String(length=128), nullable=True),
    sa.Column('status', sa.String(length=16), nullable=False),
    sa.Column('started_at', sa.DateTime(timezone=True), nullable=False),
    sa.Column('answered_at', sa.DateTime(timezone=True), nullable=True),
    sa.Column('ended_at', sa.DateTime(timezone=True), nullable=True),
    sa.Column('duration_seconds', sa.Integer(), nullable=False),
    sa.Column('talk_seconds', sa.Integer(), nullable=False),
    sa.Column('outcome', sa.String(length=32), nullable=True),
    sa.Column('followup_at', sa.DateTime(timezone=True), nullable=True),
    sa.Column('disposition_at', sa.DateTime(timezone=True), nullable=True),
    sa.Column('failure_reason', sa.String(length=500), nullable=True),
    sa.Column('id', sa.Uuid(), nullable=False),
    sa.Column('created_at', sa.DateTime(timezone=True), nullable=False),
    sa.Column('updated_at', sa.DateTime(timezone=True), nullable=False),
    sa.CheckConstraint("direction IN ('outbound', 'inbound')", name=op.f('ck_human_calls_direction_valid')),
    sa.CheckConstraint("outcome IS NULL OR outcome IN ('interested', 'not_interested', 'follow_up_required', 'meeting_scheduled', 'converted', 'wrong_number', 'no_response')", name=op.f('ck_human_calls_outcome_valid')),
    sa.CheckConstraint("status IN ('initiated', 'ringing', 'connected', 'completed', 'busy', 'not_answered', 'failed', 'rejected')", name=op.f('ck_human_calls_status_valid')),
    sa.ForeignKeyConstraint(['lead_id'], ['leads.id'], name=op.f('fk_human_calls_lead_id_leads'), ondelete='SET NULL'),
    sa.ForeignKeyConstraint(['salesperson_id'], ['users.id'], name=op.f('fk_human_calls_salesperson_id_users'), ondelete='RESTRICT'),
    sa.ForeignKeyConstraint(['team_id'], ['teams.id'], name=op.f('fk_human_calls_team_id_teams'), ondelete='SET NULL'),
    sa.PrimaryKeyConstraint('id', name=op.f('pk_human_calls'))
    )
    op.create_index(op.f('ix_human_calls_lead_id'), 'human_calls', ['lead_id'], unique=False)
    op.create_index(op.f('ix_human_calls_outcome'), 'human_calls', ['outcome'], unique=False)
    op.create_index(op.f('ix_human_calls_phone_hash'), 'human_calls', ['phone_hash'], unique=False)
    op.create_index('ix_human_calls_provider_call', 'human_calls', ['provider', 'provider_call_id'], unique=False)
    op.create_index(op.f('ix_human_calls_salesperson_id'), 'human_calls', ['salesperson_id'], unique=False)
    op.create_index('ix_human_calls_salesperson_started', 'human_calls', ['salesperson_id', 'started_at'], unique=False)
    op.create_index(op.f('ix_human_calls_status'), 'human_calls', ['status'], unique=False)
    op.create_index(op.f('ix_human_calls_team_id'), 'human_calls', ['team_id'], unique=False)
    op.create_table('lead_activities',
    sa.Column('lead_id', sa.Uuid(), nullable=False),
    sa.Column('type', sa.String(length=32), nullable=False),
    sa.Column('title', sa.String(length=255), nullable=False),
    sa.Column('description', sa.Text(), nullable=True),
    sa.Column('actor_id', sa.Uuid(), nullable=True),
    sa.Column('actor_name', sa.String(length=160), nullable=True),
    sa.Column('ref_id', sa.Uuid(), nullable=True),
    sa.Column('created_at', sa.DateTime(timezone=True), nullable=False),
    sa.Column('id', sa.Uuid(), nullable=False),
    sa.ForeignKeyConstraint(['actor_id'], ['users.id'], name=op.f('fk_lead_activities_actor_id_users'), ondelete='SET NULL'),
    sa.ForeignKeyConstraint(['lead_id'], ['leads.id'], name=op.f('fk_lead_activities_lead_id_leads'), ondelete='CASCADE'),
    sa.PrimaryKeyConstraint('id', name=op.f('pk_lead_activities'))
    )
    op.create_index(op.f('ix_lead_activities_lead_id'), 'lead_activities', ['lead_id'], unique=False)
    op.create_table('lead_assignments',
    sa.Column('lead_id', sa.Uuid(), nullable=False),
    sa.Column('from_user_id', sa.Uuid(), nullable=True),
    sa.Column('to_user_id', sa.Uuid(), nullable=True),
    sa.Column('assigned_by_id', sa.Uuid(), nullable=True),
    sa.Column('created_at', sa.DateTime(timezone=True), nullable=False),
    sa.Column('id', sa.Uuid(), nullable=False),
    sa.ForeignKeyConstraint(['assigned_by_id'], ['users.id'], name=op.f('fk_lead_assignments_assigned_by_id_users'), ondelete='SET NULL'),
    sa.ForeignKeyConstraint(['from_user_id'], ['users.id'], name=op.f('fk_lead_assignments_from_user_id_users'), ondelete='SET NULL'),
    sa.ForeignKeyConstraint(['lead_id'], ['leads.id'], name=op.f('fk_lead_assignments_lead_id_leads'), ondelete='CASCADE'),
    sa.ForeignKeyConstraint(['to_user_id'], ['users.id'], name=op.f('fk_lead_assignments_to_user_id_users'), ondelete='SET NULL'),
    sa.PrimaryKeyConstraint('id', name=op.f('pk_lead_assignments'))
    )
    op.create_index(op.f('ix_lead_assignments_lead_id'), 'lead_assignments', ['lead_id'], unique=False)
    op.create_index(op.f('ix_lead_assignments_to_user_id'), 'lead_assignments', ['to_user_id'], unique=False)
    op.create_table('lead_call_locks',
    sa.Column('lead_id', sa.Uuid(), nullable=False),
    sa.Column('holder_type', sa.String(length=16), nullable=False),
    sa.Column('holder_id', sa.Uuid(), nullable=False),
    sa.Column('acquired_at', sa.DateTime(timezone=True), nullable=False),
    sa.Column('expires_at', sa.DateTime(timezone=True), nullable=False),
    sa.ForeignKeyConstraint(['lead_id'], ['leads.id'], name=op.f('fk_lead_call_locks_lead_id_leads'), ondelete='CASCADE'),
    sa.PrimaryKeyConstraint('lead_id', name=op.f('pk_lead_call_locks'))
    )
    op.create_table('opt_outs',
    sa.Column('phone_hash', sa.String(length=64), nullable=False),
    sa.Column('reason', sa.String(length=255), nullable=True),
    sa.Column('source', sa.String(length=32), nullable=False),
    sa.Column('lead_id', sa.Uuid(), nullable=True),
    sa.Column('created_by_id', sa.Uuid(), nullable=True),
    sa.Column('created_at', sa.DateTime(timezone=True), nullable=False),
    sa.Column('id', sa.Uuid(), nullable=False),
    sa.ForeignKeyConstraint(['created_by_id'], ['users.id'], name=op.f('fk_opt_outs_created_by_id_users'), ondelete='SET NULL'),
    sa.ForeignKeyConstraint(['lead_id'], ['leads.id'], name=op.f('fk_opt_outs_lead_id_leads'), ondelete='SET NULL'),
    sa.PrimaryKeyConstraint('id', name=op.f('pk_opt_outs')),
    sa.UniqueConstraint('phone_hash', name=op.f('uq_opt_outs_phone_hash'))
    )
    op.create_table('ai_campaign_leads',
    sa.Column('campaign_id', sa.Uuid(), nullable=False),
    sa.Column('lead_id', sa.Uuid(), nullable=False),
    sa.Column('status', sa.String(length=16), nullable=False),
    sa.Column('attempts', sa.Integer(), nullable=False),
    sa.Column('next_attempt_at', sa.DateTime(timezone=True), nullable=True),
    sa.Column('last_call_status', sa.String(length=16), nullable=True),
    sa.Column('outcome', sa.String(length=32), nullable=True),
    sa.Column('interest_level', sa.String(length=16), nullable=True),
    sa.Column('last_ai_call_id', sa.Uuid(), nullable=True),
    sa.Column('id', sa.Uuid(), nullable=False),
    sa.Column('created_at', sa.DateTime(timezone=True), nullable=False),
    sa.Column('updated_at', sa.DateTime(timezone=True), nullable=False),
    sa.CheckConstraint("status IN ('pending', 'in_progress', 'completed', 'failed', 'skipped', 'opted_out')", name=op.f('ck_ai_campaign_leads_status_valid')),
    sa.ForeignKeyConstraint(['campaign_id'], ['ai_campaigns.id'], name=op.f('fk_ai_campaign_leads_campaign_id_ai_campaigns'), ondelete='CASCADE'),
    sa.ForeignKeyConstraint(['lead_id'], ['leads.id'], name=op.f('fk_ai_campaign_leads_lead_id_leads'), ondelete='CASCADE'),
    sa.PrimaryKeyConstraint('id', name=op.f('pk_ai_campaign_leads')),
    sa.UniqueConstraint('campaign_id', 'lead_id', name=op.f('uq_ai_campaign_leads_campaign_id_lead_id'))
    )
    op.create_index(op.f('ix_ai_campaign_leads_lead_id'), 'ai_campaign_leads', ['lead_id'], unique=False)
    op.create_index('ix_campaign_leads_due', 'ai_campaign_leads', ['campaign_id', 'status', 'next_attempt_at'], unique=False)
    op.create_table('campaign_logs',
    sa.Column('campaign_id', sa.Uuid(), nullable=False),
    sa.Column('level', sa.String(length=16), nullable=False),
    sa.Column('event', sa.String(length=64), nullable=False),
    sa.Column('message', sa.Text(), nullable=False),
    sa.Column('lead_id', sa.Uuid(), nullable=True),
    sa.Column('ai_call_id', sa.Uuid(), nullable=True),
    sa.Column('created_at', sa.DateTime(timezone=True), nullable=False),
    sa.Column('id', sa.Uuid(), nullable=False),
    sa.ForeignKeyConstraint(['campaign_id'], ['ai_campaigns.id'], name=op.f('fk_campaign_logs_campaign_id_ai_campaigns'), ondelete='CASCADE'),
    sa.PrimaryKeyConstraint('id', name=op.f('pk_campaign_logs'))
    )
    op.create_index(op.f('ix_campaign_logs_campaign_id'), 'campaign_logs', ['campaign_id'], unique=False)
    op.create_index(op.f('ix_campaign_logs_created_at'), 'campaign_logs', ['created_at'], unique=False)
    op.create_table('ai_calls',
    sa.Column('agent_id', sa.Uuid(), nullable=False),
    sa.Column('campaign_id', sa.Uuid(), nullable=True),
    sa.Column('campaign_lead_id', sa.Uuid(), nullable=True),
    sa.Column('lead_id', sa.Uuid(), nullable=True),
    sa.Column('lead_name', sa.String(length=160), nullable=True),
    sa.Column('phone_number', sa.Text(), nullable=False),
    sa.Column('phone_hash', sa.String(length=64), nullable=False),
    sa.Column('initiated_by_id', sa.Uuid(), nullable=True),
    sa.Column('provider', sa.String(length=32), nullable=False),
    sa.Column('provider_call_id', sa.String(length=128), nullable=True),
    sa.Column('status', sa.String(length=16), nullable=False),
    sa.Column('attempt', sa.Integer(), nullable=False),
    sa.Column('language', sa.String(length=16), nullable=False),
    sa.Column('started_at', sa.DateTime(timezone=True), nullable=False),
    sa.Column('answered_at', sa.DateTime(timezone=True), nullable=True),
    sa.Column('ended_at', sa.DateTime(timezone=True), nullable=True),
    sa.Column('duration_seconds', sa.Integer(), nullable=False),
    sa.Column('interest_level', sa.String(length=16), nullable=True),
    sa.Column('qualification_score', sa.Integer(), nullable=True),
    sa.Column('handoff_requested', sa.Boolean(), nullable=False),
    sa.Column('transfer_to_number', sa.Text(), nullable=True),
    sa.Column('summary', sa.Text(), nullable=True),
    sa.Column('intelligence', sa.JSON(), nullable=True),
    sa.Column('analysis_status', sa.String(length=16), nullable=False),
    sa.Column('failure_reason', sa.String(length=500), nullable=True),
    sa.Column('id', sa.Uuid(), nullable=False),
    sa.Column('created_at', sa.DateTime(timezone=True), nullable=False),
    sa.Column('updated_at', sa.DateTime(timezone=True), nullable=False),
    sa.CheckConstraint("analysis_status IN ('pending', 'running', 'done', 'failed', 'skipped')", name=op.f('ck_ai_calls_analysis_status_valid')),
    sa.CheckConstraint("status IN ('initiated', 'ringing', 'connected', 'completed', 'busy', 'not_answered', 'failed', 'rejected')", name=op.f('ck_ai_calls_status_valid')),
    sa.ForeignKeyConstraint(['agent_id'], ['ai_agents.id'], name=op.f('fk_ai_calls_agent_id_ai_agents'), ondelete='RESTRICT'),
    sa.ForeignKeyConstraint(['campaign_id'], ['ai_campaigns.id'], name=op.f('fk_ai_calls_campaign_id_ai_campaigns'), ondelete='SET NULL'),
    sa.ForeignKeyConstraint(['campaign_lead_id'], ['ai_campaign_leads.id'], name=op.f('fk_ai_calls_campaign_lead_id_ai_campaign_leads'), ondelete='SET NULL'),
    sa.ForeignKeyConstraint(['initiated_by_id'], ['users.id'], name=op.f('fk_ai_calls_initiated_by_id_users'), ondelete='SET NULL'),
    sa.ForeignKeyConstraint(['lead_id'], ['leads.id'], name=op.f('fk_ai_calls_lead_id_leads'), ondelete='SET NULL'),
    sa.PrimaryKeyConstraint('id', name=op.f('pk_ai_calls'))
    )
    op.create_index(op.f('ix_ai_calls_agent_id'), 'ai_calls', ['agent_id'], unique=False)
    op.create_index('ix_ai_calls_agent_started', 'ai_calls', ['agent_id', 'started_at'], unique=False)
    op.create_index(op.f('ix_ai_calls_campaign_id'), 'ai_calls', ['campaign_id'], unique=False)
    op.create_index(op.f('ix_ai_calls_interest_level'), 'ai_calls', ['interest_level'], unique=False)
    op.create_index(op.f('ix_ai_calls_lead_id'), 'ai_calls', ['lead_id'], unique=False)
    op.create_index(op.f('ix_ai_calls_phone_hash'), 'ai_calls', ['phone_hash'], unique=False)
    op.create_index('ix_ai_calls_provider_call', 'ai_calls', ['provider', 'provider_call_id'], unique=False)
    op.create_index(op.f('ix_ai_calls_status'), 'ai_calls', ['status'], unique=False)
    op.create_table('ai_handoffs',
    sa.Column('ai_call_id', sa.Uuid(), nullable=False),
    sa.Column('lead_id', sa.Uuid(), nullable=True),
    sa.Column('reason', sa.Text(), nullable=False),
    sa.Column('notified_user_id', sa.Uuid(), nullable=True),
    sa.Column('transferred', sa.Boolean(), nullable=False),
    sa.Column('created_at', sa.DateTime(timezone=True), nullable=False),
    sa.Column('id', sa.Uuid(), nullable=False),
    sa.ForeignKeyConstraint(['ai_call_id'], ['ai_calls.id'], name=op.f('fk_ai_handoffs_ai_call_id_ai_calls'), ondelete='CASCADE'),
    sa.ForeignKeyConstraint(['lead_id'], ['leads.id'], name=op.f('fk_ai_handoffs_lead_id_leads'), ondelete='SET NULL'),
    sa.ForeignKeyConstraint(['notified_user_id'], ['users.id'], name=op.f('fk_ai_handoffs_notified_user_id_users'), ondelete='SET NULL'),
    sa.PrimaryKeyConstraint('id', name=op.f('pk_ai_handoffs'))
    )
    op.create_index(op.f('ix_ai_handoffs_ai_call_id'), 'ai_handoffs', ['ai_call_id'], unique=False)
    op.create_index(op.f('ix_ai_handoffs_lead_id'), 'ai_handoffs', ['lead_id'], unique=False)
    op.create_table('call_notes',
    sa.Column('human_call_id', sa.Uuid(), nullable=True),
    sa.Column('ai_call_id', sa.Uuid(), nullable=True),
    sa.Column('author_id', sa.Uuid(), nullable=True),
    sa.Column('author_name', sa.String(length=160), nullable=True),
    sa.Column('body', sa.Text(), nullable=False),
    sa.Column('created_at', sa.DateTime(timezone=True), nullable=False),
    sa.Column('id', sa.Uuid(), nullable=False),
    sa.CheckConstraint('(human_call_id IS NOT NULL AND ai_call_id IS NULL) OR (human_call_id IS NULL AND ai_call_id IS NOT NULL)', name=op.f('ck_call_notes_one_parent')),
    sa.ForeignKeyConstraint(['ai_call_id'], ['ai_calls.id'], name=op.f('fk_call_notes_ai_call_id_ai_calls'), ondelete='CASCADE'),
    sa.ForeignKeyConstraint(['author_id'], ['users.id'], name=op.f('fk_call_notes_author_id_users'), ondelete='SET NULL'),
    sa.ForeignKeyConstraint(['human_call_id'], ['human_calls.id'], name=op.f('fk_call_notes_human_call_id_human_calls'), ondelete='CASCADE'),
    sa.PrimaryKeyConstraint('id', name=op.f('pk_call_notes'))
    )
    op.create_index(op.f('ix_call_notes_ai_call_id'), 'call_notes', ['ai_call_id'], unique=False)
    op.create_index(op.f('ix_call_notes_human_call_id'), 'call_notes', ['human_call_id'], unique=False)
    op.create_table('call_recordings',
    sa.Column('human_call_id', sa.Uuid(), nullable=True),
    sa.Column('ai_call_id', sa.Uuid(), nullable=True),
    sa.Column('provider', sa.String(length=32), nullable=False),
    sa.Column('provider_recording_id', sa.String(length=128), nullable=True),
    sa.Column('url', sa.Text(), nullable=False),
    sa.Column('duration_seconds', sa.Integer(), nullable=True),
    sa.Column('created_at', sa.DateTime(timezone=True), nullable=False),
    sa.Column('id', sa.Uuid(), nullable=False),
    sa.CheckConstraint('(human_call_id IS NOT NULL AND ai_call_id IS NULL) OR (human_call_id IS NULL AND ai_call_id IS NOT NULL)', name=op.f('ck_call_recordings_one_parent')),
    sa.ForeignKeyConstraint(['ai_call_id'], ['ai_calls.id'], name=op.f('fk_call_recordings_ai_call_id_ai_calls'), ondelete='CASCADE'),
    sa.ForeignKeyConstraint(['human_call_id'], ['human_calls.id'], name=op.f('fk_call_recordings_human_call_id_human_calls'), ondelete='CASCADE'),
    sa.PrimaryKeyConstraint('id', name=op.f('pk_call_recordings'))
    )
    op.create_index(op.f('ix_call_recordings_ai_call_id'), 'call_recordings', ['ai_call_id'], unique=False)
    op.create_index(op.f('ix_call_recordings_human_call_id'), 'call_recordings', ['human_call_id'], unique=False)
    op.create_table('call_transcripts',
    sa.Column('human_call_id', sa.Uuid(), nullable=True),
    sa.Column('ai_call_id', sa.Uuid(), nullable=True),
    sa.Column('language', sa.String(length=16), nullable=True),
    sa.Column('segments', sa.JSON(), nullable=False),
    sa.Column('full_text', sa.Text(), nullable=False),
    sa.Column('created_at', sa.DateTime(timezone=True), nullable=False),
    sa.Column('id', sa.Uuid(), nullable=False),
    sa.CheckConstraint('(human_call_id IS NOT NULL AND ai_call_id IS NULL) OR (human_call_id IS NULL AND ai_call_id IS NOT NULL)', name=op.f('ck_call_transcripts_one_parent')),
    sa.ForeignKeyConstraint(['ai_call_id'], ['ai_calls.id'], name=op.f('fk_call_transcripts_ai_call_id_ai_calls'), ondelete='CASCADE'),
    sa.ForeignKeyConstraint(['human_call_id'], ['human_calls.id'], name=op.f('fk_call_transcripts_human_call_id_human_calls'), ondelete='CASCADE'),
    sa.PrimaryKeyConstraint('id', name=op.f('pk_call_transcripts')),
    sa.UniqueConstraint('ai_call_id', name=op.f('uq_call_transcripts_ai_call_id')),
    sa.UniqueConstraint('human_call_id', name=op.f('uq_call_transcripts_human_call_id'))
    )
    op.create_table('followups',
    sa.Column('lead_id', sa.Uuid(), nullable=False),
    sa.Column('assigned_to_id', sa.Uuid(), nullable=True),
    sa.Column('due_at', sa.DateTime(timezone=True), nullable=False),
    sa.Column('status', sa.String(length=16), nullable=False),
    sa.Column('note', sa.Text(), nullable=True),
    sa.Column('source', sa.String(length=16), nullable=False),
    sa.Column('human_call_id', sa.Uuid(), nullable=True),
    sa.Column('ai_call_id', sa.Uuid(), nullable=True),
    sa.Column('reminded_at', sa.DateTime(timezone=True), nullable=True),
    sa.Column('completed_at', sa.DateTime(timezone=True), nullable=True),
    sa.Column('created_by_id', sa.Uuid(), nullable=True),
    sa.Column('id', sa.Uuid(), nullable=False),
    sa.Column('created_at', sa.DateTime(timezone=True), nullable=False),
    sa.Column('updated_at', sa.DateTime(timezone=True), nullable=False),
    sa.CheckConstraint("source IN ('human_call', 'ai_call', 'manual')", name=op.f('ck_followups_source_valid')),
    sa.CheckConstraint("status IN ('pending', 'done', 'cancelled')", name=op.f('ck_followups_status_valid')),
    sa.ForeignKeyConstraint(['ai_call_id'], ['ai_calls.id'], name=op.f('fk_followups_ai_call_id_ai_calls'), ondelete='SET NULL'),
    sa.ForeignKeyConstraint(['assigned_to_id'], ['users.id'], name=op.f('fk_followups_assigned_to_id_users'), ondelete='SET NULL'),
    sa.ForeignKeyConstraint(['created_by_id'], ['users.id'], name=op.f('fk_followups_created_by_id_users'), ondelete='SET NULL'),
    sa.ForeignKeyConstraint(['human_call_id'], ['human_calls.id'], name=op.f('fk_followups_human_call_id_human_calls'), ondelete='SET NULL'),
    sa.ForeignKeyConstraint(['lead_id'], ['leads.id'], name=op.f('fk_followups_lead_id_leads'), ondelete='CASCADE'),
    sa.PrimaryKeyConstraint('id', name=op.f('pk_followups'))
    )
    op.create_index('ix_followups_assignee_due', 'followups', ['assigned_to_id', 'status', 'due_at'], unique=False)
    op.create_index(op.f('ix_followups_lead_id'), 'followups', ['lead_id'], unique=False)


def downgrade() -> None:
    if op.get_bind().dialect.name != 'sqlite':
        op.drop_constraint(op.f('fk_teams_manager_id_users'), 'teams', type_='foreignkey')
    op.drop_index(op.f('ix_followups_lead_id'), table_name='followups')
    op.drop_index('ix_followups_assignee_due', table_name='followups')
    op.drop_table('followups')
    op.drop_table('call_transcripts')
    op.drop_index(op.f('ix_call_recordings_human_call_id'), table_name='call_recordings')
    op.drop_index(op.f('ix_call_recordings_ai_call_id'), table_name='call_recordings')
    op.drop_table('call_recordings')
    op.drop_index(op.f('ix_call_notes_human_call_id'), table_name='call_notes')
    op.drop_index(op.f('ix_call_notes_ai_call_id'), table_name='call_notes')
    op.drop_table('call_notes')
    op.drop_index(op.f('ix_ai_handoffs_lead_id'), table_name='ai_handoffs')
    op.drop_index(op.f('ix_ai_handoffs_ai_call_id'), table_name='ai_handoffs')
    op.drop_table('ai_handoffs')
    op.drop_index(op.f('ix_ai_calls_status'), table_name='ai_calls')
    op.drop_index('ix_ai_calls_provider_call', table_name='ai_calls')
    op.drop_index(op.f('ix_ai_calls_phone_hash'), table_name='ai_calls')
    op.drop_index(op.f('ix_ai_calls_lead_id'), table_name='ai_calls')
    op.drop_index(op.f('ix_ai_calls_interest_level'), table_name='ai_calls')
    op.drop_index(op.f('ix_ai_calls_campaign_id'), table_name='ai_calls')
    op.drop_index('ix_ai_calls_agent_started', table_name='ai_calls')
    op.drop_index(op.f('ix_ai_calls_agent_id'), table_name='ai_calls')
    op.drop_table('ai_calls')
    op.drop_index(op.f('ix_campaign_logs_created_at'), table_name='campaign_logs')
    op.drop_index(op.f('ix_campaign_logs_campaign_id'), table_name='campaign_logs')
    op.drop_table('campaign_logs')
    op.drop_index('ix_campaign_leads_due', table_name='ai_campaign_leads')
    op.drop_index(op.f('ix_ai_campaign_leads_lead_id'), table_name='ai_campaign_leads')
    op.drop_table('ai_campaign_leads')
    op.drop_table('opt_outs')
    op.drop_table('lead_call_locks')
    op.drop_index(op.f('ix_lead_assignments_to_user_id'), table_name='lead_assignments')
    op.drop_index(op.f('ix_lead_assignments_lead_id'), table_name='lead_assignments')
    op.drop_table('lead_assignments')
    op.drop_index(op.f('ix_lead_activities_lead_id'), table_name='lead_activities')
    op.drop_table('lead_activities')
    op.drop_index(op.f('ix_human_calls_team_id'), table_name='human_calls')
    op.drop_index(op.f('ix_human_calls_status'), table_name='human_calls')
    op.drop_index('ix_human_calls_salesperson_started', table_name='human_calls')
    op.drop_index(op.f('ix_human_calls_salesperson_id'), table_name='human_calls')
    op.drop_index('ix_human_calls_provider_call', table_name='human_calls')
    op.drop_index(op.f('ix_human_calls_phone_hash'), table_name='human_calls')
    op.drop_index(op.f('ix_human_calls_outcome'), table_name='human_calls')
    op.drop_index(op.f('ix_human_calls_lead_id'), table_name='human_calls')
    op.drop_table('human_calls')
    op.drop_table('favourite_leads')
    op.drop_index(op.f('ix_ai_campaigns_status'), table_name='ai_campaigns')
    op.drop_index(op.f('ix_ai_campaigns_agent_id'), table_name='ai_campaigns')
    op.drop_table('ai_campaigns')
    op.drop_index(op.f('ix_user_sessions_user_id'), table_name='user_sessions')
    op.drop_table('user_sessions')
    op.drop_index('ix_notifications_user_read', table_name='notifications')
    op.drop_index(op.f('ix_notifications_created_at'), table_name='notifications')
    op.drop_table('notifications')
    op.drop_index('uq_leads_phone_hash_live', table_name='leads', postgresql_where=sa.text('deleted_at IS NULL'), sqlite_where=sa.text('deleted_at IS NULL'))
    op.drop_index('uq_leads_email_hash_live', table_name='leads', postgresql_where=sa.text('deleted_at IS NULL AND email_hash IS NOT NULL'), sqlite_where=sa.text('deleted_at IS NULL AND email_hash IS NOT NULL'))
    op.drop_index('ix_leads_status_assigned', table_name='leads')
    op.drop_index(op.f('ix_leads_source'), table_name='leads')
    op.drop_index(op.f('ix_leads_next_followup_at'), table_name='leads')
    op.drop_index(op.f('ix_leads_industry'), table_name='leads')
    op.drop_index(op.f('ix_leads_full_name'), table_name='leads')
    op.drop_index(op.f('ix_leads_deleted_at'), table_name='leads')
    op.drop_index(op.f('ix_leads_company_name'), table_name='leads')
    op.drop_index(op.f('ix_leads_assigned_to_id'), table_name='leads')
    op.drop_index(op.f('ix_leads_alternate_phone_hash'), table_name='leads')
    op.drop_table('leads')
    op.drop_index(op.f('ix_device_tokens_user_id'), table_name='device_tokens')
    op.drop_table('device_tokens')
    op.drop_index(op.f('ix_audit_logs_entity_type'), table_name='audit_logs')
    op.drop_index(op.f('ix_audit_logs_created_at'), table_name='audit_logs')
    op.drop_index(op.f('ix_audit_logs_actor_id'), table_name='audit_logs')
    op.drop_index(op.f('ix_audit_logs_action'), table_name='audit_logs')
    op.drop_table('audit_logs')
    op.drop_table('ai_agents')
    op.drop_index(op.f('ix_users_team_id'), table_name='users')
    op.drop_index(op.f('ix_users_role_id'), table_name='users')
    op.drop_table('users')
    op.drop_index(op.f('ix_telephony_events_provider_call_id'), table_name='telephony_events')
    op.drop_index(op.f('ix_telephony_events_call_ref_id'), table_name='telephony_events')
    op.drop_table('telephony_events')
    op.drop_index(op.f('ix_teams_manager_id'), table_name='teams')
    op.drop_table('teams')
    op.drop_table('roles')
    op.drop_table('org_settings')

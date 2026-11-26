"""unified reporting view over human and AI calls

Revision ID: 0002
Revises: 0001
Create Date: 2026-11-26
"""
from collections.abc import Sequence

from alembic import op

from app.models import unified_calls_view_sql

revision: str = "0002"
down_revision: str | None = "0001"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.execute(unified_calls_view_sql(op.get_bind().dialect.name))


def downgrade() -> None:
    op.execute("DROP VIEW IF EXISTS v_unified_calls")

"""Add price_labels table for storing pre-computed 5-day forward return labels

Revision ID: 0003
Revises: 0002
Create Date: 2026-04-27
"""

from alembic import op
import sqlalchemy as sa

revision = "0003"
down_revision = "0002"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "price_labels",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("ticker", sa.String(length=10), nullable=False),
        sa.Column("date", sa.Date(), nullable=False),
        sa.Column("close_price", sa.Numeric(12, 4), nullable=True),
        sa.Column("forward_return_5d", sa.Numeric(10, 6), nullable=True),
        sa.Column("label", sa.String(length=10), nullable=False, server_default="STABLE"),
        sa.Column("fetched_at", sa.DateTime(timezone=True), nullable=True),
        sa.UniqueConstraint("ticker", "date", name="uq_price_label_ticker_date"),
    )
    op.create_index("ix_price_labels_ticker", "price_labels", ["ticker"])
    op.create_index("ix_price_labels_date", "price_labels", ["date"])


def downgrade() -> None:
    op.drop_index("ix_price_labels_date", table_name="price_labels")
    op.drop_index("ix_price_labels_ticker", table_name="price_labels")
    op.drop_table("price_labels")

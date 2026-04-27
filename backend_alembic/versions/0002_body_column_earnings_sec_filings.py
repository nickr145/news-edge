"""Add body column to articles; create earnings_events and sec_filings tables

Revision ID: 0002_body_column_earnings_sec_filings
Revises: 0001_initial
Create Date: 2026-04-26
"""

from alembic import op
import sqlalchemy as sa

revision = "0002"
down_revision = "0001_initial"
branch_labels = None
depends_on = None


def upgrade() -> None:
    # articles.body — stores scraped full article text (nullable, additive)
    op.add_column("articles", sa.Column("body", sa.Text(), nullable=True))

    # earnings_events — Finnhub earnings calendar per ticker
    op.create_table(
        "earnings_events",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("ticker", sa.String(length=10), nullable=False),
        sa.Column("report_date", sa.DateTime(timezone=True), nullable=False),
        sa.Column("fiscal_date_ending", sa.String(length=20), nullable=True),
        sa.Column("estimated_eps", sa.Numeric(12, 4), nullable=True),
        sa.Column("actual_eps", sa.Numeric(12, 4), nullable=True),
        sa.Column("surprise_pct", sa.Numeric(10, 4), nullable=True),
        sa.Column("ingested_at", sa.DateTime(timezone=True), nullable=True),
        sa.UniqueConstraint("ticker", "report_date", name="uq_earnings_ticker_date"),
    )
    op.create_index("ix_earnings_events_ticker", "earnings_events", ["ticker"])
    op.create_index("ix_earnings_events_report_date", "earnings_events", ["report_date"])

    # sec_filings — SEC EDGAR 8-K / 10-K / 10-Q filing index
    op.create_table(
        "sec_filings",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("ticker", sa.String(length=10), nullable=False),
        sa.Column("cik", sa.String(length=15), nullable=False),
        sa.Column("accession_number", sa.String(length=25), nullable=False, unique=True),
        sa.Column("form_type", sa.String(length=10), nullable=False),
        sa.Column("filed_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("description", sa.Text(), nullable=True),
        sa.Column("filing_url", sa.Text(), nullable=False),
        sa.Column(
            "article_id",
            sa.Integer(),
            sa.ForeignKey("articles.id", ondelete="SET NULL"),
            nullable=True,
        ),
        sa.Column("ingested_at", sa.DateTime(timezone=True), nullable=True),
    )
    op.create_index("ix_sec_filings_ticker", "sec_filings", ["ticker"])
    op.create_index("ix_sec_filings_accession_number", "sec_filings", ["accession_number"])
    op.create_index("ix_sec_filings_filed_at", "sec_filings", ["filed_at"])
    op.create_index("ix_sec_filings_form_type", "sec_filings", ["form_type"])


def downgrade() -> None:
    op.drop_index("ix_sec_filings_form_type", table_name="sec_filings")
    op.drop_index("ix_sec_filings_filed_at", table_name="sec_filings")
    op.drop_index("ix_sec_filings_accession_number", table_name="sec_filings")
    op.drop_index("ix_sec_filings_ticker", table_name="sec_filings")
    op.drop_table("sec_filings")

    op.drop_index("ix_earnings_events_report_date", table_name="earnings_events")
    op.drop_index("ix_earnings_events_ticker", table_name="earnings_events")
    op.drop_table("earnings_events")

    op.drop_column("articles", "body")

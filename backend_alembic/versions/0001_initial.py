"""initial tables

Revision ID: 0001_initial
Revises: 
Create Date: 2026-03-09
"""

from alembic import op
import sqlalchemy as sa


revision = "0001_initial"
down_revision = None
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "articles",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("external_id", sa.String(length=64), nullable=True),
        sa.Column("url", sa.Text(), nullable=False, unique=True),
        sa.Column("headline", sa.Text(), nullable=False),
        sa.Column("summary", sa.Text(), nullable=True),
        sa.Column("source", sa.String(length=100), nullable=True),
        sa.Column("published_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("ingested_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("raw_payload", sa.JSON(), nullable=True),
    )
    op.create_index("ix_articles_id", "articles", ["id"])
    op.create_index("ix_articles_external_id", "articles", ["external_id"])

    op.create_table(
        "predictions",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("ticker", sa.String(length=10), nullable=False),
        sa.Column("predicted_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("recommendation", sa.String(length=10), nullable=False),
        sa.Column("confidence", sa.Numeric(5, 4), nullable=False),
        sa.Column("sentiment_score", sa.Numeric(6, 4), nullable=False),
        sa.Column("price_rsi", sa.Numeric(6, 2), nullable=False),
        sa.Column("feature_importances", sa.JSON(), nullable=True),
        sa.Column("horizon_days", sa.Integer(), nullable=False),
    )
    op.create_index("ix_predictions_ticker", "predictions", ["ticker"])

    op.create_table(
        "article_tickers",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("article_id", sa.Integer(), sa.ForeignKey("articles.id", ondelete="CASCADE"), nullable=False),
        sa.Column("ticker", sa.String(length=10), nullable=False),
        sa.UniqueConstraint("article_id", "ticker", name="uq_article_ticker"),
    )
    op.create_index("ix_article_tickers_ticker", "article_tickers", ["ticker"])

    op.create_table(
        "sentiment_scores",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("article_id", sa.Integer(), sa.ForeignKey("articles.id", ondelete="CASCADE"), nullable=False),
        sa.Column("ticker", sa.String(length=10), nullable=False),
        sa.Column("model", sa.String(length=20), nullable=False),
        sa.Column("score_positive", sa.Numeric(5, 4), nullable=False),
        sa.Column("score_negative", sa.Numeric(5, 4), nullable=False),
        sa.Column("score_neutral", sa.Numeric(5, 4), nullable=False),
        sa.Column("compound", sa.Numeric(6, 4), nullable=False),
        sa.Column("label", sa.String(length=10), nullable=False),
        sa.Column("scored_at", sa.DateTime(timezone=True), nullable=True),
    )
    op.create_index("ix_sentiment_scores_article_id", "sentiment_scores", ["article_id"])
    op.create_index("ix_sentiment_scores_ticker", "sentiment_scores", ["ticker"])


def downgrade() -> None:
    op.drop_index("ix_sentiment_scores_ticker", table_name="sentiment_scores")
    op.drop_index("ix_sentiment_scores_article_id", table_name="sentiment_scores")
    op.drop_table("sentiment_scores")

    op.drop_index("ix_article_tickers_ticker", table_name="article_tickers")
    op.drop_table("article_tickers")

    op.drop_index("ix_predictions_ticker", table_name="predictions")
    op.drop_table("predictions")

    op.drop_index("ix_articles_external_id", table_name="articles")
    op.drop_index("ix_articles_id", table_name="articles")
    op.drop_table("articles")

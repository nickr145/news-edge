"""
Pytest session fixture: redirect all tests to a fresh in-memory SQLite DB so
tests are isolated from the local dev newsedge.db and always see the latest schema.
"""
import os

import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

_TEST_DB_URL = "sqlite:///:memory:"


@pytest.fixture(scope="session", autouse=True)
def _test_database():
    import app.core.config as cfg_mod
    import app.db.session as sess_mod
    from app.db.base import Base
    from app.models import article, earnings, prediction, sec_filing, sentiment  # noqa: F401

    cfg_mod.get_settings.cache_clear()
    os.environ["DATABASE_URL"] = _TEST_DB_URL

    # StaticPool: all checkouts reuse the same underlying connection,
    # so every session sees the same in-memory database.
    test_engine = create_engine(
        _TEST_DB_URL,
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    TestSession = sessionmaker(autocommit=False, autoflush=False, bind=test_engine)

    original_engine = sess_mod.engine
    original_session = sess_mod.SessionLocal

    sess_mod.engine = test_engine
    sess_mod.SessionLocal = TestSession

    Base.metadata.drop_all(bind=test_engine)
    Base.metadata.create_all(bind=test_engine)

    yield

    Base.metadata.drop_all(bind=test_engine)
    sess_mod.engine = original_engine
    sess_mod.SessionLocal = original_session
    cfg_mod.get_settings.cache_clear()

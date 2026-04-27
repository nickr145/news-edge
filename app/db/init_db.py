from app.db.base import Base
from app.db.session import engine
from app.models import article, earnings, prediction, sec_filing, sentiment


def init_db() -> None:
    Base.metadata.create_all(bind=engine)

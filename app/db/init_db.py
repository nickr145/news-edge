from app.db.base import Base
from app.db.session import engine
from app.models import article, prediction, sentiment


def init_db() -> None:
    Base.metadata.create_all(bind=engine)

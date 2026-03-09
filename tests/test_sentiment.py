from app.services.sentiment import VaderLikeEngine


def test_vader_like_engine_positive_and_negative_words():
    engine = VaderLikeEngine()
    pos = engine.score("Company earnings beat expectations", "Strong growth and profit")
    neg = engine.score("Company faces lawsuit", "Potential loss and downgrade")

    assert pos.compound > 0
    assert neg.compound < 0

from app.utils.stats import ewma, mean, std


def test_mean_std_ewma_basic():
    values = [0.2, -0.1, 0.3, 0.0]
    assert round(mean(values), 4) == 0.1
    assert std(values) > 0
    assert -1 <= ewma(values) <= 1

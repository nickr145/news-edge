from __future__ import annotations

from math import sqrt


def mean(values: list[float]) -> float:
    if not values:
        return 0.0
    return sum(float(v) for v in values) / len(values)


def std(values: list[float]) -> float:
    if len(values) < 2:
        return 0.0
    m = mean(values)
    var = sum((float(v) - m) ** 2 for v in values) / (len(values) - 1)
    return sqrt(var)


def ewma(values: list[float], alpha: float = 0.3) -> float:
    if not values:
        return 0.0
    acc = float(values[0])
    for v in values[1:]:
        acc = alpha * float(v) + (1 - alpha) * acc
    return acc

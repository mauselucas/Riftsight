"""Small statistics toolkit (no numpy needed)."""
from __future__ import annotations

import math
from statistics import fmean, pstdev
from typing import Iterable, Sequence


def logit(p: float) -> float:
    p = min(max(p, 1e-4), 1 - 1e-4)
    return math.log(p / (1.0 - p))


def sigmoid(x: float) -> float:
    return 1.0 / (1.0 + math.exp(-x))


def smoothed(wins: float, games: float, prior: float, weight: float) -> float:
    """Empirical-Bayes shrinkage towards ``prior`` with ``weight`` pseudo games."""
    return (wins + weight * prior) / (games + weight)


def blend(current: float, n_current: int, previous: float | None, target: int) -> float:
    """Pre-patch blending: w = min(1, N/target), p = w·p_curr + (1-w)·p_prev."""
    if previous is None:
        return current
    w = min(1.0, n_current / max(1, target))
    return w * current + (1.0 - w) * previous


def wilson_lower(wins: int, games: int, z: float = 1.96) -> float:
    if games == 0:
        return 0.0
    p = wins / games
    denom = 1 + z * z / games
    centre = p + z * z / (2 * games)
    margin = z * math.sqrt(p * (1 - p) / games + z * z / (4 * games * games))
    return (centre - margin) / denom


def zscores(values: Sequence[float]) -> list[float]:
    if not values:
        return []
    mean = fmean(values)
    sd = max(pstdev(values), 1e-6)
    return [(v - mean) / sd for v in values]


def assign_tier(score: float) -> str:
    if score >= 65.0:
        return "S+"
    if score >= 57.5:
        return "S"
    if score >= 50.0:
        return "A"
    if score >= 42.5:
        return "B"
    if score >= 35.0:
        return "C"
    return "D"


def composite_scores(components: Iterable[tuple[float, Sequence[float]]]) -> list[float]:
    """score = clamp(50 + 10 · Σ wᵢ·z(xᵢ), 0, 100)."""
    parts = [(w, zscores(list(xs))) for w, xs in components]
    n = len(parts[0][1]) if parts else 0
    raw = [sum(w * z[i] for w, z in parts) for i in range(n)]
    return [min(100.0, max(0.0, 50.0 + 10.0 * r)) for r in raw]


def rnd(value: float, digits: int = 4) -> float:
    """Round and guard against NaN/inf (the schema gate rejects those)."""
    if value is None or math.isnan(value) or math.isinf(value):
        return 0.0
    return round(float(value), digits)

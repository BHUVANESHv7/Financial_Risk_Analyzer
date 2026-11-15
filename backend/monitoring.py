"""
monitoring.py
─────────────
Model health: is the live applicant population still like the data the
model was trained on?

Uses the Population Stability Index (PSI), the standard credit-risk drift
metric, per input feature:
    PSI < 0.10  stable · 0.10–0.25  moderate shift · > 0.25  significant shift
A significant shift means the model is scoring people unlike those it learned
from, so it should be retrained on recent data (train_model.py --data …).
"""

import threading

import numpy as np
from sqlalchemy.orm import Session

from database import LoanAnalysis
from risk_model import FEATURES, feature_matrix, synthetic_raw

LABELS = {
    "monthly_income": "Monthly income",
    "loan_amount": "Loan amount",
    "existing_emis": "Existing EMIs",
    "employment_years": "Employment years",
    "credit_score": "Credit score",
    "num_dependents": "Dependents",
    "dti": "Debt-to-income",
    "loan_to_annual_income": "Loan ÷ annual income",
}
MIN_SAMPLE = 30
STABLE, MODERATE = 0.10, 0.25
_BINS = 10

_reference = None
_lock = threading.Lock()


def _reference_bins():
    """Decile edges and shares of the training distribution (computed once)."""
    global _reference
    with _lock:
        if _reference is None:
            X = feature_matrix(synthetic_raw(20_000, seed=7))  # same generator as training
            ref = {}
            for j, name in enumerate(FEATURES):
                col = X[:, j]
                edges = np.unique(np.quantile(col, np.linspace(0, 1, _BINS + 1)[1:-1]))
                ref[name] = (edges, _shares(col, edges))
            _reference = ref
    return _reference


def _shares(values: np.ndarray, edges: np.ndarray) -> np.ndarray:
    counts = np.bincount(np.searchsorted(edges, values, side="right"), minlength=len(edges) + 1)
    return np.clip(counts / max(len(values), 1), 1e-4, None)


def psi(expected: np.ndarray, actual: np.ndarray) -> float:
    return float(np.sum((actual - expected) * np.log(actual / expected)))


def _status(value: float) -> str:
    if value < STABLE:
        return "stable"
    return "moderate" if value < MODERATE else "significant"


def drift_report(db: Session, window: int = 500) -> dict:
    rows = db.query(
        LoanAnalysis.monthly_income, LoanAnalysis.loan_amount, LoanAnalysis.existing_emis,
        LoanAnalysis.employment_years, LoanAnalysis.credit_score, LoanAnalysis.num_dependents,
        LoanAnalysis.tenure_months, LoanAnalysis.interest_rate, LoanAnalysis.risk_level,
    ).order_by(LoanAnalysis.timestamp.desc()).limit(window).all()

    n = len(rows)
    mix = {}
    for r in rows:
        mix[r[-1] or "UNKNOWN"] = mix.get(r[-1] or "UNKNOWN", 0) + 1

    base = {"sample_size": n, "window": window, "thresholds": {"stable": STABLE, "moderate": MODERATE},
            "risk_mix": {k: round(v / n, 3) for k, v in mix.items()} if n else {}}
    if n < MIN_SAMPLE:
        return {**base, "status": "insufficient_data", "features": [],
                "message": f"Needs at least {MIN_SAMPLE} applications to measure drift ({n} so far)."}

    raw = np.array([[r[0] or 0, r[1] or 0, r[2] or 0, r[3] or 0, r[4] or 650, r[5] or 0,
                     r[6] or 60, r[7] or 10.5] for r in rows], dtype=float)
    live = feature_matrix(raw)
    ref = _reference_bins()

    features = []
    for j, name in enumerate(FEATURES):
        edges, expected = ref[name]
        value = psi(expected, _shares(live[:, j], edges))
        features.append({"feature": name, "label": LABELS[name], "psi": round(value, 3),
                         "status": _status(value), "live_median": round(float(np.median(live[:, j])), 3)})
    features.sort(key=lambda f: -f["psi"])

    worst = features[0]
    overall = worst["status"]
    message = {
        "stable": "Live applications look like the training data. No action needed.",
        "moderate": f"{worst['label']} has shifted. Keep an eye on it.",
        "significant": f"{worst['label']} has shifted a lot. Retrain the model on recent data.",
    }[overall]
    return {**base, "status": overall, "max_psi": worst["psi"], "features": features,
            "message": message}

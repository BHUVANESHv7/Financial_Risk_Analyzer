"""
risk_model.py
─────────────
Layer 2 — ML Module
Predicts loan risk as LOW / MEDIUM / HIGH, plus a continuous 0–100 risk
score and plain-language key factors.

Model (v3): an *ordinal, monotone* gradient-boosting model.
  • Risk levels are ordered, so instead of three unrelated classes we learn
    two questions: "is it at least MEDIUM?" and "is it HIGH?".
  • Each question is a HistGradientBoosting model with monotonic constraints,
    which guarantees sensible behaviour: a higher credit score, higher income
    or longer employment can never increase risk, and more debt can never
    decrease it.

Train / evaluate / retrain on real data with:  python train_model.py --help
"""

import json
import os
import threading

# Avoids a noisy (harmless) joblib warning about counting CPU cores on Windows.
os.environ.setdefault("LOKY_MAX_CPU_COUNT", str(os.cpu_count() or 1))

import joblib  # noqa: E402
import numpy as np
from sklearn.ensemble import HistGradientBoostingClassifier

from finance import ratios

_HERE = os.path.dirname(os.path.abspath(__file__))
MODEL_PATH = os.path.join(_HERE, "risk_model.pkl")
REPORT_PATH = os.path.join(_HERE, "model_report.json")
MODEL_VERSION = 3

FEATURES = [
    "monthly_income",
    "loan_amount",
    "existing_emis",
    "employment_years",
    "credit_score",
    "num_dependents",
    "dti",
    "loan_to_annual_income",
]
# +1: feature can only raise risk, -1: can only lower risk.
MONOTONE = {
    "monthly_income": -1,
    "loan_amount": 1,
    "existing_emis": 1,
    "employment_years": -1,
    "credit_score": -1,
    "num_dependents": 1,
    "dti": 1,
    "loan_to_annual_income": 1,
}
LABELS = ["LOW", "MEDIUM", "HIGH"]
# Weight of each class when collapsing probabilities into a 0–100 score.
_SCORE_WEIGHTS = {"LOW": 0.0, "MEDIUM": 50.0, "HIGH": 100.0}

# Uncertainty added to synthetic labels near policy cut-offs (see policy_labels).
LABEL_NOISE = 0.6

# Tuned with train_model.py (see model_report.json).
HYPERPARAMS = dict(
    learning_rate=0.1,
    max_leaf_nodes=31,
    max_iter=1500,
    early_stopping=True,
    validation_fraction=0.1,
    n_iter_no_change=30,
    random_state=42,
)

DEFAULTS = {
    "monthly_income": 30000.0,
    "loan_amount": 100000.0,
    "existing_emis": 0.0,
    "employment_years": 1.0,
    "credit_score": 650.0,
    "num_dependents": 1.0,
}


class OrdinalRiskModel:
    """Two monotone binary boosters: P(risk ≥ MEDIUM) and P(risk ≥ HIGH)."""

    classes_ = np.array(LABELS)

    def __init__(self, **params):
        self.params = {**HYPERPARAMS, **params}
        self.models = []

    def fit(self, X, y):
        level = np.array([LABELS.index(v) for v in y])
        cst = [MONOTONE[f] for f in FEATURES]
        self.models = [
            HistGradientBoostingClassifier(monotonic_cst=cst, **self.params).fit(X, level >= k)
            for k in (1, 2)
        ]
        return self

    def predict_proba(self, X):
        X = np.asarray(X, dtype=float)
        p_med = self.models[0].predict_proba(X)[:, 1]
        p_high = np.minimum(self.models[1].predict_proba(X)[:, 1], p_med)  # keep ordered
        return np.column_stack([1 - p_med, p_med - p_high, p_high])

    def predict(self, X):
        return self.classes_[self.predict_proba(X).argmax(1)]


# ── Synthetic training data ───────────────────────────────────────────────────

def _label(income, loan, emis, years, credit, deps, dti) -> str:
    """Rule-based risk tier used to label synthetic data."""
    score = 0
    if credit >= 750: score += 3
    elif credit >= 680: score += 2
    elif credit >= 600: score += 1
    elif credit < 550: score -= 2

    if income >= 60000: score += 2
    elif income >= 30000: score += 1

    if years >= 3: score += 1
    if years < 1: score -= 1

    lti = loan / max(income * 12, 1)
    if lti < 1: score += 2
    elif lti < 2: score += 1
    elif lti > 4: score -= 1

    if dti > 0.65: score -= 4
    elif dti > 0.5: score -= 2
    elif dti > 0.35: score -= 1

    if deps >= 4 and income < 30000: score -= 1

    if score >= 5: return "LOW"
    if score >= 2: return "MEDIUM"
    return "HIGH"


def feature_matrix(raw: np.ndarray) -> np.ndarray:
    """
    raw columns: income, loan, emis, years, credit, deps, tenure_months, rate
    → model features in FEATURES order (vectorised).
    """
    inc, loan, emis, yrs, cs, deps, months, rate = np.asarray(raw, dtype=float).T
    inc = np.maximum(inc, 1.0)
    r = rate / 1200
    growth = (1 + r) ** months
    with np.errstate(divide="ignore", invalid="ignore"):
        emi = np.where(r > 0, loan * r * growth / (growth - 1), loan / np.maximum(months, 1))
    emi = np.where(loan > 0, emi, 0.0)
    dti = (emis + emi) / inc
    lti = loan / (inc * 12)
    return np.column_stack([inc, loan, emis, yrs, cs, deps, dti, lti])


def synthetic_raw(n: int, seed: int) -> np.ndarray:
    rng = np.random.default_rng(seed)
    income = np.round(np.exp(rng.uniform(np.log(12000), np.log(300000), n)), -2)
    loan = np.round(np.exp(rng.uniform(np.log(30000), np.log(5000000), n)), -3)
    emis = np.round(income * rng.beta(1.2, 5, n), -2)
    years = rng.integers(0, 31, n).astype(float)
    credit = np.clip(rng.normal(690, 90, n), 300, 900).round()
    deps = rng.integers(0, 7, n).astype(float)
    months = rng.choice([12, 24, 36, 48, 60, 84, 120], n).astype(float)
    rate = rng.uniform(8, 18, n)
    return np.column_stack([income, loan, emis, years, credit, deps, months, rate])


def policy_points(X: np.ndarray) -> np.ndarray:
    """Vectorised version of the points used by _label (higher = safer)."""
    inc, loan, emis, yrs, cs, deps, dti, lti = np.asarray(X, dtype=float).T
    s = np.select([cs >= 750, cs >= 680, cs >= 600, cs < 550], [3, 2, 1, -2], 0).astype(float)
    s += np.select([inc >= 60000, inc >= 30000], [2, 1], 0)
    s += (yrs >= 3).astype(float) - (yrs < 1)
    s += np.select([lti < 1, lti < 2, lti > 4], [2, 1, -1], 0)
    s += np.select([dti > 0.65, dti > 0.5, dti > 0.35], [-4, -2, -1], 0)
    s -= (deps >= 4) & (inc < 30000)
    return s


def policy_labels(X: np.ndarray, noise: float = 0.0, seed: int = 0) -> np.ndarray:
    """
    Risk tier from the lending policy. With noise > 0, applicants near a
    cut-off sometimes land in the neighbouring tier — like real outcomes.
    This teaches the model graded probabilities instead of hard 0/50/100
    jumps, so the live risk score moves smoothly.
    """
    s = policy_points(X)
    if noise > 0:
        # Separate stream from synthetic_raw(seed) so noise is independent of features.
        s = s + np.random.default_rng([seed, 0xA11CE]).logistic(0, noise, len(s))
    # Cut-offs sit half-way between integer points (same tiers as _label).
    return np.where(s >= 4.5, "LOW", np.where(s >= 1.5, "MEDIUM", "HIGH"))


def synthetic_dataset(n: int = 150_000, seed: int = 7, noise: float = LABEL_NOISE):
    X = feature_matrix(synthetic_raw(n, seed))
    return X, policy_labels(X, noise, seed)


# ── Training / loading ────────────────────────────────────────────────────────

def save(model, report: dict | None = None):
    joblib.dump({"version": MODEL_VERSION, "features": FEATURES, "pipeline": model}, MODEL_PATH)
    if report is not None:
        with open(REPORT_PATH, "w", encoding="utf-8") as fh:
            json.dump(report, fh, indent=2)
    print(f"[ML] Model v{MODEL_VERSION} saved to {MODEL_PATH}")


def train_and_save():
    """Fallback used when no saved model exists. Prefer train_model.py."""
    X, y = synthetic_dataset()
    model = OrdinalRiskModel().fit(X, y)
    save(model)
    return model


_model = None
_lock = threading.Lock()


def get_model():
    global _model
    if _model is not None:
        return _model
    with _lock:
        if _model is None:
            bundle = None
            if os.path.exists(MODEL_PATH):
                try:
                    bundle = joblib.load(MODEL_PATH)
                except Exception as e:  # noqa: BLE001
                    print(f"[ML] Could not load model: {e}")
            if isinstance(bundle, dict) and bundle.get("version") == MODEL_VERSION:
                _model = bundle["pipeline"]
                print(f"[ML] Model v{MODEL_VERSION} loaded")
            else:
                print("[ML] Training new model (about 15s)...")
                _model = train_and_save()
    return _model


def model_report() -> dict:
    try:
        with open(REPORT_PATH, encoding="utf-8") as fh:
            return json.load(fh)
    except (OSError, ValueError):
        return {"version": MODEL_VERSION, "note": "Run train_model.py to generate metrics"}


# ── Prediction ────────────────────────────────────────────────────────────────

def normalise(features: dict) -> dict:
    """Fill gaps with defaults and coerce numbers."""
    out = dict(features)
    for key, default in DEFAULTS.items():
        try:
            val = float(out.get(key))
        except (TypeError, ValueError):
            val = default
        out[key] = max(val, 0.0)
    out["credit_score"] = min(max(out["credit_score"], 300.0), 900.0)
    return out


def predict_risk(features: dict) -> dict:
    """Returns risk_level, risk_score (0–100), confidence, probabilities, decision, factors."""
    f = normalise(features)
    r = ratios(f)
    row = [[
        f["monthly_income"], f["loan_amount"], f["existing_emis"],
        f["employment_years"], f["credit_score"], f["num_dependents"],
        r["dti"], r["loan_to_annual_income"],
    ]]
    model = get_model()
    proba = model.predict_proba(np.array(row))[0]
    classes = list(model.classes_)
    probs = {c: float(proba[classes.index(c)]) for c in LABELS if c in classes}

    risk_level = max(probs, key=probs.get)
    risk_score = sum(_SCORE_WEIGHTS[c] * p for c, p in probs.items())

    return {
        "risk_level": risk_level,
        "risk_score": round(risk_score, 1),
        "confidence": round(probs[risk_level], 3),
        "probabilities": {k: round(v, 3) for k, v in probs.items()},
        "decision": _make_decision(risk_level, f, r),
        "factors": explain(f, r),
        "ratios": {
            "new_emi": r["new_emi"],
            "total_obligations": r["total_obligations"],
            "dti": round(r["dti"], 3),
            "loan_to_annual_income": round(r["loan_to_annual_income"], 2),
            "disposable_income": r["disposable_income"],
        },
    }


def _make_decision(risk_level: str, f: dict, r: dict) -> str:
    """LOW → APPROVE, HIGH → REJECT, MEDIUM → MANUAL REVIEW, with hard limits."""
    if f["credit_score"] < 550 or r["dti"] > 0.65:
        return "REJECT"
    if risk_level == "LOW":
        return "APPROVE"
    if risk_level == "HIGH":
        return "REJECT"
    return "MANUAL REVIEW"


def explain(f: dict, r: dict) -> list[dict]:
    """
    Plain-language reasons behind the score, strongest first.
    impact: "positive" (lowers risk) / "negative" (raises risk) / "neutral".
    """
    out = []

    def add(key, label, value, impact, weight, detail):
        out.append({"key": key, "label": label, "value": value,
                    "impact": impact, "weight": weight, "detail": detail})

    cs = f["credit_score"]
    if cs >= 750:
        add("credit_score", "Credit score", f"{cs:.0f}", "positive", 3, "Excellent credit history")
    elif cs >= 680:
        add("credit_score", "Credit score", f"{cs:.0f}", "positive", 2, "Good credit history")
    elif cs >= 600:
        add("credit_score", "Credit score", f"{cs:.0f}", "neutral", 1, "Fair — below the preferred 680")
    else:
        add("credit_score", "Credit score", f"{cs:.0f}", "negative", 3, "Poor — under the 600 minimum")

    dti = r["dti"]
    pct = f"{dti * 100:.0f}%"
    if dti > 0.65:
        add("dti", "Debt-to-income", pct, "negative", 4, "Repayments would take most of the income")
    elif dti > 0.5:
        add("dti", "Debt-to-income", pct, "negative", 3, "Above the 50% regulatory limit")
    elif dti > 0.35:
        add("dti", "Debt-to-income", pct, "neutral", 1, "Manageable but stretched")
    else:
        add("dti", "Debt-to-income", pct, "positive", 2, "Comfortable repayment capacity")

    lti = r["loan_to_annual_income"]
    val = f"{lti:.1f}× annual income"
    if lti > 4:
        add("lti", "Loan size", val, "negative", 2, "Large relative to income")
    elif lti < 1:
        add("lti", "Loan size", val, "positive", 2, "Small relative to income")
    else:
        add("lti", "Loan size", val, "neutral", 1, "Moderate relative to income")

    inc = f["monthly_income"]
    if inc >= 60000:
        add("income", "Monthly income", f"₹{inc:,.0f}", "positive", 2, "Strong income")
    elif inc < 15000:
        add("income", "Monthly income", f"₹{inc:,.0f}", "negative", 2, "Below the ₹15,000 minimum")
    else:
        add("income", "Monthly income", f"₹{inc:,.0f}", "neutral", 1, "Average income")

    yrs = f["employment_years"]
    if yrs >= 3:
        add("employment", "Employment", f"{yrs:.0f} yrs", "positive", 1, "Stable employment")
    elif yrs < 1:
        add("employment", "Employment", f"{yrs:.0f} yrs", "negative", 1, "Less than a year in work")
    else:
        add("employment", "Employment", f"{yrs:.0f} yrs", "neutral", 0, "Short employment history")

    order = {"negative": 0, "positive": 1, "neutral": 2}
    out.sort(key=lambda x: (order[x["impact"]], -x["weight"]))
    return out

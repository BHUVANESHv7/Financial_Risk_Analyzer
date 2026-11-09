"""
risk_model.py
─────────────
Layer 2 — ML Module
Random Forest classifier that predicts loan risk as LOW / MEDIUM / HIGH,
plus a continuous 0–100 risk score and plain-language key factors.

The model trains on synthetic data the first time (or when the saved
model is from an older version). Replace `_synthetic_dataset` with real
data in production.
"""

import os
import threading

import joblib
import numpy as np
from sklearn.ensemble import RandomForestClassifier
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import StandardScaler

from finance import estimate_emi, ratios

MODEL_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "risk_model.pkl")
MODEL_VERSION = 2

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
LABELS = ["LOW", "MEDIUM", "HIGH"]
# Weight of each class when collapsing probabilities into a 0–100 score.
_SCORE_WEIGHTS = {"LOW": 0.0, "MEDIUM": 50.0, "HIGH": 100.0}

DEFAULTS = {
    "monthly_income": 30000.0,
    "loan_amount": 100000.0,
    "existing_emis": 0.0,
    "employment_years": 1.0,
    "credit_score": 650.0,
    "num_dependents": 1.0,
}


# ── Training ──────────────────────────────────────────────────────────────────

def _label(income, loan, emis, years, credit, deps, dti) -> str:
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


def _synthetic_dataset(n: int = 6000, seed: int = 42):
    rng = np.random.default_rng(seed)
    income = np.round(np.exp(rng.uniform(np.log(12000), np.log(300000), n)), -2)
    loan = np.round(np.exp(rng.uniform(np.log(30000), np.log(5000000), n)), -3)
    emis = np.round(income * rng.beta(1.2, 5, n), -2)
    years = rng.integers(0, 31, n).astype(float)
    credit = np.clip(rng.normal(690, 90, n), 300, 900).round()
    deps = rng.integers(0, 7, n).astype(float)
    months = rng.choice([12, 24, 36, 48, 60, 84, 120], n)
    rate = rng.uniform(8, 18, n)

    rows, y = [], []
    for i in range(n):
        new_emi = estimate_emi(loan[i], rate[i], int(months[i]))
        dti = (emis[i] + new_emi) / income[i]
        lti = loan[i] / (income[i] * 12)
        rows.append([income[i], loan[i], emis[i], years[i], credit[i], deps[i], dti, lti])
        y.append(_label(income[i], loan[i], emis[i], years[i], credit[i], deps[i], dti))
    return np.array(rows), np.array(y)


def train_and_save():
    X, y = _synthetic_dataset()
    pipeline = Pipeline([
        ("scaler", StandardScaler()),
        ("clf", RandomForestClassifier(
            n_estimators=150, max_depth=12, min_samples_leaf=3,
            random_state=42, n_jobs=-1,
        )),
    ])
    pipeline.fit(X, y)
    joblib.dump({"version": MODEL_VERSION, "features": FEATURES, "pipeline": pipeline}, MODEL_PATH)
    print(f"[ML] Model v{MODEL_VERSION} trained and saved to {MODEL_PATH}")
    return pipeline


# ── Loading ───────────────────────────────────────────────────────────────────

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
                print("[ML] Training new model...")
                _model = train_and_save()
    return _model


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

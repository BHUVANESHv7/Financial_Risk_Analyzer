"""
risk_model.py
─────────────
Layer 2 — ML Module
Trains and runs a Random Forest classifier to predict
loan risk as LOW / MEDIUM / HIGH.

On first run it trains on synthetic data and saves the model.
In production replace the synthetic data with your real dataset.
"""

import os
import numpy as np
import joblib
from sklearn.ensemble import RandomForestClassifier
from sklearn.preprocessing import StandardScaler
from sklearn.pipeline import Pipeline

MODEL_PATH = "risk_model.pkl"

# Feature order must match what nlp_parser.py returns
FEATURES = [
    "monthly_income",
    "loan_amount",
    "existing_emis",
    "employment_years",
    "credit_score",
    "num_dependents",
]

LABELS = ["LOW", "MEDIUM", "HIGH"]


# ── Train (run once) ──────────────────────────────────────────────────────────

def train_and_save():
    """
    Trains on synthetic data and saves model to disk.
    Replace synthetic data with your real CSV in production.
    """
    np.random.seed(42)
    n = 1000

    # Synthetic training data
    monthly_income   = np.random.randint(15000,  200000, n).astype(float)
    loan_amount      = np.random.randint(50000, 2000000, n).astype(float)
    existing_emis    = np.random.randint(0,      30000,  n).astype(float)
    employment_years = np.random.randint(0,      30,     n).astype(float)
    credit_score     = np.random.randint(300,    900,    n).astype(float)
    num_dependents   = np.random.randint(0,      6,      n).astype(float)

    X = np.column_stack([
        monthly_income, loan_amount, existing_emis,
        employment_years, credit_score, num_dependents,
    ])

    # Synthetic labels based on simple rules
    # LOW  → safe to APPROVE
    # MEDIUM → MANUAL REVIEW
    # HIGH   → REJECT
    y = []
    for i in range(n):
        score = 0
        if credit_score[i]     >= 750: score += 3
        elif credit_score[i]   >= 680: score += 2
        elif credit_score[i]   >= 600: score += 1
        if monthly_income[i]   >= 60000: score += 2
        elif monthly_income[i] >= 30000: score += 1
        if employment_years[i] >= 3: score += 1
        ratio = loan_amount[i] / max(monthly_income[i], 1)
        if ratio < 10:   score += 2
        elif ratio < 20: score += 1
        emi_ratio = existing_emis[i] / max(monthly_income[i], 1)
        if emi_ratio > 0.5: score -= 3
        elif emi_ratio > 0.3: score -= 1

        if score >= 4:   y.append("LOW")     # safe — approve
        elif score >= 1: y.append("MEDIUM")  # borderline — review
        else:            y.append("HIGH")    # risky — reject

    # Build pipeline: scale → forest
    pipeline = Pipeline([
        ("scaler", StandardScaler()),
        ("clf",    RandomForestClassifier(
            n_estimators=200,
            max_depth=10,
            random_state=42,
        )),
    ])
    pipeline.fit(X, y)
    joblib.dump(pipeline, MODEL_PATH)
    print(f"[ML] Model trained and saved to {MODEL_PATH}")
    return pipeline


# ── Load / lazy-init ──────────────────────────────────────────────────────────

_model = None

def _get_model():
    global _model
    if _model is None:
        if os.path.exists(MODEL_PATH):
            _model = joblib.load(MODEL_PATH)
            print(f"[ML] Model loaded from {MODEL_PATH}")
        else:
            print("[ML] No saved model found — training now...")
            _model = train_and_save()
    return _model


# ── Predict ───────────────────────────────────────────────────────────────────

def predict_risk(features: dict) -> dict:
    """
    Takes the features dict from nlp_parser.extract_features().
    Returns risk_level, confidence, and decision.
    """
    model = _get_model()

    X = np.array([[
        features.get("monthly_income",   30000),
        features.get("loan_amount",     100000),
        features.get("existing_emis",        0),
        features.get("employment_years",     1),
        features.get("credit_score",       650),
        features.get("num_dependents",       1),
    ]])

    risk_level   = model.predict(X)[0]               # LOW / MEDIUM / HIGH
    probabilities = model.predict_proba(X)[0]
    confidence   = float(max(probabilities))

    decision = _make_decision(risk_level, features)

    return {
        "risk_level": risk_level,
        "confidence": round(confidence, 3),
        "decision":   decision,
    }


def _make_decision(risk_level: str, features: dict) -> str:
    """
    Map ML risk level to a loan decision.
    LOW  → APPROVE  (primary rule: if the model says low risk, we approve)
    HIGH → REJECT
    MEDIUM → MANUAL REVIEW
    Hard overrides (fraud / compliance) are applied afterwards in main.py.
    """
    credit = features.get("credit_score", 650)
    income = features.get("monthly_income", 30000)
    emis   = features.get("existing_emis", 0)
    loan   = features.get("loan_amount", 0)

    from compliance_checker import _estimate_emi
    new_emi = _estimate_emi(loan)
    total_obligations = emis + new_emi
    dti_ratio = total_obligations / max(income, 1)

    # ── Decision Matrix ──────────────────────────────────────────
    # LOW risk → always APPROVE (If the model says low risk, we trust it)
    if risk_level == "LOW":
        return "APPROVE"

    # Absolute REJECT conditions for MEDIUM/HIGH risk cases
    if credit < 550 or dti_ratio > 0.65:
        return "REJECT"

    # HIGH risk → REJECT
    if risk_level == "HIGH":
        return "REJECT"

    # MEDIUM → manual review
    return "MANUAL REVIEW"

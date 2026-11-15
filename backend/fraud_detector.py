"""
fraud_detector.py
─────────────────
Layer 3 — Fraud Detection Module
Rule-based anomaly checks on extracted features.
"""

FRAUD_THRESHOLD = 4


def check_fraud(features: dict) -> dict:
    """Returns fraud_flag, fraud_score, fraud_reasons (if flagged) and warnings (always)."""
    flags = []
    score = 0

    income = float(features.get("monthly_income") or 0)
    loan = float(features.get("loan_amount") or 0)
    emis = float(features.get("existing_emis") or 0)
    credit = float(features.get("credit_score") or 0)
    years = float(features.get("employment_years") or 0)
    doc_len = features.get("raw_text_length")

    def flag(reason, points):
        nonlocal score
        flags.append(reason)
        score += points

    if income > 0 and (loan / income) > 60:
        flag("Loan-to-income ratio extremely high (>60x monthly income)", 3)
    if income > 0 and emis >= income:
        flag("Existing EMIs exceed monthly income", 3)
    if income > 100000 and credit < 400:
        flag("High income but very low credit score — inconsistent", 2)
    if income > 0 and income % 100000 == 0 and loan > 0 and loan % 1000000 == 0:
        flag("Income and loan amounts are suspiciously round", 1)
    # Only meaningful when the data came from an uploaded document.
    if doc_len is not None and doc_len < 50:
        flag("Document appears empty or unreadable", 2)
    if years == 0 and loan > 500000:
        flag("No employment history with large loan request", 2)

    # Velocity checks — set by the server on submit (never trusted from clients).
    # Many tweaked re-submissions suggest someone probing for an approval.
    recent = int(features.get("recent_applications") or 0)
    similar = int(features.get("similar_recent_applications") or 0)
    if recent >= 5:
        flag(f"{recent} applications submitted in the last 24 hours", 2)
    if similar >= 2:
        flag(f"{similar} near-identical applications in the last 24 hours", 2)

    is_fraud = score >= FRAUD_THRESHOLD
    return {
        "fraud_flag": is_fraud,
        "fraud_score": score,
        "fraud_reasons": flags if is_fraud else [],
        "warnings": flags,
    }

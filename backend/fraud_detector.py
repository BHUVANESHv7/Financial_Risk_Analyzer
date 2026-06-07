"""
fraud_detector.py
─────────────────
Layer 3 — Fraud Detection Module
Runs simple rule-based + anomaly checks on extracted features
to flag suspicious loan applications.
"""


def check_fraud(features: dict) -> dict:
    """
    Takes features dict from nlp_parser.
    Returns fraud_flag (bool) and reasons list.
    """
    flags   = []
    score   = 0

    income  = features.get("monthly_income",   0)
    loan    = features.get("loan_amount",       0)
    emis    = features.get("existing_emis",     0)
    credit  = features.get("credit_score",      0)
    years   = features.get("employment_years",  0)
    doc_len = features.get("raw_text_length",   0)

    # ── Rule 1: Loan amount suspiciously high vs income ──────────
    if income > 0 and (loan / income) > 60:
        flags.append("Loan-to-income ratio extremely high (>60x)")
        score += 3

    # ── Rule 2: EMI already exceeds income ───────────────────────
    if income > 0 and emis >= income:
        flags.append("Existing EMIs exceed monthly income")
        score += 3

    # ── Rule 3: Very high income but very low credit score ───────
    if income > 100000 and credit < 400:
        flags.append("High income but very low credit score — inconsistent")
        score += 2

    # ── Rule 4: Suspiciously round numbers ───────────────────────
    if income > 0 and income % 100000 == 0 and loan % 1000000 == 0:
        flags.append("Income and loan amounts are suspiciously round")
        score += 1

    # ── Rule 5: Document too short (possible fake/empty doc) ─────
    if doc_len < 50:
        flags.append("Document appears empty or unreadable")
        score += 2

    # ── Rule 6: Zero employment but high loan request ────────────
    if years == 0 and loan > 500000:
        flags.append("No employment history with large loan request")
        score += 2

    is_fraud = score >= 4

    return {
        "fraud_flag": is_fraud,
        "fraud_score": score,
        "fraud_reasons": flags if is_fraud else [],
    }

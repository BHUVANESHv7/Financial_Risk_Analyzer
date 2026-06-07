"""
bias_monitor.py
───────────────
Layer 5 — Bias Monitoring Module
Audits ML predictions for potential demographic or financial bias
to ensure fair lending practices.
"""

def check_bias(features: dict, risk_result: dict) -> dict:
    """
    Analyzes features and risk result for potential bias.
    Returns bias_flag (bool) and assessment details.
    """
    assessment = []
    bias_score = 0

    income = features.get("monthly_income", 0)
    dependents = features.get("num_dependents", 0)
    risk_level = risk_result.get("risk_level", "MEDIUM")

    # ── Check 1: Dependency Bias ──────────────────────────────────
    # Flag if high number of dependents is causing HIGH risk 
    # even when income is relatively high.
    if dependents >= 4 and risk_level == "HIGH" and income > 50000:
        assessment.append("Potential Dependency Bias: High dependents flagged as High Risk despite stable income.")
        bias_score += 1

    # ── Check 2: Low-Income Sensitivity ───────────────────────────
    # Flag if the model is overly sensitive to lower (but valid) incomes
    if income < 25000 and income >= 15000 and risk_level == "HIGH":
        assessment.append("Low-Income Sensitivity: Applicant is in valid income bracket but flagged as High Risk.")
        bias_score += 1

    # ── Check 3: Feature Dominance — Num Dependents ───────────────
    # If the model's decision is heavily influenced by dependents 
    # (a common proxy for demographic bias)
    if dependents > 3 and risk_level != "LOW":
        # This is a warning, not necessarily a hard bias flag
        assessment.append("Notice: Large family size is significantly impacting the risk score.")

    is_bias_suspected = bias_score >= 1

    return {
        "bias_detected": is_bias_suspected,
        "bias_score": bias_score,
        "assessment": assessment if assessment else ["No significant algorithmic bias detected."],
        "metrics": {
            "dependent_impact": "Medium" if dependents > 2 else "Low",
            "income_parity": "Balanced" if income > 20000 else "Sensitive",
        }
    }

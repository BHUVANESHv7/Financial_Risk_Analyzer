"""
compliance_checker.py
─────────────────────
Layer 4 — Regulatory Compliance Module
Checks that the loan decision follows RBI / fair-lending rules.
"""


def check_compliance(risk_result: dict, features: dict) -> dict:
    """
    Takes risk prediction and features.
    Returns compliant (bool) and list of violations.
    """
    violations = []

    income  = features.get("monthly_income",   0)
    loan    = features.get("loan_amount",       0)
    credit  = features.get("credit_score",      0)
    decision = risk_result.get("decision",    "")

    # ── Rule R1: Minimum income requirement ──────────────────────
    if income < 15000 and decision == "APPROVE":
        violations.append("R1: Income below banking minimum threshold (₹15,000/month)")

    # ── Rule R2: Combined DSR (Debt Service Ratio) limit ──────────
    # Existing EMIs + New Estimated EMI should not exceed 50% of income
    existing_emis = features.get("existing_emis", 0)
    new_emi = _estimate_emi(loan)
    total_obligation = existing_emis + new_emi
    
    if income > 0 and (total_obligation / income) > 0.5:
        violations.append(f"R2: Combined debt-to-income ratio ({ (total_obligation/income)*100 :.1f}%) exceeds 50% limit")

    # ── Rule R3: Minimum credit score for approval ────────────────
    if credit < 600 and decision == "APPROVE":
        violations.append("R3: Credit score below minimum 600 for safe approval")

    # ── Rule R4: Loan amount cap (6x annual income) ─────────────
    # Standard banking multiplier for personal/unsecured loans
    annual_income = income * 12
    if annual_income > 0 and loan > annual_income * 6:
        violations.append(f"R4: Loan exceeds 6x annual income cap (Limit: ₹{annual_income * 6:,.0f})")

    # ── Rule R5: Employment check for large loans ─────────────────
    years = features.get("employment_years", 0)
    if loan > 1000000 and years < 2 and decision == "APPROVE":
        violations.append("R5: Large loan (>10L) requires minimum 2 years stable employment")

    is_compliant = len(violations) == 0

    return {
        "compliant":  is_compliant,
        "violations": violations,
    }

def _estimate_emi(principal: float, rate_annual: float = 10.5, years: int = 5) -> float:
    """Simple EMI formula: [P x R x (1+R)^N]/[(1+R)^N-1]"""
    if principal <= 0: return 0
    r = rate_annual / (12 * 100) # monthly interest rate
    n = years * 12               # number of monthly installments
    emi = (principal * r * (1 + r)**n) / ((1 + r)**n - 1)
    return emi

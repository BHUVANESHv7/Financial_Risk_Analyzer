"""
compliance_checker.py
─────────────────────
Layer 4 — Regulatory Compliance Module
Checks that the loan follows RBI / fair-lending style rules.
"""

from finance import ratios


def check_compliance(risk_result: dict, features: dict) -> dict:
    """Returns compliant (bool), violations (list) and rule-by-rule checks."""
    income = float(features.get("monthly_income") or 0)
    loan = float(features.get("loan_amount") or 0)
    credit = float(features.get("credit_score") or 0)
    years = float(features.get("employment_years") or 0)
    approving = risk_result.get("decision") == "APPROVE"
    r = ratios(features)

    checks = [
        ("R1", "Minimum income ₹15,000/month",
         not (approving and income < 15000),
         "Income below banking minimum threshold (₹15,000/month)"),
        ("R2", "Debt-to-income ≤ 50%",
         not (income > 0 and r["dti"] > 0.5),
         f"Combined debt-to-income ratio ({r['dti'] * 100:.1f}%) exceeds 50% limit"),
        ("R3", "Credit score ≥ 600 for approval",
         not (approving and credit < 600),
         "Credit score below minimum 600 for safe approval"),
        ("R4", "Loan ≤ 6× annual income",
         not (income > 0 and loan > income * 12 * 6),
         f"Loan exceeds 6x annual income cap (Limit: ₹{income * 12 * 6:,.0f})"),
        ("R5", "2+ years employment for loans over ₹10L",
         not (approving and loan > 1_000_000 and years < 2),
         "Large loan (>10L) requires minimum 2 years stable employment"),
    ]

    violations = [f"{code}: {msg}" for code, _, ok, msg in checks if not ok]
    return {
        "compliant": not violations,
        "violations": violations,
        "checks": [{"code": c, "rule": rule, "passed": ok} for c, rule, ok, _ in checks],
    }

"""
finance.py
──────────
Small, pure helpers for loan maths shared by every module.
"""

from config import DEFAULT_INTEREST_RATE, DEFAULT_TENURE_MONTHS


def estimate_emi(principal: float,
                 rate_annual: float = DEFAULT_INTEREST_RATE,
                 months: int = DEFAULT_TENURE_MONTHS) -> float:
    """Standard reducing-balance EMI: P·r·(1+r)^n / ((1+r)^n − 1)."""
    if principal <= 0 or months <= 0:
        return 0.0
    r = rate_annual / (12 * 100)
    if r == 0:
        return principal / months
    growth = (1 + r) ** months
    return principal * r * growth / (growth - 1)


def loan_terms(features: dict) -> tuple[float, int]:
    rate = float(features.get("interest_rate") or DEFAULT_INTEREST_RATE)
    months = int(features.get("tenure_months") or DEFAULT_TENURE_MONTHS)
    return rate, months


def ratios(features: dict) -> dict:
    """Key affordability ratios used by the model, rules and the UI."""
    income = float(features.get("monthly_income") or 0)
    loan = float(features.get("loan_amount") or 0)
    emis = float(features.get("existing_emis") or 0)
    rate, months = loan_terms(features)

    new_emi = estimate_emi(loan, rate, months)
    safe_income = max(income, 1.0)
    return {
        "new_emi": round(new_emi, 2),
        "total_obligations": round(emis + new_emi, 2),
        "dti": (emis + new_emi) / safe_income,              # debt-to-income (monthly)
        "existing_emi_ratio": emis / safe_income,
        "loan_to_annual_income": loan / (safe_income * 12),
        "disposable_income": round(income - emis - new_emi, 2),
    }

"""
advisor.py
──────────
"Path to approval" — counterfactual advice.

For an application that would not be auto-approved, finds the *smallest*
single change that flips the decision to APPROVE (borrow less, choose a
longer tenure, clear existing EMIs, add co-applicant income, raise the
credit score). For an approvable one, finds the largest loan that would
still be approved on the same terms.

Every candidate is scored with the real pipeline (model + fraud +
compliance), so the advice can never contradict the actual decision.
The model is monotone, which makes a binary search on each lever exact.
"""

import numpy as np

from compliance_checker import check_compliance
from finance import ratios
from fraud_detector import check_fraud
from pipeline import assess
from risk_model import LABELS, _make_decision, feature_matrix, get_model, normalise

# Longest tenure we suggest per category (months).
MAX_TENURE = {"Home": 360, "Business": 120, "Education": 120, "Vehicle": 84}
DEFAULT_MAX_TENURE = 84
TENURE_STEPS = [12, 24, 36, 48, 60, 72, 84, 120, 180, 240, 300, 360]

# Lower = easier for the applicant. Used to rank the options.
EFFORT = {"tenure_months": 1, "loan_amount": 2, "existing_emis": 3,
          "monthly_income": 4, "credit_score": 5}

# Server-set signals that must never feed into what-if advice.
_SERVER_ONLY = ("recent_applications", "similar_recent_applications")


def _decision(f: dict, risk_level: str) -> str:
    """Same decision logic as pipeline.assess, given a model risk level."""
    r = ratios(f)
    decision = _make_decision(risk_level, f, r)
    if check_fraud(f)["fraud_flag"]:
        return "REJECT"
    if decision == "APPROVE" and not check_compliance({"decision": decision}, f)["compliant"]:
        return "MANUAL REVIEW"
    return decision


def _approves_batch(f: dict, key: str, values) -> np.ndarray:
    """Which of these values for one lever give APPROVE? One model call for all."""
    rows = [normalise({**f, key: float(v)}) for v in values]
    raw = [[x["monthly_income"], x["loan_amount"], x["existing_emis"], x["employment_years"],
            x["credit_score"], x["num_dependents"], int(x.get("tenure_months") or 60),
            float(x.get("interest_rate") or 10.5)] for x in rows]
    levels = np.array(LABELS)[get_model().predict_proba(feature_matrix(np.array(raw))).argmax(1)]
    return np.array([_decision(x, lvl) == "APPROVE" for x, lvl in zip(rows, levels)])


def _approves(f: dict) -> bool:
    return assess(f)["decision"] == "APPROVE"


def _with(f: dict, **change) -> dict:
    return {**f, **change}


def _search(f: dict, key: str, lo: float, hi: float, want_high: bool, step: float):
    """
    Search one lever with two batched passes (coarse grid, then fine grid).
    want_high=True  → smallest value in [lo, hi] that approves (e.g. income).
    want_high=False → largest  value in [lo, hi] that approves (e.g. loan).
    Returns None if no value in the range approves.
    """
    if hi <= lo:
        return None
    for _ in range(2):
        grid = np.linspace(lo, hi, 64)
        ok = _approves_batch(f, key, grid)
        if not ok.any():
            return None
        if want_high:
            i = int(np.argmax(ok))                       # first approving value
            lo, hi = (grid[i - 1] if i else grid[0]), grid[i]
            good = hi
        else:
            i = len(ok) - 1 - int(np.argmax(ok[::-1]))   # last approving value
            lo, hi = grid[i], (grid[i + 1] if i + 1 < len(grid) else grid[i])
            good = lo
        if hi - lo <= step:
            break
    # Round towards the safe side so the suggestion definitely approves.
    rounded = float((-(-good // step) * step) if want_high else (good // step) * step)
    return rounded if _approves(_with(f, **{key: rounded})) else float(good)


def _option(f: dict, key: str, value: float, title: str, detail: str) -> dict:
    result = assess(_with(f, **{key: value}))
    return {
        "key": key,
        "value": value,
        "title": title,
        "detail": detail,
        "effort": EFFORT[key],
        "new_risk_score": result["risk_score"],
        "new_risk_level": result["risk_level"],
        "new_emi": result["ratios"]["new_emi"],
    }


def _inr(v: float) -> str:
    return f"₹{v:,.0f}"


def approval_path(features: dict) -> dict:
    f = {k: v for k, v in features.items() if k not in _SERVER_ONLY}
    base = assess(f)
    f = base["features"]
    income = float(f["monthly_income"])
    loan = float(f["loan_amount"])
    emis = float(f["existing_emis"])
    credit = float(f["credit_score"])
    tenure = int(f.get("tenure_months") or 60)
    category = f.get("loan_category") or "Personal"

    out = {
        "decision": base["decision"],
        "risk_score": base["risk_score"],
        "qualifies": base["decision"] == "APPROVE",
        "fraud_blocked": base["fraud_flag"],
        "max_loan_amount": None,
        "options": [],
    }

    if base["fraud_flag"]:
        out["message"] = ("This application was flagged for possible fraud, so it needs a "
                          "bank officer's review. Changing the numbers will not help.")
        return out

    if out["qualifies"]:
        # Headroom: the biggest loan still auto-approved on these terms (R4 cap 6× annual).
        cap = max(loan, income * 12 * 6)
        best = _search(f, "loan_amount", loan, cap, want_high=False, step=1000)
        out["max_loan_amount"] = best
        out["has_headroom"] = bool(best and best > loan)
        out["message"] = (f"You qualify. On these terms you could borrow up to {_inr(best)}."
                          if best and best > loan else "You qualify for this loan.")
        return out

    options = []

    best_loan = _search(f, "loan_amount", 10_000, loan, want_high=False, step=1000)
    if best_loan is not None and best_loan < loan:
        options.append(_option(
            f, "loan_amount", best_loan, f"Borrow {_inr(best_loan)}",
            f"{_inr(loan - best_loan)} less than requested ({(1 - best_loan / loan) * 100:.0f}% lower)."))
    out["max_loan_amount"] = best_loan

    max_tenure = MAX_TENURE.get(category, DEFAULT_MAX_TENURE)
    longer = [m for m in TENURE_STEPS if tenure < m <= max_tenure]
    ok = _approves_batch(f, "tenure_months", longer) if longer else []
    for months, approved in zip(longer, ok):
        if approved:
            years = months / 12
            options.append(_option(
                f, "tenure_months", months, f"Repay over {months} months",
                f"{years:g} years instead of {tenure} months lowers each EMI. "
                "You pay more interest in total."))
            break

    if emis > 0:
        keep = _search(f, "existing_emis", 0, emis, want_high=False, step=500)
        if keep is not None and keep < emis:
            options.append(_option(
                f, "existing_emis", keep, f"Clear {_inr(emis - keep)}/month of existing EMIs",
                "Close or prepay a current loan so your EMIs drop to "
                f"{_inr(keep)}/month before applying."))

    need = _search(f, "monthly_income", income, max(income * 3, 15_000), want_high=True, step=1000)
    if need is not None and need > income:
        options.append(_option(
            f, "monthly_income", need, f"Add {_inr(need - income)}/month of income",
            "For example, apply with a co-applicant (spouse or parent) whose income counts."))

    score = _search(f, "credit_score", credit, 900, want_high=True, step=5)
    if score is not None and score > credit:
        options.append(_option(
            f, "credit_score", score, f"Raise your credit score to {score:.0f}",
            "Pay every bill on time and keep card usage under 30%. "
            "This usually takes 6–12 months."))

    options.sort(key=lambda o: (o["effort"], o["new_risk_score"]))
    out["options"] = options
    if options:
        out["message"] = (f"Any one of these {len(options)} changes would get this loan "
                          "approved automatically." if len(options) > 1 else
                          "This change would get the loan approved automatically.")
    else:
        out["message"] = ("No single change gets automatic approval. A bank officer can "
                          "still review the application.")
    return out

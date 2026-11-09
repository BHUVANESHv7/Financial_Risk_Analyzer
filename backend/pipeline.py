"""
pipeline.py
───────────
Runs ML → fraud → compliance → bias on a set of features and returns
one complete risk report. Used by both the upload flow and the live
"what-if" recalculation so the logic lives in exactly one place.
"""

from bias_monitor import check_bias
from compliance_checker import check_compliance
from fraud_detector import check_fraud
from risk_model import normalise, predict_risk


def assess(features: dict) -> dict:
    f = normalise(features)
    risk = predict_risk(f)
    fraud = check_fraud(f)
    compliance = check_compliance(risk, f)
    bias = check_bias(f, risk)

    decision = risk["decision"]
    if fraud["fraud_flag"]:
        decision = "REJECT"
    elif not compliance["compliant"] and decision == "APPROVE":
        # Never auto-approve an application that breaks a lending rule.
        decision = "MANUAL REVIEW"

    summary = build_summary(f, risk, fraud, compliance, decision)
    summary += f" (Bias Status: {'WARNING' if bias['bias_detected'] else 'PASS'})"

    return {
        "applicant_name": f.get("applicant_name") or "Unknown Applicant",
        "risk_level": risk["risk_level"],
        "risk_score": risk["risk_score"],
        "decision": decision,
        "confidence": risk["confidence"],
        "probabilities": risk["probabilities"],
        "factors": risk["factors"],
        "ratios": risk["ratios"],
        "monthly_income": f["monthly_income"],
        "loan_amount": f["loan_amount"],
        "existing_emis": f["existing_emis"],
        "credit_score": f["credit_score"],
        "fraud_flag": fraud["fraud_flag"],
        "fraud_score": fraud["fraud_score"],
        "fraud_reasons": fraud["fraud_reasons"],
        "fraud_warnings": fraud["warnings"],
        "compliant": compliance["compliant"],
        "violations": compliance["violations"],
        "compliance_checks": compliance["checks"],
        "bias_report": bias,
        "report_summary": summary,
        "features": f,
    }


def build_summary(features, risk, fraud, compliance, decision) -> str:
    income = features.get("monthly_income", 0)
    loan = features.get("loan_amount", 0)
    credit = features.get("credit_score", 0)
    years = features.get("employment_years", 0)

    parts = [
        f"Applicant earns ₹{income:,.0f}/month with {years:.0f} years of employment.",
        f"Requested loan amount: ₹{loan:,.0f} (estimated EMI ₹{risk['ratios']['new_emi']:,.0f}).",
        f"Credit score: {credit:.0f}.",
        f"Risk level assessed as {risk['risk_level']} "
        f"(score {risk['risk_score']:.0f}/100, confidence {risk['confidence'] * 100:.1f}%).",
    ]
    if fraud["fraud_flag"]:
        parts.append("FRAUD ALERT: Suspicious patterns detected — "
                     + "; ".join(fraud["fraud_reasons"]) + ".")
    else:
        parts.append("No fraud indicators found.")
    if compliance["compliant"]:
        parts.append("Application is regulatory compliant.")
    else:
        parts.append("Compliance issues: " + "; ".join(compliance["violations"]) + ".")
    parts.append(f"Final decision: {decision}.")
    return " ".join(parts)

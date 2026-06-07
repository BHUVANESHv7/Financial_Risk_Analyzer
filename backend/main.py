"""
main.py
───────
FastAPI Backend — AI Financial Risk Analyzer
Receives uploaded document from Flutter, runs NLP + ML + Fraud + Compliance,
returns a complete JSON risk report.

Run with:
    uvicorn main:app --reload --host 0.0.0.0 --port 8000
"""

import os
import shutil
import uuid
from datetime import timedelta

from fastapi import FastAPI, UploadFile, File, HTTPException, Depends, status
from fastapi.middleware.cors import CORSMiddleware
from fastapi.security import OAuth2PasswordRequestForm
from sqlalchemy.orm import Session

from nlp_parser import extract_features
from risk_model import predict_risk
from fraud_detector import check_fraud
from compliance_checker import check_compliance
from bias_monitor import check_bias
from database import init_db, get_db, LoanAnalysis, User
from auth import (
    get_current_user,
    get_password_hash,
    verify_password,
    create_access_token,
    ACCESS_TOKEN_EXPIRE_MINUTES,
)

# ── App setup ─────────────────────────────────────────────────────────────────

app = FastAPI(
    title="AI Financial Risk Analyzer",
    description="Loan risk assessment API using NLP + ML",
    version="1.0.0",
)

# ── CORS — allow Flutter app to call this API ─────────────────────────────────
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],   # In production: set to your Flutter app's domain
    allow_methods=["*"],
    allow_headers=["*"],
)

UPLOAD_DIR = "uploads"
os.makedirs(UPLOAD_DIR, exist_ok=True)


# ── Startup ───────────────────────────────────────────────────────────────────

@app.on_event("startup")
def startup_event():
    init_db()


# ── Health check ──────────────────────────────────────────────────────────────

@app.get("/health")
def health():
    """Flutter calls this to show the green 'Server online' dot."""
    return {"status": "online", "service": "AI Loan Risk Analyzer"}


# ── History ───────────────────────────────────────────────────────────────────

@app.get("/history")
def get_history(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """
    Retrieve analysis history.
    - Applicants see only their own history.
    - Admins see everything.
    """
    query = db.query(LoanAnalysis)

    if current_user.role != "ADMIN":
        query = query.filter(LoanAnalysis.user_id == current_user.id)

    records = query.order_by(LoanAnalysis.timestamp.desc()).limit(50).all()

    result = []
    for r in records:
        result.append({
            "id":               r.id,
            "applicant_name":   r.applicant_name,
            "timestamp":        r.timestamp.isoformat() if r.timestamp else None,
            "risk_level":       r.risk_level,
            "decision":         r.decision,
            "confidence":       r.confidence,
            "monthly_income":   r.monthly_income,
            "loan_amount":      r.loan_amount,
            "credit_score":     r.credit_score,
            "existing_emis":    r.existing_emis,
            "fraud_flag":       r.fraud_flag,
            "compliant":        r.compliant,
            "report_summary":   r.report_summary,
        })
    return result


# ── Auth Endpoints ────────────────────────────────────────────────────────────

@app.post("/register")
async def register(user_data: dict, db: Session = Depends(get_db)):
    """Create a new user account."""
    email    = user_data.get("email")
    password = user_data.get("password")
    role_raw = user_data.get("role", "APPLICANT")
    role     = (role_raw if role_raw else "APPLICANT").upper()

    if not email or not password:
        raise HTTPException(status_code=400, detail="Email and password required")

    existing = db.query(User).filter(User.email == email).first()
    if existing:
        raise HTTPException(status_code=400, detail="Email already registered")

    new_user = User(
        email=email,
        hashed_password=get_password_hash(password),
        role=role,
    )
    db.add(new_user)
    db.commit()
    return {"message": "User registered successfully"}


@app.post("/login")
async def login(
    form_data: OAuth2PasswordRequestForm = Depends(),
    db: Session = Depends(get_db)
):
    """Authenticates user and returns JWT token."""
    user = db.query(User).filter(User.email == form_data.username).first()
    if not user or not verify_password(form_data.password, user.hashed_password):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Incorrect email or password",
            headers={"WWW-Authenticate": "Bearer"},
        )

    access_token = create_access_token(
        data={"sub": user.email},
        expires_delta=timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES),
    )
    return {
        "access_token": access_token,
        "token_type":   "bearer",
        "role":         user.role,
        "email":        user.email,
    }


# ── Recalculate ───────────────────────────────────────────────────────────────

@app.post("/recalculate")
async def recalculate(features: dict):
    """
    Receives (possibly modified) features.
    Returns full risk assessment JSON without re-running NLP.
    """
    try:
        print("[API] Recalculating risk...")
        risk_result  = predict_risk(features)
        fraud_result = check_fraud(features)
        compliance   = check_compliance(risk_result, features)
        bias_report  = check_bias(features, risk_result)

        final_decision = risk_result["decision"]
        if fraud_result["fraud_flag"]:
            final_decision = "REJECT"
        elif not compliance["compliant"] and risk_result["risk_level"] != "LOW":
            if final_decision == "APPROVE":
                final_decision = "MANUAL REVIEW"

        summary = _build_summary(
            features, risk_result, fraud_result, compliance, final_decision
        )

        return {
            "applicant_name": features.get("applicant_name", "Unknown"),
            "risk_level":     risk_result["risk_level"],
            "decision":       final_decision,
            "confidence":     risk_result["confidence"],
            "monthly_income": features.get("monthly_income", 0),
            "loan_amount":    features.get("loan_amount", 0),
            "existing_emis":  features.get("existing_emis", 0),
            "fraud_flag":     fraud_result["fraud_flag"],
            "fraud_reasons":  fraud_result["fraud_reasons"],
            "compliant":      compliance["compliant"],
            "violations":     compliance["violations"],
            "bias_report":    bias_report,
            "report_summary": summary + f" (Bias Status: {'PASS' if not bias_report['bias_detected'] else 'WARNING'})",
            "features":       features,
        }
    except Exception as e:
        print(f"[API] Recalculate Error: {e}")
        raise HTTPException(status_code=500, detail=str(e))


# ── Analyze Loan ──────────────────────────────────────────────────────────────

@app.post("/analyze-loan")
async def analyze_loan(
    file: UploadFile = File(...),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """
    Accepts a PDF or image file.
    Returns full risk assessment JSON including features for verification.
    """

    # ── Step 1: Validate file type ────────────────────────────────
    allowed = {".pdf", ".jpg", ".jpeg", ".png"}
    ext = os.path.splitext(file.filename)[1].lower()
    if ext not in allowed:
        raise HTTPException(
            status_code=400,
            detail=f"Unsupported file type '{ext}'. Upload PDF, JPG, or PNG.",
        )

    # ── Step 2: Save file temporarily ─────────────────────────────
    temp_name = f"{uuid.uuid4().hex}{ext}"
    temp_path = os.path.join(UPLOAD_DIR, temp_name)

    try:
        with open(temp_path, "wb") as f:
            shutil.copyfileobj(file.file, f)

        # ── Step 3: NLP ───────────────────────────────────────────
        print(f"[API] Running NLP on {file.filename}...")
        features = extract_features(temp_path)
        print(f"[API] Extracted features: {features}")

        # ── Step 4: ML risk prediction ────────────────────────────
        print("[API] Running ML risk prediction...")
        risk_result = predict_risk(features)
        print(f"[API] Risk result: {risk_result}")

        # ── Step 5: Fraud detection ───────────────────────────────
        print("[API] Running fraud detection...")
        fraud_result = check_fraud(features)
        print(f"[API] Fraud result: {fraud_result}")

        # ── Step 6: Compliance check ──────────────────────────────
        print("[API] Running compliance check...")
        compliance = check_compliance(risk_result, features)
        print(f"[API] Compliance: {compliance}")

        # ── Step 6.1: Bias Monitoring ─────────────────────────────
        print("[API] Running bias monitoring...")
        bias_report = check_bias(features, risk_result)
        print(f"[API] Bias Report: {bias_report}")

        # ── Step 7: Final Decision Logic ──────────────────────────
        final_decision = risk_result["decision"]

        if fraud_result["fraud_flag"]:
            final_decision = "REJECT"
        elif not compliance["compliant"] and risk_result["risk_level"] != "LOW":
            if final_decision == "APPROVE":
                final_decision = "MANUAL REVIEW"

        # ── Step 8: Build report summary ──────────────────────────
        summary = _build_summary(
            features, risk_result, fraud_result, compliance, final_decision
        )

        # ── Step 9: Persist to DB ─────────────────────────────────
        try:
            record = LoanAnalysis(
                user_id=        current_user.id,
                applicant_name= features["applicant_name"],
                monthly_income= features["monthly_income"],
                loan_amount=    features["loan_amount"],
                credit_score=   int(features["credit_score"]),
                existing_emis=  features["existing_emis"],
                risk_level=     risk_result["risk_level"],
                decision=       final_decision,
                confidence=     risk_result["confidence"],
                fraud_flag=     fraud_result["fraud_flag"],
                compliant=      compliance["compliant"],
                report_summary= summary,
            )
            db.add(record)
            db.commit()
            print("[DB] ✅ Analysis saved to MySQL.")
        except Exception as db_err:
            print(f"[DB] ❌ Error saving to DB: {db_err}")

        # ── Step 10: Return response ──────────────────────────────
        return {
            "applicant_name": features["applicant_name"],
            "risk_level":     risk_result["risk_level"],
            "decision":       final_decision,
            "confidence":     risk_result["confidence"],
            "monthly_income": features["monthly_income"],
            "loan_amount":    features["loan_amount"],
            "existing_emis":  features["existing_emis"],
            "fraud_flag":     fraud_result["fraud_flag"],
            "fraud_reasons":  fraud_result["fraud_reasons"],
            "compliant":      compliance["compliant"],
            "violations":     compliance["violations"],
            "bias_report":    bias_report,
            "report_summary": summary + f" (Bias Status: {'PASS' if not bias_report['bias_detected'] else 'WARNING'})",
            "features":       features,
        }

    except Exception as e:
        print(f"[API] Error: {e}")
        raise HTTPException(status_code=500, detail=str(e))

    finally:
        if os.path.exists(temp_path):
            os.remove(temp_path)


# ── Helper ────────────────────────────────────────────────────────────────────

def _build_summary(features, risk, fraud, compliance, decision) -> str:
    income = features.get("monthly_income", 0)
    loan   = features.get("loan_amount", 0)
    credit = features.get("credit_score", 0)
    years  = features.get("employment_years", 0)

    parts = [
        f"Applicant earns ₹{income:,.0f}/month with {years:.0f} years of employment.",
        f"Requested loan amount: ₹{loan:,.0f}.",
        f"Credit score: {credit:.0f}.",
        f"Risk level assessed as {risk['risk_level']} "
        f"(confidence: {risk['confidence']*100:.1f}%).",
    ]

    if fraud["fraud_flag"]:
        parts.append(
            "FRAUD ALERT: Suspicious patterns detected — " +
            "; ".join(fraud["fraud_reasons"]) + "."
        )
    else:
        parts.append("No fraud indicators found.")

    if not compliance["compliant"]:
        parts.append(
            "Compliance issues: " + "; ".join(compliance["violations"]) + "."
        )
    else:
        parts.append("Application is regulatory compliant.")

    parts.append(f"Final decision: {decision}.")
    return " ".join(parts)
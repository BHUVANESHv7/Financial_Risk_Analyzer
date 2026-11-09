"""
Seed demo accounts (and optionally sample applications).

    python seed_final.py            # demo users only
    python seed_final.py --demo     # demo users + ~25 sample applications
"""

import random
import sys
from datetime import timedelta

from auth import get_password_hash
from config import LOAN_CATEGORIES
from database import LoanAnalysis, SessionLocal, User, init_db
from pipeline import assess

DEMO_USERS = [
    ("admin@risk.com", "admin123", "ADMIN", "Bank Officer"),
    ("applicant@risk.com", "password123", "APPLICANT", "Demo Applicant"),
]

NAMES = ["Ravi Kumar", "Priya Sharma", "Arjun Mehta", "Ananya Iyer", "Vikram Singh",
         "Sneha Reddy", "Rahul Verma", "Kavya Nair", "Aditya Rao", "Meera Pillai"]


def seed_users(db):
    for email, pwd, role, name in DEMO_USERS:
        user = db.query(User).filter(User.email == email).first()
        if user:
            print(f"[SEED] {email} exists — resetting password and role")
        else:
            print(f"[SEED] Creating {email}")
            user = User(email=email)
            db.add(user)
        user.hashed_password = get_password_hash(pwd)
        user.role = role
        user.full_name = user.full_name or name
    db.commit()


def seed_applications(db, n=25):
    from main import _now, _status_for  # reuse API helpers

    owner = db.query(User).filter(User.email == "applicant@risk.com").first()
    rng = random.Random(7)
    for i in range(n):
        features = {
            "applicant_name": rng.choice(NAMES),
            "monthly_income": rng.choice([18000, 25000, 42000, 55000, 80000, 120000]),
            "loan_amount": rng.choice([150000, 300000, 600000, 1200000, 2500000]),
            "existing_emis": rng.choice([0, 0, 3000, 8000, 15000]),
            "employment_years": rng.randint(0, 15),
            "credit_score": rng.randint(520, 860),
            "num_dependents": rng.randint(0, 4),
            "loan_category": rng.choice(LOAN_CATEGORIES),
            "tenure_months": rng.choice([24, 36, 60, 84]),
            "interest_rate": 10.5,
        }
        rep = assess(features)
        f = rep["features"]
        db.add(LoanAnalysis(
            user_id=owner.id, applicant_name=rep["applicant_name"],
            timestamp=_now() - timedelta(days=rng.randint(0, 13), hours=rng.randint(0, 23)),
            monthly_income=f["monthly_income"], loan_amount=f["loan_amount"],
            credit_score=int(f["credit_score"]), existing_emis=f["existing_emis"],
            employment_years=f["employment_years"], num_dependents=int(f["num_dependents"]),
            loan_category=f["loan_category"], tenure_months=f["tenure_months"],
            interest_rate=f["interest_rate"], risk_level=rep["risk_level"],
            risk_score=rep["risk_score"], decision=rep["decision"], confidence=rep["confidence"],
            fraud_flag=rep["fraud_flag"], compliant=rep["compliant"],
            report_summary=rep["report_summary"], status=_status_for(rep["decision"]),
            details={k: rep[k] for k in ("probabilities", "factors", "ratios", "fraud_score",
                                         "fraud_reasons", "fraud_warnings", "violations",
                                         "compliance_checks", "bias_report", "features")},
        ))
    db.commit()
    print(f"[SEED] Added {n} sample applications")


if __name__ == "__main__":
    init_db()
    session = SessionLocal()
    try:
        seed_users(session)
        if "--demo" in sys.argv:
            seed_applications(session)
        print("[SUCCESS] Seeding complete.")
    finally:
        session.close()

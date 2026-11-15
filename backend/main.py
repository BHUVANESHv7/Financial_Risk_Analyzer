"""
main.py
───────
FastAPI Backend — AI Financial Risk Analyzer

Flow:
  1. POST /analyze-loan      upload → OCR/NLP → preview report (not saved)
  2. POST /recalculate       live "what-if" while the user edits values (not saved)
  3. POST /applications      submit verified values → saved + pushed live
  4. PATCH /applications/id/review   bank officer approves / rejects → pushed live
  5. POST /advice            "path to approval": smallest change that gets auto-approval
  6. GET  /applications/id/audit     tamper-evident, hash-chained audit trail
  7. GET  /model/health      live data drift (PSI) vs. the training data
  8. WS   /ws                real-time events (first message: {"type":"auth","token":…})

Run with:
    uvicorn main:app --reload --host 0.0.0.0 --port 8000
"""

import asyncio
import json
import os
import tempfile
from contextlib import asynccontextmanager
from datetime import datetime, timedelta, timezone
from typing import Optional

from fastapi import (
    Depends, FastAPI, File, HTTPException, Query, Request, UploadFile, WebSocket,
    WebSocketDisconnect, status,
)
from fastapi.responses import Response
from fastapi.concurrency import run_in_threadpool
from fastapi.middleware.cors import CORSMiddleware
from fastapi.security import OAuth2PasswordRequestForm
from sqlalchemy import func, or_
from sqlalchemy.orm import Session

import audit
import config
from advisor import approval_path
from auth import (
    create_access_token, get_current_user, get_password_hash, require_admin,
    user_from_token, verify_password,
)
from database import LoanAnalysis, SessionLocal, User, engine, get_db, init_db
from monitoring import drift_report
from pipeline import assess
from realtime import Client, manager
from risk_model import MODEL_VERSION, get_model, model_report
from schemas import FeaturesIn, RegisterIn, ReviewIn
from security import SECURITY_HEADERS, csv_safe, login_limiter, register_limiter


@asynccontextmanager
async def lifespan(_: FastAPI):
    init_db()
    with SessionLocal() as db:
        audit.backfill(db)
    await run_in_threadpool(get_model)  # warm the model so the first request is fast
    yield


app = FastAPI(
    title="AI Financial Risk Analyzer",
    description="Loan risk assessment API using NLP + ML, with live updates",
    version="2.0.0",
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=config.CORS_ORIGINS,
    allow_methods=["*"],
    allow_headers=["*"],
    expose_headers=["Content-Disposition", "Retry-After"],  # readable by the web app
)


@app.middleware("http")
async def add_security_headers(request: Request, call_next):
    response = await call_next(request)
    for key, value in SECURITY_HEADERS.items():
        response.headers.setdefault(key, value)
    return response


def _client_ip(request: Request) -> str:
    return request.client.host if request.client else "unknown"


def _now():
    return datetime.now(timezone.utc).replace(tzinfo=None)


def _iso(dt: Optional[datetime]) -> Optional[str]:
    # Stored as naive UTC; mark it so clients convert to local time correctly.
    return dt.replace(tzinfo=timezone.utc).isoformat() if dt else None


# ── Serialisation ─────────────────────────────────────────────────────────────

def serialize(r: LoanAnalysis, full: bool = False) -> dict:
    out = {
        "id": r.id,
        "user_id": r.user_id,
        "applicant_email": r.owner.email if r.owner else None,
        "applicant_name": r.applicant_name,
        "timestamp": _iso(r.timestamp),
        "risk_level": r.risk_level,
        "risk_score": r.risk_score,
        "decision": r.decision,
        "status": r.status or "PENDING",
        "confidence": r.confidence,
        "monthly_income": r.monthly_income,
        "loan_amount": r.loan_amount,
        "credit_score": r.credit_score,
        "existing_emis": r.existing_emis,
        "loan_category": r.loan_category,
        "tenure_months": r.tenure_months,
        "fraud_flag": r.fraud_flag,
        "compliant": r.compliant,
        "reviewer_notes": r.reviewer_notes,
        "reviewer_email": r.reviewer.email if r.reviewer else None,
        "reviewed_at": _iso(r.reviewed_at),
    }
    if full:
        out["report_summary"] = r.report_summary
        out.update(r.details or {})
    return out


def _status_for(decision: str) -> str:
    return {"APPROVE": "APPROVED", "REJECT": "REJECTED"}.get(decision, "PENDING")


# ── Health & metadata ─────────────────────────────────────────────────────────

@app.get("/health")
def health():
    return {
        "status": "online",
        "service": "AI Loan Risk Analyzer",
        "database": engine.url.get_backend_name(),
        "model_version": MODEL_VERSION,
        "live_connections": manager.count,
    }


@app.get("/model")
def model_info():
    """Algorithm, training data and held-out test metrics of the live model."""
    return model_report()


@app.get("/model/health")
def model_health(window: int = Query(500, ge=30, le=5000), db: Session = Depends(get_db),
                 _: User = Depends(require_admin)):
    """Data drift of recent applications vs. the training data (officers)."""
    return drift_report(db, window)


@app.get("/meta")
def meta():
    return {
        "loan_categories": config.LOAN_CATEGORIES,
        "default_interest_rate": config.DEFAULT_INTEREST_RATE,
        "default_tenure_months": config.DEFAULT_TENURE_MONTHS,
        "max_upload_mb": config.MAX_UPLOAD_MB,
        "officer_signup_enabled": bool(config.ADMIN_INVITE_CODE),
    }


# ── Auth ──────────────────────────────────────────────────────────────────────

def _too_many(wait: int):
    minutes = max(1, round(wait / 60))
    raise HTTPException(
        status_code=status.HTTP_429_TOO_MANY_REQUESTS,
        detail=f"Too many attempts. Please try again in about {minutes} minute{'s' if minutes > 1 else ''}.",
        headers={"Retry-After": str(wait)},
    )


@app.post("/register", status_code=201)
def register(body: RegisterIn, request: Request, db: Session = Depends(get_db)):
    ip_key = _client_ip(request)
    if wait := register_limiter.retry_after(ip_key):
        _too_many(wait)
    register_limiter.hit(ip_key)
    role = body.role.upper()
    if role == "ADMIN":
        if not config.ADMIN_INVITE_CODE or body.invite_code != config.ADMIN_INVITE_CODE:
            raise HTTPException(403, "A valid officer invite code is required to register as a bank officer")

    if db.query(User).filter(User.email == body.email).first():
        raise HTTPException(400, "Email already registered")

    db.add(User(
        email=body.email,
        full_name=(body.full_name or "").strip() or None,
        hashed_password=get_password_hash(body.password),
        role=role,
    ))
    db.commit()
    return {"message": "User registered successfully"}


@app.post("/login")
def login(request: Request, form_data: OAuth2PasswordRequestForm = Depends(),
          db: Session = Depends(get_db)):
    email = form_data.username.strip().lower()
    key = f"{email}|{_client_ip(request)}"
    if wait := login_limiter.retry_after(key):
        _too_many(wait)

    user = db.query(User).filter(func.lower(User.email) == email).first()
    if not user or not verify_password(form_data.password, user.hashed_password):
        login_limiter.hit(key)  # only failed attempts count
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Incorrect email or password",
            headers={"WWW-Authenticate": "Bearer"},
        )
    login_limiter.reset(key)
    return {
        "access_token": create_access_token({"sub": user.email}),
        "token_type": "bearer",
        "role": user.role,
        "email": user.email,
        "full_name": user.full_name,
    }


@app.get("/me")
def me(user: User = Depends(get_current_user)):
    return {"id": user.id, "email": user.email, "full_name": user.full_name, "role": user.role}


# ── Analysis ──────────────────────────────────────────────────────────────────

async def _save_upload(file: UploadFile) -> str:
    ext = os.path.splitext(file.filename or "")[1].lower()
    if ext not in config.ALLOWED_EXTENSIONS:
        raise HTTPException(400, f"Unsupported file type '{ext}'. Upload PDF, JPG, or PNG.")

    limit = config.MAX_UPLOAD_MB * 1024 * 1024
    fd, path = tempfile.mkstemp(suffix=ext)
    size = 0
    try:
        with os.fdopen(fd, "wb") as out:
            while chunk := await file.read(1024 * 1024):
                size += len(chunk)
                if size > limit:
                    raise HTTPException(413, f"File is larger than {config.MAX_UPLOAD_MB} MB")
                out.write(chunk)
    except Exception:
        os.remove(path)
        raise
    if size == 0:
        os.remove(path)
        raise HTTPException(400, "The uploaded file is empty")
    return path


@app.post("/analyze-loan")
async def analyze_loan(file: UploadFile = File(...), _: User = Depends(get_current_user)):
    """Extract features from a document and return a preview report (not saved)."""
    path = await _save_upload(file)
    try:
        from nlp_parser import extract_features  # heavy import (spaCy/OCR) — load on demand
        features = await run_in_threadpool(extract_features, path)
    except HTTPException:
        raise
    except RuntimeError as e:  # missing OCR tools etc. — message is user-friendly
        raise HTTPException(422, str(e))
    except Exception as e:  # noqa: BLE001
        print(f"[API] Extraction error: {e}")
        raise HTTPException(422, "Could not read this document. Try a clearer scan or a digital PDF.")
    finally:
        if os.path.exists(path):
            os.remove(path)

    features["source_file"] = file.filename
    features.setdefault("tenure_months", config.DEFAULT_TENURE_MONTHS)
    features.setdefault("interest_rate", config.DEFAULT_INTEREST_RATE)
    features.setdefault("loan_category", "Personal")
    return await run_in_threadpool(assess, features)


@app.post("/recalculate")
async def recalculate(body: FeaturesIn, _: User = Depends(get_current_user)):
    """Live what-if scoring. Fast and side-effect free."""
    return await run_in_threadpool(assess, body.model_dump())


@app.post("/advice")
async def advice(body: FeaturesIn, _: User = Depends(get_current_user)):
    """
    Path to approval: the smallest single change (loan, tenure, EMIs, income,
    credit score) that would get automatic approval — or, if it already
    qualifies, the largest loan that would still be approved.
    """
    return await run_in_threadpool(approval_path, body.model_dump())


@app.post("/applications", status_code=201)
async def submit_application(
    body: FeaturesIn,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    """Score the verified values, save them, and notify officers live."""
    features = body.model_dump()
    # Server-side velocity signals for fraud detection.
    since = _now() - timedelta(hours=24)
    recent = db.query(LoanAnalysis.loan_amount).filter(
        LoanAnalysis.user_id == user.id, LoanAnalysis.timestamp >= since,
        or_(LoanAnalysis.status.is_(None), LoanAnalysis.status != "WITHDRAWN"),
    ).all()
    features["recent_applications"] = len(recent)
    features["similar_recent_applications"] = sum(
        1 for (amount,) in recent
        if amount and abs(amount - body.loan_amount) <= 0.1 * max(body.loan_amount, 1)
    )
    report = await run_in_threadpool(assess, features)
    f = report["features"]

    record = LoanAnalysis(
        user_id=user.id,
        applicant_name=report["applicant_name"],
        monthly_income=f["monthly_income"],
        loan_amount=f["loan_amount"],
        credit_score=int(f["credit_score"]),
        existing_emis=f["existing_emis"],
        employment_years=f["employment_years"],
        num_dependents=int(f["num_dependents"]),
        loan_category=f.get("loan_category"),
        tenure_months=f.get("tenure_months"),
        interest_rate=f.get("interest_rate"),
        source_file=f.get("source_file"),
        risk_level=report["risk_level"],
        risk_score=report["risk_score"],
        decision=report["decision"],
        confidence=report["confidence"],
        fraud_flag=report["fraud_flag"],
        compliant=report["compliant"],
        report_summary=report["report_summary"],
        status=_status_for(report["decision"]),
        details={k: report[k] for k in (
            "probabilities", "factors", "ratios", "fraud_score", "fraud_reasons",
            "fraud_warnings", "violations", "compliance_checks", "bias_report", "features",
        )},
    )
    db.add(record)
    db.commit()
    db.refresh(record)

    audit.record_event(db, record, "CREATED", user)
    data = serialize(record, full=True)
    await manager.notify_application("application.created", serialize(record))
    return data


def _scoped(db: Session, user: User):
    q = db.query(LoanAnalysis)
    if user.role != "ADMIN":
        q = q.filter(LoanAnalysis.user_id == user.id)
    return q


@app.get("/applications")
def list_applications(
    status_: Optional[str] = Query(None, alias="status"),
    risk: Optional[str] = None,
    q: Optional[str] = None,
    fraud: Optional[bool] = None,
    limit: int = Query(50, ge=1, le=200),
    offset: int = Query(0, ge=0),
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    query = _scoped(db, user)
    if status_:
        query = query.filter(LoanAnalysis.status == status_.upper())
    if risk:
        query = query.filter(LoanAnalysis.risk_level == risk.upper())
    if fraud is not None:
        query = query.filter(LoanAnalysis.fraud_flag == fraud)
    if q:
        like = f"%{q.strip()}%"
        query = query.outerjoin(User, LoanAnalysis.user_id == User.id).filter(
            or_(LoanAnalysis.applicant_name.ilike(like), User.email.ilike(like))
        )
    total = query.count()
    rows = query.order_by(LoanAnalysis.timestamp.desc(), LoanAnalysis.id.desc()) \
        .offset(offset).limit(limit).all()
    return {"total": total, "items": [serialize(r) for r in rows]}


@app.get("/history")
def history(db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    """Backwards-compatible alias: latest 50 applications as a plain list."""
    rows = _scoped(db, user).order_by(LoanAnalysis.timestamp.desc()).limit(50).all()
    return [serialize(r, full=True) for r in rows]


EXPORT_COLUMNS = [
    "id", "timestamp", "applicant_name", "applicant_email", "loan_category", "loan_amount",
    "monthly_income", "existing_emis", "credit_score", "tenure_months", "risk_level",
    "risk_score", "decision", "status", "fraud_flag", "compliant", "reviewer_email",
    "reviewed_at", "reviewer_notes",
]


@app.get("/applications/export")
def export_applications(
    status_: Optional[str] = Query(None, alias="status"),
    risk: Optional[str] = None,
    fraud: Optional[bool] = None,
    db: Session = Depends(get_db),
    officer: User = Depends(require_admin),
):
    """CSV of applications matching the filters (officers only)."""
    import csv
    import io

    query = _scoped(db, officer)
    if status_:
        query = query.filter(LoanAnalysis.status == status_.upper())
    if risk:
        query = query.filter(LoanAnalysis.risk_level == risk.upper())
    if fraud is not None:
        query = query.filter(LoanAnalysis.fraud_flag == fraud)

    buf = io.StringIO()
    writer = csv.writer(buf)
    writer.writerow(EXPORT_COLUMNS)
    for r in query.order_by(LoanAnalysis.timestamp.desc()).limit(10_000):
        row = serialize(r)
        writer.writerow([csv_safe(row.get(c)) for c in EXPORT_COLUMNS])
    filename = f"applications_{_now():%Y%m%d_%H%M}.csv"
    return Response(
        content="﻿" + buf.getvalue(),  # BOM so Excel reads ₹ and names correctly
        media_type="text/csv; charset=utf-8",
        headers={"Content-Disposition": f'attachment; filename="{filename}"'},
    )


def _get_owned(app_id: int, db: Session, user: User) -> LoanAnalysis:
    record = db.get(LoanAnalysis, app_id)
    if not record or (user.role != "ADMIN" and record.user_id != user.id):
        raise HTTPException(404, "Application not found")
    return record


@app.get("/applications/{app_id}")
def get_application(app_id: int, db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    return serialize(_get_owned(app_id, db, user), full=True)


@app.get("/applications/{app_id}/audit")
def application_audit(app_id: int, db: Session = Depends(get_db),
                      user: User = Depends(get_current_user)):
    """Every recorded change to this application, each with its hash-chain check."""
    _get_owned(app_id, db, user)
    events = audit.events_for(db, app_id)
    return {"application_id": app_id, "events": events,
            "verified": all(e["verified"] for e in events)}


@app.get("/audit/verify")
def verify_audit(db: Session = Depends(get_db), _: User = Depends(require_admin)):
    """Re-hash the entire ledger and report the first broken link, if any."""
    return audit.verify_chain(db)


@app.patch("/applications/{app_id}/review")
async def review_application(
    app_id: int,
    body: ReviewIn,
    db: Session = Depends(get_db),
    officer: User = Depends(require_admin),
):
    record = _get_owned(app_id, db, officer)
    if record.status == "WITHDRAWN":
        raise HTTPException(409, "The applicant has withdrawn this application")
    record.status = body.status
    record.reviewer_notes = (body.notes or "").strip() or None
    record.reviewer_id = officer.id
    record.reviewed_at = _now()
    db.commit()
    db.refresh(record)
    audit.record_event(db, record, "REVIEWED", officer)

    await manager.notify_application("application.updated", serialize(record))
    return serialize(record, full=True)


@app.post("/applications/{app_id}/withdraw")
async def withdraw_application(app_id: int, db: Session = Depends(get_db),
                               user: User = Depends(get_current_user)):
    """Applicant cancels their own application while it is still pending."""
    record = db.get(LoanAnalysis, app_id)
    if not record or record.user_id != user.id:
        raise HTTPException(404, "Application not found")
    if record.status != "PENDING":
        raise HTTPException(409, "Only pending applications can be withdrawn")
    record.status = "WITHDRAWN"
    db.commit()
    db.refresh(record)
    audit.record_event(db, record, "WITHDRAWN", user)
    await manager.notify_application("application.updated", serialize(record))
    return serialize(record, full=True)


# ── Stats ─────────────────────────────────────────────────────────────────────

@app.get("/stats")
def stats(days: int = Query(14, ge=1, le=90), db: Session = Depends(get_db),
          user: User = Depends(get_current_user)):
    base = _scoped(db, user)

    def grouped(col):
        rows = base.with_entities(col, func.count()).group_by(col).all()
        return {(k or "UNKNOWN"): n for k, n in rows}

    total = base.count()
    by_status = grouped(LoanAnalysis.status)
    agg = base.with_entities(
        func.avg(LoanAnalysis.risk_score),
        func.avg(LoanAnalysis.credit_score),
        func.sum(LoanAnalysis.loan_amount),
    ).one()
    fraud = base.filter(LoanAnalysis.fraud_flag.is_(True)).count()

    since = _now() - timedelta(days=days - 1)
    day = func.date(LoanAnalysis.timestamp)
    trend_rows = base.filter(LoanAnalysis.timestamp >= since.replace(hour=0, minute=0, second=0)) \
        .with_entities(day, LoanAnalysis.status, func.count()) \
        .group_by(day, LoanAnalysis.status).all()
    trend = {}
    for i in range(days):
        d = (since + timedelta(days=i)).date().isoformat()
        trend[d] = {"date": d, "total": 0, "APPROVED": 0, "REJECTED": 0, "PENDING": 0}
    for d, st, n in trend_rows:
        key = str(d)[:10]
        if key in trend:
            trend[key]["total"] += n
            trend[key][st or "PENDING"] = trend[key].get(st or "PENDING", 0) + n

    decided = by_status.get("APPROVED", 0) + by_status.get("REJECTED", 0)
    return {
        "total": total,
        "by_status": by_status,
        "by_risk": grouped(LoanAnalysis.risk_level),
        "by_decision": grouped(LoanAnalysis.decision),
        "by_category": grouped(LoanAnalysis.loan_category),
        "pending": by_status.get("PENDING", 0),
        "fraud_alerts": fraud,
        "approval_rate": round(by_status.get("APPROVED", 0) / decided, 3) if decided else None,
        "avg_risk_score": round(agg[0], 1) if agg[0] is not None else None,
        "avg_credit_score": round(agg[1]) if agg[1] is not None else None,
        "total_requested": agg[2] or 0,
        "trend": list(trend.values()),
        **manager.presence(),
    }


# ── WebSocket ─────────────────────────────────────────────────────────────────

@app.websocket("/ws")
async def websocket_endpoint(ws: WebSocket):
    """
    Clients authenticate with their first message: {"type": "auth", "token": "<jwt>"}.
    (Keeping the token out of the URL keeps it out of server/proxy logs.)
    """
    await ws.accept()
    try:
        first = await asyncio.wait_for(ws.receive_text(), timeout=10)
        token = json.loads(first).get("token", "")
    except Exception:  # noqa: BLE001 — timeout, bad JSON, disconnect
        token = ""

    db = SessionLocal()
    try:
        user = user_from_token(token, db) if token else None
        identity = (user.id, user.role, user.email) if user else None
    finally:
        db.close()

    if identity is None:
        await ws.close(code=4401)
        return

    client = Client(ws=ws, user_id=identity[0], role=identity[1], email=identity[2])
    await manager.connect(client)
    try:
        while True:
            msg = await ws.receive_text()
            if msg == "ping":
                async with client.lock:
                    await ws.send_text('{"type":"pong"}')
    except WebSocketDisconnect:
        pass
    finally:
        await manager.disconnect(client)

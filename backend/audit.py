"""
audit.py
────────
Tamper-evident audit trail.

Every state change (submitted, reviewed, withdrawn) is appended to a single
SHA-256 hash chain — the same idea as a blockchain ledger, without the
blockchain. Each event's hash covers its content and the previous hash, so
changing, inserting or deleting any past event is detected by verify_chain().

Note: appends are serialised with a process lock. Running several API worker
processes against one database would need a database-level lock instead.
"""

import hashlib
import json
import threading
from datetime import datetime, timezone

from sqlalchemy import true
from sqlalchemy.orm import Session

from database import AuditEvent, LoanAnalysis

GENESIS = "0" * 64
_lock = threading.Lock()


def _now():
    return datetime.now(timezone.utc).replace(tzinfo=None, microsecond=0)


def compute_hash(prev_hash: str, application_id: int, actor_email, action: str,
                 data, timestamp: datetime) -> str:
    payload = json.dumps({
        "prev": prev_hash,
        "application_id": application_id,
        "actor": actor_email,
        "action": action,
        "data": data,
        "ts": timestamp.replace(microsecond=0).isoformat(),
    }, sort_keys=True, separators=(",", ":"), default=str)
    return hashlib.sha256(payload.encode("utf-8")).hexdigest()


def _event_hash(e: AuditEvent) -> str:
    return compute_hash(e.prev_hash, e.application_id, e.actor_email, e.action, e.data, e.timestamp)


def snapshot(record: LoanAnalysis) -> dict:
    """The facts worth proving later: what was decided, on what numbers."""
    return {
        "status": record.status,
        "decision": record.decision,
        "risk_level": record.risk_level,
        "risk_score": record.risk_score,
        "loan_amount": record.loan_amount,
        "monthly_income": record.monthly_income,
        "credit_score": record.credit_score,
        "fraud_flag": bool(record.fraud_flag),
        "notes": record.reviewer_notes,
    }


def record_event(db: Session, record: LoanAnalysis, action: str, actor=None,
                 timestamp: datetime | None = None) -> AuditEvent:
    """Append one event and commit it."""
    with _lock:
        last = db.query(AuditEvent).order_by(AuditEvent.id.desc()).first()
        prev = last.hash if last else GENESIS
        ts = (timestamp or _now()).replace(microsecond=0)
        data = snapshot(record)
        event = AuditEvent(
            application_id=record.id,
            actor_id=getattr(actor, "id", None),
            actor_email=getattr(actor, "email", None),
            actor_role=getattr(actor, "role", None),
            action=action,
            data=data,
            timestamp=ts,
            prev_hash=prev,
        )
        event.hash = compute_hash(prev, record.id, event.actor_email, action, data, ts)
        db.add(event)
        db.commit()
        return event


def verify_chain(db: Session) -> dict:
    """Walk the whole ledger and report the first broken link, if any."""
    prev = GENESIS
    count = 0
    for e in db.query(AuditEvent).order_by(AuditEvent.id).yield_per(500):
        count += 1
        if e.prev_hash != prev:
            return {"valid": False, "events": count, "broken_at": e.id,
                    "reason": "An event is missing or out of order before this one"}
        if _event_hash(e) != e.hash:
            return {"valid": False, "events": count, "broken_at": e.id,
                    "reason": "This event was modified after it was recorded"}
        prev = e.hash
    return {"valid": True, "events": count, "broken_at": None, "head": prev}


def events_for(db: Session, application_id: int) -> list[dict]:
    rows = db.query(AuditEvent).filter(AuditEvent.application_id == application_id) \
        .order_by(AuditEvent.id).all()
    out = []
    for e in rows:
        linked = e.prev_hash == GENESIS or db.query(AuditEvent.id) \
            .filter(AuditEvent.hash == e.prev_hash).first() is not None
        out.append({
            "id": e.id,
            "action": e.action,
            "actor_email": e.actor_email,
            "actor_role": e.actor_role,
            "timestamp": e.timestamp.replace(tzinfo=timezone.utc).isoformat(),
            "data": e.data,
            "hash": e.hash,
            "prev_hash": e.prev_hash,
            "verified": linked and _event_hash(e) == e.hash,
        })
    return out


def backfill(db: Session):
    """Give applications created before the audit trail an IMPORTED event."""
    have = {a for (a,) in db.query(AuditEvent.application_id).distinct()}
    missing = db.query(LoanAnalysis).filter(~LoanAnalysis.id.in_(have) if have else true()) \
        .order_by(LoanAnalysis.timestamp, LoanAnalysis.id).all()
    for r in missing:
        record_event(db, r, "IMPORTED", r.owner, timestamp=r.timestamp)
    if missing:
        print(f"[AUDIT] Backfilled {len(missing)} application(s)")

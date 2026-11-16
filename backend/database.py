"""
database.py
───────────
SQLAlchemy engine, models and session helpers.

Connects to DATABASE_URL, else MySQL, else falls back to a local SQLite file
so the app always starts in development.
"""

import time
from datetime import datetime, timezone

from sqlalchemy import (
    Boolean, Column, DateTime, Float, ForeignKey, Index, Integer, JSON, String, Text,
    create_engine, inspect, text,
)
from sqlalchemy.orm import declarative_base, relationship, sessionmaker

import config


def _utcnow():
    return datetime.now(timezone.utc).replace(tzinfo=None)


def _connect(url: str, attempts: int):
    is_sqlite = url.startswith("sqlite")
    kwargs = {"connect_args": {"check_same_thread": False}} if is_sqlite else {
        "pool_pre_ping": True, "pool_recycle": 300, "pool_size": 5, "max_overflow": 10,
    }
    try:
        eng = create_engine(url, **kwargs)
    except Exception as e:  # noqa: BLE001 — e.g. database driver not installed
        print(f"[DB] Cannot use {url.split(':', 1)[0]}: {type(e).__name__}: {e}")
        return None
    for attempt in range(1, attempts + 1):
        try:
            with eng.connect():
                pass
            print(f"[DB] Connected using {eng.url.get_backend_name()}")
            return eng
        except Exception as e:  # noqa: BLE001
            print(f"[DB] Could not connect to {eng.url.get_backend_name()} "
                  f"(attempt {attempt}/{attempts}): {type(e).__name__}")
            if attempt < attempts:
                time.sleep(min(2 * attempt, 10))
    return None


def _make_engine():
    configured = config.DATABASE_URL or (
        f"mysql+pymysql://{config.DB_USER}:{config.DB_PASS}"
        f"@{config.DB_HOST}:{config.DB_PORT}/{config.DB_NAME}" if config.DB_HOST else ""
    )
    if configured:
        # In production a configured database must be used: silently switching to a
        # local SQLite file would lose data. Retry while the database starts up.
        eng = _connect(configured, attempts=8 if config.IS_PRODUCTION else 1)
        if eng is not None:
            return eng
        if config.IS_PRODUCTION:
            raise RuntimeError("The configured database is unreachable.")
        print("[DB] Falling back to local SQLite (development only).")
    elif config.IS_PRODUCTION:
        print("[DB] WARNING: no DATABASE_URL set — using SQLite. Data is lost if the "
              "server's disk is not persistent.")
    eng = _connect(config.SQLITE_URL, attempts=1)
    if eng is None:
        raise RuntimeError("No database available")
    return eng


engine = _make_engine()
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
Base = declarative_base()


class User(Base):
    __tablename__ = "users"

    id = Column(Integer, primary_key=True, index=True)
    email = Column(String(255), unique=True, index=True)
    full_name = Column(String(255), nullable=True)
    hashed_password = Column(String(255))
    role = Column(String(50), default="APPLICANT")  # APPLICANT or ADMIN
    created_at = Column(DateTime, default=_utcnow, nullable=True)

    analyses = relationship(
        "LoanAnalysis", back_populates="owner", foreign_keys="LoanAnalysis.user_id"
    )


class LoanAnalysis(Base):
    __tablename__ = "loan_analyses"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"), index=True)
    applicant_name = Column(String(255))
    timestamp = Column(DateTime, default=_utcnow, index=True)

    # Financial details
    monthly_income = Column(Float)
    loan_amount = Column(Float)
    credit_score = Column(Integer)
    existing_emis = Column(Float)
    employment_years = Column(Float, nullable=True)
    num_dependents = Column(Integer, nullable=True)
    loan_category = Column(String(50), nullable=True)
    tenure_months = Column(Integer, nullable=True)
    interest_rate = Column(Float, nullable=True)
    source_file = Column(String(255), nullable=True)

    # Model results
    risk_level = Column(String(50), index=True)
    risk_score = Column(Float, nullable=True)        # 0 (safe) … 100 (risky)
    decision = Column(String(50))                    # AI recommendation
    confidence = Column(Float)
    fraud_flag = Column(Boolean, index=True)
    compliant = Column(Boolean)
    report_summary = Column(Text)
    details = Column(JSON, nullable=True)            # factors, violations, bias…

    # Officer review workflow
    status = Column(String(30), default="PENDING", nullable=True, index=True)  # PENDING / APPROVED / REJECTED / WITHDRAWN
    reviewer_id = Column(Integer, ForeignKey("users.id"), nullable=True)
    reviewer_notes = Column(Text, nullable=True)
    reviewed_at = Column(DateTime, nullable=True)

    owner = relationship("User", back_populates="analyses", foreign_keys=[user_id])

    # Speeds up per-user history and the 24h fraud velocity check.
    __table_args__ = (Index("ix_loan_user_time", "user_id", "timestamp"),)
    reviewer = relationship("User", foreign_keys=[reviewer_id])


class AuditEvent(Base):
    """
    Append-only, hash-chained ledger of everything that happens to an application.
    Each row stores the SHA-256 of its own content plus the previous row's hash,
    so editing or deleting any past row breaks the chain (see audit.verify_chain).
    """
    __tablename__ = "audit_events"

    id = Column(Integer, primary_key=True, index=True)
    application_id = Column(Integer, ForeignKey("loan_analyses.id"), index=True)
    actor_id = Column(Integer, ForeignKey("users.id"), nullable=True)
    actor_email = Column(String(255), nullable=True)
    actor_role = Column(String(50), nullable=True)
    action = Column(String(50))                      # CREATED / REVIEWED / WITHDRAWN
    data = Column(JSON, nullable=True)
    timestamp = Column(DateTime, default=_utcnow)
    prev_hash = Column(String(64))
    hash = Column(String(64), unique=True)


def _add_missing_columns():
    """
    Tiny migration helper: create_all() never alters existing tables,
    so add any new nullable columns that older databases are missing.
    """
    insp = inspect(engine)
    for table in Base.metadata.sorted_tables:
        if not insp.has_table(table.name):
            continue
        existing = {c["name"] for c in insp.get_columns(table.name)}
        for col in table.columns:
            if col.name in existing:
                continue
            col_type = col.type.compile(dialect=engine.dialect)
            with engine.begin() as conn:
                conn.execute(text(f"ALTER TABLE {table.name} ADD COLUMN {col.name} {col_type}"))
            print(f"[DB] Added column {table.name}.{col.name}")


def _add_missing_indexes():
    for table in Base.metadata.sorted_tables:
        for index in table.indexes:
            index.create(bind=engine, checkfirst=True)


def init_db():
    Base.metadata.create_all(bind=engine)
    _add_missing_columns()
    _add_missing_indexes()
    # Records created before the review workflow: AI decision is final.
    with engine.begin() as conn:
        conn.execute(text(
            "UPDATE loan_analyses SET status = CASE "
            "WHEN decision = 'APPROVE' THEN 'APPROVED' "
            "WHEN decision = 'REJECT' THEN 'REJECTED' ELSE 'PENDING' END "
            "WHERE status IS NULL"
        ))
    print("[DB] Database ready.")


def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()

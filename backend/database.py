import os
from sqlalchemy import create_engine, Column, Integer, String, Float, Boolean, DateTime, Text, ForeignKey
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import sessionmaker, relationship
from datetime import datetime
from dotenv import load_dotenv

load_dotenv()

DB_HOST = os.getenv("DB_HOST", "localhost")
DB_PORT = os.getenv("DB_PORT", "3306")
DB_USER = os.getenv("DB_USER", "root")
DB_PASS = os.getenv("DB_PASS", "")
DB_NAME = os.getenv("DB_NAME", "loan_analyzer")

# Connection URL for MySQL (requires pymysql)
DATABASE_URL = f"mysql+pymysql://{DB_USER}:{DB_PASS}@{DB_HOST}:{DB_PORT}/{DB_NAME}"

# Add pool_pre_ping to auto-reconnect if connection drops
engine = create_engine(
    DATABASE_URL,
    pool_pre_ping=True,
    pool_recycle=300,
)

SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
Base = declarative_base()


class User(Base):
    __tablename__ = "users"

    id = Column(Integer, primary_key=True, index=True)
    email = Column(String(255), unique=True, index=True)
    hashed_password = Column(String(255))
    role = Column(String(50), default="APPLICANT")  # APPLICANT or ADMIN

    analyses = relationship("LoanAnalysis", back_populates="owner")


class LoanAnalysis(Base):
    __tablename__ = "loan_analyses"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"), index=True)
    applicant_name = Column(String(255))
    timestamp = Column(DateTime, default=datetime.utcnow)

    # Financial Details
    monthly_income = Column(Float)
    loan_amount = Column(Float)
    credit_score = Column(Integer)
    existing_emis = Column(Float)

    # Results
    risk_level = Column(String(50))
    decision = Column(String(50))
    confidence = Column(Float)
    fraud_flag = Column(Boolean)
    compliant = Column(Boolean)

    # Full Report
    report_summary = Column(Text)

    owner = relationship("User", back_populates="analyses")


def init_db():
    try:
        Base.metadata.create_all(bind=engine)
        print("[DB] ✅ Database initialized successfully.")
    except Exception as e:
        print(f"[DB] ❌ Error initializing database: {e}")
        print("[DB] TIP: Make sure MySQL is running and database 'loan_analyzer' exists.")
        print("[DB] Run this in MySQL: CREATE DATABASE IF NOT EXISTS loan_analyzer;")


def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
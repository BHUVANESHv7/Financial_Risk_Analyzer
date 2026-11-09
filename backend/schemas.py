"""
schemas.py
──────────
Request bodies with validation, so bad input is rejected with clear
422 messages instead of crashing deep inside the pipeline.
"""

import re
from typing import Literal, Optional

from pydantic import BaseModel, Field, field_validator

from config import LOAN_CATEGORIES

_EMAIL_RE = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")


class RegisterIn(BaseModel):
    email: str
    password: str = Field(min_length=6, max_length=128)
    full_name: Optional[str] = Field(default=None, max_length=255)
    role: Literal["APPLICANT", "ADMIN", "applicant", "admin"] = "APPLICANT"
    invite_code: Optional[str] = None

    @field_validator("email")
    @classmethod
    def _email(cls, v: str) -> str:
        v = v.strip().lower()
        if not _EMAIL_RE.match(v):
            raise ValueError("Enter a valid email address")
        return v


class FeaturesIn(BaseModel):
    applicant_name: Optional[str] = Field(default=None, max_length=255)
    monthly_income: float = Field(ge=0, le=100_000_000)
    loan_amount: float = Field(ge=0, le=10_000_000_000)
    existing_emis: float = Field(default=0, ge=0, le=100_000_000)
    employment_years: float = Field(default=1, ge=0, le=60)
    credit_score: float = Field(default=650, ge=300, le=900)
    num_dependents: float = Field(default=1, ge=0, le=20)
    loan_category: Optional[str] = "Personal"
    tenure_months: int = Field(default=60, ge=3, le=360)
    interest_rate: float = Field(default=10.5, ge=0, le=40)
    raw_text_length: Optional[int] = None
    source_file: Optional[str] = Field(default=None, max_length=255)

    model_config = {"extra": "ignore"}

    @field_validator("loan_category")
    @classmethod
    def _category(cls, v):
        return v if v in LOAN_CATEGORIES else "Personal"


class ReviewIn(BaseModel):
    status: Literal["APPROVED", "REJECTED", "PENDING"]
    notes: Optional[str] = Field(default=None, max_length=2000)

"""
config.py
─────────
Central place for all environment-driven settings.
Every other module imports from here instead of calling os.getenv directly.
"""

import os
import warnings
from dotenv import load_dotenv

load_dotenv()

# ── Database ──────────────────────────────────────────────────────────────────
# Priority:
#   1. DATABASE_URL (any SQLAlchemy URL, e.g. postgres on Render)
#   2. MySQL built from DB_HOST / DB_USER / ... (original setup)
#   3. Local SQLite file (automatic fallback when MySQL is unreachable)
DATABASE_URL = os.getenv("DATABASE_URL", "").strip()

def _with_driver(url: str) -> str:
    """
    Name the installed driver explicitly. Hosting platforms hand out
    "postgres://" / "postgresql://" URLs, but SQLAlchemy 2.1 maps a bare
    "postgresql://" to psycopg 3, while this app ships psycopg2.
    """
    for prefix in ("postgres://", "postgresql://"):
        if url.startswith(prefix):
            return "postgresql+psycopg2://" + url[len(prefix):]
    if url.startswith("mysql://"):
        return "mysql+pymysql://" + url[len("mysql://"):]
    return url


DATABASE_URL = _with_driver(DATABASE_URL)
DB_HOST = os.getenv("DB_HOST", "")
DB_PORT = os.getenv("DB_PORT", "3306")
DB_USER = os.getenv("DB_USER", "root")
DB_PASS = os.getenv("DB_PASS", "")
DB_NAME = os.getenv("DB_NAME", "loan_analyzer")
_HERE = os.path.dirname(os.path.abspath(__file__))
SQLITE_URL = os.getenv(
    "SQLITE_URL", "sqlite:///" + os.path.join(_HERE, "loan_analyzer.db").replace("\\", "/")
)

# ── Auth ──────────────────────────────────────────────────────────────────────
_DEV_SECRET = "dev-only-secret-change-me"
SECRET_KEY = os.getenv("SECRET_KEY", _DEV_SECRET)
ALGORITHM = os.getenv("ALGORITHM", "HS256")
ACCESS_TOKEN_EXPIRE_MINUTES = int(os.getenv("ACCESS_TOKEN_EXPIRE_MINUTES", 60 * 24))

# Bank-officer (ADMIN) accounts can only be created with this code.
# Leave empty to disable officer self-registration entirely.
ADMIN_INVITE_CODE = os.getenv("ADMIN_INVITE_CODE", "")

ENVIRONMENT = os.getenv("ENV", os.getenv("PYTHON_ENV", "development")).lower()
IS_PRODUCTION = ENVIRONMENT in ("production", "prod")

if SECRET_KEY == _DEV_SECRET or len(SECRET_KEY) < 16:
    if IS_PRODUCTION:
        raise RuntimeError("SECRET_KEY must be set to a long random value in production.")
    warnings.warn("SECRET_KEY is not set — using an insecure development key.")

# Interactive API docs (/docs, /redoc). Off by default in production.
ENABLE_DOCS = os.getenv("ENABLE_DOCS", "false" if IS_PRODUCTION else "true").lower() in ("1", "true", "yes")

# ── Web app ───────────────────────────────────────────────────────────────────
# Folder with the built Flutter web app (flutter build web). When it exists the
# API also serves the web app, so the whole product is a single service/URL.
WEB_DIR = os.getenv("WEB_DIR", os.path.join(_HERE, "..", "flutter_app", "build", "web"))

# ── Uploads ───────────────────────────────────────────────────────────────────
MAX_UPLOAD_MB = int(os.getenv("MAX_UPLOAD_MB", 10))
ALLOWED_EXTENSIONS = {".pdf", ".jpg", ".jpeg", ".png"}

# ── CORS ──────────────────────────────────────────────────────────────────────
CORS_ORIGINS = [o.strip() for o in os.getenv("CORS_ORIGINS", "*").split(",") if o.strip()]

# ── Lending defaults (used for EMI estimates) ─────────────────────────────────
DEFAULT_INTEREST_RATE = float(os.getenv("DEFAULT_INTEREST_RATE", 10.5))   # % per year
DEFAULT_TENURE_MONTHS = int(os.getenv("DEFAULT_TENURE_MONTHS", 60))

LOAN_CATEGORIES = [
    "Personal",
    "Education",
    "Medical",
    "Home Improvement",
    "Debt Consolidation",
    "Business",
    "Vehicle",
]

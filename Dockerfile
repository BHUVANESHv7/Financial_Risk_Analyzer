# syntax=docker/dockerfile:1
#
# One image = the whole product: FastAPI backend + the Flutter web app.
#   docker build -t loan-risk .
#   docker run -p 8000:8000 -e SECRET_KEY=... loan-risk      → http://localhost:8000
#
# ── Stage 1: build the Flutter web app ────────────────────────────────────────
FROM ghcr.io/cirruslabs/flutter:3.41.0 AS web
WORKDIR /src
COPY flutter_app/pubspec.yaml flutter_app/pubspec.lock ./
RUN flutter pub get
COPY flutter_app/ ./
# SAME_ORIGIN: the app calls the API on the domain it is served from.
RUN flutter build web --release --no-tree-shake-icons --dart-define=SAME_ORIGIN=true

# ── Stage 2: API server (also serves the web app) ─────────────────────────────
FROM python:3.11-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    ENV=production \
    PORT=8000 \
    WEB_DIR=/app/web \
    # Trust X-Forwarded-For from the platform's proxy so rate limits see real client IPs.
    FORWARDED_ALLOW_IPS=*

# OCR + PDF tooling for document uploads
RUN apt-get update && apt-get install -y --no-install-recommends \
        tesseract-ocr tesseract-ocr-eng poppler-utils \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY backend/requirements.txt .
RUN pip install -r requirements.txt \
    && python -m spacy download en_core_web_sm

COPY backend/ .
COPY --from=web /src/build/web ./web

# Load the ML model at build time (fails the build if it is broken).
RUN SECRET_KEY=build-only-secret-not-used-at-runtime ENV=development \
    python -c "from risk_model import get_model, predict_risk; get_model(); print(predict_risk({'monthly_income': 50000, 'loan_amount': 300000})['risk_level'])"

# Run as an unprivileged user.
RUN useradd --create-home --uid 1000 app && chown -R app:app /app
USER app

EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=5s --start-period=40s --retries=3 \
    CMD python -c "import os,urllib.request,sys; sys.exit(0 if urllib.request.urlopen(f'http://127.0.0.1:{os.environ.get(\"PORT\",\"8000\")}/health', timeout=4).status == 200 else 1)"

# Single worker on purpose: live updates, rate limits and the audit-chain lock
# are in-process. Scale up (bigger instance), not out (more workers).
CMD ["sh", "-c", "exec uvicorn main:app --host 0.0.0.0 --port ${PORT:-8000} --proxy-headers --timeout-keep-alive 30"]

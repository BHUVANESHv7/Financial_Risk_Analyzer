# AI Financial Risk Analyzer

Loan risk assessment with OCR + NLP document reading, an ML risk model, rule-based
fraud/compliance/bias checks, and **real-time updates** between applicants and bank officers.

```
flutter_app/   Flutter client (web, Android, iOS)
backend/       FastAPI API + WebSocket server
```

## How it works

1. **Applicant uploads** a salary slip / statement (or enters values manually).
2. The backend extracts the numbers (OCR + spaCy) and returns a **preview** score.
3. The applicant corrects any values — the **risk score, decision and key factors update live** as they type.
4. On **submit**, the application is saved and **instantly appears on every officer's dashboard**.
5. Low-risk, compliant applications are auto-approved; high-risk or fraud are auto-rejected;
   everything else goes to the **officer review queue**.
6. When an officer approves or rejects, the **applicant sees it immediately** (WebSocket push).

## Run locally

### Backend

```bash
cd backend
python -m venv venv
venv\Scripts\activate            # macOS/Linux: source venv/bin/activate
pip install -r requirements.txt
python -m spacy download en_core_web_sm
copy .env.example .env           # then edit SECRET_KEY etc.
python seed_final.py --demo      # demo users + sample applications
uvicorn main:app --reload --port 8000
```

No MySQL? The API automatically falls back to a local SQLite file (`backend/loan_analyzer.db`).
Tesseract OCR (and Poppler, for scanned PDFs) must be installed for image/scan uploads;
digital PDFs and manual entry work without them.

Demo accounts (local development only):

| Role        | Email                | Password      |
|-------------|----------------------|---------------|
| Bank officer| `admin@risk.com`     | `admin123`    |
| Applicant   | `applicant@risk.com` | `password123` |

New officer accounts require `ADMIN_INVITE_CODE` (set it in `.env`).

### Flutter app

```bash
cd flutter_app
flutter pub get
flutter run -d chrome
# point at another server:
flutter run --dart-define=API_URL=http://192.168.1.10:8000
```

Defaults: web → `http://127.0.0.1:8000`, Android emulator → `http://10.0.2.2:8000`.

### Docker (backend + MySQL)

```bash
set SECRET_KEY=your-long-random-secret      # macOS/Linux: export SECRET_KEY=...
docker compose up --build
docker compose exec api python seed_final.py --demo
```

### Tests

```bash
cd backend && venv\Scripts\python -m pytest -q     # API, model, security
cd flutter_app && flutter test                      # models, live updates, widgets
```

GitHub Actions runs both suites, `flutter analyze` and a web build on every push.

## Security & safeguards

- **Login protection:** 5 wrong passwords for an account lock it for 15 minutes (per IP);
  sign-ups are limited per IP.
- **Production guard:** the API refuses to start with `ENV=production` and a weak `SECRET_KEY`.
- **Security headers** on every response; WebSocket tokens are sent in a message, not the URL.
- **Fraud velocity checks:** many applications or near-identical re-submissions within 24 hours
  are flagged — catching attempts to probe the live score for an approval.
- **CSV export** neutralises spreadsheet formulas (CSV injection).
- Docker image runs as a non-root user with a health check.

## Risk model

**Ordinal, monotone gradient boosting** (`backend/risk_model.py`, v3):

- Risk levels are ordered, so the model answers two questions — *"at least MEDIUM?"* and
  *"HIGH?"* — each with a `HistGradientBoostingClassifier`.
- **Monotonic constraints** guarantee logical behaviour: a better credit score, higher income or
  longer employment can never raise risk; more debt or a bigger loan can never lower it.
- Trained on 150k synthetic applications labelled by the lending policy, with realistic
  uncertainty near cut-offs so the 0–100 risk score moves smoothly instead of jumping.

Held-out results (20k unseen applications) vs. the previous Random Forest:

| Metric | Previous | Current |
|---|---|---|
| Agreement with lending policy (accuracy) | 95.4% | **99.6%** |
| Macro F1 | 0.947 | **0.996** |
| MEDIUM-risk recall | 92.4% | **99.4%** |
| Illogical score changes (e.g. paying off EMIs raises risk) | up to 9.6% | **0%** |
| Prediction time | 17 ms | **4 ms** |

Full metrics: `backend/model_report.json` or `GET /model`.

### Retrain

```bash
cd backend
venv\Scripts\python train_model.py --cv 5              # synthetic data
venv\Scripts\python train_model.py --data loans.csv     # your real historical data
```

The CSV needs `monthly_income, loan_amount, existing_emis, employment_years, credit_score,
num_dependents, risk_level` (optional `tenure_months`, `interest_rate`). The script compares
against the current model and only replaces it if it scores at least as well (`--force` to override).

> Synthetic labels follow the app's own lending rules, so these numbers measure how faithfully
> the model learns that policy. Real-world accuracy needs real repayment data via `--data`.

## API overview

| Method | Path | Purpose |
|---|---|---|
| POST | `/register`, `/login` | Accounts (JWT) |
| POST | `/analyze-loan` | Upload document → extracted values + preview (not saved) |
| POST | `/recalculate` | Live what-if score (not saved) |
| POST | `/applications` | Submit verified values (saved, pushed live) |
| GET | `/applications` | List with `status`, `risk`, `fraud`, `q`, `limit`, `offset` |
| GET | `/applications/{id}` | Full report |
| PATCH | `/applications/{id}/review` | Officer approves / rejects (pushed live) |
| POST | `/applications/{id}/withdraw` | Applicant withdraws a pending application |
| GET | `/applications/export` | Officer CSV export (same filters as the list) |
| GET | `/stats` | Dashboard KPIs, risk mix, 14-day trend |
| GET | `/model` | Model algorithm and held-out test metrics |
| WS | `/ws` | Live events; first message `{"type":"auth","token":"…"}` |

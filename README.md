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

### Tests

```bash
cd backend
venv\Scripts\python -m pytest -q
```

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
| GET | `/stats` | Dashboard KPIs, risk mix, 14-day trend |
| WS | `/ws` | Live events; first message `{"type":"auth","token":"…"}` |

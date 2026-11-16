# Deploying AI Loan Risk Analyzer

The whole product ships as **one Docker image**: the FastAPI backend also serves the
Flutter web app, so you get a single URL, no CORS setup and no separate frontend hosting.
Live updates (WebSocket) use the same URL.

Every push to `main` builds this image in GitHub Actions, starts it in production mode
against PostgreSQL and runs an end-to-end smoke test (`.github/smoke_test.py`).
If CI is green, the image deploys.

---

## Option A: Render (recommended, free tier available)

1. Push this repository to GitHub (already done).
2. Go to [render.com](https://render.com) → **New → Blueprint** → pick the repository.
   Render reads `render.yaml` and creates:
   - **loan-risk-analyzer**: the web service (Docker)
   - **loan-risk-db**: a PostgreSQL database, connected automatically
   - a random `SECRET_KEY` and a random `ADMIN_INVITE_CODE`
3. Click **Apply** and wait for the first build (about 10 minutes, mostly the Flutter web build).
4. Open the service URL (`https://loan-risk-analyzer-xxxx.onrender.com`).

**Create the first bank-officer account:** in the Render dashboard open the web service →
**Environment** → copy `ADMIN_INVITE_CODE`. Then in the app choose *Create an account →
Bank officer* and enter that code. Applicants sign up without a code.

**Check the deployment** from your computer:

```bash
python .github/smoke_test.py https://YOUR-APP.onrender.com YOUR_ADMIN_INVITE_CODE
```

(It creates two throwaway test accounts and one test application.)

**Free-tier limits to know about**

| Limit | Effect | Fix |
|---|---|---|
| The service sleeps after 15 minutes idle | The first visit afterwards takes ~1 minute | Paid instance ($7/month), or accept it |
| Free PostgreSQL expires after 30 days | **Data is deleted** | Upgrade the database before going live with real users |
| 512 MB RAM | Enough for this app | A bigger instance if many people upload scans at once |

---

## Option B: Any server with Docker (VPS, on-premise)

```bash
git clone https://github.com/BHUVANESHv7/Financial_Risk_Analyzer.git
cd Financial_Risk_Analyzer
```

Create a `.env` file next to `docker-compose.yml`:

```
SECRET_KEY=<output of: python -c "import secrets; print(secrets.token_hex(32))">
ADMIN_INVITE_CODE=<a code you give to bank officers>
POSTGRES_PASSWORD=<a strong password>
```

Start it:

```bash
docker compose up -d --build
```

The app runs at `http://SERVER:8000` with PostgreSQL data kept in a Docker volume.
Put it behind HTTPS (Caddy, Nginx or a cloud load balancer). Browsers only allow the
camera scan on HTTPS, and passwords must never travel over plain HTTP.

Update to a new version:

```bash
git pull
docker compose up -d --build
```

---

## Option C: Other platforms (Railway, Fly.io, Google Cloud Run, Azure, …)

Point the platform at the root `Dockerfile` and set these environment variables:

| Variable | Required | Value |
|---|---|---|
| `SECRET_KEY` | yes | long random string (`secrets.token_hex(32)`) |
| `DATABASE_URL` | yes | PostgreSQL (or MySQL) URL; `postgres://…` is accepted |
| `ADMIN_INVITE_CODE` | recommended | code for officer sign-up; empty disables it |
| `PORT` | set by most platforms | the image listens on `$PORT` (default 8000) |
| `CORS_ORIGINS` | optional | only needed if another website calls the API |
| `ENABLE_DOCS` | optional | `true` to expose `/docs` in production |
| `MAX_UPLOAD_MB` | optional | default 10 |

Health check path: `/health` (returns 503 if the database is unreachable).

**Run exactly one instance with one worker.** Live updates, login rate limits and the
audit-chain lock live in memory. Scale up (a bigger machine), not out (more copies).

---

## Mobile app (Android)

Build it against your deployed URL:

```bash
cd flutter_app
flutter build apk --release --dart-define=API_URL=https://YOUR-APP.onrender.com
```

The APK is in `flutter_app/build/app/outputs/flutter-apk/app-release.apk`.

---

## What production mode does differently

`ENV=production` (set in the Docker image):

- Refuses to start without a strong `SECRET_KEY`.
- Refuses to start if the configured database is unreachable (it retries for ~1 minute while
  the database boots) instead of silently using a throwaway SQLite file.
- Hides the interactive API docs (`/docs`) unless `ENABLE_DOCS=true`.
- `seed_final.py` refuses to create the demo accounts, which have publicly known passwords.
- Errors are logged on the server; users only see a friendly message, never a stack trace.

## Before real customers use it

- [ ] Rotate `SECRET_KEY` and any database passwords that were ever in the old `.env`
      (it is still visible in the first commits of the Git history).
- [ ] Use a paid, backed-up database (Render free PostgreSQL is deleted after 30 days).
- [ ] Use HTTPS only (Render does this automatically).
- [ ] Retrain the risk model on your bank's real repayment data
      (`python train_model.py --data loans.csv`). The shipped model learned a synthetic policy.
- [ ] Have compliance review the lending rules in `compliance_checker.py` for your jurisdiction.

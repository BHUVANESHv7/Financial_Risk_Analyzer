"""
End-to-end smoke test of a running deployment (standard library only).

    python .github/smoke_test.py https://your-app.onrender.com <ADMIN_INVITE_CODE>

Creates two throwaway accounts (an applicant and an officer) and one application.
"""

import json
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

BASE = (sys.argv[1] if len(sys.argv) > 1 else "http://localhost:8000").rstrip("/")
INVITE = sys.argv[2] if len(sys.argv) > 2 else "ci-officer"
EXPECT_DB = sys.argv[3] if len(sys.argv) > 3 else None
STAMP = int(time.time())


def call(method, path, body=None, token=None, form=False):
    headers = {}
    data = None
    if body is not None:
        if form:
            data = urllib.parse.urlencode(body).encode()
            headers["Content-Type"] = "application/x-www-form-urlencoded"
        else:
            data = json.dumps(body).encode()
            headers["Content-Type"] = "application/json"
    if token:
        headers["Authorization"] = f"Bearer {token}"
    req = urllib.request.Request(BASE + path, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            raw = r.read().decode("utf-8-sig")
            ctype = r.headers.get("Content-Type", "")
            return r.status, (json.loads(raw) if "json" in ctype else raw)
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode()


def check(name, ok, detail=""):
    print(("PASS  " if ok else "FAIL  ") + name + (f"  -> {detail}" if not ok else ""))
    if not ok:
        sys.exit(1)


status, health = call("GET", "/health")
check("health", status == 200 and health.get("database_ok") is True, health)
if EXPECT_DB:
    check(f"database is {EXPECT_DB}", health["database"] == EXPECT_DB, health["database"])
check("web app bundled", health.get("web_app") is True, health)

status, page = call("GET", "/")
check("web app served", status == 200 and "<html" in page.lower(), status)
status, _ = call("GET", "/main.dart.js")
check("web app script served", status == 200, status)
status, _ = call("GET", "/docs")
check("API docs hidden in production", status == 404, status)


def account(email, role="APPLICANT", invite=None):
    body = {"email": email, "password": "smoke-test-pass", "role": role}
    if invite:
        body["invite_code"] = invite
    status, out = call("POST", "/register", body)
    check(f"register {role.lower()}", status == 201, out)
    status, out = call("POST", "/login", {"username": email, "password": "smoke-test-pass"}, form=True)
    check(f"login {role.lower()}", status == 200, out)
    return out["access_token"]


user = account(f"smoke-{STAMP}@example.com")
officer = account(f"smoke-officer-{STAMP}@example.com", "ADMIN", INVITE)

loan = {"applicant_name": "Smoke Test", "monthly_income": 45000, "loan_amount": 500000,
        "credit_score": 660, "employment_years": 2, "tenure_months": 60, "interest_rate": 10.5}
status, out = call("POST", "/recalculate", loan, user)
check("live score", status == 200 and 0 <= out["risk_score"] <= 100, out)
status, out = call("POST", "/advice", loan, user)
check("path to approval", status == 200 and "options" in out, out)

status, app = call("POST", "/applications", loan, user)
check("submit application", status == 201, app)
status, out = call("PATCH", f"/applications/{app['id']}/review",
                   {"status": "APPROVED", "notes": "smoke test"}, officer)
check("officer review", status == 200 and out["status"] == "APPROVED", out)
status, out = call("GET", f"/applications/{app['id']}/audit", token=user)
check("audit trail verified", status == 200 and out["verified"]
      and [e["action"] for e in out["events"]] == ["CREATED", "REVIEWED"], out)
status, out = call("GET", "/audit/verify", token=officer)
check("audit ledger intact", status == 200 and out["valid"], out)
status, out = call("GET", "/stats", token=officer)
check("stats", status == 200 and out["total"] >= 1, out)
status, out = call("GET", "/model/health", token=officer)
check("model health", status == 200, out)
status, out = call("GET", "/applications/export", token=officer)
check("csv export", status == 200 and "applicant_name" in out, status)

print("\nAll smoke tests passed.")

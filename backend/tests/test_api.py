"""
API tests. Run from the backend folder:
    venv\\Scripts\\python -m pytest -q
Uses a throwaway SQLite database.
"""

import os
import sys
import tempfile

_DB = os.path.join(tempfile.mkdtemp(), "test.db")
# CI also runs the suite against PostgreSQL via TEST_DATABASE_URL.
os.environ["DATABASE_URL"] = os.getenv("TEST_DATABASE_URL") or f"sqlite:///{_DB}"
# A fake built web app, to test single-service serving.
_WEB = tempfile.mkdtemp()
with open(os.path.join(_WEB, "index.html"), "w") as fh:
    fh.write("<!DOCTYPE html><title>AI Loan Risk Analyzer</title>")
with open(os.path.join(_WEB, "main.dart.js"), "w") as fh:
    fh.write("console.log('app')")
os.environ["WEB_DIR"] = _WEB
os.environ["ADMIN_INVITE_CODE"] = "officer-code"
os.environ["SECRET_KEY"] = "test-secret"
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import pytest  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402

from main import app  # noqa: E402

GOOD = {
    "applicant_name": "Ravi Kumar", "monthly_income": 90000, "loan_amount": 300000,
    "existing_emis": 0, "employment_years": 8, "credit_score": 800, "num_dependents": 1,
    "loan_category": "Education", "tenure_months": 60, "interest_rate": 10.5,
}
RISKY = {**GOOD, "applicant_name": "Risky Person", "monthly_income": 20000,
         "loan_amount": 2500000, "existing_emis": 12000, "credit_score": 520,
         "employment_years": 0}
MEDIUM_RISK = {**GOOD, "applicant_name": "Medium Risk", "monthly_income": 45000,
               "loan_amount": 500000, "existing_emis": 0, "credit_score": 660,
               "employment_years": 2}  # → MANUAL REVIEW (pending)
BORDERLINE = {**GOOD, "applicant_name": "Border Line", "monthly_income": 40000,
              "loan_amount": 900000, "existing_emis": 4000, "credit_score": 660,
              "employment_years": 2}


@pytest.fixture(scope="module")
def client():
    with TestClient(app) as c:
        yield c


def _token(client, email, password, role="APPLICANT", invite=None):
    body = {"email": email, "password": password, "role": role}
    if invite:
        body["invite_code"] = invite
    client.post("/register", json=body)
    r = client.post("/login", data={"username": email, "password": password})
    assert r.status_code == 200, r.text
    return r.json()["access_token"]


@pytest.fixture(scope="module")
def applicant(client):
    return {"Authorization": f"Bearer {_token(client, 'app@test.com', 'secret1')}"}


@pytest.fixture(scope="module")
def officer(client):
    t = _token(client, "officer@test.com", "secret1", "ADMIN", "officer-code")
    return {"Authorization": f"Bearer {t}"}


def test_health(client):
    r = client.get("/health")
    assert r.status_code == 200 and r.json()["status"] == "online"


def test_admin_signup_requires_invite(client):
    r = client.post("/register", json={"email": "x@test.com", "password": "secret1", "role": "ADMIN"})
    assert r.status_code == 403


def test_register_validates_email(client):
    r = client.post("/register", json={"email": "not-an-email", "password": "secret1"})
    assert r.status_code == 422


def test_recalculate_requires_auth(client):
    assert client.post("/recalculate", json=GOOD).status_code == 401


def test_recalculate_scores(client, applicant):
    good = client.post("/recalculate", json=GOOD, headers=applicant).json()
    risky = client.post("/recalculate", json=RISKY, headers=applicant).json()
    assert good["decision"] == "APPROVE" and good["risk_level"] == "LOW"
    assert risky["decision"] == "REJECT"
    assert good["risk_score"] < risky["risk_score"]
    assert good["factors"] and good["compliance_checks"]


def test_compliance_violation_blocks_auto_approve(client, applicant):
    # Strong profile but loan > 6x annual income → must not auto-approve.
    body = {**GOOD, "monthly_income": 30000, "loan_amount": 2_400_000, "tenure_months": 360}
    r = client.post("/recalculate", json=body, headers=applicant).json()
    assert not r["compliant"]
    assert r["decision"] != "APPROVE"


def test_submit_list_review_flow(client, applicant, officer):
    created = client.post("/applications", json=BORDERLINE, headers=applicant)
    assert created.status_code == 201, created.text
    app_id = created.json()["id"]
    assert created.json()["loan_category"] == "Education"

    # Applicant sees own; officer sees all
    mine = client.get("/applications", headers=applicant).json()
    assert any(a["id"] == app_id for a in mine["items"])

    # Applicant cannot review
    r = client.patch(f"/applications/{app_id}/review", json={"status": "APPROVED"}, headers=applicant)
    assert r.status_code == 403

    r = client.patch(f"/applications/{app_id}/review",
                     json={"status": "APPROVED", "notes": "Verified salary"}, headers=officer)
    assert r.status_code == 200
    assert r.json()["status"] == "APPROVED"
    assert r.json()["reviewer_email"] == "officer@test.com"

    detail = client.get(f"/applications/{app_id}", headers=applicant).json()
    assert detail["reviewer_notes"] == "Verified salary"


def test_other_applicant_cannot_see(client, applicant):
    other = {"Authorization": f"Bearer {_token(client, 'other@test.com', 'secret1')}"}
    created = client.post("/applications", json=GOOD, headers=applicant).json()
    assert client.get(f"/applications/{created['id']}", headers=other).status_code == 404


def test_filters_and_stats(client, applicant, officer):
    client.post("/applications", json=RISKY, headers=applicant)
    rejected = client.get("/applications?status=REJECTED", headers=officer).json()
    assert all(a["status"] == "REJECTED" for a in rejected["items"])
    search = client.get("/applications?q=risky", headers=officer).json()
    assert search["total"] >= 1

    s = client.get("/stats", headers=officer).json()
    assert s["total"] >= 3
    assert len(s["trend"]) == 14
    assert sum(d["total"] for d in s["trend"]) == s["total"]


def test_websocket_pushes_events(client, applicant, officer):
    officer_token = officer["Authorization"].split()[1]
    with client.websocket_connect("/ws") as ws:
        ws.send_json({"type": "auth", "token": officer_token})
        assert ws.receive_json()["type"] == "hello"
        client.post("/applications", json=GOOD, headers=applicant)
        types = set()
        for _ in range(4):
            msg = ws.receive_json()
            types.add(msg["type"])
            if "application.created" in types:
                break
        assert "application.created" in types


def test_websocket_rejects_bad_token(client):
    from starlette.websockets import WebSocketDisconnect
    with pytest.raises(WebSocketDisconnect):
        with client.websocket_connect("/ws") as ws:
            ws.send_json({"type": "auth", "token": "bad"})
            ws.receive_json()


def test_upload_rejects_bad_type(client, applicant):
    r = client.post("/analyze-loan", files={"file": ("x.txt", b"hello", "text/plain")}, headers=applicant)
    assert r.status_code == 400


def test_text_extraction():
    from nlp_parser import extract_from_text
    text = ("Employee Name: Ravi Kumar\nNet Pay: 45,000\nLoan Amount: 5,00,000\n"
            "CIBIL Score: 765\nExperience: 6 years\nDependents: 2\n")
    f = extract_from_text(text)
    assert f["applicant_name"] == "Ravi Kumar"
    assert f["monthly_income"] == 45000
    assert f["credit_score"] == 765


# ── Model quality ─────────────────────────────────────────────────────────────

def _score(**over):
    from risk_model import predict_risk
    return predict_risk({**BORDERLINE, **over})["risk_score"]


def test_model_is_monotone():
    """Improving any single factor must never raise the risk score."""
    import numpy as np
    import risk_model as rm

    raw = rm.synthetic_raw(2000, seed=123)
    model = rm.get_model()
    w = np.array([0, 50, 100])
    base = model.predict_proba(rm.feature_matrix(raw)) @ w
    for col, fn in [(4, lambda c: np.clip(c + 60, 300, 900)), (3, lambda c: c + 5),
                    (0, lambda c: c * 1.3), (2, lambda c: c * 0.5)]:
        better = raw.copy()
        better[:, col] = fn(better[:, col])
        after = model.predict_proba(rm.feature_matrix(better)) @ w
        assert np.all(after <= base + 1e-6)


def test_score_moves_in_expected_direction():
    assert _score(credit_score=820) < _score(credit_score=560)
    assert _score(existing_emis=0) < _score(existing_emis=30000)
    assert _score(monthly_income=150000) < _score(monthly_income=25000)


def test_model_accuracy_on_holdout():
    import risk_model as rm
    from sklearn.metrics import f1_score

    raw = rm.synthetic_raw(5000, seed=2024)
    X = rm.feature_matrix(raw)
    y = [rm._label(*r[:6], r[6]) for r in X]
    assert f1_score(y, rm.get_model().predict(X), average="macro") > 0.99


def test_model_endpoint(client):
    r = client.get("/model").json()
    assert r["version"] == 3
    assert r["test_metrics"]["macro_f1"] > 0.99


# ── Security & workflow ───────────────────────────────────────────────────────

def test_security_headers(client):
    r = client.get("/health")
    assert r.headers["X-Content-Type-Options"] == "nosniff"
    assert r.headers["X-Frame-Options"] == "DENY"


def test_login_rate_limited_after_failures(client):
    client.post("/register", json={"email": "brute@test.com", "password": "rightpass"})
    for _ in range(5):
        r = client.post("/login", data={"username": "brute@test.com", "password": "wrong"})
        assert r.status_code == 401
    r = client.post("/login", data={"username": "brute@test.com", "password": "rightpass"})
    assert r.status_code == 429  # locked even with the right password
    assert "Retry-After" in r.headers


def test_successful_login_resets_failures(client):
    client.post("/register", json={"email": "oops@test.com", "password": "rightpass"})
    for _ in range(4):
        client.post("/login", data={"username": "oops@test.com", "password": "wrong"})
    assert client.post("/login", data={"username": "oops@test.com", "password": "rightpass"}).status_code == 200
    for _ in range(4):
        client.post("/login", data={"username": "oops@test.com", "password": "wrong"})
    assert client.post("/login", data={"username": "oops@test.com", "password": "rightpass"}).status_code == 200


def test_withdraw_rules(client, applicant, officer):
    other = {"Authorization": f"Bearer {_token(client, 'other2@test.com', 'secret1')}"}
    created = client.post("/applications", json=MEDIUM_RISK, headers=applicant).json()
    assert created["status"] == "PENDING"
    app_id = created["id"]

    assert client.post(f"/applications/{app_id}/withdraw", headers=other).status_code == 404
    r = client.post(f"/applications/{app_id}/withdraw", headers=applicant)
    assert r.status_code == 200 and r.json()["status"] == "WITHDRAWN"
    # Can't withdraw twice, and officers can't review it any more.
    assert client.post(f"/applications/{app_id}/withdraw", headers=applicant).status_code == 409
    r = client.patch(f"/applications/{app_id}/review", json={"status": "APPROVED"}, headers=officer)
    assert r.status_code == 409


def test_cannot_withdraw_decided_application(client, applicant):
    app_id = client.post("/applications", json=RISKY, headers=applicant).json()["id"]  # auto-rejected
    assert client.post(f"/applications/{app_id}/withdraw", headers=applicant).status_code == 409


def test_csv_export(client, applicant, officer):
    client.post("/applications", json={**GOOD, "applicant_name": "=HYPERLINK(\"x\")"}, headers=applicant)
    assert client.get("/applications/export", headers=applicant).status_code == 403
    r = client.get("/applications/export", headers=officer)
    assert r.status_code == 200
    assert r.headers["content-type"].startswith("text/csv")
    body = r.content.decode("utf-8-sig")
    assert body.splitlines()[0].startswith("id,timestamp,applicant_name")
    assert "'=HYPERLINK" in body          # formula neutralised
    rejected = client.get("/applications/export?status=REJECTED", headers=officer).content.decode("utf-8-sig")
    assert all(",REJECTED," in line for line in rejected.splitlines()[1:])


def test_repeat_submissions_flagged():
    from fraud_detector import check_fraud
    base = {**GOOD, "raw_text_length": None}
    assert check_fraud(base)["warnings"] == []
    many = check_fraud({**base, "recent_applications": 6, "similar_recent_applications": 4})
    assert many["fraud_flag"] and len(many["fraud_reasons"]) == 2
    some = check_fraud({**base, "recent_applications": 2, "similar_recent_applications": 2})
    assert not some["fraud_flag"] and some["warnings"]  # warning only


def test_velocity_counts_set_by_server(client):
    t = {"Authorization": f"Bearer {_token(client, 'velocity@test.com', 'secret1')}"}
    for i in range(6):
        r = client.post("/applications", json={**BORDERLINE, "loan_amount": 900000 + i * 1000,
                                                "recent_applications": 0}, headers=t)
    last = r.json()
    assert last["features"]["recent_applications"] == 5   # client value ignored
    assert last["fraud_flag"] is True
    assert last["status"] == "REJECTED"


# ── Path to approval ──────────────────────────────────────────────────────────

def test_advice_finds_a_change_that_approves(client, applicant):
    from pipeline import assess
    assert client.post("/advice", json=MEDIUM_RISK).status_code == 401
    r = client.post("/advice", json=MEDIUM_RISK, headers=applicant)
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["qualifies"] is False and body["options"]
    for opt in body["options"]:
        # Every suggestion must really flip the decision when applied.
        changed = {**MEDIUM_RISK, opt["key"]: opt["value"]}
        assert assess(changed)["decision"] == "APPROVE", opt
    efforts = [o["effort"] for o in body["options"]]
    assert efforts == sorted(efforts)


def test_advice_shows_headroom_when_approved(client, applicant):
    from pipeline import assess
    body = client.post("/advice", json=GOOD, headers=applicant).json()
    assert body["qualifies"] is True
    assert body["max_loan_amount"] >= GOOD["loan_amount"]
    assert assess({**GOOD, "loan_amount": body["max_loan_amount"]})["decision"] == "APPROVE"


def test_advice_refuses_to_coach_around_fraud(client, applicant):
    body = client.post("/advice", json={**RISKY, "loan_amount": 2_000_000, "monthly_income": 30000,
                                        "existing_emis": 40000}, headers=applicant).json()
    assert body["fraud_blocked"] is True and body["options"] == []


# ── Audit trail ───────────────────────────────────────────────────────────────

def test_audit_trail_records_and_verifies(client, applicant, officer):
    app_id = client.post("/applications", json=MEDIUM_RISK, headers=applicant).json()["id"]
    client.patch(f"/applications/{app_id}/review", json={"status": "APPROVED", "notes": "ok"},
                 headers=officer)
    r = client.get(f"/applications/{app_id}/audit", headers=applicant)
    assert r.status_code == 200
    body = r.json()
    assert [e["action"] for e in body["events"]] == ["CREATED", "REVIEWED"]
    assert body["verified"] is True
    assert body["events"][1]["data"]["status"] == "APPROVED"
    assert body["events"][1]["actor_email"] == "officer@test.com"

    other = {"Authorization": f"Bearer {_token(client, 'snoop@test.com', 'secret1')}"}
    assert client.get(f"/applications/{app_id}/audit", headers=other).status_code == 404
    assert client.get("/audit/verify", headers=applicant).status_code == 403
    assert client.get("/audit/verify", headers=officer).json()["valid"] is True


def test_audit_detects_tampering(client, officer):
    from database import AuditEvent, SessionLocal
    with SessionLocal() as db:
        event = db.query(AuditEvent).order_by(AuditEvent.id).first()
        original = dict(event.data)
        event.data = {**original, "status": "APPROVED", "risk_score": 1.0}
        db.commit()
        try:
            result = client.get("/audit/verify", headers=officer).json()
            assert result["valid"] is False and result["broken_at"] == event.id
        finally:
            event.data = original
            db.commit()
    assert client.get("/audit/verify", headers=officer).json()["valid"] is True


# ── Model health ──────────────────────────────────────────────────────────────

def test_model_health_reports_drift(client, applicant, officer):
    assert client.get("/model/health", headers=applicant).status_code == 403
    for i in range(30):
        client.post("/applications", json={**GOOD, "loan_amount": 300000 + i * 7000},
                    headers=applicant)
    body = client.get("/model/health", headers=officer).json()
    assert body["sample_size"] >= 30
    assert body["status"] in ("stable", "moderate", "significant")
    assert len(body["features"]) == 8
    # Every test applicant earns ₹90k with 8 years' service — clearly unlike training data.
    assert body["status"] == "significant"


def test_psi_is_zero_for_identical_distributions():
    import numpy as np
    from monitoring import psi
    p = np.full(10, 0.1)
    assert psi(p, p) == 0
    assert psi(p, np.array([0.5] + [0.5 / 9] * 9)) > 0.25


# ── Deployment ────────────────────────────────────────────────────────────────

def test_web_app_served_alongside_api(client):
    r = client.get("/")
    assert r.status_code == 200 and "AI Loan Risk Analyzer" in r.text
    assert r.headers["cache-control"] == "no-cache"          # new releases picked up
    assert client.get("/main.dart.js").status_code == 200
    # API routes still win over the web app.
    h = client.get("/health")
    assert h.headers["content-type"].startswith("application/json")
    assert h.json()["database_ok"] is True and h.json()["web_app"] is True
    assert client.get("/applications").status_code == 401
    assert client.get("/no-such-file.js").status_code == 404


def test_camera_allowed_for_document_scan(client):
    assert "camera=(self)" in client.get("/health").headers["permissions-policy"]


def test_seed_refuses_demo_accounts_in_production():
    import subprocess
    env = {**os.environ, "ENV": "production", "SECRET_KEY": "x" * 40}
    backend = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    r = subprocess.run([sys.executable, "seed_final.py"], cwd=backend, env=env,
                       capture_output=True, text=True, timeout=120)
    assert r.returncode != 0 and "Refusing" in (r.stdout + r.stderr)


def test_audit_numbers_are_canonical():
    from audit import _canon
    assert _canon(300000.0) == 300000 and isinstance(_canon(300000.0), int)
    assert _canon(16.123456) == 16.1235
    assert _canon(True) is True and _canon(None) is None and _canon("x") == "x"


# ── Edge cases ────────────────────────────────────────────────────────────────

EDGE_CASES = [
    {"monthly_income": 0, "loan_amount": 0},
    {"monthly_income": 0, "loan_amount": 500000},
    {"monthly_income": 50000, "loan_amount": 0},
    {"monthly_income": 100_000_000, "loan_amount": 10_000_000_000, "existing_emis": 100_000_000,
     "employment_years": 60, "credit_score": 900, "num_dependents": 20, "tenure_months": 360,
     "interest_rate": 40},
    {"monthly_income": 1, "loan_amount": 1, "credit_score": 300, "tenure_months": 3,
     "interest_rate": 0, "employment_years": 0, "num_dependents": 0},
    {"monthly_income": 30000, "loan_amount": 800000, "existing_emis": 30000},
    {"monthly_income": 45000, "loan_amount": 600000, "loan_category": "Not a category"},
]


@pytest.mark.parametrize("features", EDGE_CASES)
def test_extreme_inputs_never_crash(client, applicant, features):
    for path in ("/recalculate", "/advice"):
        r = client.post(path, json=features, headers=applicant)
        assert r.status_code == 200, (path, features, r.text)
    body = client.post("/recalculate", json=features, headers=applicant).json()
    assert 0 <= body["risk_score"] <= 100
    assert body["decision"] in ("APPROVE", "REJECT", "MANUAL REVIEW")


@pytest.mark.parametrize("bad", [
    {"monthly_income": -1, "loan_amount": 1000},
    {"monthly_income": 1000, "loan_amount": 1000, "credit_score": 1200},
    {"monthly_income": 1000, "loan_amount": 1000, "tenure_months": 0},
    {"monthly_income": "lots", "loan_amount": 1000},
    {"loan_amount": 1000},
])
def test_invalid_inputs_rejected_cleanly(client, applicant, bad):
    for path in ("/recalculate", "/advice", "/applications"):
        r = client.post(path, json=bad, headers=applicant)
        assert r.status_code == 422, (path, r.text)
        assert isinstance(r.json()["detail"], list)


def test_malformed_requests(client, applicant):
    assert client.post("/recalculate", content=b"not json", headers={
        **applicant, "Content-Type": "application/json"}).status_code == 422
    assert client.get("/applications/999999", headers=applicant).status_code == 404
    assert client.get("/applications/999999/audit", headers=applicant).status_code == 404
    assert client.get("/applications/abc", headers=applicant).status_code == 422
    assert client.get("/me", headers={"Authorization": "Bearer garbage"}).status_code == 401
    assert client.post("/login", data={"username": "nobody@x.com", "password": ""}).status_code in (401, 422)


def test_empty_upload_rejected(client, applicant):
    r = client.post("/analyze-loan", files={"file": ("slip.pdf", b"", "application/pdf")},
                    headers=applicant)
    assert r.status_code == 400


def test_corrupt_pdf_upload_gives_friendly_error(client, applicant):
    r = client.post("/analyze-loan", files={"file": ("slip.pdf", b"%PDF-1.4 garbage", "application/pdf")},
                    headers=applicant)
    assert r.status_code == 422
    assert "detail" in r.json()

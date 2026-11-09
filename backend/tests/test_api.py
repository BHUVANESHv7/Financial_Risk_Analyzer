"""
API tests. Run from the backend folder:
    venv\\Scripts\\python -m pytest -q
Uses a throwaway SQLite database.
"""

import os
import sys
import tempfile

_DB = os.path.join(tempfile.mkdtemp(), "test.db")
os.environ["DATABASE_URL"] = f"sqlite:///{_DB}"
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

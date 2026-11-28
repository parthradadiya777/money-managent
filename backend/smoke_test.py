"""End-to-end smoke test for the isolated free test API. Uses synthetic records only."""
import json
import os
import secrets
import time
from urllib.error import HTTPError, URLError
from urllib.parse import quote
from urllib.request import Request, urlopen

BASE = os.environ.get("API_BASE_URL", "https://digitechified-bm-test-api.onrender.com").rstrip("/")
RUN_ID = os.environ.get("GITHUB_RUN_ID", str(int(time.time())))
ATTEMPT = os.environ.get("GITHUB_RUN_ATTEMPT", "1")
EMAIL = f"smoke-{RUN_ID}-{ATTEMPT}@example.com"
EMAIL_B = f"smoke-partner-b-{RUN_ID}-{ATTEMPT}@example.com"
PASSWORD = "SmokeTest!" + secrets.token_urlsafe(18)
RECORD_ID = f"smoke-{RUN_ID}-{ATTEMPT}"


def call(method, path, body=None, token=None):
    data = None if body is None else json.dumps(body).encode()
    headers = {"Content-Type": "application/json"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    req = Request(BASE + path, data=data, headers=headers, method=method)
    try:
        with urlopen(req, timeout=20) as response:
            raw = response.read()
            return response.status, json.loads(raw) if raw else {}
    except HTTPError as exc:
        raw = exc.read()
        try:
            detail = json.loads(raw)
        except Exception:
            detail = raw.decode(errors="replace")
        raise RuntimeError(f"{method} {path} returned {exc.code}: {detail}") from exc


def main():
    last_error = None
    for _ in range(30):
        try:
            status, health = call("GET", "/health")
            if status == 200 and health.get("status") == "ok":
                break
        except (URLError, TimeoutError, RuntimeError) as exc:
            last_error = exc
            time.sleep(5)
    else:
        raise RuntimeError(f"API health check did not become ready: {last_error}")

    _, auth = call("POST", "/api/auth/register", {
        "business_name": "Demo Smoke Test",
        "email": EMAIL,
        "password": PASSWORD,
    })
    token = auth["access_token"]

    _, profile = call("GET", "/api/auth/me", token=token)
    assert profile["email"] == EMAIL.lower(), profile
    assert profile["role"] in ("partner", "owner"), profile

    _, saved = call("PUT", "/api/records/batch", {
        "records": [{
            "record_id": RECORD_ID,
            "module": "Masters",
            "payload": {"Name": "Synthetic Smoke Record", "Environment": "test"},
        }]
    }, token=token)
    assert saved.get("saved") == 1 or saved.get("ok") is True or saved.get("count") == 1, saved

    # A second synthetic partner must never see or delete the first partner's record.
    _, auth_b = call("POST", "/api/auth/register", {
        "business_name": "Demo Smoke Partner B",
        "email": EMAIL_B,
        "password": PASSWORD,
    })
    token_b = auth_b["access_token"]
    _, listed = call("GET", "/api/records", token=token)
    assert any(x["record_id"] == RECORD_ID for x in listed.get("records", [])), listed
    _, partner_b_records = call("GET", "/api/records", token=token_b)
    assert not any(x["record_id"] == RECORD_ID for x in partner_b_records.get("records", [])), partner_b_records
    try:
        call("DELETE", "/api/records/" + quote(RECORD_ID, safe=""), token=token_b)
        raise AssertionError("Partner B unexpectedly deleted Partner A's record")
    except RuntimeError as exc:
        assert "404" in str(exc), str(exc)

    call("DELETE", "/api/records/" + quote(RECORD_ID, safe=""), token=token)
    _, after_delete = call("GET", "/api/records", token=token)
    assert not any(x["record_id"] == RECORD_ID for x in after_delete.get("records", [])), after_delete

    print("PASS: partner registration, profile, tenant-isolated record create/read/delete")
    print("Synthetic account:", EMAIL)


if __name__ == "__main__":
    main()

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
    assert profile["role"] == "partner", profile

    _, saved = call("PUT", "/api/records/batch", {
        "records": [{
            "record_id": RECORD_ID,
            "module": "Masters",
            "payload": {"Name": "Synthetic Smoke Record", "Environment": "test"},
        }]
    }, token=token)
    assert saved.get("saved") == 1 or saved.get("ok") is True or saved.get("count") == 1, saved

    _, listed = call("GET", "/api/records", token=token)
    assert any(x["record_id"] == RECORD_ID for x in listed.get("records", [])), listed

    call("DELETE", "/api/records/" + quote(RECORD_ID, safe=""), token=token)
    _, after_delete = call("GET", "/api/records", token=token)
    assert not any(x["record_id"] == RECORD_ID for x in after_delete.get("records", [])), after_delete

    print("PASS: test-only partner registration, profile, tenant record create/read/delete")
    print("Synthetic account:", EMAIL)


if __name__ == "__main__":
    main()

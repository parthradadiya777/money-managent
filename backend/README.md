# Business Manager API

FastAPI cloud API for Digitechified Business Manager.

## Multi-partner access model

- One Digitechified `super_admin` controls partner creation and management.
- Public self-registration is disabled. Partners are created only by the Super Admin.
- Each partner has one login; partner-created staff accounts are not supported.
- A shared PostgreSQL database stores all tenants, while every business record remains scoped to its tenant.
- Existing tenant records are retained. On startup, missing partner metadata is provisioned for legacy tenants.
- The Super Admin can open an active partner workspace using a short-lived, 30-minute impersonation token. The token keeps the Super Admin as its subject and changes only the authorized tenant scope.
- Partner enable/disable, password reset, profile updates and admin workspace access are recorded in admin audit logs.

## Admin bootstrap

Set these environment variables on the API service before deployment:

- `SUPERADMIN_EMAIL`: the owner's login ID (email format).
- `SUPERADMIN_PASSWORD`: a unique password of at least 12 characters.

On startup, the API creates the Super Admin if that login does not already exist. If the email already belongs to a non-admin account, it is deliberately not promoted; use a separate admin login ID. Passwords are stored as password hashes, never in readable form.

## Key endpoints

- `POST /api/auth/login`
- `POST /api/auth/register` — intentionally disabled
- `GET /api/auth/me`
- `GET /api/admin/partners`
- `POST /api/admin/partners`
- `PATCH /api/admin/partners/{tenant_id}`
- `POST /api/admin/partners/{tenant_id}/reset-password`
- `POST /api/admin/partners/{tenant_id}/access`
- `GET /api/admin/audit-logs`
- `GET /api/records` — tenant-scoped, paginated
- `PUT /api/records`
- `PUT /api/records/batch`
- `DELETE /api/records/{record_id}`

Partner create/update payloads use `name`, `login_id`, `password` (create only), and `status` (`active` or `disabled`). Login IDs use email format.

## Run locally

```bash
cd backend
python -m venv .venv
pip install -r requirements.txt
cp .env.example .env
# Set DATABASE_URL, JWT_SECRET, SUPERADMIN_EMAIL and SUPERADMIN_PASSWORD.
uvicorn app.main:app --reload
```

Health check: `GET /health`; API docs: `/docs`.

## Migration and production safety

The current schema uses `create_all` for new tables; it does not alter or delete existing tenant/business-record tables. Existing tenant records remain in place. Before production rollout, take a PostgreSQL backup and verify the partner metadata backfill on a staging database. Production still requires formal versioned migrations, rate limiting, email verification/password reset delivery, secure token storage/rotation and revocation, automated backups, strict CORS, and integration/security tests. Do not use the free test database for live accounting data.

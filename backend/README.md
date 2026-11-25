# Business Manager API

Initial cloud API foundation for Digitechified Business Manager.

## Features
- Tenant-isolated business data
- Email/password registration and login
- JWT bearer authentication
- JSON record storage by module (orders, returns/RTO, purchases, vendor payments, settlements, bank transactions, expenses, masters)
- Batch upsert endpoint for later device synchronization
- Audit log for record create/update/delete

## Run locally

```bash
cd backend
python -m venv .venv
# activate the environment, then:
pip install -r requirements.txt
cp .env.example .env
# Set DATABASE_URL and a strong JWT_SECRET in .env
uvicorn app.main:app --reload
```

Health check: `GET /health`
API docs: `/docs`

## Important
This is the first backend foundation, not yet connected to the Flutter client. Before production use, add schema migrations, rate limiting, email verification/password reset, automated backups, stricter CORS, token revocation/rotation, and automated integration/security tests. Do not store live business records until these checks and Flutter sync are complete.

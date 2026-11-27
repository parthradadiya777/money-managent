# Digitechified Business Manager

Flutter app for multi-marketplace orders, GST entities, returns/RTO, vendor purchases, settlements, bank transactions and expenses.

## Supported targets
- Web
- Android
- Windows desktop

## Current MVP
- Dashboard with orders, delivered sales, returns, RTO, settlements and bank summaries
- Manual entry for orders, returns/RTO, purchases, vendor payments, settlements, bank transactions and expenses
- Excel import/export per module
- Login and registration UI when a cloud API URL is configured
- Cloud sync client with batch upload, download/merge, and remote record deletion
- Marketplace starter list: Meesho, Myntra, Flipkart, Amazon and AJIO
- Synthetic demo firms: Demo Fashion Store, Demo Home Store and Demo Myntra Store

## Run locally
Install the current stable Flutter SDK (Dart 3 or newer):

```bash
flutter pub get
flutter run -d chrome
```

Android:
```bash
flutter run -d android
flutter build apk --release --dart-define=API_BASE_URL=https://YOUR-API-SERVICE.onrender.com
```

Windows (Windows 10/11 + Visual Studio Desktop development with C++ workload):
```bash
flutter create --platforms=windows --org com.digitechified .
flutter run -d windows
flutter build windows --release --dart-define=API_BASE_URL=https://YOUR-API-SERVICE.onrender.com
```

## Important data limitation
The app keeps a local Hive copy on each device. Test builds use the separate `business_manager_test` Hive box and the free test API; they must contain synthetic/demo data only. Never enter real business, customer, vendor, GST, bank or order data in the test environment. The free test PostgreSQL database expires on 25 December 2026 and the free API may sleep when idle. Do not use this MVP as the sole live accounting database: schema migrations, robust conflict resolution/tombstones, secure token storage/rotation, backups, rate limiting and production security review are still required.

## Multi-partner edition (development)
The `feature/multi-partner-admin` branch adds the backend foundation for a Digitechified Super Admin and isolated partner workspaces. Public registration is disabled; partners are created by the admin. Set `SUPERADMIN_EMAIL` and `SUPERADMIN_PASSWORD` on the API service to bootstrap the owner login. Partner records remain isolated by tenant. This branch is under development and must pass staging migration, security, Flutter integration and deployment checks before production use.

## Cloud API
The FastAPI backend is in `backend/`. Configure `DATABASE_URL` and a strong `JWT_SECRET`, then run it with `uvicorn app.main:app --host 0.0.0.0 --port $PORT` from that folder. API documentation is available at `/docs` after deployment. The Flutter app uses `API_BASE_URL` at build time; leave it unset to run in local-only mode. CI test builds set `APP_ENV=test` and point to `https://digitechified-bm-test-api.onrender.com`, which isolates test storage from the normal local Hive box.

## CI builds
GitHub Actions builds the Web bundle and prepares Android and Windows scaffolding before creating APK and Windows release artifacts. Workflow: `.github/workflows/flutter-build.yml`.

## Initial business setup
Masters includes editable synthetic examples:
- Demo Fashion Store — Meesho
- Demo Home Store — Meesho
- Demo Myntra Store — Myntra

Use only synthetic information in test builds. Configure production firms and sensitive details only after a separately reviewed production deployment.

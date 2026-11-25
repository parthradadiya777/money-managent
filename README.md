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
- Firm starter list: JPWels, House of Ishika and Jipro Store

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
The app still keeps a local Hive copy on each device. The initial authenticated API client and merge/upload sync flow are now in the codebase, but cloud sync remains inactive until a PostgreSQL database and API are deployed and the app is built with `--dart-define=API_BASE_URL=...`. Do not use it as the sole live accounting database yet: schema migrations, conflict resolution, automated backups, token hardening, and end-to-end tests must be completed before production use.

## Cloud API
The FastAPI backend is in `backend/`. Configure `DATABASE_URL` and a strong `JWT_SECRET`, then run it with `uvicorn app.main:app --host 0.0.0.0 --port $PORT` from that folder. API documentation is available at `/docs` after deployment. The Flutter app uses `API_BASE_URL` at build time; leave it unset to run in local-only mode.

## CI builds
GitHub Actions builds the Web bundle and prepares Android and Windows scaffolding before creating APK and Windows release artifacts. Workflow: `.github/workflows/flutter-build.yml`.

## Initial business setup
Masters includes editable examples:
- JPWels — Meesho
- House of Ishika — Meesho
- Jipro Store — Myntra

Enter the actual GSTIN, state, bank details and remaining marketplace-to-firm mappings before recording live transactions.

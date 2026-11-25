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
flutter build apk --release
```

Windows (Windows 10/11 + Visual Studio Desktop development with C++ workload):
```bash
flutter create --platforms=windows --org com.digitechified .
flutter run -d windows
flutter build windows --release
```

## Important data limitation
The current MVP stores records locally in the browser/device using Hive. **It does not yet synchronize data between Web, Android and Windows.** Do not use it as the sole live accounting database yet. The production phase must add authenticated cloud storage, business/tenant separation, roles, backups, audit history and conflict-safe synchronization before central business use.

## CI builds
GitHub Actions builds the Web bundle and prepares Android and Windows scaffolding before creating APK and Windows release artifacts. Workflow: `.github/workflows/flutter-build.yml`.

## Initial business setup
Masters includes editable examples:
- JPWels — Meesho
- House of Ishika — Meesho
- Jipro Store — Myntra

Enter the actual GSTIN, state, bank details and remaining marketplace-to-firm mappings before recording live transactions.

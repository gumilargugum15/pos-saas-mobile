# Kagoem POS Mobile

Android (phone and tablet) cashier app for **Kagoem POS SaaS**. It is a
client of the existing Laravel backend (`kagoem-pos-saas`); the backend stays
the source of truth for prices, stock, totals, invoices and permissions.

Scope: cashier operations only. Admin features (users, roles, settings,
products CRUD, reports) are not part of this app.

Design and backend analysis: [`docs/`](docs/)
([PROJECT_ANALYSIS](docs/PROJECT_ANALYSIS.md) ·
[API_MAPPING](docs/API_MAPPING.md) ·
[DATABASE_MAPPING](docs/DATABASE_MAPPING.md) ·
[CASHIER_PERMISSION](docs/CASHIER_PERMISSION.md)).

## Status

| Phase | Content | Status |
|---|---|---|
| 1 | Backend analysis and docs | Done |
| 2 | Foundation: architecture, theme, routing, API client, auth, tenant, secure storage | Done |
| 3 | Dashboard, products, categories, barcode, cart | Next |
| 4 | Customer, checkout, payment, transactions | Planned |
| 5 | Receipt, Bluetooth thermal printer | Planned |
| 6 | Extended tests | Planned |

## Requirements

- Flutter **3.47.5** stable, Dart **3.13.4** (`flutter --version`)
- Android SDK 36, JDK 17
- A running `kagoem-pos-saas` backend (`/api/v1`)
- For checkout safety, the backend should include the `feature/sales-idempotency` change
  (`Idempotency-Key` on `POST /sales`); older backends simply ignore the header.

## Architecture

```text
lib/
├── core/        config, error (AppFailure), network (ApiClient, error mapping),
│                storage (secure session), theme, utils (Money, CurrencyFormatter), widgets
├── domain/      entities, repository contracts, use cases (CashierAccess) — no Dio/Flutter IO
├── data/        models (JSON ↔ entities), remote data sources, repository implementations
├── features/    auth, tenant, dashboard, … (presentation + application state)
├── routing/     go_router, redirects driven by the session state
├── app.dart
└── main.dart
```

- **State management:** Riverpod 3 (only).
- **HTTP:** one `ApiClient` (Dio). It adds `Accept`, `Authorization: Bearer`
  and `X-Tenant-ID`, turns every error into an `AppFailure` with an
  Indonesian, cashier-friendly message, retries **GETs only**, and publishes
  session events (401 → logout, tenant revoked → tenant re-selection).
- **Session flow:** Splash → check token (`/auth/me`) → tenants (`/tenants`) →
  auto-select / picker → access check (`manage-sales` + plan module `sales`) → app.
- **Storage:** token, active tenant and branch in `flutter_secure_storage`
  (Android Keystore). Passwords are never stored. Android backup is disabled.
- **Money:** integer minor units (`Money`), formatting only through `CurrencyFormatter`.

## Setup

```bash
flutter pub get
cp env/development.example.json env/development.json   # then edit API_BASE_URL
```

### Environment

Configuration is passed at build time with `--dart-define-from-file`
(no secrets live in the app; real `env/*.json` files are git-ignored).

| Key | Values |
|---|---|
| `APP_ENV` | `development` · `staging` · `production` |
| `API_BASE_URL` | Backend base including `/api/v1`, e.g. `https://pos.example.com/api/v1` |

Rules enforced at startup: `API_BASE_URL` is required; staging and
production must use `https`. Plain `http` is only allowed in debug builds
(`usesCleartextTraffic` is enabled for the debug build type only).

### Reaching a local backend from a phone

`localhost` on the phone is the phone itself. Either:

```bash
# serve the backend on the LAN and use the PC's IP in env/development.json
php artisan serve --host=0.0.0.0 --port=8001

# or, with the phone on USB
adb reverse tcp:8001 tcp:8001   # then API_BASE_URL=http://127.0.0.1:8001/api/v1
```

## Development

```bash
flutter run --dart-define-from-file=env/development.json
flutter analyze
flutter test
```

Login uses the backend user's **email + password**. The account needs the
`manage-sales` permission (role `Kasir`, or Owner/Admin) and an active tenant
membership whose plan includes the `sales` module; otherwise the app shows
*Akses Ditolak*.

## Build APK

```bash
flutter build apk --release --dart-define-from-file=env/production.json
# output: build/app/outputs/flutter-apk/app-release.apk
```

Release signing reads `android/key.properties` (git-ignored):

```properties
storeFile=/absolute/path/upload-keystore.jks
storePassword=...
keyAlias=upload
keyPassword=...
```

Without that file the release APK is signed with the debug key — fine for
internal testing, **not** for distribution.

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| "Konfigurasi aplikasi tidak valid" | Run with `--dart-define-from-file=env/<env>.json`; check `API_BASE_URL`. |
| "Tidak dapat terhubung ke server" | Phone cannot reach the backend: use the LAN IP or `adb reverse`; check firewall. |
| Works in debug, fails in release with `http://` | Release builds block cleartext traffic. Use `https`. |
| "Akses Ditolak – tidak memiliki izin kasir" | The user lacks `manage-sales` in the backend. |
| "…tidak mencakup fitur Penjualan" | The tenant's plan has no `sales` module. |
| Logged out after reinstall / device restore | Expected: the Keystore-encrypted session is not portable. |
| 429 "Terlalu banyak percobaan" at login | Backend allows 5 logins/minute per IP+email. |

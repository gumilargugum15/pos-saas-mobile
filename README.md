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
| 3 | Dashboard, products, categories, barcode, cart | Done |
| 4 | Outlet, customer, checkout, payment, transactions | Done |
| 5 | Receipt, Bluetooth thermal printer | Done |
| 6 | Tests (unit, repository, widget, integration), docs | Done |
| + | Shift & cash drawer (open, cash in/out, close with count) | Done |
| + | Hold transaction (park a cart, resume later) | Done |
| + | Product add & edit for Admin / Owner (`manage-products`) | Done |

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
- **Checkout safety:** one request in flight; one `Idempotency-Key` per distinct
  checkout, reused on re-send; a lost response is "unknown", resolved by looking
  up recent server sales before anything is sent again; the cart is cleared only
  after the server confirms the sale. Totals shown after payment are the server's.

## Variants (one codebase, two apps)

| Flavor | App | Backend | Application id |
|---|---|---|---|
| `saas` | Kagoem POS | `kagoem-pos-saas` (multi-tenant) | `id.kagoem.kagoem_pos_mobile` |
| `cashier` | Warung Epon | `pos-cashier` (single store) | `id.kagoem.poscashier` |

Both share every feature (POS, checkout, receipts, printer, shift, hold).
The `cashier` variant skips tenant selection (no `/tenants`, no `X-Tenant-ID`)
and, because that backend has no sales date filter yet, hides the history
date chips (`SALES_DATE_FILTER=false`). Checkout idempotency is detected at
runtime; without it a timeout falls back to manual verification.

```bash
# Kagoem POS
flutter build apk --release --split-per-abi --flavor saas    --dart-define-from-file=env/production.json
# Warung Epon
flutter build apk --release --split-per-abi --flavor cashier --dart-define-from-file=env/cashier-production.json
```

Extra env keys for `cashier`: `APP_NAME` (store name shown in the app) and
`SALES_DATE_FILTER` (`true` once the pos-cashier backend forwards
`date_from`/`date_to`). See `env/cashier-*.example.json`.

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
flutter run --flavor saas --dart-define-from-file=env/development.json
flutter analyze
flutter test
```

Login uses the backend user's **email + password**. The account needs the
`manage-sales` permission (role `Kasir`, or Owner/Admin) and an active tenant
membership whose plan includes the `sales` module; otherwise the app shows
*Akses Ditolak*.

## Testing

```bash
flutter analyze
flutter test                                    # unit, repository and widget tests
flutter test integration_test --flavor saas -d <device-id>   # full cashier journey on a device
```

Tests run against an in-memory fake of the Laravel API (`test/helpers/fake_backend.dart`),
a fake printer and in-memory secure storage — no server, Bluetooth or keystore needed.

| Area | Where |
|---|---|
| Config, error mapping, API client (headers, envelope, retries, 401/tenant events) | `test/core/` |
| Money & currency, cart totals vs. backend formula, barcode matching, access rules | `test/core/utils/`, `test/domain/` |
| Repositories (catalog, sales, customers, branches) | `test/data/` |
| Session: login ok/failed, token expired, logout, tenant picker, access denied | `test/features/auth/` |
| Cart, POS screen (phone & tablet), hardware scanner | `test/features/cart/`, `test/features/pos/` |
| Checkout: cash, insufficient cash, success, server errors, double tap, timeout/idempotency, outlet | `test/features/checkout/` |
| History filters, receipt layout/ESC-POS, printing & sharing | `test/features/transactions/`, `test/features/receipt/` |
| Permissions (no admin endpoints/screens, customer creation) and tenant isolation | `test/features/permission_test.dart`, `test/features/tenant_isolation_test.dart` |
| End-to-end on a device | `integration_test/cashier_flow_test.dart` |

## Build APK

```bash
flutter build apk --release --split-per-abi --flavor saas --dart-define-from-file=env/production.json
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

## Releasing an update (Kagoem POS)

The app checks `GET /api/v1/mobile-app/android` (kagoem-pos-saas
`MobileAppController`) on launch and shows **"Update tersedia"** on the
dashboard when the published version is newer than its own `version:`.

1. Bump `version:` in `pubspec.yaml` (e.g. `1.4.0+5`) and build the `saas` flavor.
2. Copy `build/app/outputs/flutter-apk/app-arm64-v8a-saas-release.apk` to the VPS as
   `storage/app/private/mobile/android/kagoem-pos.apk`.
3. On the VPS set `MOBILE_APP_ANDROID_VERSION=1.4.0` in `.env`, then `php artisan config:cache`.

The link is only followed when it is on the API's own host and scheme. Backends
without the endpoint (pos-cashier) simply show no banner. Menu ⋮ → **Tentang
Aplikasi** shows the installed version and checks again.

## Receipt printing

- Pair the Bluetooth thermal printer (58 mm or 80 mm, ESC/POS) in **Android
  Settings → Bluetooth** first.
- In the app: menu ⋮ → **Printer Struk** → choose the printer → **TEST PRINT**.
  Paper width follows the store setting `receipt_paper_size` unless overridden.
- Print / share from the success screen, or reprint from
  **Transaksi → detail → 🧾**.
- Layout matches the web POS receipt (`frontend/src/lib/escpos.ts`); the tenant
  and outlet are printed under the store name.
- Architecture: `ReceiptFormatter` (layout) → `EscPosEncoder` (bytes) →
  `PrinterService` (transport). Only `BluetoothPrinterService` knows the plugin.

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
| Printer not listed | Pair it in Android Bluetooth settings first; allow "Perangkat di sekitar" permission. |
| "Tidak dapat terhubung ke printer" | Printer off, out of range, or connected to another phone. |
| Strange characters on paper | The printer uses a single-byte code page; non-Latin characters print as `?`. |

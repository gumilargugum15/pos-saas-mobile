# Kagoem POS Mobile — Implementation Report

Date: 2026-10-03 · Branch: `feature/testing` (Phases 1–5 already merged to `main`)

## Summary

| Item | Value |
|---|---|
| Flutter / Dart | 3.47.5 stable / 3.13.4 |
| Backend | `kagoem-pos-saas` (Laravel 12, Sanctum, Spatie Permission) |
| App code | 78 Dart files in `lib/` (~7.4k lines) |
| Tests | 137 unit/repository/widget tests + 1 integration test (Android emulator), all passing |
| `flutter analyze` | no issues |
| `flutter build apk --release` | builds (signed with the debug key until `android/key.properties` exists) |

## Status by area

| Area | Status | Notes |
|---|---|---|
| Authentication | ✅ | Email + password (Sanctum token in Keystore), session restore, logout, 401 handling anywhere |
| Tenant | ✅ | `GET /tenants`, auto-select / picker, `X-Tenant-ID` on every request, switch, revoked membership handled, no data crosses tenants |
| Cashier access | ✅ | `manage-sales` + plan module `sales`; Access Denied otherwise; no admin endpoints or screens |
| Dashboard | ✅ | Cashier, tenant, outlet, today's tenant-wide sales/transactions/products |
| Products & categories | ✅ | Search (name/SKU/barcode), category chips, infinite scroll, detail |
| Barcode | ✅ | Camera (EAN-13/8, UPC-A/E, Code 128, Code 39, QR) and hardware scanners; exact match only |
| Cart | ✅ | Add/remove/qty/manual qty/clear; totals replicate `SaleService::checkout` |
| Outlet | ✅ | Home branch fixed; otherwise chosen (auto when single) |
| Customer | ✅ | Search/pick, Walk-in, create only with `manage-customers` |
| Checkout & payment | ✅ | 6 backend methods, cash received/change, non-cash = total |
| Transaction safety | ✅ | Single flight, `Idempotency-Key`, unknown-outcome recovery, cart cleared only on server success |
| Transaction history | ✅ | Invoice search, date presets/range, method/status filters, detail |
| Receipt | ✅ | Web-identical layout, 58/80 mm, preview, share (text), reprint |
| Printer | ✅ | `PrinterService` → `BluetoothPrinterService`; settings, test print; errors never break a sale |
| Shift / cash drawer | ✅ | Open shift with float, cash in/out (backend categories), close with physical count; server expected balance & variance; optional (selling does not require it, as on the web) |
| Product edit | ✅ | Admin / Owner (`manage-products` + plan module `products`): all web-form fields, photo from camera/gallery, only changed fields sent; Kasir never sees it |
| Variants | ✅ | One codebase, two Android flavors: `saas` (Kagoem POS SaaS, multi-tenant) and `cashier` (pos-cashier / Warung Epon, single store: no tenant step, no history date filter) |
| Hold transaction | ✅ | Like the web POS "Hold/Resume", stored on the device per tenant + cashier (max 20), survives restarts; resuming holds the current cart first and re-checks price/availability/stock with the server |
| Offline mode | ❌ By design | Online only; layers allow a local data source later. No offline sales without a sync design |

## Backend changes (kagoem-pos-saas)

Branch `feature/sales-idempotency` (commit `0470c76`, **not merged yet**):

- `POST /sales` accepts `Idempotency-Key` (stored in new nullable `sales.client_reference`,
  unique per tenant); a retry returns the original sale (200), a reused key with a
  different cart is rejected (422). Requests without the header are unchanged.
- `GET /sales` forwards `date_from` / `date_to` (repository already supported them).
- 7 new backend tests; full backend suite 511 passing.
- Migration `2026_10_02_020000_add_client_reference_to_sales_table` must run on each environment.

## API endpoints used

| Method | Endpoint | Feature |
|---|---|---|
| POST | `/auth/login` | Login |
| GET | `/auth/me` | Session restore, permissions |
| POST | `/auth/logout` | Logout |
| GET | `/tenants` | Tenant list / picker |
| GET | `/dashboard` | Dashboard figures |
| GET | `/settings` | Currency format, store name, paper size |
| GET | `/products`, `/products/{id}` | Catalog, search, barcode lookup, detail |
| GET | `/categories` | Category chips |
| GET | `/branches` | Outlet selection |
| GET / POST | `/customers` | Customer search / create |
| POST (`_method=PUT`) | `/products/{id}` | Product edit (manage-products) |
| GET | `/brands`, `/units` | Product edit dropdowns |
| GET | `/shifts/current` | Drawer status and live totals |
| POST | `/shifts`, `/shifts/{id}/close` | Open / close shift |
| GET / POST | `/cash-transactions` | Cash in/out of the open shift |
| POST | `/sales` | Checkout |
| GET | `/sales`, `/sales/{id}` | History, detail, unknown-outcome recovery, reprint |

## Dependencies

Runtime: `flutter_riverpod`, `dio`, `flutter_secure_storage`, `go_router`, `intl`, `uuid`,
`mobile_scanner`, `print_bluetooth_thermal`, `share_plus`, `flutter_localizations` (SDK).
Dev: `flutter_test`, `integration_test` (SDK), `flutter_lints`.

## Known limitations

1. **Backend PR not merged.** Until `feature/sales-idempotency` is merged and migrated
   everywhere, safe re-send after a timeout falls back to manual verification, and the
   history date filter is ignored by the server.
2. **Shift live totals** come from the backend, whose cash-sales figure counts all cash sales of the tenant during the shift window (not only the shift owner's) — see PROJECT_ANALYSIS §9.7.
3. **Not yet verified on physical hardware:** camera scanning and Bluetooth printing were
   tested with fakes and an emulator only.
4. **Release signing:** without `android/key.properties` the APK uses the debug key.
5. **iOS** project exists but was not built or tested (needs macOS/Xcode).
6. **Backend data scope:** dashboard figures are tenant-wide; sales history shows all
   cashiers of the outlet; `settings` (store name) are global, not per tenant.
7. **Backend invoice numbering** (`countForToday() + 1`) can collide under concurrent
   checkouts in one tenant → one request fails with 500 (no duplicate, no stock loss).
8. Receipts are shared as text (no PDF/image); non-Latin characters print as `?`.
9. Product images are not cached on disk; catalog requires a connection.

## Recommended next tasks

1. Merge `kagoem-pos-saas` `feature/sales-idempotency` and run the migration on staging/production.
2. Field test on the target phones (Infinix HOT 60 Pro+) with a real thermal printer and real barcodes.
3. Create the release keystore and `android/key.properties`; build with `--split-per-abi`.
4. Backend: scope the shift's cash-sales total to the shift owner/branch (affects expected balance).
5. Backend: per-tenant invoice sequence (fix the race), per-tenant settings, optional `user_id` filter on `/sales`.
6. Optional: image disk cache; PDF receipt sharing.

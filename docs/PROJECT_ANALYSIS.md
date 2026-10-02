# Project Analysis — Kagoem POS Mobile (Cashier)

Phase 1 output. Analysis date: 2026-10-02.
Backend analysed: `/var/www/kagoem-pos-saas` @ `27a9669` (branch `main`, clean tree).
Companion docs: [API_MAPPING.md](API_MAPPING.md) · [DATABASE_MAPPING.md](DATABASE_MAPPING.md) · [CASHIER_PERMISSION.md](CASHIER_PERMISSION.md)

No backend files were modified during this phase.

---

## 1. Repository layout

```text
kagoem-pos-saas/
├── backend/    Laravel 12 (PHP ^8.2) REST API: the source of truth
├── frontend/   React + Vite SPA (TanStack Router/Query, axios, shadcn/radix): admin + web POS
└── *.md        design/implementation records (tenancy, isolation, provisioning, plans)
```

`/var/www/pos-cashier` is the older single-tenant "Nova POS" predecessor. It is
**not** the target backend. Some legacy naming remains in kagoem-pos-saas
(`nova_pos_*` storage keys, `company_name` default `Nova POS`).

## 2. Environment

| Tool | Version |
|---|---|
| Flutter | 3.47.5 (stable, 2026-09-17) |
| Dart | 3.13.4 |
| Flutter project root | `/var/www/pos-saas-mobile` (empty; not a git repo yet) |

`flutter doctor` (Android toolchain, licenses) is checked at the start of Phase 2.

## 3. Backend architecture

Layered as Controller → FormRequest (validation) → Service (business logic) →
Repository (interface + Eloquent) → Model, with an API Resource for each response.

| Concern | Implementation |
|---|---|
| Framework | Laravel 12 |
| API prefix | `/api/v1` |
| Auth | **Laravel Sanctum personal access tokens** (Bearer). `expiration = null`, **no refresh token** |
| Authorization | **spatie/laravel-permission** v8, `teams = false` (global roles), route `can:` middleware |
| Multi-tenancy | Single database, `tenant_id` column + `BelongsToTenant` global scope; active tenant from the `X-Tenant-ID` header |
| Plan gating | `tenant.module:<products\|sales\|reports\|inventory>` middleware, from `tenants.modules` |
| Responses | `{success, message, data[, meta]}`; errors `{success:false, message, errors[, code]}` |
| Tests | PHPUnit feature tests for every controller (`tests/Feature/Api/*`) |

## 4. Authentication

- Login by **email + password** only (`LoginRequest`: `email` must be a valid email). There is no username login.
- `POST /auth/login` returns `{user, token}`. The token is a Sanctum plain-text token.
- Inactive users (`is_active = false`) get a 422 at login.
- Throttle: 5 logins/min per IP+email.
- Logout revokes only the current token.
- **No refresh flow.** The token lives until logout or server-side revocation. Any 401 means a fresh login is needed.
- Session restore: the stored token, then `GET /auth/me`.

## 5. Tenant mechanism

```text
Login → GET /tenants (active memberships of active tenants)
      → 0: Access Denied   1: auto-select   >1: picker
      → every request: X-Tenant-ID: <id>
      → TenantMiddleware → TenantResolver (tenant exists, status active,
        membership exists, membership active) → TenantContext
      → BelongsToTenant global scope filters all tenant models
```

- The resolver is the single source of truth, and the backend keeps no server-side "active tenant" (the design record says so explicitly). The client keeps the selection.
- A missing header with exactly one membership is resolved automatically. With several memberships the backend returns 409 `TENANT_REQUIRED`.
- Cross-tenant ids return 404 (route binding) or the validation error `validation.exists` (`BelongsToActiveTenant`). Ids never leak between tenants.
- The web frontend clears the active tenant on `TENANT_NOT_FOUND / INACTIVE / ACCESS_DENIED / MEMBERSHIP_INACTIVE`. Mobile does the same, and also handles `TENANT_REQUIRED`, which the web does not.
- On tenant switch the mobile app **clears the cart, the product/category/customer caches and the dashboard**. The web does not, which is a web bug that mobile won't copy.

**Branch (outlet):** `users.branch_id` is an optional *home branch*. When set, the
server forces it on every branch-aware call (sales, shifts, cash, lists).
A user without a home branch can choose a branch, which is sent as `branch_id`.
Mobile: `effectiveBranchId = user.branch_id ?? selectedBranchId`, the same as the web.

## 6. Roles & permissions (summary)

Seeded roles: Admin, Owner, Manager, Supervisor, **Kasir**, Gudang.
Kasir = `manage-sales` + `operate-cash-drawer`.
The web gates the POS page on permission `manage-sales` + module `sales`, never on role name.
Full matrix: [CASHIER_PERMISSION.md](CASHIER_PERMISSION.md).

## 7. Domain findings relevant to the cashier

### Products
- Fields: price, stock (int), min_stock, per-product `tax_percentage` (default 11) and `discount_percentage`, barcode and sku (both **globally** unique), image, is_active.
- Search is a LIKE over name, sku and barcode. **There is no exact barcode endpoint.** The web does search + exact match on the client, and mobile does the same.

### Pricing / totals
- Calculated **only on the server**. The client sends `product_id` + `qty`.
- Discount and tax are per product, line by line (formula in API_MAPPING §6.2).
- There is no manual discount, no cart-level discount and no promo engine. The spec's "discount if backend allows" therefore means **display-only per-product discount**.
- The global `settings.tax_percentage` is not used by checkout.

### Stock
- Validated and decremented inside the checkout transaction with row locks (`lockForUpdate`). This makes the backend the authority.
- The client pre-check (`qty ≤ product.stock`) is only a UX hint. The web does the same.
- Checkout does not write `stock_movements` rows.
- Checkout does not reject `is_active = false` products. The catalog already filters `is_active=1`, so this isn't a concern for mobile.

### Payment
- One method per sale. The enum is `cash, debit, credit_card, transfer, qris, e_wallet`.
- There is no payment table, payment gateway or QRIS integration. Non-cash methods are only recorded labels.
- Rule: `paid_amount ≥ grand_total`. The server computes change.

### Sale / invoice
- The server generates `invoice_number = TX-YYMMDD-NNNNN`, unique per tenant. The checkout always creates `status = paid`.
- The response (`SaleResource`) carries everything the receipt needs.
- Refund exists (it restores stock and sets `status = refunded`).

### Shift / cash drawer
- Exists, but the **sale is not linked to a shift** and checkout does not require one. The web POS does not enforce shifts either.

### Hold cart
- No backend support. The web keeps held carts in localStorage (a product snapshot, not refreshed on resume).
- Mobile can provide a **local** hold feature backed by device storage, scoped by tenant + user and re-validated against the API on resume. It never creates server data.

### Customers
- List/search are open to members. Create needs `manage-customers` (Kasir lacks it).
- Walk-in = `customer_id: null`.

### Settings
- A **global** key/value table with no `tenant_id`. `company_name` is the same for every tenant.

### Receipt (web reference)
- Fields: company_name, date, invoice, cashier, customer/Walk-in, items (qty × price, subtotal), Subtotal, Diskon, Pajak, Total, method + paid, Kembalian, and the footer "Terima kasih atas kunjungan Anda".
- Width: 58mm = 32 cols, 80mm = 48 cols.
- The web already has an **ESC/POS builder** (`frontend/src/lib/escpos.ts`) and Web-Bluetooth printing. The mobile `ReceiptFormatter` will reproduce the same layout.

## 8. Existing web POS behaviour that mobile follows (or improves)

| Behaviour | Web | Mobile plan |
|---|---|---|
| Gate | `manage-sales` + module `sales` | same |
| Catalog | `is_active=1`, per_page 100, category chips | same filters, infinite scroll |
| Barcode | Enter in search → exact barcode/sku match, silent if none | camera scanner (and HID scanners) → exact match → "Produk tidak ditemukan" |
| Cart limits | qty clamped to stock, out of stock blocked | same (hint only) |
| Totals preview | client replica of server formula | same, integer money math |
| Customer | picker with Walk-in (hidden on small screens) | always available |
| Payment | 6 methods, non-cash sets paid = ceil(total) | same; amount locked for non-cash; quick-cash buttons |
| Double submit | button disabled while pending | + single-flight guard + no retry + "status unknown" recovery |
| Success | dialog: invoice, total, change, print, new | receipt screen: print / share / new transaction |
| History | invoice search, status/method filter, no date filter, no reprint | same filters + reprint; date filter blocked by backend (§9) |
| Hold cart | localStorage, global, not cleared on logout | local, scoped per tenant+user, re-priced on resume |

## 9. Backend gaps and proposed changes (NOT implemented: need approval)

The rules say: document first, don't change the backend without reason.
In priority order:

1. ✅ **Done in PR `feature/sales-idempotency` (D4 approved).** **Checkout idempotency (high).** There is no way to make `POST /sales` safe to retry. If a request times out after the server commits, the cashier may charge twice.
   Proposal (additive, backward compatible):
   - Nullable column `sales.client_reference` (UUID) with unique `(tenant_id, client_reference)`.
   - The optional header `Idempotency-Key` (or a body field) is stored on create. If the key already exists, the endpoint returns the existing sale with 200.
   - Web and existing clients are unaffected.
2. **Invoice number race (medium).** `countForToday() + 1` without a lock. Two concurrent checkouts in the same tenant can both compute the same number. The `(tenant_id, invoice_number)` unique index then makes one of them fail with a 500, and stock is rolled back. That is safe, but the cashier sees an error. The fix is a per-tenant sequence/lock or a retry on unique violation.
3. ✅ **Done in the same PR.** **Sales date filter (low, trivial).** Add `'date_from', 'date_to'` to `$request->only()` in `SaleController::index`. The repository already supports them.
4. **"My transactions" filter (low).** `user_id` filter on `GET /sales` (optional).
5. **Exact barcode lookup (low, optional).** Something like `GET /products?barcode=` with an exact match. The current search + client match works, so this is only an optimisation.
6. **Settings are not tenant-scoped (medium, product decision).** Receipts across tenants share `company_name`. This is out of the mobile scope, recorded for the backend owner.
7. **Shift live summary counts all cash sales in the tenant** (`cashTotalForRange` has no `user_id`/branch filter), not just the shift owner's. Recorded only; the mobile app does not depend on it.

Phases 2–5 are **built against the backend as it is now**. Until change 1 exists, the
mobile app uses the client-side mitigation in API_MAPPING §6.3.

## 10. Decisions needed before / during Phase 2

| # | Question | Proposed default |
|---|---|---|
| D1 | Who can use the app: any user with `manage-sales` (web parity) or only role `Kasir`? | Permission `manage-sales` (web parity; role names are editable) |
| D2 | Expose refund in mobile? (backend allows it for Kasir) | No in the MVP |
| D3 | Include shift open/close + cash in/out in mobile? | Yes, as an optional menu (not a gate on selling, same as web) |
| D4 | Implement backend idempotency (§9.1) in kagoem-pos-saas? | Yes, as a separate small backend PR, after approval |
| D5 | Receipt header given global settings | `company_name` + tenant name + branch name |
| D6 | Project location | Flutter project at `/var/www/pos-saas-mobile`, git init + branch `feature/mobile-cashier` |

## 11. Mobile architecture plan (Phase 2 preview)

- **State:** Riverpod (single framework).
- **HTTP:** Dio with interceptors:
  - `AuthInterceptor` adds the Bearer token, `X-Tenant-ID` and `Accept`.
  - `ErrorInterceptor` maps responses to `AppFailure`.
  - Retry applies to GETs only.
- **Storage:**
  - `flutter_secure_storage`: token, active tenant id, selected branch id.
  - Local DB (drift/sqflite): product and category cache plus held carts (Phase 3+), behind `LocalDataSource`.
- **Routing:** go_router with redirect guards in this order: splash → login → tenant → access check → home.
- **Layers:** `data` (models, remote/local datasources, repository impls) → `domain` (entities, repository contracts, use cases) → `features/*` (UI + providers). The domain layer has no Dio import.
- **Money:** `Money` value type in integer sen; `CurrencyFormatter` driven by the settings keys.
- **Config:** `--dart-define-from-file=env/<flavor>.json` with `API_BASE_URL` for development, staging and production. No secrets exist client-side.
- **Scanner:** `mobile_scanner` (EAN-13/8, UPC-A/E, Code128, Code39, QR). HID/keyboard scanners are also supported through the search field.
- **Printing:** an abstract `PrinterService`, with `BluetoothPrinterService` as the implementation and `ReceiptFormatter` that produces ESC/POS bytes. The library is isolated behind the interface.
- **Responsive:** below 600dp the flow is catalog → cart → checkout; from 840dp up it uses two panes (catalog | cart).

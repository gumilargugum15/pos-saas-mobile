# API Mapping — Kagoem POS Mobile (Cashier)

Mapping: **Flutter feature → endpoint → method → request → response → auth → permission**.

Every endpoint below exists in `kagoem-pos-saas/backend/routes/api.php` and was
confirmed with `php artisan route:list`. The web POS usage
(`kagoem-pos-saas/frontend/src`) is noted where it defines the expected behaviour.

---

## 0. Conventions (apply to every call)

| Item | Value |
|---|---|
| Base URL | `${API_BASE_URL}` = `<host>/api/v1` (web uses `VITE_API_URL`, e.g. `http://localhost:8001/api/v1`) |
| Headers | `Accept: application/json` (**required**: without it Laravel may return HTML/redirects), `Content-Type: application/json` |
| Auth | `Authorization: Bearer <sanctum plain-text token>` |
| Tenant | `X-Tenant-ID: <tenants.id>` on every request once a tenant is selected (the web POS sends it on all requests) |
| Token lifetime | Sanctum `expiration = null`: tokens do not expire; **no refresh-token endpoint exists** |
| Login throttle | `throttle:login` = 5/min per IP+email → 429 |

### Success envelope (`Controller::success`)
```json
{ "success": true, "message": "Berhasil", "data": { } }
```

### Paginated envelope (`Controller::paginated`)
```json
{ "success": true, "message": "Berhasil", "data": [ ],
  "meta": { "current_page": 1, "last_page": 4, "per_page": 15, "total": 52 } }
```
Query: `page`, `per_page` (default 15, no server max), `sort`, `direction` (`asc|desc`).

### Error envelope (`bootstrap/app.php`)
| Status | Body | Source | Mobile message |
|---|---|---|---|
| 401 | `{success:false, message:"Unauthenticated.", errors:[]}` | `AuthenticationException` | "Sesi Anda telah berakhir. Silakan login kembali." → clear token → Login |
| 403 | `{success:false, message:"This action is unauthorized.", errors:[]}` | `can:` middleware | "Anda tidak memiliki akses untuk fitur ini." |
| 403 | `{..., code:"PLAN_MODULE_UNAVAILABLE"}` | `tenant.module` | backend `message` (already Indonesian) |
| 403/404 | `{..., code:"TENANT_ACCESS_DENIED" \| "TENANT_MEMBERSHIP_INACTIVE" \| "TENANT_INACTIVE" \| "TENANT_NOT_FOUND"}` | `TenantResolver` | backend `message` → clear active tenant → tenant picker |
| 409 | `{..., code:"TENANT_REQUIRED"}` | `TenantResolver` | → tenant picker |
| 404 | `{success:false, message:"No query results for model ...", errors:[]}` | route-model binding (also cross-tenant ids) | "Data tidak ditemukan." (never show raw message) |
| 422 | `{success:false, message:"Validasi Gagal", errors:{field:[msg]}}` | `ValidationException` | first `errors` message (already Indonesian for business rules, e.g. stock) |
| 422 | `{..., code:"PLAN_LIMIT_REACHED", errors:{...}}` | `TenantPlan` | backend `message` (not hit by cashier flows) |
| 429 | `{success:false, message:"Too Many Attempts.", errors:[]}` | throttle | "Terlalu banyak percobaan. Coba lagi sebentar." |
| 5xx | `{message:"Server Error"}` (no envelope) | unhandled | "Terjadi kesalahan pada server. Silakan coba lagi." |
| timeout / no network | — | Dio | "Tidak dapat terhubung ke server." (**checkout: see §6.3**) |

Money fields arrive as JSON numbers (PHP `(float)` cast). Settings values arrive as strings.

---

## 1. Authentication

### Login
- `POST /auth/login` · public · throttle 5/min
- Request: `{ "email": "kasir@toko.id", "password": "..." }` (`email` must be a valid email; there is no username login)
- 200: `data = { user: UserResource, token: "1|abc..." }`
- 422: `errors.email = ["Email atau password salah."]` or `["Akun Anda tidak aktif. Hubungi administrator."]`

### Current user
- `GET /auth/me` · Bearer
- 200: `data = UserResource { id, name, email, phone, avatar_url, is_active, branch_id, branch_name, roles[], permissions[] }`
- Used on splash (session check) and after a 403 (refresh permissions).

### Logout
- `POST /auth/logout` · Bearer → revokes the current token only. The client clears local state even if this call fails.

### Profile / password (optional, profile screen)
- `PUT /auth/profile` · Bearer
- `PUT /auth/change-password` · Bearer · `{current_password, password, password_confirmation}` (see `ChangePasswordRequest`)

Not used: `forgot-password` / `reset-password` (email-link flow for the web).

## 2. Tenant & branch

### Tenant list
- `GET /tenants` · Bearer · **no** `tenant.context`
- 200: `data = [ { id, name, slug, status, role, membership_status, plan, limits{max_users,max_branches,max_products}, modules: string[]|null } ]`
- Only active memberships of active tenants are returned.
- 1 tenant → auto-select. More than one → picker. 0 → Access Denied.
- Selection is purely client-side: there is **no** switch endpoint (`TENANT_SWITCHING_API_ARCHITECTURE_RECONCILIATION.md`).

### Branches
- `GET /branches` · Bearer + tenant · query `search, is_active, sort, direction, per_page`
- `GET /branches/{id}`
- Rule (`Controller::resolveBranchId`): if `user.branch_id` is set, the server **forces** it and ignores client input. Otherwise the client may send `branch_id` on sales, shifts and cash transactions and on list filters. Effective branch = `user.branch_id ?? selectedBranchId` (same as web).

## 3. Dashboard

- `GET /dashboard` · Bearer + tenant · no permission
- 200: `data = { stats: { today_sales, today_sales_change_percent, today_profit, today_profit_change_percent, transactions_count, transactions_change_percent, products_count, customers_count, low_stock_count, pending_orders_count, cash_in_drawer }, sales_trend[], payment_methods[], sales_by_category[], top_products[], latest_transactions[], low_stock_products[] }`
- Mobile uses `stats.today_sales`, `stats.transactions_count`, `stats.products_count` only. These are **tenant-wide, not branch or cashier** figures.

## 4. Catalog

### Product list / search / barcode
- `GET /products` · Bearer + tenant · read is open to every member
- Query: `search` (LIKE on `name`, `sku`, `barcode`), `category_id`, `brand_id`, `is_active` (`1`), `low_stock`, `sort` (`name|sku|price|cost_price|stock|is_active|created_at`), `direction`, `per_page`, `page`
- 200: paginated `ProductResource { id, barcode, sku, name, category_id, category_name, brand_id, brand_name, unit_id, unit_name, cost_price, price, stock, min_stock, tax_percentage, discount_percentage, image_url, is_active, is_low_stock, created_at }`
- Catalog: `is_active=1&per_page=50` with infinite scroll (web uses `per_page=100`, no paging).
- **Barcode scan**: there is **no exact-lookup endpoint**. Same approach as the web: `GET /products?search=<code>&is_active=1&per_page=5`, then pick the item where `barcode == code || sku == code` exactly. No exact match → "Produk tidak ditemukan" (the web fails silently; mobile shows a message). Never create a product.

### Product detail
- `GET /products/{id}` · 200 `data = ProductResource` · 404 if missing or another tenant's product.

### Categories
- `GET /categories` · query `search, is_active, sort, direction, per_page` → paginated `{ id, name, slug, is_active, created_at }`
- Mobile: `is_active=1&per_page=100` → filter chips.

## 5. Customers

- `GET /customers` · Bearer + tenant + module `sales` · query `search` (name/phone/email), `is_active`, `sort`, `direction`, `per_page`
- 200: paginated `{ id, name, phone, email, address, is_active, created_at }`
- Picker at checkout: `is_active=1&per_page=20`, debounced search. The first option is **Walk-in** (`customer_id = null`).
- `GET /customers/{id}`
- `POST /customers` · `can:manage-customers` (**Kasir does not have it**) · `{ name*, phone?, email? (unique), address?, is_active? }` → 201. Shown only when the permission is present.

## 6. Checkout (create sale)

### 6.1 Request
- `POST /sales` · Bearer + tenant + module `sales` + `can:manage-sales`
```json
{
  "branch_id": 3,            // nullable; ignored when user has a home branch
  "customer_id": null,       // nullable = walk-in
  "items": [ { "product_id": 12, "qty": 2 }, { "product_id": 40, "qty": 1 } ],
  "payment_method": "cash",  // cash | debit | credit_card | transfer | qris | e_wallet
  "paid_amount": 50000
}
```
Validation (`StoreSaleRequest`): `items` min 1; `qty` integer ≥ 1; product, customer and branch ids must belong to the active tenant; `paid_amount` numeric ≥ 0.

**The client never sends prices, discounts, tax or totals.** The server computes everything from current product rows.

### 6.2 Server behaviour (`SaleService::checkout`, one DB transaction)
1. `SELECT … FOR UPDATE` on the products.
2. Per line: stock check → 422 `items: ["Stok {name} tidak mencukupi (tersisa N)."]`.
3. `gross = price×qty`; `disc = round(gross×disc%/100, 2)`; `tax = round((gross−disc)×tax%/100, 2)`; `line = gross−disc+tax`.
4. Decrement stock.
5. `grand_total = round(Σgross − Σdisc + Σtax, 2)`. If `paid_amount < grand_total` → 422 `paid_amount: ["Jumlah pembayaran kurang dari total belanja."]`.
6. Insert the sale with `status = paid`, `invoice_number = TX-YYMMDD-NNNNN` (per-tenant daily count + 1), `user_id = auth user`, and the sale items.

- 201: `data = SaleResource { id, invoice_number, branch_id, branch_name, customer{id,name}|null, cashier_name, items[{id, product_id, product_name, qty, price, discount_amount, tax_amount, subtotal}], subtotal, discount_amount, tax_amount, grand_total, paid_amount, change_amount, payment_method, status, created_at }`
- No manual or cart-level discount input exists. Discount = per-product `discount_percentage` only.
- No split payment. One method per sale.
- An open shift is **not** required (the web POS does not require one either).
- Non-cash methods: the web sets `paid_amount = ceil(grand_total)`. Mobile does the same and locks the field for non-cash.

### 6.3 Idempotency / double submit

**Backend support:** branch `feature/sales-idempotency` (kagoem-pos-saas `0470c76`, pending merge).
- Header `Idempotency-Key: <uuid v4>` (`[A-Za-z0-9_-]`, max 64), stored as `sales.client_reference` (unique per tenant).
- First request returns **201**. A retry with the same key and the same cart returns **200** `"Transaksi sudah tersimpan sebelumnya"` with the **original** sale, and stock is not decremented again.
- The same key with a different cart, payment method, customer or paid amount returns **422** `errors.idempotency_key`.
- `SaleResource` now includes `client_reference`.

**Mobile contract:**
- Generate one key per checkout attempt (a new key only after the cart, customer or payment changes, or after success).
- On timeout or network loss, retry **with the same key**. Treat 200 and 201 both as success.

**Fallback while the branch is not merged/deployed.** The header is ignored by the old backend; the following applies:
- No idempotency header, no client reference column, no unique key besides `invoice_number`, which is server-generated.
- Mobile mitigation (no backend change):
  - The button is disabled and the submit runs as a single in-flight `Future`.
  - **No automatic retry** on POST `/sales`. The Dio retry interceptor excludes it.
  - A client `checkoutAttemptId` is kept in memory for logging only.
  - On timeout or a lost connection after send, the outcome is shown as **"Status transaksi tidak diketahui"**. The app fetches `GET /sales?sort=created_at&direction=desc&per_page=10` (branch scoped) and shows recent sales so the cashier can confirm whether the sale exists before resubmitting.
- The backend change it needs is in PROJECT_ANALYSIS §9 (proposal only; not implemented).

## 7. Transaction history

- `GET /sales` · Bearer + tenant + module `sales` · read open to members
- Query that **actually works**: `search` (invoice LIKE), `status` (`paid|refunded|void|pending`), `payment_method`, `customer_id`, `branch_id` (forced to home branch), `sort` (`invoice_number|grand_total|status|created_at`), `direction`, `per_page`, `page`.
- `date_from`, `date_to` (`YYYY-MM-DD`, inclusive, on `created_at`): enabled in branch `feature/sales-idempotency`. On the old backend they are silently ignored.
- Results are **not** limited to the cashier's own sales.
- Detail: `GET /sales/{id}` → `SaleResource` with items, customer, cashier, branch. 404 cross-tenant.
- Reprint: built client-side from the `SaleResource` (no reprint endpoint, none needed).
- Refund: `POST /sales/{id}/refund` (no body) exists and Kasir is allowed, but it is **not exposed in the MVP** (CASHIER_PERMISSION §5.1).

## 8. Shift & cash drawer (optional module for cashier)

| Feature | Endpoint | Request | Response `data` |
|---|---|---|---|
| Current shift | `GET /shifts/current` | — | `{ shift: ShiftResource\|null, live: {cash_sales, cash_in_total, cash_out_total, expected_balance}\|null }` |
| Open | `POST /shifts` | `{ branch_id?, opening_balance*, notes? }` | `ShiftResource` (201); 422 if one is already open |
| Close | `POST /shifts/{id}/close` | `{ closing_balance*, notes? }` | `ShiftResource` with `expected_balance`, `variance` |
| History | `GET /shifts` | `status, sort, direction, per_page, branch_id` | paginated (own shifts only for non-`manage-finance`) |
| Cash in/out | `POST /cash-transactions` | `{ branch_id?, type: in\|out, category: income\|deposit\|expense\|withdrawal\|other, amount ≥0.01, description* }` | 201 |
| Cash list | `GET /cash-transactions` | `search, branch_id, sort, direction, per_page` | paginated |

All are gated by `can:operate-cash-drawer` and module `sales`.

## 9. Settings (receipt / currency)

- `GET /settings` · Bearer · **no tenant scope** (global table)
- 200: `data = { currency_name, currency_code, currency_symbol, symbol_position, decimal_digits, thousand_separator, decimal_separator, tax_percentage, company_name, company_address, company_phone, company_email, timezone, receipt_paper_size }` (all strings)
- Receipt uses `company_name` (the web does too) and `receipt_paper_size` (`58mm` = 32 cols, `80mm` = 48 cols). Because settings are global, `company_name` is the same for every tenant. Mobile prints the **tenant name** and **branch name** under it (PROJECT_ANALYSIS §10).

## 10. Endpoints intentionally unused by the mobile app

`/provisioning/tenants`, `/users*`, `/roles*`, `/permissions*`, `PUT /settings`,
`POST|PUT|DELETE` on products/categories/brands/units/branches/warehouses,
`/brands*`, `/units*`, `/warehouses*`, `/suppliers*`, `/purchases*`,
`/stock-movements*`, `/reports/*`, `PUT|DELETE /customers/{id}`,
`/auth/forgot-password`, `/auth/reset-password`.

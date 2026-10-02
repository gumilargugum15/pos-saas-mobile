# Database Mapping — Kagoem POS Mobile (Cashier)

Mapping: **Flutter model → Backend model/resource → Database table**.

Source of truth: `kagoem-pos-saas/backend` (Laravel 12). Every field below was
read from the migration, the Eloquent model, and the API Resource that actually
serializes it. The Flutter app only ever sees **API Resource fields**, never raw
columns, so the "API field" column is what the Flutter model parses.

Conventions found in the backend:

- Money columns are `DECIMAL(18,2)`, but every Resource casts them with
  `(float)` → JSON numbers (e.g. `15000.0`). Flutter must parse them into an
  integer-based `Money` type (see §9), never keep them as `double`.
- Percentages are `DECIMAL(5,2)` → JSON float.
- Timestamps are ISO-8601 strings (`toIso8601String()`), server timezone.
- Tenant-owned tables carry `tenant_id` and use the `BelongsToTenant` global
  scope. `tenant_id` is **never** exposed in Resources and must never be sent
  by the client (it is overwritten server-side on create).

---

## 1. User (session user)

| Flutter (`UserModel`) | API field (`UserResource`) | Column (`users`) | Notes |
|---|---|---|---|
| `id` | `id` | `id` | |
| `name` | `name` | `name` | |
| `email` | `email` | `email` | unique, login identifier |
| `phone` | `phone` | `phone` | nullable |
| `avatarUrl` | `avatar_url` | `avatar_path` | resolved via `asset('storage/...')` |
| `isActive` | `is_active` | `is_active` | inactive users cannot log in |
| `branchId` | `branch_id` | `branch_id` | nullable FK `branches`; **home branch lock** (see API_MAPPING §Branch) |
| `branchName` | `branch_name` | via `branch` relation | |
| `roles` | `roles` | `model_has_roles` → `roles.name` | Spatie, **global (teams = false)** |
| `permissions` | `permissions` | `role_has_permissions` / `model_has_permissions` | Spatie permission names |

Not exposed / never stored by Flutter: `password`, `remember_token`.

Endpoints: `POST /auth/login` (`data.user`), `GET /auth/me` (`data`).

## 2. Tenant membership

| Flutter (`TenantModel`) | API field (`TenantMembershipResource`) | Source |
|---|---|---|
| `id` | `id` | `tenants.id` — value sent as `X-Tenant-ID` |
| `name` | `name` | `tenants.name` |
| `slug` | `slug` | `tenants.slug` |
| `status` | `status` | `tenants.status` (only `active` returned) |
| `role` | `role` | `tenant_users.role` (string mirror of the Spatie role name, e.g. `Owner`, `Kasir`) |
| `membershipStatus` | `membership_status` | `tenant_users.status` (only `active` returned) |
| `plan` | `plan` | `tenants.plan` |
| `limits` | `limits.{max_users,max_branches,max_products}` | `tenants.max_*` (null = unlimited) |
| `modules` | `modules` | `tenants.modules` JSON; **`null` = all modules** |

Endpoint: `GET /tenants`.

## 3. Branch (outlet)

| Flutter (`BranchModel`) | API field (`BranchResource`) | Column (`branches`) |
|---|---|---|
| `id` | `id` | `id` |
| `name` | `name` | `name` |
| `code` | `code` | `code` (unique) |
| `phone` | `phone` | `phone` |
| `address` | `address` | `address` |
| `isActive` | `is_active` | `is_active` |

Table also has `tenant_id`, `deleted_at` (soft delete).

## 4. Category

| Flutter (`CategoryModel`) | API field (`CategoryResource`) | Column (`categories`) |
|---|---|---|
| `id` | `id` | `id` |
| `name` | `name` | `name` |
| `slug` | `slug` | `slug` |
| `isActive` | `is_active` | `is_active` |

## 5. Product

| Flutter (`ProductModel`) | API field (`ProductResource`) | Column (`products`) | Type | Cashier use |
|---|---|---|---|---|
| `id` | `id` | `id` | int | sent as `items[].product_id` |
| `barcode` | `barcode` | `barcode` | string? (**globally unique**) | scanner lookup |
| `sku` | `sku` | `sku` | string (**globally unique**) | search |
| `name` | `name` | `name` | string | |
| `categoryId` / `categoryName` | `category_id` / `category_name` | `category_id` | int / string | filter chips |
| `brandId` / `brandName` | `brand_id` / `brand_name` | `brand_id` | | display only |
| `unitId` / `unitName` | `unit_id` / `unit_name` | `unit_id` | | e.g. "pcs" |
| — | `cost_price` | `cost_price` | decimal(18,2) | **not used / not displayed in cashier UI** |
| `price` | `price` | `price` | decimal(18,2) → `Money` | |
| `stock` | `stock` | `stock` | int | display + soft pre-check |
| `minStock` | `min_stock` | `min_stock` | int | |
| `taxPercentage` | `tax_percentage` | `tax_percentage` | decimal(5,2), **default 11** | cart estimate |
| `discountPercentage` | `discount_percentage` | `discount_percentage` | decimal(5,2) | cart estimate |
| `imageUrl` | `image_url` | `image_path` | string? | |
| `isActive` | `is_active` | `is_active` | bool | list filter |
| `isLowStock` | `is_low_stock` | computed `stock <= min_stock` | bool | badge |

Table also has `tenant_id`, `deleted_at` (soft delete).

## 6. Customer

| Flutter (`CustomerModel`) | API field (`CustomerResource`) | Column (`customers`) |
|---|---|---|
| `id` | `id` | `id` |
| `name` | `name` | `name` |
| `phone` | `phone` | `phone` |
| `email` | `email` | `email` (validated `unique:customers,email` — **globally**, not per tenant) |
| `address` | `address` | `address` |
| `isActive` | `is_active` | `is_active` |

"Walk-in" is **not a row**: it is `customer_id = null` on the sale
(the backend's own dashboard renders null as `'Walk-in'`).

## 7. Sale (transaction) & Sale item

### `sales`

| Flutter (`SaleModel`) | API field (`SaleResource`) | Column | Notes |
|---|---|---|---|
| `id` | `id` | `id` | |
| `invoiceNumber` | `invoice_number` | `invoice_number` | **server generated** `TX-YYMMDD-NNNNN`; unique per `(tenant_id, invoice_number)` |
| `branchId` / `branchName` | `branch_id` / `branch_name` | `branch_id` | |
| `customer` | `customer {id,name}` \| null | `customer_id` | null = walk-in |
| `cashierName` | `cashier_name` | `user_id` → `users.name` | |
| `items` | `items[]` | `sale_items` | |
| `subtotal` | `subtotal` | `subtotal` | sum of gross lines (price × qty), **before** discount & tax |
| `discountAmount` | `discount_amount` | `discount_amount` | sum of per-line product discounts |
| `taxAmount` | `tax_amount` | `tax_amount` | sum of per-line taxes |
| `grandTotal` | `grand_total` | `grand_total` | `subtotal − discount + tax` |
| `paidAmount` | `paid_amount` | `paid_amount` | |
| `changeAmount` | `change_amount` | `change_amount` | `paid − grand_total` |
| `paymentMethod` | `payment_method` | `payment_method` ENUM | `cash, debit, credit_card, transfer, qris, e_wallet` |
| `status` | `status` | `status` ENUM | `paid, refunded, void, pending` (checkout always creates `paid`) |
| `createdAt` | `created_at` | `created_at` | |

Table also has `tenant_id`. **No** `shift_id`, **no** idempotency/client reference
column, **no** per-sale manual discount column, **no** note column.

### `sale_items`

| Flutter (`SaleItemModel`) | API field (`SaleItemResource`) | Column |
|---|---|---|
| `id` | `id` | `id` |
| `productId` | `product_id` | `product_id` |
| `productName` | `product_name` | `product_name` (snapshot at sale time) |
| `qty` | `qty` | `qty` (int) |
| `price` | `price` | `price` (snapshot) |
| `discountAmount` | `discount_amount` | `discount_amount` |
| `taxAmount` | `tax_amount` | `tax_amount` |
| `subtotal` | `subtotal` | `subtotal` = line gross − discount + tax |

`sale_items.cost_price` exists but is not exposed by the Resource.

## 8. Shift (cash drawer session)

| Flutter (`ShiftModel`) | API field (`ShiftResource`) | Column (`shifts`) |
|---|---|---|
| `id` | `id` | `id` |
| `userName` | `user_name` | `user_id` → `users.name` |
| `branchId` / `branchName` | `branch_id` / `branch_name` | `branch_id` |
| `openingBalance` | `opening_balance` | `opening_balance` |
| `closingBalance` | `closing_balance` | `closing_balance` (null while open) |
| `expectedBalance` | `expected_balance` | `expected_balance` |
| `variance` | `variance` | `variance` |
| `status` | `status` | ENUM `open, closed` |
| `notes` | `notes` | `notes` |
| `openedAt` / `closedAt` | `opened_at` / `closed_at` | |

`GET /shifts/current` additionally returns
`live {cash_sales, cash_in_total, cash_out_total, expected_balance}`.

## 9. Settings (store / receipt / currency)

`settings` is a **global key/value table** (`key`, `value`) — it has **no
`tenant_id`**. `GET /settings` returns a flat object, defaults merged with
stored rows:

| Key | Default | Flutter use |
|---|---|---|
| `company_name` | `Nova POS` | receipt header |
| `company_address` | `''` | receipt header |
| `company_phone` | `''` | receipt header |
| `company_email` | `''` | receipt header |
| `currency_symbol` | `Rp` | `CurrencyFormatter` |
| `symbol_position` | `front` | `CurrencyFormatter` |
| `decimal_digits` | `0` | `CurrencyFormatter` |
| `thousand_separator` | `.` | `CurrencyFormatter` |
| `decimal_separator` | `,` | `CurrencyFormatter` |
| `tax_percentage` | `11` | informational only — checkout uses per-product `tax_percentage` |
| `timezone` | `Asia/Jakarta` | receipt date display |
| `receipt_paper_size` | `80mm` | `ReceiptFormatter` line width (58mm/80mm) |

All values are strings.

## 10. Money representation in Flutter

- Backend stores 2 decimals, but IDR is displayed with `decimal_digits = 0`.
- Flutter `Money` stores **integer minor units (sen, ×100)**, parsed from the JSON
  number via `(value * 100).round()` once at the model boundary.
- Cart estimates replicate `SaleService::checkout` line-by-line with integer
  math and the same half-up rounding to 2 decimals, so the preview matches the
  server; the **server response is always what gets displayed after checkout**.
- `paid_amount` is sent as a decimal string/number in rupiah (e.g. `50000`).

## 11. Tables the cashier app does not touch

`suppliers`, `purchases`, `purchase_items`, `warehouses`, `stock_movements`,
`brands` (read only via product), `units` (read only via product),
`roles`/`permissions` (read only via `/auth/me`), `tenants` writes,
`personal_access_tokens` (managed by Sanctum).

Note: the checkout path decrements `products.stock` directly and does **not**
write a `stock_movements` row.

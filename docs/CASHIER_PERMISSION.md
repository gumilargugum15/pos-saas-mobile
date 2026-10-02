# Cashier Permission Mapping — Kagoem POS Mobile

Mapping: **Feature → Permission → Backend role**, plus the extra gates
(tenant module, branch lock) the backend applies.

Source of truth:
- `backend/database/seeders/RoleAndPermissionSeeder.php` (roles and default grants)
- `backend/routes/api.php` (`can:` and `tenant.module:` middleware)
- `backend/app/Services/ShiftService.php` (in-service `manage-finance` checks)
- `backend/config/plans.php` + `EnsureTenantHasModule` (plan modules)

Authorization uses **Spatie Laravel Permission** with `teams = false`:
roles and permissions are attached to the **user globally**, not per tenant.
`tenant_users.role` is only a display string that mirrors the role name.
The Flutter app reads permissions from `GET /auth/me` → `data.permissions`.

---

## 1. Roles and their default permissions (seeded)

| Permission | Admin | Owner | Manager | Supervisor | **Kasir** | Gudang |
|---|:-:|:-:|:-:|:-:|:-:|:-:|
| `manage-settings` | ✔ | ✔ | | | | |
| `manage-users` | ✔ | ✔ | | | | |
| `manage-products` | ✔ | ✔ | | | | |
| `manage-customers` | ✔ | ✔ | | | | |
| `manage-suppliers` | ✔ | ✔ | | | | |
| `manage-sales` | ✔ | ✔ | | | **✔** | |
| `manage-purchases` | ✔ | ✔ | | | | |
| `manage-inventory` | ✔ | ✔ | | | | ✔ |
| `manage-finance` | ✔ | ✔ | | | | |
| `view-reports` | ✔ | ✔ | ✔ | ✔ | | |
| `operate-cash-drawer` | ✔ | ✔ | | | **✔** | |

Roles are editable at runtime (`/roles`, `/permissions` for `manage-users`),
so the app **must not hard-code role names** — it gates on permission names.
The cashier role is named **`Kasir`** (not `CASHIER`).

## 2. App entry gate

| Check | Source | Result if it fails |
|---|---|---|
| Login ok, `is_active = true` | `AuthService::login` (422 otherwise) | Show the backend message |
| User has **`manage-sales`** | `/auth/me` permissions; backend gates `POST /sales` with it | **Access Denied** screen and logout |
| Active tenant resolved | `GET /tenants`, then `X-Tenant-ID` | Tenant picker; zero tenants → Access Denied |
| Tenant plan includes the **`sales`** module | `tenant.modules` (`null` = all) | "Fitur Sales tidak tersedia di paket Anda" |

Proposed rule: the app opens for any user with `manage-sales` (Kasir, and also
Owner/Admin, the same way the web POS does). Making it **Kasir-only** would mean
checking the role name, which the backend itself never does. This is an open
decision (see PROJECT_ANALYSIS §10).

## 3. Feature → permission → route

| Mobile feature | Endpoint(s) | Route gates | Permission | Kasir |
|---|---|---|---|:-:|
| Login / logout / me | `/auth/*` | — / `auth:sanctum` | — | ✔ |
| Change own password / profile | `PUT /auth/change-password`, `PUT /auth/profile` | `auth:sanctum` | — | ✔ |
| Tenant list / select | `GET /tenants` | `auth:sanctum` | — | ✔ |
| Dashboard summary | `GET /dashboard` | `tenant.context` | **none** | ✔ (see §5) |
| Product list / search / barcode / detail | `GET /products`, `GET /products/{id}` | `tenant.context` | none (read) | ✔ |
| Category list | `GET /categories` | `tenant.context` | none (read) | ✔ |
| Branch info | `GET /branches`, `GET /branches/{id}` | `tenant.context` | none (read) | ✔ |
| Customer list / search / pick | `GET /customers`, `GET /customers/{id}` | `tenant.context`, `tenant.module:sales` | none (read) | ✔ |
| **Create customer** | `POST /customers` | + `can:manage-customers` | `manage-customers` | **✘** |
| **Checkout (create sale)** | `POST /sales` | `tenant.module:sales`, `can:manage-sales` | `manage-sales` | ✔ |
| Transaction history / detail / reprint | `GET /sales`, `GET /sales/{id}` | `tenant.module:sales` | none (read) | ✔ |
| Refund | `POST /sales/{id}/refund` | `can:manage-sales` | `manage-sales` | ✔ (backend allows; see §5) |
| Shift open / current / close / history | `/shifts*` | `tenant.module:sales`, `can:operate-cash-drawer` | `operate-cash-drawer` | ✔ |
| Shift of another user | `GET /shifts/{id}`, close | in-service | `manage-finance` | ✘ (403) |
| Cash in / out | `/cash-transactions` | `can:operate-cash-drawer` | `operate-cash-drawer` | ✔ |
| Store / receipt settings (read) | `GET /settings` | `auth:sanctum` | none | ✔ |

## 4. Not in the mobile app at all

These are admin features. They are neither built nor routed, whatever the
user's permissions:

User Management (`/users`), Role and Permission Management (`/roles`,
`/permissions`), Tenant provisioning, Settings update (`PUT /settings`),
Branch and Warehouse CRUD, Product/Category/Brand/Unit CRUD, Suppliers,
Purchases, Stock Movements, Reports (`/reports/*`).

## 5. Gaps between "cashier" intent and backend permissions

Flutter must not loosen what the backend denies. Where the backend allows
**more** than a cashier app needs, the app hides the extra function and the
behaviour is documented here (the backend is not changed):

1. **Refund is allowed for Kasir.** `manage-sales` covers both
   `POST /sales` and `POST /sales/{id}/refund`. The mobile spec does not list
   refund. Default: **not exposed** in the MVP. This needs a product decision.
2. **Dashboard has no permission gate.** It returns tenant-wide
   `today_profit`, `cash_in_drawer`, `top_products`, and so on, and it is
   **not branch-filtered**. The mobile dashboard shows only
   `today_sales`, `transactions_count` and `products_count`, and labels them as
   tenant-wide. Profit is never displayed.
3. **Kasir cannot create customers** (`manage-customers` is missing). The "add customer"
   button is shown only when `permissions` contains `manage-customers`.
4. **Branch lock.** A user with a home `branch_id` is always forced to that branch
   (`Controller::resolveBranchId`). Any `branch_id` the client sends is ignored. A cashier
   without a home branch writes sales with `branch_id = null` unless
   the client sends one.
5. **Sales history is not limited to the cashier's own sales.** `GET /sales`
   filters by branch (home branch lock) only, not by `user_id`. Inside a
   branch, a cashier sees every cashier's transactions.

## 6. Client-side gating rules (implementation contract)

```text
canUseApp        = permissions ∋ 'manage-sales' && tenant.hasModule('sales')
canCheckout      = permissions ∋ 'manage-sales'
canCreateCustomer= permissions ∋ 'manage-customers'
canUseShift      = permissions ∋ 'operate-cash-drawer'
canRefund        = false   // MVP decision, see §5.1
tenant.hasModule(m) = tenant.modules == null || tenant.modules ∋ m
```

Client gating only affects the UI. The backend response (403 `This action is
unauthorized.`, 403 `PLAN_MODULE_UNAVAILABLE`, 403 `TENANT_*`) always wins.
On a 403 for a feature the app showed, the app shows the message and
re-fetches `/auth/me` so its permission cache refreshes.

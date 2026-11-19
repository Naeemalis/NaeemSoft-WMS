# NaeemSoft-WMS

Warehouse and inventory management system. PostgreSQL is the primary database and Flutter is the Android client.

## Repository layout

- `database/migrations/` — ordered PostgreSQL schema migrations.
- `backend/` — FastAPI service used by the Android app.
- `mobile/` — Flutter Android application source.
- `docker-compose.yml` — local PostgreSQL + API stack.
- `.github/workflows/android-build.yml` — builds a release APK and publishes it as a GitHub Actions artifact.

## Run the backend

1. Copy `.env.example` to `.env`.
2. Set a strong `POSTGRES_PASSWORD` and `WMS_API_KEY`.
3. Confirm `WMS_BASE_CURRENCY` is the currency you intend to use. The example value is DJF.
4. Start with `docker compose up --build -d`.
5. Check `http://localhost:8000/health` and API docs at `http://localhost:8000/docs`.

For an existing database volume, apply new migrations deliberately. Do not delete a production volume to force initialization.

## Android APK

A push changing `mobile/**` starts the **Build NaeemSoft-WMS Android APK** workflow. Download the `NaeemSoft-WMS-Android-APK` artifact from the successful Actions run.

## Implemented milestone 0.2

- Arabic right-to-left Android shell, dashboard, product catalogue and stock display.
- Separate multi-line receiving cashier with product grid; receipt drafts are submitted for approval and only approved receipts increase stock.
- Separate wholesale issue cashier with an available-stock product grid; zero-stock items are excluded from the issue catalogue.
- Issue drafts require submission and approval; approval allocates stock from batches using earliest expiry first and blocks insufficient stock.
- Product-specific unit conversions and manually entered prices per sale unit.
- Supplier and recipient account statement APIs and screens.
- Supplier settlement and recipient collection entries.
- Stock monitoring for zero balances and expiry within 30 days (highlighted green).
- API URL and API-key configuration.

## Important limitations

The first integration milestone still uses a shared private service API key and a system actor. It is for a trusted development/private network only. Before public or production exposure, implement per-user authentication, branch-scoped authorization, TLS and permission checks for approval and payment actions.

The current statement model records supplier receipts/payments and approved recipient issues/collections. Supplier and recipient return workflows, minimum-stock thresholds, stock counts, transfers, full role/permission UI and valuation (FIFO vs weighted average) still require subsequent implementation. The valuation method has not been selected.


## Product lifecycle traceability

- Product movement history API: `GET /api/products/{product_id}/movements` returns the append-only stock ledger with batch, warehouse, source document and actor references.
- Per-product reorder level API: `PATCH /api/products/{product_id}/reorder-level`; alerts are available from `GET /api/stock/reorder-alerts`.
- Migration 009 adds relational structures for return, count and transfer documents. These document workflows are schema groundwork only; posting/approval APIs and Android screens are still pending.

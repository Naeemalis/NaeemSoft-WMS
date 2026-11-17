# NaeemSoft-WMS

Warehouse and inventory management system. The project is being implemented in stages, with PostgreSQL as the primary database and Flutter for Android.

## Repository layout

- `database/migrations/` — ordered PostgreSQL schema migrations.
- `backend/` — FastAPI service used by the Android app.
- `mobile/` — Flutter Android application source.
- `docker-compose.yml` — local PostgreSQL + API stack.
- `.github/workflows/android-build.yml` — builds a release APK and publishes it as a GitHub Actions artifact.

## Run the backend

1. Copy `.env.example` to `.env`.
2. Set a strong `POSTGRES_PASSWORD` and `WMS_API_KEY`.
3. Confirm `WMS_BASE_CURRENCY` is the currency you intend to use. The example value is DJF; change it if needed.
4. Start the stack with Docker Compose:

   ```bash
   docker compose up --build -d
   ```

5. Check `http://localhost:8000/health` and API documentation at `http://localhost:8000/docs`.

The database migrations are mounted into PostgreSQL's initialization directory and run when the database volume is first created. If you change the initial migration set after the volume already exists, apply the new migration deliberately; do not delete a production database volume to force initialization.

## Build the Android APK

Every push that changes `mobile/**` or the Android build workflow starts the **Build NaeemSoft-WMS Android APK** workflow. Open the repository's Actions tab, select the successful run, and download the `NaeemSoft-WMS-Android-APK` artifact.

## Current Android milestone (0.1)

- Arabic right-to-left application shell.
- Dashboard indicators.
- Product master with product-specific units and independently entered prices.
- Stock display in the smallest/base unit only.
- Supplier registration.
- Receipt creation as draft, submission for approval and approval.
- API URL and API-key configuration from the app.

The current API uses a private service API key and a service actor for the first integration milestone. It is intended for a trusted development/private network only. Before public or production exposure, implement per-user login, branch-scoped permissions, TLS, and authorization checks for approval actions.

Sales invoices, quotations, customer and supplier statements, returns, stock counts, transfers, exchange-rate management, competitor intelligence and the full role/permission UI remain planned milestones. The valuation method (FIFO or weighted average) remains intentionally undecided.

# NaeemSoft-WMS Android

The Android source is in `lib/`. GitHub Actions generates the native Flutter Android wrapper and builds a release APK.

## Connect to the API

1. Start the PostgreSQL + API stack from the repository root (see the root README).
2. Open NaeemSoft-WMS on the Android phone.
3. Open **الإعدادات** and enter the API base URL, for example `http://192.168.1.20:8000` when the phone and server are on the same local network.
4. Enter the API key from the server's `.env` file and test the connection.

Use HTTPS when the API is exposed outside a trusted local network. Cleartext HTTP is enabled in this development build only to allow LAN testing.

## Current app scope

- Dashboard
- Product master with per-product units and independently entered sale prices
- Stock balance in the smallest/base unit only
- Suppliers
- Receipt draft, submit-for-approval and approval flow

Sales, customer accounts, returns, branch administration and full user/role authentication are later implementation milestones. The first API slice uses a private service API key and a service actor; do not expose it publicly before replacing that with per-user authentication and authorization.

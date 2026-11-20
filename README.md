# NaeemSoft-WMS

Offline-first Android inventory management for **one warehouse on one Android device**.

## Product decisions
- Flutter Android application; responsive on phones and tablets, portrait and landscape.
- SQLite database stored locally in the app's private storage. No server, API key, PostgreSQL, or internet dependency.
- Arabic, English, and French interface.
- Separate receiving and issuing cashiers with product catalogues.
- Recipient-based issue documents; every issue line is priced.
- Supplier and recipient statements, receiving/issue registers, daily/monthly receiving reports, and purchase-request register.
- Batch-level expiry tracking, FEFO issuing, stocktaking, returns, audit trail, and role-based local users.
- Product status indicators: out of stock, low stock, stagnant, expired, near expiry, and available.

## Repository layout
- `mobile/`: Flutter application source and package manifest.
- `.github/workflows/android-build.yml`: Android APK build and static analysis.
- `docs/`: architecture and database design notes.

## Build
The GitHub Actions workflow generates the Android platform wrapper, resolves Flutter packages, runs analysis/tests, builds a release APK, and uploads it as an artifact.

## Data safety
The SQLite database lives in the Android app's private data directory. Uninstalling the app or clearing its storage can delete local data. Export/restore backup functionality is a required production milestone and must be tested before operational use.

## Current milestone
This repository is being rebuilt as a local-only Android application. A successful APK build validates the application foundation, not completion of every inventory workflow. Receiving/issuing approvals, accounting postings, returns, stocktaking, PDF printing, and backup/restore must each pass their own tests before production use.

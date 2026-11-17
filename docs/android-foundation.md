# Android client foundation

## Confirmed target

- Android only; no iOS target is planned.
- Flutter is the application framework.
- Arabic is the default locale and uses RTL direction.
- English and French are also supported.
- The client must communicate with a secure backend API. PostgreSQL credentials must never be embedded in the APK.

## Current implementation

- Flutter app entry point and Material 3 theme.
- Language selector for Arabic, English and French.
- Initial dashboard shell identifying the WMS modules.
- Widget test for the default Arabic dashboard.
- GitHub Actions workflow for formatting, analysis, tests and release APK artifact generation.

## Not yet implemented

The shell is not connected to a live backend or database. Product management, receiving, receipt approval UI, stock browsing, issuing, sales, user administration and reports will be implemented against the existing PostgreSQL migrations and their business rules.

Do not mark a module complete until its UI, API contract, authorization checks, database transaction and acceptance tests are connected.

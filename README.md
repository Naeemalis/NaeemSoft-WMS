# NaeemSoft-WMS

Independent warehouse and inventory management system. The first client target is Android only.

## Technology

- Android client: Flutter
- Database: PostgreSQL, organized as ordered migrations under database/migrations
- Backend: secure API layer to be implemented; the Android app will not connect directly to PostgreSQL
- Languages: Arabic (default), English and French

## Current repository

The main branch already contains the PostgreSQL foundation and receipt-approval smoke tests. This Android development branch adds the Flutter client foundation without replacing or duplicating those database migrations.

## Android application foundation

- Arabic RTL is the default interface.
- The language selector supports Arabic, English and French.
- The current screen is the application shell, not a claim that the inventory workflows are already connected.
- Android platform files are generated in CI before the APK build.

## Build APK

The Android APK workflow runs Flutter formatting, analysis, widget tests and a release build. After a successful run, open the workflow run and download the artifact named NaeemSoft-WMS-Android-APK.

For local setup with Flutter installed:

    flutter create . --platforms=android --org com.naeemsoft --project-name naeemsoft_wms
    flutter pub get
    flutter run

## Database

Read database/README.md for migration order, inventory rules and current database scope.

## Current Android branch

android/flutter-foundation

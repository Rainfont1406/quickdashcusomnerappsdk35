# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

This project uses [FVM](https://fvm.app/) pinned to Flutter **3.27.3** (`fvm_config.json`). Prefix all Flutter commands with `fvm`:

```bash
fvm flutter pub get          # Install dependencies
fvm flutter run              # Run on connected device/emulator
fvm flutter build apk        # Android release build
fvm flutter build ios        # iOS release build
fvm flutter analyze          # Static analysis (flutter_lints rules)
fvm flutter test             # Run all tests
fvm flutter test test/foo_test.dart  # Run a single test file
```

After modifying `lib/services/localDatabase.dart` (the Moor/SQLite schema), regenerate the generated file:
```bash
fvm flutter pub run build_runner build --delete-conflicting-outputs
```

## Architecture Overview

**QuickDash Customer App** is a multi-service marketplace Flutter app backed entirely by Firebase (Firestore, Auth, Storage, FCB Messaging). It supports six distinct service verticals that share a common auth/user layer.

### Service Verticals

Each vertical has its own dashboard entry point, UI screens, and data models:

| Vertical | Dashboard | Root screen |
|---|---|---|
| Food/Vendor ordering | — | `lib/ui/home/HomeScreen.dart` |
| E-commerce | `lib/ecommarce_service/ecommarce_dashboard.dart` | `EcommerceHomeScreen.dart` |
| On-demand services | `lib/onDemand_service/onDemand_ui/onDemand_dashboard.dart` | `ondemand_home_screen.dart` |
| Parcel delivery | `lib/parcel_delivery/parcel_dashboard.dart` | `parcel_home_screen.dart` |
| Vehicle rental | `lib/rental_service/rental_service_dash_board.dart` | `rental_service_home_screen.dart` |
| Cab/ride | `lib/cab_service/dashboard_cab_service.dart` | `cab_home_screen.dart` |

`ServiceListScreen` (`lib/ui/service_list_screen.dart`) is the post-login router: it loads Firestore `sections`, selects the first active section, initialises all payment gateways, then pushes the appropriate dashboard.

### App Shell

`ContainerScreen` (`lib/ui/container/ContainerScreen.dart`) is the main scaffold. It owns the side drawer (`DrawerSelection` enum) and swaps `_currentWidget` in-place. All top-level screens (Home, Orders, Cart, Wallet, Profile, etc.) are rendered inside it. The `HomeScreen` is special-cased to hide the AppBar.

### Global State

Two global singletons span the entire app:

- `MyAppState.currentUser` — the logged-in `User` object; `null` when unauthenticated
- `sectionConstantModel` — the active `SectionModel` loaded from Firestore; used everywhere to gate features (e.g. `sectionConstantModel!.dineInActive`)

These live in `lib/main.dart` and `lib/constants.dart` respectively. Widgets read them directly rather than via Provider.

`DarkThemeProvider` (`lib/utils/DarkThemeProvider.dart`) is the only Provider-managed state and controls light/dark mode across the app.

### Data Layer

**`FireStoreUtils`** (`lib/services/FirebaseHelper.dart`) is the single data access class for all Firestore reads and writes. All Firestore collection name constants are in `lib/constants.dart`.

**`CartDatabase`** (`lib/services/localDatabase.dart`) is a local SQLite database (via `moor_flutter`) that persists cart items between sessions. The generated file `localDatabase.g.dart` must not be edited manually. Cart enforces single-vendor constraint — adding an item from a different vendor returns `false`.

### Navigation

Navigation helpers (`push`, `pushReplacement`, `pushAndRemoveUntil`) are in `lib/services/helper.dart`. Standard `Navigator` is used; there is no named routes or go_router setup.

### Theming

`AppThemeData` (`lib/theme/app_them_data.dart`) defines all colours and font family names. `primary500` is the brand colour and is used for interactive elements throughout. `primary300` is mutable — it gets overwritten at runtime from `settings/globalSettings` in Firestore (and again from the active section's `color` field). Always use `AppThemeData.*` constants; never hardcode hex values. Use `isDarkMode(context)` (from `lib/services/helper.dart`) to branch between light and dark variants.

Font families: `RadioCanadaBig-Regular/Medium/Bold/SemiBold` — accessed via `AppThemeData.regular`, `.medium`, `.bold`, `.semiBold`.

### Localisation

Uses `easy_localization`. Translation JSON files are in `assets/translations/` (en, ar, nl, fr, it, ru). All user-visible strings must be wrapped with `.tr()`. The active locale is persisted in `SharedPreferences` under key `"languageCode"`.

### Payment Gateways

All gateway credentials are fetched from Firestore at startup inside `ServiceListScreen._autoSelectFirstService()`. Supported gateways: Stripe, Razorpay, PayPal, PayStack, FlutterWave, Paytm, PayFast, MercadoPago, OrangeMoney, Xendit, MidTrans. Gateway setting models live in `lib/model/payment_model/` and `lib/model/`.

### Notifications

`NotificationService` (`lib/services/notification_service.dart`) wraps FCM. The FCM sender ID and service JSON URL are loaded from `settings/notification_setting` in Firestore. The FCM token is stored on the user's Firestore document and refreshed on every login.

### Firebase App Check

App Check is intentionally disabled in `lib/main.dart` (commented out with a TODO). Re-enable before production release with proper `playIntegrity`/`appAttest` providers.

# Where the red color comes from

## Summary
Red in the app can come from **two** places:

1. **Runtime overwrite of `AppThemeData.primary300`** (main cause for “Delivery type” and many accents)
2. **Hardcoded `Colors.red`** in some screens

---

## 1. Runtime overwrite of primary300 (why Delivery type and accents look red)

`AppThemeData.primary300` is the **only** non-const color in the theme. It is **reassigned at runtime** from your backend/section configuration:

| File | When / Where |
|------|----------------|
| `lib/main.dart` | App startup – section color from Firebase |
| `lib/ui/location_permission_screen.dart` | First section’s `color` |
| `lib/ui/QrCodeScanner/QrCodeScanner.dart` | Section model `color` |
| `lib/ui/service_list_screen.dart` | First section’s `color` |
| `lib/controller/on_boarding_controller.dart` | `app_customer_color` from onboarding |

So if the **section color** or **app_customer_color** in Firebase/admin is set to **red**, then **every UI that uses `primary300`** (Delivery type selector, View all, many buttons, icons, selected states) will show red.

**Default in code:** In `lib/theme/app_them_data.dart`, `primary300` is set to a blue/purple (`0xFF7C84BF`). That default is overridden as soon as the app loads the section/app color from the server.

**Fix options:**
- In **admin/Firebase**: set the section/app color to your desired primary (e.g. blue), **or**
- In **code**: use a **const** primary for key UIs (e.g. `primary500` / `primary400`) so they never turn red. This was done for Bill Details discount text, Delivery type selector, and Cart options.

---

## 2. Hardcoded `Colors.red`

Some screens use **explicit** `Colors.red` (e.g. for discounts, remove actions, errors). Those were replaced with theme primary where the intent was “accent” rather than “error”:

- **Order Details (Bill Details):** “Special Discount” and “Discount” amounts now use `primary500` / `primary400` (light/dark) instead of `Colors.red`.
- **Cart options sheet:** “Remove from Cart” text now uses `primary500` instead of `Colors.red`.

Other `Colors.red` usages remain where the intent is clearly **error/danger** (e.g. validation, alerts, wallet errors).

---

## 3. What was changed so red is not used for accents

- **Delivery type selector** (`lib/widget/delivery_type_selector.dart`): All previous `primary300` accents (header icon, selected option border/background/icon/text, checkmark, OK button) now use **`primary500`** (light) or **`primary400`** (dark). These are const and are not overwritten by the server, so Delivery type will not turn red even if section color is red.
- **Order Details – Bill Details:** Discount and Special Discount amounts use **`primary500`** (light) and **`primary400`** (dark) instead of `Colors.red`.
- **Cart options sheet:** “Remove from Cart” uses **`primary500`** instead of `Colors.red`.

So: **red on “Delivery type” and similar accents** = `primary300` coming from your backend/section color. **Red on discount/remove text** = previously hardcoded `Colors.red`; now replaced with primary for both light and dark mode.

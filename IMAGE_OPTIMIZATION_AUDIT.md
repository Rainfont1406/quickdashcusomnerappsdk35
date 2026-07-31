# QuickDash Customer App — Image Optimization Audit

Generated during the startup-performance investigation, 2026-07-15. Companion to the
progressive/viewport-based image loading fix in `HomeScreen.dart` (`_RestaurantCardImage`,
`_MenuCarousel`).

## 0. Progressive loading fix — verified working

Root cause: `AllStore` (`HomeScreen.dart:2761`, the main vertical "Restaurants Around You"
list) uses `shrinkWrap: true` + `NeverScrollableScrollPhysics`, which forces Flutter to
**build** all 10 vendor cards immediately regardless of scroll position. Each card's
`_RestaurantCardImage`/`_MenuCarousel` used to trigger its image fetch the instant it was
built, causing ~19 concurrent image requests on first paint (see investigation history).

Fix: added `visibility_detector` (pubspec.yaml) and gated both `_RestaurantCardImage` and
`_MenuCarousel` so they render a shimmer placeholder (`_StoryShimmer`) until the card is
actually scroll-visible; only then does the real `NetworkImageWidget` (and its image
fetch) get built. The gate latches permanently once visible (no re-hide/reload on scroll-away).

**Verified on-device (fresh launch, PID 19632):** zero `vendorCard START` events during the
entire `getData()`/`getBanner()` sequence; first burst after first frame = 4 images (1 story
circle + 3 vendor cards), then 2 more shortly after — vs. ~19 simultaneous before the fix.

## 1. Image inventory by screen

| Screen | Image | Display size (logical px) | Source field | Current hosting | Size variant used? |
|---|---|---|---|---|---|
| Home | Vendor card cover (`AllStore`, `_RestaurantCardImage`) | ~360×220 (`Responsive.height(24)` × full width) | `VendorModel.coverPhotoUrl(photos[i])` | Bunny (`cdn.quickdash.co.in/store/photos/`) — some legacy on Firebase Storage | **Yes** — picks pre-generated "cover" derivative over original |
| Home | Vendor logo fallback (no gallery photos) | same card slot, ~360×220 | `vendorModel.photo` (raw) | Bunny `profiles/vendors/` — some legacy Firebase Storage | No |
| Home | "New Arrivals" card | 155×~120 (`Responsive.height(14)`) | same as above, `_RestaurantCardImage`/`_MenuCarousel` | Bunny / mixed | Cover: yes; logo fallback: no |
| Home | "Popular near you" product carousel | 148×~94-131 (`_imgH`) | `productModel.photo` (raw) | Bunny `store/products/` | No |
| Home | Story circle avatar | 64×64 (ring padding included) | `vendor.photo` (raw) | Bunny `profiles/` — some legacy Firebase Storage | No |
| Home | Category icon | within 112px-tall row | `VendorCategoryModel.photo` | not sampled | No |
| Home | Top/middle banner | full-width, not measured this pass | `BannerModel.photo` | not sampled | No |
| Restaurant Details | Header cover (no gallery) | ~full-width × 40% screen height | `vendorModel.photo` (raw) | Bunny/mixed | No |
| Restaurant Details | Header cover carousel (gallery) | same, ~full-width × 40% | `VendorModel.coverPhotoUrl(photos[i])` | Bunny/mixed | **Yes** |
| Restaurant Details | Dish grid tile | `AspectRatio(16:9)`, tile width | `product.photo` (raw) | Bunny `store/products/` | No |
| Restaurant Details | Menu item thumbnail (main list) | 130×130 | `productModel.photo` (raw) | Bunny `store/products/` | No |
| Restaurant Details | "Pairs well with" card | 128×95 | `productModel.photo` (raw) | Bunny `store/products/` | No |
| Restaurant Details | Vendor info bottom-sheet photo | full-width × 150-220 (clamped) | `vendorModel.photo` (raw) | Bunny/mixed | No |
| Search | Result vendor logo | 100×100, `BoxFit.contain` | `_logoUrl(v)` — prefers `photos.first`, else `photo` (raw, no cover picked) | Bunny/mixed | No |
| Offers | Offer banner thumbnail | 100×100 | `OfferModel.imageOffer` (raw) | Bunny `store/photos/` (assumed) | No |

**Sampled real files** (downloaded and measured directly, not estimated):

| File | Claimed use | Real dimensions | Real size |
|---|---|---|---|
| `store/photos/d8c24d36-...jpg` | Vendor card cover | **1600×900px** | 278KB |
| `profiles/vendors/bf551335-...png` (actually a JPEG despite `.png` URL) | Vendor logo fallback | **633×573px** | 140KB |
| `profiles/0c17b9a9-...png` | Story circle source | **915×915px** | 1.12MB |
| `store/photos/9dc79b36-...jpg` | Vendor card cover | (parse unreliable — treat with caution) | **1.35MB** (confirmed via direct network measurement) |
| Largest observed (`store/photos/693e786b...jpg`) | Vendor card cover | not sampled for pixels | **5.48MB** (confirmed via network measurement) |

Every one of these is displayed at somewhere between 64px and ~450px logical width. None of
the sampled files are anywhere close to an appropriate source resolution for their use.

**Extra finding:** several files served under a `.png` URL are actually JPEG content
(confirmed via magic-byte inspection) — a mislabeling bug in the upload pipeline, unrelated
to size but worth fixing alongside everything else (wrong `Content-Type` can cause decode
issues on stricter clients).

## 2. Bunny on-the-fly resizing — tested, NOT currently available

Tested directly against the production pull zone:

```
curl "https://cdn.quickdash.co.in/store/photos/d8c24d36-....jpg"
  → content-length: 284947

curl "https://cdn.quickdash.co.in/store/photos/d8c24d36-....jpg?width=300&quality=80"
  → content-length: 284947   (IDENTICAL — params silently ignored)
```

Bunny's Optimizer add-on (which supports exactly this: `?width=`, `?height=`, `?quality=`,
`?aspect_ratio=`, `?crop=` etc.) is **not enabled** on this pull zone (`cdn-pullzone: 6063427`).
This is an account-level toggle in the Bunny dashboard (Pull Zone → Optimizer), not a code
change — if enabled, every existing image URL in the app would immediately support resize
params with zero app-code changes needed for read paths. This is the single highest-leverage,
lowest-effort fix available, if the account has (or adds) the Optimizer add-on.

Absent that, resizing has to happen at upload time (see §4).

## 3. Recommended image profiles

Targets assume ~2x device-pixel-ratio serving (so images stay crisp on typical phones
without over-serving for low-DPI ones) and JPEG at the given quality unless noted.

| Profile | Target dimensions | Quality | Target file size | Used for |
|---|---|---|---|---|
| **Vendor/story avatar** | 240×240px (square) | q80 | ≤20KB | Story circle, search result logo, vendor logo fallback |
| **Restaurant cover** | 800×450px (16:9) | q78 | ≤60KB | Home card cover, restaurant-details header, "New Arrivals" card |
| **Menu/product thumbnail** | 300×300px (or 300×170 for 16:9 tiles) | q75 | ≤25KB | Menu list, "pairs well with", "Popular" carousel, dish grid |
| **Banner** | 1000×300px | q80 | ≤80KB | Home top/middle banner, offer banner |
| **Full-screen image** | 1200×1200px max dimension (preserve aspect) | q85 | ≤200KB | Photo gallery viewer only — the one case that legitimately needs near-original resolution for pinch-zoom |

Note `VendorModel.coverPhotoUrl()` already implements the *mechanism* for a "cover" variant
(used in 2 of the 15 image sites above) — it's just currently generating an oversized
1600×900 cover instead of the ~800×450 target above. Fixing its generation step (wherever
that derivative is produced today) covers those two sites immediately; every other site in
the table above has no size-variant mechanism at all yet and serves the raw upload.

## 4. Admin Panel upload audit + migration plan

**Current state** (from source audit):
- Flutter apps (Customer, Vendor) correctly upload through `uploadImageToBunny()` →
  `admin.quickdash.co.in/api/bunny/image/upload` (`bunny_storage.dart`, `FirebaseHelper.dart:746/793`
  and the Vendor app's equivalent).
- `QuickDashAdminPanel-main` (Laravel) does **not**: `resources/views/vendors/create.blade.php`
  (lines 1020, 2140, 2170, 2188) and `vendors/edit.blade.php` (lines 1193, 2654, 2700, 2739)
  upload the vendor owner photo, store/restaurant photos, and menu photos directly via the
  Firebase JS SDK (`firebase.storage().ref('images').putString(...)`). New vendors created or
  edited through the admin panel today still land on Firebase Storage.
- A `BunnyController` (`app/Http/Controllers/BunnyController.php`) with working
  `uploadImage`/`deleteAsset` endpoints already exists and is already used by the Stories
  admin flow — it's simply not wired up on the vendor pages.
- Historical migration (`scripts/migrate-firebase-to-bunny.js`, ran 2026-06-27): moved 344 of
  421 found Firebase-hosted images to Bunny successfully. The remaining ~77 failed with
  HTTP 404 — source files no longer exist in Firebase Storage, permanently orphaned. These
  vendor records still carry their original Firebase URL and can only be fixed by having the
  vendor re-upload that specific photo; no script can recover a deleted source file.

**Migration plan:**

1. **Replace the direct Firebase upload calls** in `vendors/create.blade.php` and
   `vendors/edit.blade.php` (the 8 call sites listed above) with an AJAX call to the existing
   `BunnyController@uploadImage` endpoint — mirror exactly what the Stories admin view
   already does (`resources/views/stories/index.blade.php`), since that integration is proven
   and live.
2. **Move resizing to the single upload chokepoint.** Rather than resizing in each of the
   ~4 places that call `uploadImageToBunny()` (2 Flutter apps × N call sites + the admin
   panel), implement the profile-based resize (§3) once, server-side, inside the
   `/api/bunny/image/upload` proxy itself — pass the target profile as a form field
   (`profile=avatar|cover|thumbnail|banner|full`) from each caller, or infer it from the
   `folder` param already being sent (`profiles/` → avatar, `store/photos/` → cover, etc.).
   This is the only way to guarantee every current and future upload path (mobile + admin
   panel) produces consistently-sized assets without relying on N client implementations
   staying in sync.
3. **Backfill the 77 orphaned records**: flag them in the admin panel (a simple "photo
   missing, needs re-upload" badge on the vendor row) rather than attempting further
   automated migration — there's no source file left to migrate.
4. **Regenerate existing Bunny-hosted assets** (the 344 successfully-migrated ones, plus
   everything already uploaded through the mobile apps to date) through the new resize
   pipeline once §2 exists, so the size wins apply retroactively and not just to new uploads.
   This can reuse the same migration-script pattern as `migrate-firebase-to-bunny.js`.

## 5. Optimization estimate

All "current" figures are **measured**, not estimated (from the fresh-install network-stage
instrumentation run). "After" figures are **estimates** based on the profiles in §3 and
standard JPEG compression ratios for this kind of downscale — flag accordingly if quoting
externally.

| Metric | Current (measured) | After progressive loading only | After progressive loading + resizing |
|---|---|---|---|
| Images transferred on first Home paint | ~19-24 (all fired at once) | ~5-6 (only what's visible) | ~5-6 |
| Total bytes transferred, first paint | **~28.9MB** (sum of measured downloads) | ~6MB (same avg 1.2MB/image, fewer images) | **~250-300KB** (5-6 × ~50KB avg) |
| Average bytes per image | ~1.26MB | ~1.26MB | ~50KB (profiles target 20-60KB) |
| Worst-case single-image load time (measured) | up to **53.6s** (queue + bandwidth contention on a 5.5MB file) | low seconds (no more 10-way queue for visible images) | **well under 1s** (small file, no contention) |
| Estimated full first-paint completion time | 30-60s (matches original user report) | ~2-5s (TTFB-dominated, ~1.5s/request, no queue) | **~1.5-2s** (TTFB-dominated; body transfer now negligible) |
| Full-session bytes (scrolling through ~20 cards) | ~28.9MB+ | ~28.9MB+ (progressive loading defers, doesn't shrink, per-image size) | **~1MB** (20 × ~50KB) |

Combined, the two fixes target different halves of the same problem: progressive loading
fixes *when* images are requested (concurrency/ordering), resizing fixes *how much* each
request costs (bytes). Progressive loading alone (already implemented and verified) should
take the worst-case first paint from 30-60s down to low single-digit seconds. Adding
image resizing on top is what gets total bytes down by roughly two orders of magnitude and
removes the "several-second body download even for a fast connection" tax entirely — the
higher-leverage of the two remaining changes, and gated only on either enabling Bunny
Optimizer (§2) or building the upload-time resize step (§4).

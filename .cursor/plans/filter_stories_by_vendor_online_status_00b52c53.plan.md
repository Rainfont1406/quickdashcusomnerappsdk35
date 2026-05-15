---
name: Filter Stories by Vendor Online Status
overview: Add real-time filtering of stories to only show stories from vendors that are online (isVendorOnline = true). The filtering will check vendor.reststatus || vendor.isOpen() and update whenever vendors change in the stream.
todos:
  - id: "1"
    content: Add allStories variable to store all fetched stories
    status: pending
  - id: "2"
    content: Add isVendorOnline check to story filtering logic - stories must be approved AND vendor must be online (vendor.reststatus || vendor.isOpen())
    status: pending
    dependencies:
      - "1"
  - id: "3"
    content: Extract story filtering logic into _filterStories() method
    status: pending
    dependencies:
      - "2"
  - id: "4"
    content: Call _filterStories() when vendors are updated in stream listener for real-time updates
    status: pending
    dependencies:
      - "3"
---

# Filter Stories by Vendor Online Status

## Overview

Currently, stories are filtered based on approval status, order type, and content type, but not based on vendor online status. This plan adds real-time filtering to only display stories that meet ALL of the following conditions:

1. Story is approved (`approved == true`)
2. Vendor is online (`isVendorOnline == true`, i.e., `vendor.reststatus || vendor.isOpen()`)
3. Matches current order type (Delivery/Dineaway)
4. Has appropriate content type (image for Delivery, video for Dineaway)

## Implementation Details

### 1. Store All Fetched Stories

- Add a new variable `List<StoryModel> allStories = []` to store all fetched stories
- This allows re-filtering when vendors update without re-fetching from Firestore

### 2. Add Vendor Online Status Check

- In the story filtering logic (around line 1223-1263 in `lib/ui/home/HomeScreen.dart`), add a check for `isVendorOnline` before adding stories
- Use the same logic as products: `bool isVendorOnline = vendor.reststatus || vendor.isOpen()`
- **IMPORTANT**: Stories will only be displayed if BOTH conditions are met:

  1. Story is approved (`element1.approved == true`)
  2. Vendor is online (`isVendorOnline == true`, i.e., `vendor.reststatus || vendor.isOpen()`)

- Only add stories to `storyList` if both the story is approved AND the vendor is online

### 3. Create Reusable Filtering Method

- Extract the story filtering logic into a separate method `_filterStories()` that:
  - Takes the current `allStories` list and `vendors` list as inputs
  - Filters based on (ALL conditions must be met):

    1. **Story approval** (`element1.approved == true`) - REQUIRED
    2. **Vendor online status** (`isVendorOnline == true`, i.e., `vendor.reststatus || vendor.isOpen()`) - REQUIRED
    3. Order type (Delivery/Dineaway)
    4. Content type (image/video)

  - Updates `storyList` and calls `setState()`

### 4. Real-time Updates

- Call `_filterStories()` in two places:

  1. After stories are initially fetched (inside `getStory().then()`)
  2. When vendors are updated (inside `lstAllRestaurant!.listen()` callback)

- This ensures stories are re-filtered whenever a vendor goes online/offline

## Files to Modify

- `lib/ui/home/HomeScreen.dart`:
  - Add `allStories` variable to store fetched stories
  - Add `isVendorOnline` check in story filtering logic
  - Extract filtering logic into `_filterStories()` method
  - Call `_filterStories()` when vendors update in stream listener

## Code Flow

```
Vendors Stream Update → Re-filter stories → Update UI
Stories Fetched → Store in allStories → Filter → Update UI
```

The filtering will check BOTH:

- Story approval: `element1.approved == true`
- Vendor online status: `vendor.reststatus || vendor.isOpen()`

Both conditions must be true for a story to be displayed. This matches the existing product filtering logic for vendor online status.
---
name: Fix Order Type Display in Order Details
overview: Update the order details page to correctly display "Dineaway (Dining)" or "Dineaway (Takeaway)" based on the stored orderType value instead of only checking the takeAway boolean.
todos:
  - id: update-main-display
    content: Update the main order type display in OrderDetailsScreen (lines 712-732) to check orderModel.orderType and show 'Dineaway (Dining)' or 'Dineaway (Takeaway)'
    status: completed
  - id: update-receipt-print
    content: Update the receipt print function (lines 1817-1828) to use orderType field when generating receipt text
    status: completed
---

# Fix Order Type Display in Order Details

## Problem

When a user selects "Dineaway" order type and chooses "Dining" or "Takeaway" in the cart, the order is stored with `orderType` field set to "Dining" or "Takeaway". However, in the order details page, it only checks the `takeAway` boolean and always shows "Takeaway" instead of showing "Dineaway (Dining)" or "Dineaway (Takeaway)".

## Solution

Update the order type display logic in [lib/ui/orderDetailsScreen/OrderDetailsScreen.dart](lib/ui/orderDetailsScreen/OrderDetailsScreen.dart) to:

1. Check if `orderModel.orderType` is not null and not empty
2. If `orderType == "Dining"`, display "Dineaway (Dining)"
3. If `orderType == "Takeaway"`, display "Dineaway (Takeaway)"
4. Otherwise, fall back to existing logic (check `takeAway` boolean for "Deliver to door" or "Takeaway")

## Changes Required

### 1. Main Order Type Display (lines 712-732)

Update the `subtitle` logic in the ListTile to check `orderModel.orderType` first before falling back to `takeAway` boolean.

### 2. Receipt Print Function (lines 1817-1828)

Update the receipt printing logic to also use `orderType` field when generating the receipt text.

## Implementation Details

- The `orderType` field is already stored in the order (set in CartScreen and passed through PaymentScreen)
- The OrderModel already has the `orderType` field defined
- Only the display logic needs to be updated - no changes to data storage or other functionality
- Maintain backward compatibility: if `orderType` is null/empty, use existing `takeAway` boolean logic
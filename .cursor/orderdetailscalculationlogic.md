# Order Details Calculation Logic - Bill Details Section

## Overview
This document explains the complete calculation logic, formulas, conditions, and data flow for the Bill Details section in the Order Details page.

---

## 1. Data Source

### Primary Data Object
- **OrderModel**: Contains all order information including products, pricing, discounts, taxes, and charges

### Data Loading Methods
1. **Direct Model**: If order model is passed directly to the screen
2. **Firestore Fetch**: If only order ID is provided, fetches order data from Firestore database

### Key Data Fields Used
- Products list with quantities, prices, and extras
- Discount amount
- Special discount configuration
- Delivery charge
- Tip amount
- Tax model configurations
- Order type (takeaway/delivery)
- Vendor settings for special discount
- Order notes
- Coupon code

---

## 2. Subtotal Calculation

### Formula
```
Subtotal = Σ (Product Quantity × Product Price) + Σ (Product Quantity × Extras Price)
```

### Calculation Steps
1. Initialize total to 0.0
2. For each product in the order:
   - If extras price exists, is not empty, and is not zero:
     - Add: (Product Quantity × Extras Price)
   - Add: (Product Quantity × Product Price)
3. Store discount value from order model

### Components
- **Product Price**: Base price of each product item
- **Extras Price**: Additional charges for product add-ons/modifications
- **Quantity**: Number of units for each product

---

## 3. Special Discount

### Display Condition
Special Discount is displayed when ALL of the following are true:
- Vendor has special discount enabled (`specialDiscountEnable == true`)
- Special discount object exists (`specialDiscount != null`)
- Special discount object is not empty (`specialDiscount.isNotEmpty`)
- Special discount value is greater than 0

### Value Extraction
```
Special Discount Amount = Parse(specialDiscount['special_discount'])
```

### Display Format
- Label: "Special Discount"
- Value: Negative amount displayed in red with parentheses: (-Amount)

---

## 4. Regular Discount

### Display Condition
Regular Discount is displayed when:
- Discount value is greater than 0.0

### Value Source
```
Discount = orderModel.discount
```

### Display Format
- Label: "Discount"
- Value: Negative amount displayed in red with parentheses: (-Amount)

---

## 5. Delivery Charges

### Display Condition
Delivery Charges are displayed when BOTH conditions are met:
- Order is NOT a takeaway order (`takeAway == false`)
- Delivery charge value is greater than 0.0

### Value Calculation
```
If deliveryCharge is null or empty:
  Delivery Charge = 0
Else:
  Delivery Charge = Parse(deliveryCharge)
```

### Display Format
- Label: "Delivery Charges"
- Value: Positive amount displayed normally

---

## 6. Tip Amount

### Display Condition
Tip Amount is displayed when BOTH conditions are met:
- Order is NOT a takeaway order (`takeAway == false`)
- Tip value is greater than 0.0

### Value Calculation
```
If tipValue is empty:
  Tip Amount = 0.0
Else:
  Tip Amount = Parse(tipValue)
```

### Display Format
- Label: "Tip Amount"
- Value: Positive amount displayed normally

---

## 7. Tax Calculation

### Tax Filtering Logic

Taxes are filtered and applied based on order type and tax configuration:

#### For Delivery Orders (takeAway == false)
- Apply taxes where `isTakeaway == false` OR `isTakeaway == null`
- These are taxes configured for delivery orders

#### For Takeaway Orders (takeAway == true)
- Apply taxes where `isTakeaway == true`
- These are taxes configured specifically for takeaway orders

### Tax Application Condition
A tax is applied when:
- Tax model exists
- Tax is enabled (`enable == true`)
- Tax matches the order type based on `isTakeaway` flag

### Tax Base Amount
```
Tax Base = Subtotal - Regular Discount - Special Discount
```

### Tax Calculation Methods

#### Fixed Tax (type == "fix")
```
Tax Amount = Tax Value (fixed amount)
```

#### Percentage Tax (type != "fix")
```
Tax Amount = (Tax Base × Tax Percentage) / 100
```

### Total Tax Calculation
```
Total Tax Amount = Sum of all applicable individual tax amounts
```

### Tax Display
- Each applicable tax is displayed as a separate line item
- Format: "Tax Title (Fixed Amount or Percentage%)"
- Value: Calculated tax amount for that specific tax

---

## 8. Order Total Calculation

### Formula - Scenario 1: No Delivery Charge
```
Order Total = Subtotal + Total Tax Amount - Regular Discount - Special Discount
```

### Formula - Scenario 2: With Delivery Charge
```
Order Total = Subtotal + Total Tax Amount + Delivery Charge + Tip Amount - Regular Discount - Special Discount
```

### Decision Logic
```
If deliveryCharge is null OR deliveryCharge is empty:
  Use Scenario 1 Formula
Else:
  Use Scenario 2 Formula
```

---

## 9. Additional Display Items

### Remarks/Notes
- **Display Condition**: Notes exist and are not empty
- **Label**: "Remarks"
- **Action**: Clickable "View" button that opens a modal with full notes

### Coupon Code
- **Display Condition**: Coupon code exists and is not empty (after trimming whitespace)
- **Label**: "Coupon Code"
- **Value**: The actual coupon code string

---

## 10. Complete Calculation Flow Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                    START CALCULATION                         │
└───────────────────────┬─────────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────────────┐
│  STEP 1: Calculate Subtotal                                 │
│  Subtotal = Σ(Quantity × Price) + Σ(Quantity × Extras)      │
└───────────────────────┬─────────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────────────┐
│  STEP 2: Extract Discounts                                  │
│  ├─ Regular Discount = orderModel.discount                  │
│  └─ Special Discount = specialDiscount['special_discount']  │
└───────────────────────┬─────────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────────────┐
│  STEP 3: Filter Taxes Based on Order Type                   │
│  ├─ For Delivery: Apply taxes with isTakeaway = false/null  │
│  └─ For Takeaway: Apply taxes with isTakeaway = true        │
└───────────────────────┬─────────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────────────┐
│  STEP 4: Calculate Each Tax                                  │
│  Tax Base = Subtotal - Regular Discount - Special Discount  │
│  ├─ Fixed Tax: Tax Amount = Fixed Value                     │
│  └─ Percentage Tax: Tax Amount = (Base × Rate) / 100       │
└───────────────────────┬─────────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────────────┐
│  STEP 5: Sum All Taxes                                      │
│  Total Tax Amount = Σ(Individual Tax Amounts)               │
└───────────────────────┬─────────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────────────┐
│  STEP 6: Add Charges (If Delivery Order)                    │
│  ├─ Delivery Charge (if exists and > 0)                     │
│  └─ Tip Amount (if exists and > 0)                          │
└───────────────────────┬─────────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────────────┐
│  STEP 7: Calculate Final Total                              │
│  If deliveryCharge exists:                                  │
│    Total = Subtotal + Taxes + Delivery + Tip - Discounts    │
│  Else:                                                       │
│    Total = Subtotal + Taxes - Discounts                     │
└───────────────────────┬─────────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────────────┐
│                    DISPLAY RESULTS                           │
└─────────────────────────────────────────────────────────────┘
```

---

## 11. Display Conditions Summary Table

| Field | Always Shown | Conditional Display | Condition |
|-------|--------------|-------------------|-----------|
| **Subtotal** | ✓ | - | Always displayed |
| **Special Discount** | - | ✓ | Vendor enabled AND exists AND not empty AND value > 0 |
| **Regular Discount** | - | ✓ | Value > 0.0 |
| **Delivery Charges** | - | ✓ | NOT takeaway AND value > 0.0 |
| **Tip Amount** | - | ✓ | NOT takeaway AND value > 0.0 |
| **Taxes** | - | ✓ | Tax enabled AND matches order type (takeaway flag) |
| **Remarks** | - | ✓ | Notes exist AND not empty |
| **Coupon Code** | - | ✓ | Code exists AND not empty (after trim) |
| **Order Total** | ✓ | - | Always displayed |

---

## 12. Important Calculation Rules

### Rule 1: Tax Base Calculation
- Taxes are calculated on the amount AFTER discounts are applied
- Tax Base = Subtotal - Regular Discount - Special Discount
- This ensures discounts reduce the taxable amount

### Rule 2: Order Type Dependency
- Delivery charges and tips ONLY appear for delivery orders (takeaway = false)
- Tax filtering depends on order type matching tax configuration

### Rule 3: Discount Application Order
1. First: Regular discount is subtracted
2. Second: Special discount is subtracted
3. Both discounts reduce the subtotal before tax calculation

### Rule 4: Tax Calculation Order
1. Filter applicable taxes based on order type
2. Calculate each tax individually on the discounted subtotal
3. Sum all applicable taxes to get total tax amount

### Rule 5: Final Total Components
- **Additions**: Subtotal, Taxes, Delivery Charge, Tip
- **Subtractions**: Regular Discount, Special Discount
- Delivery charge and tip are only added for delivery orders

---

## 13. Formula Reference Card

### Quick Reference Formulas

```
Subtotal = Σ(Quantity × Price) + Σ(Quantity × Extras)

Tax Base = Subtotal - Regular Discount - Special Discount

Fixed Tax = Tax Fixed Value

Percentage Tax = (Tax Base × Tax Percentage) / 100

Total Tax = Σ(All Applicable Taxes)

If Delivery Charge Exists:
  Order Total = Subtotal + Total Tax + Delivery Charge + Tip - Regular Discount - Special Discount
Else:
  Order Total = Subtotal + Total Tax - Regular Discount - Special Discount
```

---

## 14. Edge Cases and Special Scenarios

### Scenario 1: Order with No Discounts
- Subtotal calculated normally
- No discount lines displayed
- Taxes calculated on full subtotal

### Scenario 2: Takeaway Order
- No delivery charge displayed
- No tip amount displayed
- Only takeaway-specific taxes applied

### Scenario 3: Order with Multiple Taxes
- Each tax calculated separately on the same tax base
- All applicable taxes summed together
- Each tax displayed as separate line item

### Scenario 4: Order with Both Discounts
- Both regular and special discounts displayed
- Both subtracted from subtotal before tax calculation
- Tax base = Subtotal - Regular Discount - Special Discount

### Scenario 5: Zero or Negative Values
- Zero values are not displayed (except subtotal and total)
- Negative values would indicate an error in calculation logic
- All amounts validated before display

---

## 15. Data Validation Points

### Before Calculation
- Order model must exist
- Products list must not be empty
- All numeric values must be parseable

### During Calculation
- Handle null/empty values gracefully
- Default to 0.0 for missing values
- Validate tax model exists before processing

### After Calculation
- Ensure total is non-negative
- Verify all displayed values are formatted correctly
- Check currency formatting applied

---

## End of Document
